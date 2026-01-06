import Foundation

enum AppConstants {

    enum Dataset {
        static let includeDatasetName = "INCLUDE"
        static let islcsltrDatasetName = "ISL-CSLTR"

        static let supportedVideoExtensions = ["mp4", "mov", "m4v", "avi"]
    }

    enum Downloads {
        static let maxConcurrentDownloads = 3
        static let backgroundSessionIdentifier = "com.signlanguage.translate.background"
    }

    enum Storage {
        static let datasetsFolderName = "Datasets"
        static let downloadsFolderName = "Downloads"
        static let thumbnailsFolderName = "Thumbnails"
        static let resumeDataFolderName = "ResumeData"
    }
}
