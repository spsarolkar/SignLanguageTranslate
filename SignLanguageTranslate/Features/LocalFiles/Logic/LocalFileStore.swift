import Foundation
import ImageIO

nonisolated struct LocalFileEntry: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    var id: String { path }

    var kind: LocalFileKind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "json", name.lowercased().hasSuffix("_features.json") { return .features }
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) { return .image }
        if ["json", "txt", "csv", "md", "log", "xml", "yaml", "yml"].contains(ext) { return .text }
        return .binary
    }
}

nonisolated enum LocalFileKind: Sendable {
    case folder, features, video, image, text, binary

    var icon: String {
        switch self {
        case .folder: return "folder"
        case .features: return "point.3.connected.trianglepath.dotted"
        case .video: return "film"
        case .image: return "photo"
        case .text: return "doc.text"
        case .binary: return "doc.zipper"
        }
    }
}

nonisolated struct LocalFilePreview: Sendable {
    let entry: LocalFileEntry
    let content: Content

    enum Content: Sendable {
        case features([FrameFeatures], rawText: String, truncated: Bool)
        case text(String, truncated: Bool, note: String?)
        case image(Data)
        case video(URL)
        case information(String)
    }
}

/// Read-only snapshots of app Documents. Does not depend on view contexts or
/// pipeline services, and never mutates a directory or artifact.
actor LocalFileStore {
    nonisolated let root: URL
    nonisolated static let textLimit = 64 * 1024
    nonisolated static let featureLimit = 8 * 1024 * 1024
    private let manager = FileManager.default
    private let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey
    ]

    nonisolated enum BrowserError: LocalizedError {
        case outsideDocuments, unavailableFolder
        var errorDescription: String? {
            switch self {
            case .outsideDocuments: return "This location is outside the app's Documents folder."
            case .unavailableFolder: return "This folder is not available yet. Refresh after the pipeline creates it."
            }
        }
    }

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func list(directory: String) throws -> [LocalFileEntry] {
        let url = try resolvedURL(path: directory)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BrowserError.unavailableFolder
        }
        return try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys),
                                                options: [.skipsHiddenFiles])
            .compactMap { try entry(at: $0) }
            .sorted(by: comesBefore)
    }

    func allFeatures() async throws -> [LocalFileEntry] {
        let directory = try resolvedURL(path: "Datasets/Features")
        guard manager.fileExists(atPath: directory.path) else { return [] }
        guard let iterator = manager.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw BrowserError.unavailableFolder
        }
        var entries: [LocalFileEntry] = []
        var visited = 0
        while let url = iterator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if let item = try entry(at: url), item.kind == .features { entries.append(item) }
            visited += 1
            if visited.isMultiple(of: 128) { await Task.yield() }
        }
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func preview(path: String) throws -> LocalFilePreview {
        let url = try resolvedURL(path: path)
        guard let item = try entry(at: url), !item.isDirectory else { throw BrowserError.unavailableFolder }
        let content: LocalFilePreview.Content
        switch item.kind {
        case .video:
            content = .video(url)
        case .features:
            let bytes = try readPrefix(url, limit: Self.featureLimit)
            let text = String(decoding: bytes.prefix(Self.textLimit), as: UTF8.self)
            if bytes.count > Self.featureLimit {
                content = .text(text, truncated: true,
                                note: "This feature file exceeds the 8 MiB interactive preview limit. Showing a text excerpt.")
            } else if let frames = try? JSONDecoder().decode([FrameFeatures].self, from: bytes) {
                content = .features(frames, rawText: text, truncated: bytes.count > Self.textLimit)
            } else {
                content = .text(text, truncated: bytes.count > Self.textLimit,
                                note: "This file could not be decoded as keypoint frames. It may be incomplete or use another format.")
            }
        case .text:
            let bytes = try readPrefix(url, limit: Self.textLimit)
            content = .text(String(decoding: bytes.prefix(Self.textLimit), as: UTF8.self),
                            truncated: bytes.count > Self.textLimit, note: nil)
        case .image:
            let bytes = try readPrefix(url, limit: Self.featureLimit)
            if bytes.count <= Self.featureLimit, let thumbnail = thumbnail(bytes) {
                content = .image(thumbnail)
            } else {
                content = .information("Image preview unavailable or exceeds the 8 MiB preview limit.")
            }
        default:
            content = .information("File information is available. Archives and binary model weights are not expanded in this browser.")
        }
        return LocalFilePreview(entry: item, content: content)
    }

    private func readPrefix(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: limit + 1) ?? Data()
    }

    private func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? result as Data : nil
    }

    private func resolvedURL(path: String) throws -> URL {
        guard !path.hasPrefix("/") else { throw BrowserError.outsideDocuments }
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        _ = try relativePath(of: url)
        return url
    }

    private func relativePath(of url: URL) throws -> String {
        // FileManager can return /private/var URLs even when the canonical root
        // uses /var (or vice versa). Normalize both sides before containment and
        // compare components so similarly named sibling directories cannot pass.
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let rootComponents = root.pathComponents
        guard components.starts(with: rootComponents) else { throw BrowserError.outsideDocuments }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func entry(at url: URL) throws -> LocalFileEntry? {
        let values = try url.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true,
              values.isDirectory == true || values.isRegularFile == true else { return nil }
        let path = try relativePath(of: url)
        guard !path.isEmpty else { return nil }
        return LocalFileEntry(path: path,
                              name: url.lastPathComponent, isDirectory: values.isDirectory == true,
                              size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate)
    }

    private func comesBefore(_ left: LocalFileEntry, _ right: LocalFileEntry) -> Bool {
        if left.isDirectory != right.isDirectory { return left.isDirectory }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}
