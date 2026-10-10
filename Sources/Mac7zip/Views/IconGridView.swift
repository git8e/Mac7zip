import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Icon view for the archive contents, mirroring the Windows 7-Zip "Icons"
/// view mode: a grid of icon + name items inside a scroll view.
struct IconGridView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 104, height: 84)
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10

        let collection = IconCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.controlBackgroundColor]
        collection.register(IconItemView.self, forItemWithIdentifier: IconItemView.identifier)
        collection.contextMenuProvider = { [weak coordinator = context.coordinator] indexPath in
            coordinator?.buildContextMenu(indexPath: indexPath)
        }

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(doubleClick)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.collectionView = collection
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let collection = context.coordinator.collectionView else { return }

        let signature = "\(model.archiveInfo?.url.path ?? "")|\(model.currentFolder)|\(model.flatView)|\(model.sort.key.rawValue)|\(model.sort.ascending)|\(model.detailsRevision)"
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            collection.reloadData()
        }
        context.coordinator.syncSelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: IconGridView
        weak var collectionView: NSCollectionView?
        var signature = ""
        private var isSyncing = false

        init(_ parent: IconGridView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.model.details.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: IconItemView.identifier, for: indexPath)
            guard let iconItem = item as? IconItemView, indexPath.item < parent.model.details.count else {
                return item
            }
            iconItem.configure(with: parent.model.details[indexPath.item])
            return iconItem
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !isSyncing else { return }
            parent.model.selection = selectedPaths()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            guard !isSyncing else { return }
            parent.model.selection = selectedPaths()
        }

        /// File promises make dragging items out of the window extract them.
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < parent.model.details.count,
                  let engine = parent.model.engine,
                  let archive = parent.model.archiveInfo?.url else { return nil }
            return ArchiveItemPasteboard.writer(
                for: parent.model.details[indexPath.item],
                engine: engine,
                archive: archive,
                password: parent.model.lastPassword
            )
        }

        private func selectedPaths() -> Set<String> {
            guard let collectionView else { return [] }
            var paths = Set<String>()
            for indexPath in collectionView.selectionIndexPaths where indexPath.item < parent.model.details.count {
                paths.insert(parent.model.details[indexPath.item].path)
            }
            return paths
        }

        func syncSelection() {
            guard let collectionView else { return }
            var indexes = Set<IndexPath>()
            for (row, node) in parent.model.details.enumerated() where parent.model.selection.contains(node.path) {
                indexes.insert(IndexPath(item: row, section: 0))
            }
            if indexes != collectionView.selectionIndexPaths {
                isSyncing = true
                collectionView.selectionIndexPaths = indexes
                isSyncing = false
            }
        }

        @objc func doubleClicked(_ recognizer: NSClickGestureRecognizer) {
            guard let collectionView else { return }
            let point = recognizer.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  indexPath.item < parent.model.details.count else { return }
            parent.model.activate(parent.model.details[indexPath.item])
        }

        // MARK: - Context menu

        func buildContextMenu(indexPath: IndexPath?) -> NSMenu? {
            let menu = NSMenu()
            let model = parent.model

            guard let indexPath, indexPath.item < model.details.count else {
                IconMenuBuilder.add(menu, L("Create Folder"), .createFolder, target: self, enabled: model.hasArchive)
                IconMenuBuilder.add(menu, L("Create File"), .createFile, target: self, enabled: model.hasArchive)
                menu.addItem(.separator())
                IconMenuBuilder.add(menu, L("Select All"), .selectAll, target: self, enabled: !model.details.isEmpty)
                IconMenuBuilder.add(menu, L("Deselect All"), .deselectAll, target: self, enabled: !model.selection.isEmpty)
                IconMenuBuilder.add(menu, L("Invert Selection"), .invertSelection, target: self, enabled: !model.details.isEmpty)
                menu.addItem(.separator())
                IconMenuBuilder.add(menu, L("Refresh"), .refresh, target: self, enabled: model.hasArchive)
                return menu
            }

            let node = model.details[indexPath.item]
            let single = model.selection.count == 1

            IconMenuBuilder.add(menu, L("Open"), .open, target: self, enabled: true)
            if !node.isDirectory {
                IconMenuBuilder.add(menu, L("Open Outside"), .openOutside, target: self, enabled: true)
                if model.isArchiveItem(node) {
                    IconMenuBuilder.add(menu, L("Open Inside"), .openInside, target: self, enabled: true)
                }
                IconMenuBuilder.add(menu, L("View"), .view, target: self, enabled: true)
                IconMenuBuilder.add(menu, L("Edit"), .edit, target: self, enabled: true)
            }
            menu.addItem(.separator())
            IconMenuBuilder.add(menu, L("Extract…"), .extractSelected, target: self, enabled: !model.selection.isEmpty)
            IconMenuBuilder.add(menu, L("Copy To…"), .copyTo, target: self, enabled: !model.selection.isEmpty)
            IconMenuBuilder.add(menu, L("Move To…"), .moveTo, target: self, enabled: !model.selection.isEmpty)
            menu.addItem(.separator())
            IconMenuBuilder.add(menu, L("Rename"), .rename, target: self, enabled: single)
            IconMenuBuilder.add(menu, L("Delete"), .delete, target: self, enabled: !model.selection.isEmpty)
            menu.addItem(.separator())
            IconMenuBuilder.add(menu, L("Properties"), .properties, target: self, enabled: single)
            return menu
        }

        @objc func performMenuAction(_ sender: NSMenuItem) {
            guard let action = MenuAction(rawValue: sender.tag) else { return }
            let model = parent.model
            let node = model.selectedNodes.first

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
    }
}

/// Small helper so both list and icon context menus build items the same way.
enum IconMenuBuilder {
    static func add(_ menu: NSMenu, _ title: String, _ action: MenuAction, target: AnyObject, enabled: Bool) {
        let item = NSMenuItem(title: title, action: #selector(IconGridView.Coordinator.performMenuAction(_:)), keyEquivalent: "")
        item.target = target
        item.tag = action.rawValue
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

/// A single icon-grid item: a large icon with a wrapped, centred name below.
final class IconItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IconItemView")

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.alignment = .center
        nameField.font = .systemFont(ofSize: 11)
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 2
        nameField.cell?.wraps = true
        nameField.cell?.isScrollable = false

        view.addSubview(iconView)
        view.addSubview(nameField)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            nameField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
        ])
    }

    func configure(with node: ArchiveTreeNode) {
        let name = node.isDirectory ? "folder.fill" : symbolName(for: node)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        iconView.image = image
        iconView.contentTintColor = node.isDirectory ? .systemBlue : .secondaryLabelColor
        nameField.stringValue = node.name
        nameField.toolTip = node.path
    }

    private func symbolName(for node: ArchiveTreeNode) -> String {
        if node.entry?.encrypted == true { return "lock.doc" }
        return "doc"
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        view.layer?.cornerRadius = 6
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
        nameField.textColor = isSelected ? .selectedContentBackgroundColor : .labelColor
    }
}

/// Collection view that selects the item under the pointer before showing its
/// context menu, and reports right-clicks with no item as a `nil` index path.
final class IconCollectionView: NSCollectionView {
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        if let indexPath {
            if !selectionIndexPaths.contains(indexPath) {
                selectionIndexPaths = [indexPath]
            }
        } else {
            selectionIndexPaths = []
        }
        return contextMenuProvider?(indexPath)
    }
}
