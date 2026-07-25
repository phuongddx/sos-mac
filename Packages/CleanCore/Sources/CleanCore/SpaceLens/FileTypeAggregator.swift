import Foundation

public enum FileCategory: String, Sendable, CaseIterable, Identifiable {
    case documents = "Documents"
    case images = "Images"
    case video = "Video"
    case audio = "Audio"
    case code = "Code"
    case archives = "Archives"
    case applications = "Applications"
    case other = "Other"

    public var id: String { rawValue }
}

public enum FileTypeAggregator {
    private static let extensionMap: [String: FileCategory] = [
        "pdf": .documents, "doc": .documents, "docx": .documents, "txt": .documents,
        "pages": .documents, "rtf": .documents, "key": .documents, "numbers": .documents,
        "xlsx": .documents, "xls": .documents, "ppt": .documents, "pptx": .documents,

        "jpg": .images, "jpeg": .images, "png": .images, "gif": .images, "heic": .images,
        "tiff": .images, "bmp": .images, "svg": .images, "webp": .images,

        "mp4": .video, "mov": .video, "avi": .video, "mkv": .video, "m4v": .video, "hevc": .video,

        "mp3": .audio, "wav": .audio, "aac": .audio, "flac": .audio, "m4a": .audio,

        "swift": .code, "m": .code, "h": .code, "cpp": .code, "c": .code, "py": .code,
        "js": .code, "ts": .code, "java": .code, "go": .code, "rs": .code,
        "json": .code, "yaml": .code, "yml": .code,

        "zip": .archives, "tar": .archives, "gz": .archives, "dmg": .archives,
        "pkg": .archives, "7z": .archives, "rar": .archives,

        "app": .applications
    ]

    public static func category(forPath path: String) -> FileCategory {
        let ext = (path as NSString).pathExtension.lowercased()
        return extensionMap[ext] ?? .other
    }

    public static func aggregate(items: [ScanItem]) -> [FileCategory: Int64] {
        var totals: [FileCategory: Int64] = [:]
        for item in items where item.kind == .file {
            totals[category(forPath: item.path), default: 0] += item.size
        }
        return totals
    }
}
