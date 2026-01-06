import Foundation

extension URL {

    /// Check if URL points to a directory
    var isDirectory: Bool {
        guard let resourceValues = try? resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory else {
            return false
        }
        return isDirectory
    }

    /// Get all subdirectories (non-recursive, excludes hidden)
    func subdirectories() -> [URL] {
        guard isDirectory else {
            return []
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { $0.isDirectory }
    }

    /// Get all files in directory (non-recursive, excludes hidden)
    func files() -> [URL] {
        guard isDirectory else {
            return []
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { !$0.isDirectory }
    }

    /// Get all video files in directory (non-recursive)
    func videoFiles() -> [URL] {
        let videoExtensions = ["mp4", "mov", "m4v", "avi"]
        return files().filter { url in
            videoExtensions.contains(url.pathExtension.lowercased())
        }
    }

    /// File size in bytes (0 if not a file)
    var fileSize: Int64 {
        guard !isDirectory else {
            return 0
        }

        guard let resourceValues = try? resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return 0
        }

        return Int64(fileSize)
    }

    /// File name without extension
    var nameWithoutExtension: String {
        return deletingPathExtension().lastPathComponent
    }
}
