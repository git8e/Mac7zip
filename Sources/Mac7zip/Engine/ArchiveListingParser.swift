import Foundation

/// Parses the technical listing produced by `7zz l -slt`.
///
/// The output is a sequence of blank-line separated blocks. The block that
/// contains `Type = ...` describes the archive itself; every other block that
/// contains `Path = ...` describes one entry.
enum ArchiveListingParser {
    static func parse(_ text: String, url: URL) -> ArchiveInfo {
        var info = ArchiveInfo(url: url)

        for block in blocks(in: text) {
            let fields = keyValues(in: block)
            guard let path = fields["Path"], !path.isEmpty else { continue }

            if fields["Type"] != nil {
                info.format = fields["Type"] ?? ""
                info.method = nonEmpty(fields["Method"])
                info.solid = fields["Solid"] == "+"
                info.physicalSize = UInt64(fields["Physical Size"] ?? "")
                info.headersSize = UInt64(fields["Headers Size"] ?? "")
                info.blocks = Int(fields["Blocks"] ?? "")
            } else {
                if let entry = makeEntry(fields) {
                    info.entries.append(entry)
                }
            }
        }
        return info
    }

    private static func makeEntry(_ fields: [String: String]) -> ArchiveEntry? {
        guard let path = fields["Path"], !path.isEmpty else { return nil }
        let attributes = fields["Attributes"] ?? ""
        let isDirectory = attributes.hasPrefix("D") || fields["Folder"] == "+" || path.hasSuffix("/")

        return ArchiveEntry(
            path: path,
            isDirectory: isDirectory,
            size: UInt64(fields["Size"] ?? ""),
            packedSize: UInt64(fields["Packed Size"] ?? ""),
            modified: parseDate(fields["Modified"]),
            crc: nonEmpty(fields["CRC"]),
            method: nonEmpty(fields["Method"]),
            encrypted: fields["Encrypted"] == "+",
            attributes: nonEmpty(attributes)
        )
    }

    private static func blocks(in text: String) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func keyValues(in block: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in block {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equals)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            result[key] = value
        }
        return result
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, value.count >= 19 else { return nil }
        return dateFormatter.date(from: String(value.prefix(19)))
    }
}
