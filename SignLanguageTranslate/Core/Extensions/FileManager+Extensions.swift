import Foundation

extension FileManager {

    /// The app's documents directory
    var documentsDirectory: URL {
        let paths = urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    /// Directory where all datasets are stored: Documents/Datasets/
    var datasetsDirectory: URL {
        let datasetsURL = documentsDirectory.appendingPathComponent("Datasets")
        try? createDirectoryIfNeeded(at: datasetsURL)
        return datasetsURL
    }

    /// Directory for temporary downloads: Documents/Downloads/
    var downloadsDirectory: URL {
        let downloadsURL = documentsDirectory.appendingPathComponent("Downloads")
        try? createDirectoryIfNeeded(at: downloadsURL)
        return downloadsURL
    }

    /// Check if file exists at URL
    func fileExists(at url: URL) -> Bool {
        return fileExists(atPath: url.path)
    }

    /// Check if directory exists at URL
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Calculate total size of directory recursively (in bytes)
    func directorySize(at url: URL) -> Int64 {
        guard directoryExists(at: url) else {
            return 0
        }

        var totalSize: Int64 = 0

        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile,
                  let fileSize = resourceValues.fileSize else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    /// Format bytes into human-readable string
    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false

        // Handle zero case specially
        if bytes == 0 {
            return "Zero KB"
        }

        return formatter.string(fromByteCount: bytes)
    }

    /// Create directory if it doesn't exist
    func createDirectoryIfNeeded(at url: URL) throws {
        guard !directoryExists(at: url) else {
            return
        }

        try createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Delete item safely (no error if doesn't exist)
    func safeDelete(at url: URL) {
        guard fileExists(at: url) else {
            return
        }

        try? removeItem(at: url)
    }
}
