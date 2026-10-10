import SwiftUI
import AppKit

/// Right hand details list, mirroring the 7-Zip File Manager item list.
/// Shows the direct children of the current folder with the familiar columns,
/// sortable by clicking headers, with a Windows-style context menu.
struct DetailsListView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = DetailsTableView()
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .default
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11.0, *) { table.style = .inset }
        table.contextMenuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.buildContextMenu(row: row)
        }

        for column in DetailsColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.defaultWidth
            tableColumn.minWidth = 44
            tableColumn.headerCell.alignment = Self.cellAlignment(for: column)
            if Self.isSortable(column) {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            }
            table.addTableColumn(tableColumn)
        }

        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.target = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.tableView = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.tableView else { return }

        // Keep column headers and visibility in sync with language and model.
        for column in table.tableColumns {
            column.title = DetailsColumn(rawValue: column.identifier.rawValue)?.title ?? column.title
            if let type = DetailsColumn(rawValue: column.identifier.rawValue) {
                column.isHidden = !model.visibleColumns.contains(type)
            }
        }

        let signature = "\(model.archiveInfo?.url.path ?? "")|\(model.currentFolder)|\(model.flatView)|\(model.sort.key.rawValue)|\(model.sort.ascending)|\(model.detailsRevision)"
        if context.coordinator.signature != signature || context.coordinator.itemCount != model.details.count {
            context.coordinator.signature = signature
            context.coordinator.itemCount = model.details.count
            table.reloadData()
        }
        context.coordinator.syncSelection()
    }

    static func isSortable(_ column: DetailsColumn) -> Bool {
        switch column {
        case .name, .size, .packed, .type, .modified: return true
        case .attributes, .crc, .method, .encrypted: return false
        }
    }

    static func cellAlignment(for column: DetailsColumn) -> NSTextAlignment {
        if column.isRightAligned { return .right }
        if column.isCentered { return .center }
        return .left
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DetailsListView
        weak var tableView: NSTableView?
        var signature = ""
        var itemCount = -1
        private var isSyncing = false

        init(_ parent: DetailsListView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.model.details.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.model.details.count, let id = tableColumn?.identifier.rawValue else { return nil }
            let node = parent.model.details[row]
            let entry = node.entry
            let cell = makeCell(tableView, id: id)

            switch id {
            case DetailsColumn.name.rawValue:
                cell.textField?.stringValue = node.name
                cell.imageView?.image = NSImage(
                    systemSymbolName: node.isDirectory ? "folder" : "doc",
                    accessibilityDescription: nil
                )
            case DetailsColumn.size.rawValue:
                cell.textField?.stringValue = node.isDirectory ? "" : Format.bytes(entry?.size)
            case DetailsColumn.packed.rawValue:
                cell.textField?.stringValue = node.isDirectory ? "" : Format.bytes(entry?.packedSize)
            case DetailsColumn.type.rawValue:
                cell.textField?.stringValue = node.typeDescription
            case DetailsColumn.modified.rawValue:
                cell.textField?.stringValue = Format.date(entry?.modified)
            case DetailsColumn.attributes.rawValue:
                cell.textField?.stringValue = entry.map(Format.attributes) ?? (node.isDirectory ? "D" : "A")
            case DetailsColumn.crc.rawValue:
                cell.textField?.stringValue = entry?.crc ?? ""
            case DetailsColumn.method.rawValue:
                cell.textField?.stringValue = entry?.method ?? ""
            case DetailsColumn.encrypted.rawValue:
                cell.textField?.stringValue = (entry?.encrypted ?? false) ? "+" : ""
            default:
                break
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let table = tableView else { return }
            var selected = Set<String>()
            for row in table.selectedRowIndexes where row < parent.model.details.count {
                selected.insert(parent.model.details[row].path)
            }
            parent.model.selection = selected
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            parent.model.applyColumnSort(id: key, ascending: descriptor.ascending)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table = tableView else { return }
            let row = table.clickedRow
            guard row >= 0, row < parent.model.details.count else { return }
            parent.model.activate(parent.model.details[row])
        }

        func syncSelection() {
            guard let table = tableView else { return }
            var indexes = IndexSet()
            for (row, node) in parent.model.details.enumerated() where parent.model.selection.contains(node.path) {
                indexes.insert(row)
            }
            if indexes != table.selectedRowIndexes {
                isSyncing = true
                table.selectRowIndexes(indexes, byExtendingSelection: false)
                isSyncing = false
            }
        }

        // MARK: - Context menu

        func buildContextMenu(row: Int) -> NSMenu? {
            let menu = NSMenu()
            let model = parent.model

            guard row >= 0, row < model.details.count else {
                addItem(menu, L("Create Folder"), .createFolder, enabled: model.hasArchive)
                addItem(menu, L("Create File"), .createFile, enabled: model.hasArchive)
                menu.addItem(.separator())
                addItem(menu, L("Select All"), .selectAll, enabled: !model.details.isEmpty)
                addItem(menu, L("Deselect All"), .deselectAll, enabled: !model.selection.isEmpty)
                addItem(menu, L("Invert Selection"), .invertSelection, enabled: !model.details.isEmpty)
                menu.addItem(.separator())
                addItem(menu, L("Refresh"), .refresh, enabled: model.hasArchive)
                return menu
            }

            let node = model.details[row]
            let single = model.selection.count == 1

            if node.isDirectory {
                addItem(menu, L("Open"), .open, enabled: true)
            } else {
                addItem(menu, L("Open"), .open, enabled: true)
                addItem(menu, L("Open Outside"), .openOutside, enabled: true)
                if isArchive(node) {
                    addItem(menu, L("Open Inside"), .openInside, enabled: true)
                }
                addItem(menu, L("View"), .view, enabled: true)
                addItem(menu, L("Edit"), .edit, enabled: true)
            }

            menu.addItem(.separator())
            addItem(menu, L("Extract…"), .extractSelected, enabled: !model.selection.isEmpty)
            addItem(menu, L("Copy To…"), .copyTo, enabled: !model.selection.isEmpty)
            addItem(menu, L("Move To…"), .moveTo, enabled: !model.selection.isEmpty)
            menu.addItem(.separator())
            addItem(menu, L("Rename"), .rename, enabled: single)
            addItem(menu, L("Delete"), .delete, enabled: !model.selection.isEmpty)
            menu.addItem(.separator())
            addItem(menu, L("Properties"), .properties, enabled: single)

            return menu
        }

        private func isArchive(_ node: ArchiveTreeNode) -> Bool {
            ArchiveTypes.extensions.contains((node.name as NSString).pathExtension.lowercased())
        }

        private func addItem(_ menu: NSMenu, _ title: String, _ action: MenuAction, enabled: Bool) {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = action.rawValue
            item.isEnabled = enabled
            menu.addItem(item)
        }

        @objc func performMenuAction(_ sender: NSMenuItem) {
            guard let action = MenuAction(rawValue: sender.tag) else { return }
            let model = parent.model
            let nodes = model.selectedNodes
            let node = nodes.first

            switch action {
            case .open:
                if let node { model.activate(node) }
            case .openInside:
                if let node { model.openInside(node) }
            case .openOutside:
                if let node { model.openOutside(node) }
            case .view:
                if let node { model.viewFile(node) }
            case .edit:
                if let node { model.editFile(node) }
            case .extractSelected:
                model.beginExtractSelected()
            case .copyTo:
                model.copySelectedTo()
            case .moveTo:
                model.moveSelectedTo()
            case .rename:
                if let node { model.beginRename(node) }
            case .delete:
                model.deleteSelected()
            case .properties:
                if let node { model.showProperties(node) }
            case .createFolder:
                model.beginCreate(.folder)
            case .createFile:
                model.beginCreate(.file)
            case .selectAll:
                model.selectAllItems()
            case .deselectAll:
                model.deselectAllItems()
            case .invertSelection:
                model.invertSelection()
            case .refresh:
                model.refresh()
            }
        }

        private func makeCell(_ table: NSTableView, id: String) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("cell-\(id)")
            if let reused = table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                return reused
            }

            let cell = NSTableCellView()
            cell.identifier = identifier

            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            text.font = .systemFont(ofSize: 12)
            cell.textField = text

            if id == DetailsColumn.name.rawValue {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.addSubview(text)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                cell.addSubview(text)
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                if id == DetailsColumn.size.rawValue || id == DetailsColumn.packed.rawValue {
                    text.alignment = .right
                    text.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                }
            }
            return cell
        }
    }
}

/// Context menu actions shared between the table and the menu bar.
enum MenuAction: Int {
    case open
    case openInside
    case openOutside
    case view
    case edit
    case extractSelected
    case copyTo
    case moveTo
    case rename
    case delete
    case properties
    case createFolder
    case createFile
    case selectAll
    case deselectAll
    case invertSelection
    case refresh
}

/// `NSTableView` subclass that selects the row under the pointer before showing
/// its context menu, so right-clicking a row acts on that row.
final class DetailsTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else {
            deselectAll(nil)
        }
        return contextMenuProvider?(row)
    }
}
