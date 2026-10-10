import Foundation

// MARK: - Archive entry

/// One item (file or folder) inside an archive.
struct ArchiveEntry: Identifiable, Hashable {
    var id: String { path }

    /// Full path inside the archive, using "/" separators (as printed by 7-Zip).
    let path: String
    let isDirectory: Bool
    let size: UInt64?
    let packedSize: UInt64?
    let modified: Date?
    let crc: String?
    let method: String?
    let encrypted: Bool
    let attributes: String?

    var name: String { ArchiveEntry.lastComponent(of: path) }

    static func lastComponent(of path: String) -> String {
        var trimmed = path
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let idx = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: idx)...])
    }

    /// The path of the parent folder ("" for top level items).
    var parentPath: String {
        var trimmed = path
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let idx = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[trimmed.startIndex..<idx])
    }
}

// MARK: - Archive summary

struct ArchiveInfo {
    let url: URL
    var format: String = ""
    var method: String?
    var solid: Bool = false
    var physicalSize: UInt64?
    var headersSize: UInt64?
    var blocks: Int?
    var entries: [ArchiveEntry] = []

    var fileCount: Int { entries.lazy.filter { !$0.isDirectory }.count }
    var folderCount: Int { entries.lazy.filter { $0.isDirectory }.count }
    var totalSize: UInt64 { entries.reduce(0) { $0 + ($1.size ?? 0) } }
}

// MARK: - Tree

/// Reference-type node used directly as an `NSOutlineView` item.
final class ArchiveTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var entry: ArchiveEntry?
    var children: [ArchiveTreeNode]

    init(path: String, name: String, isDirectory: Bool, entry: ArchiveEntry?, children: [ArchiveTreeNode]) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.entry = entry
        self.children = children
    }

    static func == (lhs: ArchiveTreeNode, rhs: ArchiveTreeNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }
}

enum ArchiveTreeBuilder {
    static func build(from entries: [ArchiveEntry]) -> [ArchiveTreeNode] {
        let root = ArchiveTreeNode(path: "", name: "", isDirectory: true, entry: nil, children: [])
        var index: [String: ArchiveTreeNode] = ["": root]

        for entry in entries {
            let comps = entry.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !comps.isEmpty else { continue }

            var node = root
            var accumulated: [String] = []
            for (i, comp) in comps.enumerated() {
                accumulated.append(comp)
                let full = accumulated.joined(separator: "/")
                let isLast = (i == comps.count - 1)
                if let existing = index[full] {
                    if isLast { existing.entry = entry }
                    node = existing
                } else {
                    let child = ArchiveTreeNode(
                        path: full,
                        name: comp,
                        isDirectory: isLast ? entry.isDirectory : true,
                        entry: isLast ? entry : nil,
                        children: []
                    )
                    index[full] = child
                    node.children.append(child)
                    node = child
                }
            }
        }

        sortRecursively(root)
        return root.children
    }

    /// Directory-only tree used for the left hand folder panel.
    static func directories(from entries: [ArchiveEntry]) -> [ArchiveTreeNode] {
        prune(build(from: entries))
    }

    private static func prune(_ nodes: [ArchiveTreeNode]) -> [ArchiveTreeNode] {
        nodes.compactMap { node in
            guard node.isDirectory else { return nil }
            return ArchiveTreeNode(
                path: node.path,
                name: node.name,
                isDirectory: true,
                entry: node.entry,
                children: prune(node.children)
            )
        }
    }

    /// Keep folders before files, then sort case-insensitively by name so the
    /// outline and the details list stay stable and predictable.
    private static func sortRecursively(_ node: ArchiveTreeNode) {
        node.children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result = a.name.localizedCaseInsensitiveCompare(b.name)
            if result == .orderedSame { return a.name < b.name }
            return result == .orderedAscending
        }
        node.children.forEach(sortRecursively)
    }
}

// MARK: - Options

enum OverwriteMode: String, CaseIterable, Identifiable {
    case overwrite
    case skip
    case rename
    case renameExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite: return L("Overwrite existing files")
        case .skip: return L("Skip existing files")
        case .rename: return L("Auto rename new files")
        case .renameExisting: return L("Auto rename existing files")
        }
    }

    var switchValue: String {
        switch self {
        case .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .rename: return "-aou"
        case .renameExisting: return "-aot"
        }
    }
}

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZip = "7z"
    case zip
    case tar
    case gzip
    case bzip2
    case xz
    case wim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gzip (gz)"
        case .bzip2: return "bzip2 (bz2)"
        case .xz: return "xz"
        case .wim: return "wim"
        }
    }

    var typeSwitch: String {
        switch self {
        case .sevenZip: return "-t7z"
        case .zip: return "-tzip"
        case .tar: return "-ttar"
        case .gzip: return "-tgzip"
        case .bzip2: return "-tbzip2"
        case .xz: return "-txz"
        case .wim: return "-twim"
        }
    }

    var fileExtension: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gz"
        case .bzip2: return "bz2"
        case .xz: return "xz"
        case .wim: return "wim"
        }
    }

    var supportsPassword: Bool { self == .sevenZip || self == .zip }
    var supportsEncryptNames: Bool { self == .sevenZip }
    var supportsSolid: Bool { self == .sevenZip || self == .tar }
    var supportsMultiVolume: Bool { self == .sevenZip || self == .zip }
    var allowsMultipleSources: Bool { !(self == .gzip || self == .bzip2 || self == .xz) }
}

