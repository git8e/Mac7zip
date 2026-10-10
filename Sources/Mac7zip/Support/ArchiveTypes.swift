import UniformTypeIdentifiers

enum ArchiveTypes {
    /// Extensions 7-Zip can usually open. Used to filter the open panel and to
    /// declare the document types in Info.plist.
    static let extensions: [String] = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "lzma", "lz", "z", "zst", "cab", "iso", "wim",
        "jar", "apk", "aes", "rpm", "deb", "cpio", "arj", "lzh", "chm",
        "msi", "nsis", "udf", "squashfs", "dmg", "img", "001", "7zip", "exe"
    ]

    static var contentTypes: [UTType] {
        var types: [UTType] = []
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    static func format(forExtension ext: String) -> ArchiveFormat? {
        switch ext.lowercased() {
        case "7z", "7zip": return .sevenZip
        case "zip": return .zip
        case "tar": return .tar
        case "gz", "tgz": return .gzip
        case "bz2", "tbz", "tbz2": return .bzip2
        case "xz", "txz": return .xz
        case "wim": return .wim
        default: return nil
        }
    }
}
