import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "" }
        if value == 0 { return "0" }
        return byteFormatter.string(fromByteCount: Int64(value))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func date(_ value: Date?) -> String {
        guard let value else { return "" }
        return dateFormatter.string(from: value)
    }

    /// Human readable attributes similar to 7-Zip: "D" for folder, plus the
    /// leading letter of each POSIX flag group (e.g. "D drwxr-xr-x").
    static func attributes(_ entry: ArchiveEntry) -> String {
        guard let attributes = entry.attributes else {
            return entry.isDirectory ? "D" : "A"
        }
        return attributes
    }
}
