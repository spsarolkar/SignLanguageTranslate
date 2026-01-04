//
//  Dataset.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import Foundation
import SwiftData

/// SwiftData model representing a downloaded dataset
@Model
final class Dataset {
    var id: UUID
    var name: String
    var sourceURL: String
    var localPath: String
    var createdAt: Date
    var downloadStatusRawValue: String
    
    /// Computed property for download status enum
    var downloadStatus: DownloadStatus {
        get {
            DownloadStatus(rawValue: downloadStatusRawValue) ?? .pending
        }
        set {
            downloadStatusRawValue = newValue.rawValue
        }
    }
    
    init(name: String, sourceURL: String, localPath: String, downloadStatus: DownloadStatus = .pending) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.localPath = localPath
        self.createdAt = Date()
        self.downloadStatusRawValue = downloadStatus.rawValue
    }
}

/// Enum representing the download status of a dataset
enum DownloadStatus: String, Codable {
    case pending = "pending"
    case downloading = "downloading"
    case downloaded = "downloaded"
    case extracting = "extracting"
    case completed = "completed"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .downloading: return "Downloading"
        case .downloaded: return "Downloaded"
        case .extracting: return "Extracting"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

