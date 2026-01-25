import Foundation

/// Service for syncing training runs to Cloudflare R2 (S3-compatible).
///
/// ## Setup
/// Store credentials in Keychain:
/// - Account ID
/// - Access Key ID
/// - Secret Access Key
/// - Bucket Name
///
/// ## Usage
/// ```swift
/// let r2 = R2SyncService(
///     accountId: "...",
///     accessKeyId: "...",
///     secretAccessKey: "...",
///     bucketName: "training-runs"
/// )
/// try await r2.uploadRun(record)
/// ```
public actor R2SyncService {
    
    // MARK: - Configuration
    
    private let accountId: String
    private let accessKeyId: String
    private let secretAccessKey: String
    private let bucketName: String
    
    private var baseURL: URL {
        URL(string: "https://\(accountId).r2.cloudflarestorage.com")!
    }
    
    // MARK: - State
    
    private var isConfigured: Bool {
        !accountId.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
    }
    
    // MARK: - Initialization
    
    public init(
        accountId: String = "",
        accessKeyId: String = "",
        secretAccessKey: String = "",
        bucketName: String = "training-runs"
    ) {
        self.accountId = accountId
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.bucketName = bucketName
    }
    
    /// Load credentials from UserDefaults (for development).
    /// In production, use Keychain.
    public static func fromUserDefaults() -> R2SyncService {
        let defaults = UserDefaults.standard
        return R2SyncService(
            accountId: defaults.string(forKey: "r2_account_id") ?? "",
            accessKeyId: defaults.string(forKey: "r2_access_key_id") ?? "",
            secretAccessKey: defaults.string(forKey: "r2_secret_access_key") ?? "",
            bucketName: defaults.string(forKey: "r2_bucket_name") ?? "training-runs"
        )
    }
    
    // MARK: - Public API
    
    /// Upload a training run record to R2.
    public func uploadRun(_ record: TrainingRunRecord) async throws {
        guard isConfigured else {
            print("[R2Sync] Not configured, skipping upload")
            return
        }
        
        let path = "runs/\(record.runId)/run.json"
        let data = try JSONEncoder.prettyEncoder.encode(record)
        try await uploadData(data, to: path, contentType: "application/json")
        
        print("[R2Sync] Uploaded run \(record.runId) (\(data.count) bytes)")
    }
    
    /// Upload epoch metrics incrementally.
    public func uploadEpoch(_ epoch: EpochRecord, runId: String) async throws {
        guard isConfigured else { return }
        
        let path = "runs/\(runId)/epochs/epoch_\(epoch.epoch).json"
        let data = try JSONEncoder.prettyEncoder.encode(epoch)
        try await uploadData(data, to: path, contentType: "application/json")
        
        print("[R2Sync] Uploaded epoch \(epoch.epoch) for run \(runId)")
    }
    
    /// Upload a checkpoint file.
    public func uploadCheckpoint(at localURL: URL, runId: String, epoch: Int) async throws {
        guard isConfigured else { return }
        
        let filename = localURL.lastPathComponent
        let path = "runs/\(runId)/checkpoints/\(filename)"
        let data = try Data(contentsOf: localURL)
        try await uploadData(data, to: path, contentType: "application/octet-stream")
        
        print("[R2Sync] Uploaded checkpoint \(filename) (\(data.count) bytes)")
    }
    
    /// Update the global index of all runs.
    public func updateIndex(runs: [CloudTrainingRunSummary]) async throws {
        guard isConfigured else { return }
        
        let path = "index.json"
        let data = try JSONEncoder.prettyEncoder.encode(runs)
        try await uploadData(data, to: path, contentType: "application/json")
        
        print("[R2Sync] Updated index with \(runs.count) runs")
    }
    
    // MARK: - Download
    
    /// Download a run record.
    public func downloadRun(runId: String) async throws -> TrainingRunRecord? {
        guard isConfigured else { return nil }
        
        let path = "runs/\(runId)/run.json"
        guard let data = try await downloadData(from: path) else { return nil }
        return try JSONDecoder().decode(TrainingRunRecord.self, from: data)
    }
    
    /// Download the index of all runs.
    public func downloadIndex() async throws -> [CloudTrainingRunSummary] {
        guard isConfigured else { return [] }
        
        guard let data = try await downloadData(from: "index.json") else { return [] }
        return try JSONDecoder().decode([CloudTrainingRunSummary].self, from: data)
    }
    
    // MARK: - S3 Signing (AWS Signature V4)
    
    private func uploadData(_ data: Data, to path: String, contentType: String) async throws {
        let url = baseURL.appendingPathComponent(bucketName).appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        // Sign the request (simplified - production should use full AWS Sig V4)
        signRequest(&request, method: "PUT", path: "/\(bucketName)/\(path)", payload: data)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw R2Error.uploadFailed(path: path)
        }
    }
    
    private func downloadData(from path: String) async throws -> Data? {
        let url = baseURL.appendingPathComponent(bucketName).appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        signRequest(&request, method: "GET", path: "/\(bucketName)/\(path)", payload: nil)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        if httpResponse.statusCode == 404 {
            return nil
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw R2Error.downloadFailed(path: path)
        }
        
        return data
    }
    
    private func signRequest(_ request: inout URLRequest, method: String, path: String, payload: Data?) {
        // Simplified signing for development
        // Production should use full AWS Signature Version 4
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let amzDate = dateFormatter.string(from: Date())
        
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(baseURL.host!, forHTTPHeaderField: "Host")
        
        // For proper signing, implement AWS Sig V4:
        // https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
        
        // Basic auth header (not secure for production!)
        let credentials = "\(accessKeyId):\(secretAccessKey)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64 = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
    }
}

// MARK: - Supporting Types

// MARK: - Training Metrics Summary

/// Summary of a training run for the cloud index.
public struct CloudTrainingRunSummary: Codable, Sendable {
    public let runId: String
    public let startedAt: Date
    public let endedAt: Date?
    public let deviceChip: String
    public let modelArchitecture: String
    public let status: RunStatus
    public let bestValLoss: Float?
    public let totalEpochs: Int
    
    public init(from record: TrainingRunRecord) {
        self.runId = record.runId
        self.startedAt = record.startedAt
        self.endedAt = record.endedAt
        self.deviceChip = record.deviceChip
        self.modelArchitecture = record.config.modelArchitecture
        self.status = record.status
        self.bestValLoss = record.bestValLoss
        self.totalEpochs = record.epochs.count
    }
}

// MARK: - Errors

public enum R2Error: LocalizedError {
    case uploadFailed(path: String)
    case downloadFailed(path: String)
    case notConfigured
    
    public var errorDescription: String? {
        switch self {
        case .uploadFailed(let path):
            return "Failed to upload to R2: \(path)"
        case .downloadFailed(let path):
            return "Failed to download from R2: \(path)"
        case .notConfigured:
            return "R2 credentials not configured"
        }
    }
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
