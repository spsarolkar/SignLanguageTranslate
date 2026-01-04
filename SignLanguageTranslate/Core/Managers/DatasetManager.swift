//
//  DatasetManager.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Manager for downloading and managing datasets from remote URLs
/// Handles background downloads, zip extraction, and SwiftData persistence
@MainActor
final class DatasetManager: NSObject {
    
    // MARK: - Singleton
    
    static let shared = DatasetManager()
    
    private override init() {
        super.init()
        setupBackgroundSession()
    }
    
    // MARK: - Properties
    
    /// Background URLSession configuration identifier
    private let backgroundSessionIdentifier = "in.sunilsarolkar.signlanguagetranslate.background.download"
    
    /// Background URLSession for downloading files
    private var backgroundSession: URLSession!
    
    /// Active download tasks mapped by task identifier
    private var activeDownloads: [Int: UUID] = [:]
    
    /// Model context for SwiftData operations
    var modelContext: ModelContext?
    
    /// Callback for background session completion (set by app delegate)
    var backgroundSessionCompletionHandler: (() -> Void)?
    
    // MARK: - Setup
    
    /// Sets up the background URLSession configuration
    /// This method can be called multiple times safely - it will reuse existing session if available
    private func setupBackgroundSession() {
        // Check if we already have a session with the same identifier
        // If the app was terminated and relaunched, we need to recreate the session
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = true
        
        // Invalidate existing session if any
        backgroundSession?.invalidateAndCancel()
        
        backgroundSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    /// Recreates the background session (useful when app is relaunched)
    func recreateBackgroundSession() {
        setupBackgroundSession()
    }
    
    // MARK: - Public Methods
    
    /// Downloads a dataset from a URL and extracts it to the Documents folder
    /// - Parameters:
    ///   - url: The URL of the zip file to download
    ///   - name: Optional name for the dataset (defaults to filename from URL)
    /// - Returns: The Dataset model instance
    func downloadDataset(from url: URL, name: String? = nil) async throws -> Dataset {
        guard let modelContext = modelContext else {
            throw DatasetManagerError.modelContextNotSet
        }
        
        let datasetName = name ?? url.lastPathComponent.replacingOccurrences(of: ".zip", with: "")
        let destinationURL = PersistenceController.shared.datasetsURL
            .appendingPathComponent(datasetName, isDirectory: false)
            .appendingPathExtension("zip")
        
        // Create dataset record
        let dataset = Dataset(
            name: datasetName,
            sourceURL: url.absoluteString,
            localPath: destinationURL.path,
            downloadStatus: .downloading
        )
        
        modelContext.insert(dataset)
        try modelContext.save()
        
        // Start background download
        let downloadTask = backgroundSession.downloadTask(with: url)
        activeDownloads[downloadTask.taskIdentifier] = dataset.id
        downloadTask.resume()
        
        return dataset
    }
    
    /// Extracts a zip file to the Documents folder
    /// - Parameters:
    ///   - zipURL: URL of the zip file
    ///   - destinationURL: Destination directory URL
    /// - Throws: Extraction errors
    /// - Note: On macOS, uses command-line unzip tool. On iOS, consider using ZIPFoundation library
    ///   (https://github.com/weichsel/ZIPFoundation) for proper zip extraction.
    func extractZip(from zipURL: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        
        // Ensure destination directory exists
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        #if os(macOS)
        // macOS: Use command-line unzip tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destinationURL.path]
        process.environment = ProcessInfo.processInfo.environment
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw DatasetManagerError.extractionFailed
        }
        #else
        // iOS: Process-based unzip is not available in sandboxed environment
        // For production iOS apps, consider adding ZIPFoundation via SPM:
        // https://github.com/weichsel/ZIPFoundation
        // 
        // Alternative: Implement zip extraction using Compression framework
        // This is a placeholder that will throw an error
        // TODO: Implement zip extraction for iOS using ZIPFoundation or Compression framework
        throw DatasetManagerError.extractionFailed
        #endif
    }
    