enum CompressionLevel: Int, CaseIterable, Identifiable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .store: return L("Store")
        case .fastest: return L("Fastest")
        case .fast: return L("Fast")
        case .normal: return L("Normal")
        case .maximum: return L("Maximum")
        case .ultra: return L("Ultra")
        }
    }

    var switchValue: String { "-mx\(rawValue)" }
}

/// Update modes shown in the Windows "Add to Archive" dialog. The concrete
/// `-u` strings are the action sets defined by the engine (see
/// `CPP/7zip/UI/Common/UpdateAction.cpp`), in `pqrxyzw` state order.
enum UpdateMode: String, CaseIterable, Identifiable {
    case addAndReplace
    case updateAndAdd
    case freshen
    case synchronize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addAndReplace: return L("Add and replace files")
        case .updateAndAdd: return L("Update and add files")
        case .freshen: return L("Freshen existing files")
        case .synchronize: return L("Synchronize files")
        }
    }

    /// `nil` means the engine default (add and replace).
    var switchValue: String? {
        switch self {
        case .addAndReplace: return nil
        case .updateAndAdd: return "-up1q1r2x1y2z1w2"
        case .freshen: return "-up1q1r0x1y2z1w2"
        case .synchronize: return "-up1q0r2x1y2z1w2"
        }
    }
}

/// How source paths are stored (Windows "Path mode"). Mirrors
/// `NWildcard::ECensorPathMode`.
enum PathMode: String, CaseIterable, Identifiable {
    case relative
    case full
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relative: return L("Relative paths")
        case .full: return L("Full paths")
        case .absolute: return L("Absolute paths")
        }
    }

    /// Switch used by the `a` command; `nil` is the engine default.
    var addSwitch: String? {
        switch self {
        case .relative: return nil
        case .full: return "-spf2"
        case .absolute: return "-spf"
        }
    }
}

/// CPU thread count for compression (`-mmt`).
enum ThreadOption: String, CaseIterable, Identifiable {
    case auto
    case one
    case two
    case four
    case eight
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return L("Auto")
        case .one: return "1"
        case .two: return "2"
        case .four: return "4"
        case .eight: return "8"
        case .off: return L("Off")
        }
    }

    /// `nil` means "let the engine decide".
    var switchValue: String? {
        switch self {
        case .auto: return nil
        case .one: return "-mmt=1"
        case .two: return "-mmt=2"
        case .four: return "-mmt=4"
        case .eight: return "-mmt=8"
        case .off: return "-mmt=off"
        }
    }
}

struct CreateOptions {
    var format: ArchiveFormat = .sevenZip
    var level: CompressionLevel = .normal
    var password: String?
    var encryptFileNames: Bool = false
    var solid: Bool = true
    var volumeSize: String?
    var method: String?
    var dictionary: String?
    var threads: ThreadOption = .auto
    var updateMode: UpdateMode = .addAndReplace
    var pathMode: PathMode = .relative
    var deleteAfterCompression: Bool = false

    /// Extra switches derived from the advanced options, in a stable order so
    /// the behaviour is easy to test and matches the Windows dialog.
    var extraArguments: [String] {
        var arguments: [String] = []
        if let method, !method.isEmpty {
            arguments.append("-m0=" + method)
        }
        if let dictionary, !dictionary.isEmpty, acceptsDictionary {
            arguments.append("-md=" + dictionary)
        }
        if let threads = threads.switchValue {
            arguments.append(threads)
        }
        if let update = updateMode.switchValue {
            arguments.append(update)
        }
        if let path = pathMode.addSwitch {
            arguments.append(path)
        }
        if deleteAfterCompression {
            arguments.append("-sdel")
        }
        return arguments
    }

    /// The dictionary-size switch (`-md`) only applies to LZMA/LZMA2.
    private var acceptsDictionary: Bool {
        switch format {
        case .sevenZip:
            guard let method else { return true }
            let value = method.lowercased()
            return value == "lzma" || value == "lzma2"
        case .zip:
            return (method?.lowercased() ?? "") == "lzma"
        default:
            return false
        }
    }
}

extension ArchiveFormat {
    /// Compression methods offered in the Add dialog for this format.
    var compressionMethods: [String] {
        switch self {
        case .sevenZip: return ["LZMA2", "LZMA", "PPMd", "BZip2", "Deflate", "Copy"]
        case .zip: return ["Deflate", "Deflate64", "BZip2", "LZMA", "PPMd", "Copy"]
        case .tar, .gzip, .bzip2, .xz, .wim: return []
        }
    }

    /// Dictionary sizes offered for the formats that accept a `-md` switch.
    var dictionarySizes: [String] {
        switch self {
        case .sevenZip, .zip:
            return ["64k", "256k", "1m", "4m", "16m", "64m", "256m", "1g"]
        default:
            return []
        }
    }
}

extension ExtractOptions {
    /// Extra switches derived from the advanced extract options.
    var extraArguments: [String] {
        var arguments: [String] = []
        if eliminateRoot {
            arguments.append("-spe")
        }
        return arguments
    }
}

// MARK: - Progress

struct OperationProgress: Equatable {
    var title: String
    var detail: String = ""
    var processed: Int = 0
    var total: Int = 0

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(processed) / Double(total)))
    }
}

struct TestResult {
    let ok: Bool
    let message: String
    let files: Int
    let size: UInt64
}
