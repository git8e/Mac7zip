import Foundation

// MARK: - Sorting (mirrors the Windows "View" menu arrange options)

enum SortKey: String, CaseIterable, Identifiable {
    case name
    case type
    case date
    case size
    case unsorted

    var id: String { rawValue }

    /// The details-list column this key sorts by, if any.
    var columnID: String? {
        switch self {
        case .name, .unsorted: return "name"
        case .type: return "type"
        case .date: return "modified"
        case .size: return "size"
        }
    }

    var title: String {
        switch self {
        case .name: return L("Name")
        case .type: return L("Type")
        case .date: return L("Date")
        case .size: return L("Size")
        case .unsorted: return L("Unsorted")
        }
    }
}

struct SortState: Equatable {
    var key: SortKey = .name
    var ascending = true
}

extension ArchiveTreeNode {
    /// Every descendant (folders and files) in depth-first order.
    var allDescendants: [ArchiveTreeNode] {
        children + children.flatMap { $0.allDescendants }
    }

    /// Extension used for the "Type" sort and for the Type column.
    var typeDescription: String {
        if isDirectory { return L("Folder") }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? L("File") : ext.uppercased()
    }
}

enum ArchiveSorter {
    /// Sorts nodes for the details list. Folders are always kept above files,
    /// matching the Windows File Manager, then the chosen key decides order.
    static func sorted(_ nodes: [ArchiveTreeNode], by sort: SortState) -> [ArchiveTreeNode] {
        guard sort.key != .unsorted else { return nodes }
        let ascending = sort.ascending
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result = compare(a, b, by: sort.key)
            if result == .orderedSame {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare(_ a: ArchiveTreeNode, _ b: ArchiveTreeNode, by key: SortKey) -> ComparisonResult {
        switch key {
        case .name, .unsorted:
            return compareNames(a, b)
        case .type:
            let result = a.typeDescription.localizedCaseInsensitiveCompare(b.typeDescription)
            return result == .orderedSame ? compareNames(a, b) : result
        case .date:
            return compareOptional(a.entry?.modified, b.entry?.modified)
        case .size:
            return compareOptional(a.entry?.size, b.entry?.size)
        }
    }

    private static func compareNames(_ a: ArchiveTreeNode, _ b: ArchiveTreeNode) -> ComparisonResult {
        let result = a.name.localizedCaseInsensitiveCompare(b.name)
        return result == .orderedSame ? (a.name < b.name ? .orderedAscending : .orderedSame) : result
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r { return .orderedSame }
            return l < r ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }
}

// MARK: - New entry kind

enum CreateEntryKind {
    case folder
    case file

    var title: String {
        switch self {
        case .folder: return L("Create Folder")
        case .file: return L("Create File")
        }
    }

    var placeholder: String {
        switch self {
        case .folder: return L("New Folder")
        case .file: return L("New File.txt")
        }
    }
}

// MARK: - View modes (Windows "View" menu)

enum ViewMode: String, CaseIterable, Identifiable {
    case icons
    case list
    case details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icons: return L("Icons")
        case .list: return L("List")
        case .details: return L("Details")
        }
    }

    var systemImage: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .details: return "list.bullet.rectangle"
        }
    }
}

/// `UserDefaults`-backed view layout preferences, so the chosen view mode and
/// tree-panel visibility survive relaunches like Windows 7-Zip.
enum ViewPreferences {
    static var viewMode: ViewMode {
        get { ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .details }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode") }
    }

    static var showTreePanel: Bool {
        get {
            if UserDefaults.standard.object(forKey: "showTreePanel") == nil { return true }
            return UserDefaults.standard.bool(forKey: "showTreePanel")
        }
        set { UserDefaults.standard.set(newValue, forKey: "showTreePanel") }
    }

    static var flatView: Bool {
        get { UserDefaults.standard.bool(forKey: "flatView") }
        set { UserDefaults.standard.set(newValue, forKey: "flatView") }
    }
}

// MARK: - Details columns (mirrors the Windows column set)

enum DetailsColumn: String, CaseIterable, Identifiable {
    case name
    case size
    case packed
    case type
    case modified
    case attributes
    case crc
    case method
    case encrypted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return L("Name")
        case .size: return L("Size")
        case .packed: return L("Packed")
        case .type: return L("Type")
        case .modified: return L("Modified")
        case .attributes: return L("Attributes")
        case .crc: return "CRC"
        case .method: return L("Method")
        case .encrypted: return L("Encrypted")
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 260
        case .size, .packed: return 90
        case .type: return 90
        case .modified: return 140
        case .attributes: return 120
        case .crc: return 90
        case .method: return 90
        case .encrypted: return 60
        }
    }

    var isRightAligned: Bool { self == .size || self == .packed }
    var isCentered: Bool { self == .encrypted }

    /// Columns shown by default (the Windows "Details" view defaults).
    var shownByDefault: Bool {
        switch self {
        case .type, .crc, .method, .encrypted: return false
        default: return true
        }
    }
}