    /// Updates the download status of a dataset
    /// - Parameters:
    ///   - datasetId: The UUID of the dataset
    ///   - status: The new status
    func updateDatasetStatus(datasetId: UUID, status: DownloadStatus) {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<Dataset>(
            predicate: #Predicate<Dataset> { $0.id == datasetId }
        )
        
        if let dataset = try? modelContext.fetch(descriptor).first {
            dataset.downloadStatus = status
            try? modelContext.save()
        }
    }
    
    /// Gets all datasets from SwiftData
    /// - Returns: Array of Dataset models
    func getAllDatasets() throws -> [Dataset] {
        guard let modelContext = modelContext else {
            throw DatasetManagerError.modelContextNotSet
        }
        
        let descriptor = FetchDescriptor<Dataset>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DatasetManager: URLSessionDownloadDelegate {
    
    /// Called when a download task completes
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let datasetId = activeDownloads[downloadTask.taskIdentifier] else {
            print("Warning: Download task completed but no dataset ID found")
            return
        }
        
        activeDownloads.removeValue(forKey: downloadTask.taskIdentifier)
        
        Task { @MainActor in
            await handleDownloadCompletion(location: location, datasetId: datasetId)
        }
    }
    
    /// Called during download progress
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Progress tracking can be added here if needed
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("Download progress: \(Int(progress * 100))%")
    }
    
    /// Called when a download task completes (with error handling)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("Download task completed with error: \(error.localizedDescription)")
            
            if let datasetId = activeDownloads[task.taskIdentifier] {
                activeDownloads.removeValue(forKey: task.taskIdentifier)
                Task { @MainActor in
                    updateDatasetStatus(datasetId: datasetId, status: .failed)
                }
            }
        }
    }
    
    /// Called when background session events need to be handled
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundSessionCompletionHandler?()
            self.backgroundSessionCompletionHandler = nil
        }
    }
    
    // MARK: - Private Helpers
    
    /// Handles the completion of a download
    private func handleDownloadCompletion(location: URL, datasetId: UUID) async {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<Dataset>(
            predicate: #Predicate<Dataset> { $0.id == datasetId }
        )
        
        guard let dataset = try? modelContext.fetch(descriptor).first else {
            print("Error: Dataset not found for ID: \(datasetId)")
            return
        }
        
        do {
            // Move downloaded file to destination
            let destinationURL = URL(fileURLWithPath: dataset.localPath)
            let fileManager = FileManager.default
            
            // Ensure destination directory exists
            let destinationDirectory = destinationURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: destinationDirectory.path) {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            }
            
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Move downloaded file to destination
            try fileManager.moveItem(at: location, to: destinationURL)
            
            // Update status to downloaded
            updateDatasetStatus(datasetId: datasetId, status: .downloaded)
            
            // Extract the zip file
            updateDatasetStatus(datasetId: datasetId, status: .extracting)
            
            let extractDestination = destinationURL.deletingLastPathComponent()
                .appendingPathComponent(dataset.name, isDirectory: true)
            
            try await extractZip(from: destinationURL, to: extractDestination)
            
            // Update dataset path to extracted directory
            dataset.localPath = extractDestination.path
            updateDatasetStatus(datasetId: datasetId, status: .completed)
            
            // Optionally remove the zip file after extraction
            try? fileManager.removeItem(at: destinationURL)
            
        } catch {
            print("Error handling download completion: \(error.localizedDescription)")
            updateDatasetStatus(datasetId: datasetId, status: .failed)
        }
    }
}

// MARK: - Errors

enum DatasetManagerError: LocalizedError {
    case modelContextNotSet
    case extractionFailed
    
    var errorDescription: String? {
        switch self {
        case .modelContextNotSet:
            return "Model context not set. Please configure SwiftData model context."
        case .extractionFailed:
            return "Failed to extract zip file. Please ensure the zip file is valid."
        }
    }
}

