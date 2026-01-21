import Foundation
import SwiftData

/// Service responsible for synchronizing extracted features and metadata with the Hugging Face Hub.
/// Implements the "Hybrid Workflow":
/// - Metadata Sync: Pulls metadata.csv to check dataset state
/// - Feature Upload: Uploads local feature JSONs to HF
actor HuggingFaceSyncService {
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    private let urlSession: URLSession
    private let token: String
    private let repoId: String
    
    private let baseUrl = "https://huggingface.co/api"
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, token: String, repoId: String) {
        self.modelContext = modelContext
        self.token = token
        self.repoId = repoId
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 300 // 5 min timeout
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Syncs local extracted features to the remote HF repository
    /// - Parameter video: The video sample whose features need uploading
    func syncFeatures(for video: VideoSample) async throws {
        // 1. Check if we have features extracted
        guard !video.featureSets.isEmpty else {
            print("[HF Sync] No features to sync for \(video.fileName)")
            return
        }
        
        // 2. Iterate through extracted features
        for featureSet in video.featureSets {
            // Check if already uploaded (we need a property for this, or check existence)
            // For now, simple "fire and forget" or overwrite
            
            try await uploadFeatureFile(featureSet, videoName: video.fileName)
        }
    }
    
    /// Upload all extracted features for a dataset to HuggingFace
    /// - Parameters:
    ///   - datasetName: Name of the dataset to sync
    ///   - progressHandler: Callback for progress updates (0.0 to 1.0)
    /// - Returns: Number of files successfully uploaded
    @discardableResult
    func uploadFeatures(
        for datasetName: String,
        progressHandler: ((Double) async -> Void)? = nil
    ) async throws -> Int {
        // 1. Find all feature sets for this dataset
        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName }
        )
        let videos = try modelContext.fetch(descriptor)
        
        var allFeatureSets: [(video: VideoSample, featureSet: FeatureSet)] = []
        for video in videos {
            for featureSet in video.featureSets {
                allFeatureSets.append((video, featureSet))
            }
        }
        
        guard !allFeatureSets.isEmpty else {
            print("[HF Sync] No features to upload for \(datasetName)")
            return 0
        }
        
        print("[HF Sync] Uploading \(allFeatureSets.count) feature files for \(datasetName)")
        
        // 2. Upload each feature file with progress tracking
        var successCount = 0
        for (index, item) in allFeatureSets.enumerated() {
            do {
                try await uploadFeatureFile(item.featureSet, videoName: item.video.fileName)
                successCount += 1
            } catch {
                print("[HF Sync] Failed to upload \(item.video.fileName): \(error.localizedDescription)")
            }
            
            // Update progress
            let progress = Double(index + 1) / Double(allFeatureSets.count)
            await progressHandler?(progress)
        }
        
        print("[HF Sync] Completed upload: \(successCount)/\(allFeatureSets.count) files")
        return successCount
    }
    
    /// Generates and uploads the master metadata.csv linking videos and labels
    func syncMetadata() async throws {
        // 1. Fetch all videos from DB
        let descriptor = FetchDescriptor<VideoSample>(sortBy: [SortDescriptor(\.originalFilename)])
        let videos = try modelContext.fetch(descriptor)
        
        // 2. Generate CSV content
        var csv = "filename,label,split,duration,video_id\n"
        for video in videos {
            let label = video.labels.first?.name ?? "Unknown"
            // Simple hash or UUID for video_id
            let videoId = video.id.uuidString
            // Assuming simplified split logic or stored property
            let split = "train" 
            
            csv += "\(video.fileName),\(label),\(split),\(video.duration),\(videoId)\n"
        }
        
        // 3. Upload to HF
        guard let data = csv.data(using: .utf8) else { return }
        try await uploadFile(data: data, path: "metadata.csv", commitMessage: "Update metadata.csv")
    }
    
    // MARK: - Private Methods
    
    private func uploadFeatureFile(_ featureSet: FeatureSet, videoName: String) async throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fullPath = documentsDirectory.appendingPathComponent(featureSet.filePath)
        
        guard fileManager.fileExists(atPath: fullPath.path) else {
            print("[HF Sync] Feature file missing: \(featureSet.filePath)")
            return
        }
        
        let data = try Data(contentsOf: fullPath)
        
        // Construct remote path: data/features/<model>/<video_name>.json
        // Sanitize video name to ensure valid filename
        let safeVideoName = (videoName as NSString).deletingPathExtension
        let remotePath = "data/features/\(featureSet.modelName)/\(safeVideoName).json"
        
        try await uploadFile(data: data, path: remotePath, commitMessage: "Add features for \(safeVideoName) (\(featureSet.modelName))")
        
        print("[HF Sync] Uploaded \(remotePath)")
    }
    
    private func uploadFile(data: Data, path: String, commitMessage: String) async throws {
        // HF API Commit Endpoint
        // POST /api/repos/{repo_id}/commit
        let url = URL(string: "\(baseUrl)/repos/\(repoId)/commit/main")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Payload structure for "create or update file"
        // Multibyte/Multipart is better for large files, but JSON commit is fine for small JSONs/CSV
        // Actually HF API prefers Direct Upload via LFS for large files, or commit API for small.
        // For feature JSONs (small), standard commit is okay.
        
        // Convert extracted JSON to base64 for API transport if needed, or use multipart.
        // The HF Commit API needs "operations".
        
        // Operation:
        // {
        //   "operations": [
        //     { "path": "path/in/repo", "operation": "createOrUpdate", "content": "base64..." }
        //   ],
        //   "commit_message": "..."
        // }
        
        let contentBase64 = data.base64EncodedString()
        
        let operation: [String: Any] = [
            "path": path,
            "operation": "createOrUpdate",
            "content": contentBase64,
            "encoding": "base64"
        ]
        
        let payload: [String: Any] = [
            "operations": [operation],
            "commit_message": commitMessage
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (responseData, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError("Invalid response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: responseData, encoding: .utf8) {
                print("[HF Sync] Error: \(errorText)")
            }
            throw SyncError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

enum SyncError: LocalizedError {
    case networkError(String)
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network Error: \(msg)"
        case .serverError(let code): return "Server Error: \(code)"
        }
    }
}
