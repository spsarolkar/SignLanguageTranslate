//
//  PersistenceController.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import Foundation

/// Singleton manager for file system operations, dataset storage, and directory management.
/// Handles large file storage (100GB+) and ensures data persistence across app updates.
@MainActor
final class PersistenceController {
    
    // MARK: - Singleton
    
    static let shared = PersistenceController()
    
    private init() {
        ensureDirectoriesExist()
    }
    
    // MARK: - Properties
    
    /// Base documents directory URL
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Datasets subdirectory URL
    var datasetsURL: URL {
        documentsURL.appendingPathComponent("Datasets", isDirectory: true)
    }
    
    // MARK: - Directory Management
    
    /// Ensures the base directory structure exists
    func ensureDirectoriesExist() {
        let fileManager = FileManager.default
        
        // Create Datasets directory
        let datasetsPath = datasetsURL.path
        if !fileManager.fileExists(atPath: datasetsPath) {
            try? fileManager.createDirectory(at: datasetsURL, withIntermediateDirectories: true)
        }
    }
    
    /// Gets or creates the directory path for a specific dataset category and label
    /// - Parameters:
    ///   - category: The dataset category name
    ///   - label: The dataset label name
    /// - Returns: URL to the dataset directory
    func getDatasetPath(category: String, label: String) -> URL {
        let datasetURL = datasetsURL
            .appendingPathComponent(category, isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        
        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: datasetURL.path) {
            try? fileManager.createDirectory(at: datasetURL, withIntermediateDirectories: true)
        }
        
        return datasetURL
    }
    
    /// Gets the videos subdirectory for a dataset
    /// - Parameters:
    ///   - category: The dataset category name
    ///   - label: The dataset label name
    /// - Returns: URL to the videos directory
    func getVideosPath(category: String, label: String) -> URL {
        let videosURL = getDatasetPath(category: category, label: label)
            .appendingPathComponent("videos", isDirectory: true)
        
        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: videosURL.path) {
            try? fileManager.createDirectory(at: videosURL, withIntermediateDirectories: true)
        }
        
        return videosURL
    }
    
    /// Gets the keypoints subdirectory for a dataset
    /// - Parameters:
    ///   - category: The dataset category name
    ///   - label: The dataset label name
    /// - Returns: URL to the keypoints directory
    func getKeypointsPath(category: String, label: String) -> URL {
        let keypointsURL = getDatasetPath(category: category, label: label)
            .appendingPathComponent("keypoints", isDirectory: true)
        
        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: keypointsURL.path) {
            try? fileManager.createDirectory(at: keypointsURL, withIntermediateDirectories: true)
        }
        
        return keypointsURL
    }
    
    // MARK: - File Operations
    
    /// Saves a file from source URL to destination URL
    /// - Parameters:
    ///   - sourceURL: Source file URL
    ///   - destinationURL: Destination file URL
    /// - Throws: File system errors
    func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
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
        
        // Copy file
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    // MARK: - Storage Information
    
    /// Calculates the total storage size used by datasets
    /// - Returns: Total size in bytes, or 0 if calculation fails
    func getStorageSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: datasetsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false,
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    /// Gets a human-readable string representation of storage size
    /// - Returns: Formatted storage size string (e.g., "1.5 GB")
    func getStorageSizeString() -> String {
        let bytes = getStorageSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter.string(fromByteCount: bytes)
    }
}

