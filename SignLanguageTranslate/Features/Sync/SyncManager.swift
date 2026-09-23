import Foundation
import SwiftData
import Security
import Combine

/// Manages synchronization of local extracted features to HuggingFace Hub
/// Provides progress tracking, credential management, and sync status
@MainActor
public class SyncManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var isSyncing = false
    @Published public private(set) var syncProgress: SyncProgress?
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastError: String?
    @Published public var repoId: String = ""

    // MARK: - Sync Progress

    public struct SyncProgress: Sendable {
        public let totalFiles: Int
        public let uploadedFiles: Int
        public let currentFile: String?
        public let status: Status

        public var percentage: Double {
            guard totalFiles > 0 else { return 0 }
            return Double(uploadedFiles) / Double(totalFiles)
        }

        public enum Status: Sendable {
            case preparing
            case uploading
            case uploadingMetadata
            case completed
            case failed(String)
        }
    }

    // MARK: - Keychain Keys

    private let tokenKeychainKey = "com.signlanguagetranslate.hftoken"
    private let repoIdKey = "com.signlanguagetranslate.hfrepo"

    // MARK: - Initialization

    public init() {
        // Load saved repo ID
        if let savedRepoId = UserDefaults.standard.string(forKey: repoIdKey) {
            self.repoId = savedRepoId
        }

        // Load last sync date
        if let timestamp = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
            self.lastSyncDate = timestamp
        }
    }

    // MARK: - Credential Management

    /// Save HuggingFace token to Keychain
    public func saveToken(_ token: String) -> Bool {
        let data = Data(token.utf8)

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve HuggingFace token from Keychain
    public func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// Check if token is stored
    public var hasToken: Bool {
        getToken() != nil
    }

    /// Delete stored token
    public func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Save repo ID
    public func saveRepoId(_ repoId: String) {
        self.repoId = repoId
        UserDefaults.standard.set(repoId, forKey: repoIdKey)
    }

    // MARK: - Sync Operations

    /// Sync all extracted features for a dataset to HuggingFace
    public func syncDataset(name: String, modelContext: ModelContext) async {
        guard let token = getToken(), !token.isEmpty else {
            lastError = "No HuggingFace token configured"
            return
        }

        guard !repoId.isEmpty else {
            lastError = "No repository ID configured"
            return
        }

        isSyncing = true
        lastError = nil
        syncProgress = SyncProgress(totalFiles: 0, uploadedFiles: 0, currentFile: nil, status: .preparing)

        do {
            let syncService = HuggingFaceSyncService(
                modelContext: modelContext,
                token: token,
                repoId: repoId
            )

            // Get total count for progress
            let descriptor = FetchDescriptor<VideoSample>(
                predicate: #Predicate { $0.datasetName == name }
            )
            let videos = try modelContext.fetch(descriptor)
            let totalFeatureSets = videos.reduce(0) { $0 + $1.featureSets.count }

            syncProgress = SyncProgress(
                totalFiles: totalFeatureSets,
                uploadedFiles: 0,
                currentFile: nil,
                status: .uploading
            )

            // Upload features with progress tracking
            var uploadedCount = 0
            let uploadedFiles = try await syncService.uploadFeatures(for: name) { progress in
                await MainActor.run {
                    uploadedCount = Int(progress * Double(totalFeatureSets))
                    self.syncProgress = SyncProgress(
                        totalFiles: totalFeatureSets,
                        uploadedFiles: uploadedCount,
                        currentFile: nil,
                        status: .uploading
                    )
                }
            }

            // Upload metadata
            syncProgress = SyncProgress(
                totalFiles: totalFeatureSets,
                uploadedFiles: uploadedFiles,
                currentFile: "metadata.csv",
                status: .uploadingMetadata
            )

            try await syncService.syncMetadata()

            // Complete
            syncProgress = SyncProgress(
                totalFiles: totalFeatureSets,
                uploadedFiles: uploadedFiles,
                currentFile: nil,
                status: .completed
            )

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")

        } catch {
            lastError = error.localizedDescription
            syncProgress = SyncProgress(
                totalFiles: syncProgress?.totalFiles ?? 0,
                uploadedFiles: syncProgress?.uploadedFiles ?? 0,
                currentFile: nil,
                status: .failed(error.localizedDescription)
            )
        }

        isSyncing = false
    }

    /// Sync single video's features
    public func syncVideo(_ video: VideoSample, modelContext: ModelContext) async {
        guard let token = getToken(), !token.isEmpty else {
            lastError = "No HuggingFace token configured"
            return
        }

        guard !repoId.isEmpty else {
            lastError = "No repository ID configured"
            return
        }

        isSyncing = true
        lastError = nil

        do {
            let syncService = HuggingFaceSyncService(
                modelContext: modelContext,
                token: token,
                repoId: repoId
            )

            try await syncService.syncFeatures(for: video)
            lastSyncDate = Date()

        } catch {
            lastError = error.localizedDescription
        }

        isSyncing = false
    }
}
