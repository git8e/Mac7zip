import SwiftUI
import AppKit

/// Left hand folder tree, mirroring the 7-Zip File Manager folder panel.
/// Shows a single archive root plus all folders inside it.
struct FolderTreeView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = nil
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.allowsMultipleSelection = false
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 12

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.title = L("Folder")
        column.width = 220
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        context.coordinator.outlineView = outline
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let outline = context.coordinator.outlineView else { return }

        let signature = "\(model.archiveInfo?.url.path ?? "")|\(model.archiveInfo?.entries.count ?? 0)"
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            context.coordinator.rebuildIndex()
            outline.reloadData()
            if let root = model.treeRoot {
                outline.expandItem(root)
                for child in root.children where !child.children.isEmpty {
                    outline.expandItem(child)
                }
            }
        }
        context.coordinator.syncSelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FolderTreeView
        weak var outlineView: NSOutlineView?
        var signature = ""
        private var index: [String: ArchiveTreeNode] = [:]
        private var isSyncing = false

        init(_ parent: FolderTreeView) {
            self.parent = parent
        }

        func rebuildIndex() {
            index.removeAll()
            if let root = parent.model.treeRoot {
                collect(root)
            }
        }

        private func collect(_ node: ArchiveTreeNode) {
            index[node.path] = node
            node.children.forEach(collect)
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard parent.model.treeRoot != nil else { return 0 }
            if let node = item as? ArchiveTreeNode { return node.children.count }
            return 1  // the single archive root
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let node = item as? ArchiveTreeNode { return node.children[index] }
            return parent.model.treeRoot as Any
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? ArchiveTreeNode)?.children.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? ArchiveTreeNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("folderCell")
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier

                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                let text = NSTextField(labelWithString: "")
                text.translatesAutoresizingMaskIntoConstraints = false
                text.lineBreakMode = .byTruncatingMiddle
                text.font = .systemFont(ofSize: 12)

                cell.addSubview(image)
                cell.addSubview(text)
                cell.imageView = image
                cell.textField = text

                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = node.name
            let symbol = node.path.isEmpty ? "archivebox" : "folder"
            cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return cell
        }

        // MARK: Delegate

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let outline = outlineView else { return }
            let row = outline.selectedRow
            guard row >= 0, let node = outline.item(atRow: row) as? ArchiveTreeNode else { return }
            if node.path != parent.model.currentFolder {
                parent.model.enter(folder: node.path)
            }
        }

        func syncSelection() {
            guard let outline = outlineView, let node = index[parent.model.currentFolder] else { return }
            let row = outline.row(forItem: node)
            guard row >= 0, outline.selectedRow != row else { return }
            isSyncing = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSyncing = false
        }
    }
}
