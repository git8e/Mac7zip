import SwiftUI
import AppKit

/// Right hand details list, mirroring the 7-Zip File Manager item list.
/// Shows the direct children of the current folder with the familiar columns.
struct DetailsListView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .default
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11.0, *) { table.style = .inset }

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("name", 260, .left),
            ("size", 90, .right),
            ("packed", 90, .right),
            ("modified", 140, .left),
            ("attributes", 120, .left),
            ("crc", 90, .left),
            ("method", 90, .left),
            ("encrypted", 50, .center),
        ]
        for (id, width, alignment) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = Self.localizedTitle(for: id)
            column.width = width
            column.minWidth = 44
            column.headerCell.alignment = alignment
            table.addTableColumn(column)
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

        // Keep column headers in sync with the current language.
        for column in table.tableColumns {
            column.title = Self.localizedTitle(for: column.identifier.rawValue)
        }

        let signature = "\(model.archiveInfo?.url.path ?? "")|\(model.currentFolder)"
        if context.coordinator.signature != signature || context.coordinator.itemCount != model.details.count {
            context.coordinator.signature = signature
            context.coordinator.itemCount = model.details.count
            table.reloadData()
        }
        context.coordinator.syncSelection()
    }

    static func localizedTitle(for id: String) -> String {
        switch id {
        case "name": return L("Name")
        case "size": return L("Size")
        case "packed": return L("Packed")
        case "modified": return L("Modified")
        case "attributes": return L("Attributes")
        case "crc": return "CRC"
        case "method": return L("Method")
        case "encrypted": return L("Encrypted")
        default: return ""
        }
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
            case "name":
                cell.textField?.stringValue = node.name
                cell.imageView?.image = NSImage(
                    systemSymbolName: node.isDirectory ? "folder" : "doc",
                    accessibilityDescription: nil
                )
            case "size":
                cell.textField?.stringValue = node.isDirectory ? "" : Format.bytes(entry?.size)
            case "packed":
                cell.textField?.stringValue = node.isDirectory ? "" : Format.bytes(entry?.packedSize)
            case "modified":
                cell.textField?.stringValue = Format.date(entry?.modified)
            case "attributes":
                cell.textField?.stringValue = entry.map(Format.attributes) ?? (node.isDirectory ? "D" : "A")
            case "crc":
                cell.textField?.stringValue = entry?.crc ?? ""
            case "method":
                cell.textField?.stringValue = entry?.method ?? ""
            case "encrypted":
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

            if id == "name" {
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
                if id == "size" || id == "packed" {
                    text.alignment = .right
                    text.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                }
            }
            return cell
        }
    }
}
