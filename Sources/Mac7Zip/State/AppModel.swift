import Foundation
import AppKit

struct AlertMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct PasswordPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var onSubmit: (String) -> Void
}

/// Central application state. Mirrors the navigation model of the Windows
/// 7-Zip File Manager: a folder tree, a "current folder" inside the archive,
/// and a details list of that folder's direct children.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine: SevenZipEngine?

    @Published var engineVersion: String?
    @Published var archiveInfo: ArchiveInfo?
    @Published var folderRoots: [ArchiveTreeNode] = []
    @Published var treeRoot: ArchiveTreeNode?
    @Published var details: [ArchiveTreeNode] = []
    @Published var detailsRevision = 0
    @Published var currentFolder: String = ""
    @Published var selection: Set<String> = []
    @Published var statusText: String = L("Ready")
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var progress: OperationProgress?
    @Published var alert: AlertMessage?
    @Published var passwordPrompt: PasswordPrompt?

    // Sheets
    @Published var showAddSheet = false
    @Published var showExtractSheet = false
    @Published var showInfoSheet = false
    @Published var showRenameSheet = false
    @Published var showCreateSheet = false
    @Published var showPropertiesSheet = false

    // View options (mirrors the Windows "View" menu)
    @Published var sort = SortState()
    @Published var flatView = false
    @Published var visibleColumns: Set<DetailsColumn> = Set(DetailsColumn.allCases.filter { $0.shownByDefault })

    // Pending operation inputs
    @Published var addSources: [URL] = []
    @Published var suggestedArchiveURL: URL?
    @Published var pendingExtractItems: [String]?
    @Published var suggestedExtractDestination: URL?
    @Published var renameTarget: ArchiveTreeNode?
    @Published var createKind: CreateEntryKind = .folder
    @Published var propertiesTarget: ArchiveTreeNode?

    private var fullTree: [ArchiveTreeNode] = []
    private var childrenMap: [String: [ArchiveTreeNode]] = [:]
    private var currentTask: Task<Void, Never>?
    private let throttle = ProgressThrottle()

    private init() {
        engine = try? SevenZipEngine.detect()
        if engine == nil {
            statusText = L("7-Zip engine not found")
        }
    }

    // MARK: - Version

    func loadVersionIfNeeded() {
        guard engineVersion == nil, let engine else { return }
        Task { self.engineVersion = await engine.version() }
    }

    // MARK: - Derived

    var hasArchive: Bool { archiveInfo != nil }
    var engineAvailable: Bool { engine != nil }
    var archiveName: String { archiveInfo?.url.lastPathComponent ?? "Mac7Zip" }

    var breadcrumb: [String] {
        currentFolder.isEmpty ? [] : currentFolder.split(separator: "/").map(String.init)
    }

    var selectedEntries: [ArchiveEntry] {
        details.filter { selection.contains($0.path) }.compactMap { $0.entry }
    }

    var selectionSummary: String {
        let items = details.filter { selection.contains($0.path) }
        guard !items.isEmpty else { return "" }
        let size = items.reduce(UInt64(0)) { $0 + ($1.entry?.size ?? 0) }
        let fileCount = items.filter { !$0.isDirectory }.count
        return LF("%d selected (%d files, %@)", items.count, fileCount, Format.bytes(size))
    }

    // MARK: - Opening

    func open(url: URL) {
        guard let engine else { presentEngineError(); return }
        isLoading = true
        statusText = LF("Opening %@…", url.lastPathComponent)
        currentTask?.cancel()
        currentTask = Task {
            do {
                let info = try await engine.list(archive: url, password: nil)
                self.apply(info)
            } catch SevenZipError.passwordRequired {
                self.isLoading = false
                self.promptForPassword(archive: url, message: LF("The archive \"%@\" is encrypted. Enter the password.", url.lastPathComponent))
            } catch SevenZipError.cancelled {
            } catch {
                self.present(error)
            }
            self.isLoading = false
        }
    }

    private func promptForPassword(archive: URL, message: String) {
        passwordPrompt = PasswordPrompt(title: L("Enter Password"), message: message) { [weak self] password in
            self?.open(url: archive, password: password)
        }
    }

    private func open(url: URL, password: String) {
        guard let engine else { presentEngineError(); return }
        isLoading = true
        currentTask = Task {
            do {
                let info = try await engine.list(archive: url, password: password)
                self.apply(info)
            } catch {
                self.present(error)
            }
            self.isLoading = false
        }
    }

    func apply(_ info: ArchiveInfo) {
        archiveInfo = info
        fullTree = ArchiveTreeBuilder.build(from: info.entries)
        childrenMap = [:]
        buildMaps(fullTree, parent: "")
        folderRoots = ArchiveTreeBuilder.directories(from: info.entries)
        treeRoot = ArchiveTreeNode(
            path: "",
            name: info.url.lastPathComponent,
            isDirectory: true,
            entry: nil,
            children: folderRoots
        )
        currentFolder = ""
        selection = []
        refreshDetails()
        statusText = LF("%d files, %d folders", info.fileCount, info.folderCount)
        if info.format.isEmpty == false {
            WindowTitle.shared.update(title: "\(info.url.lastPathComponent)")
        }
    }

    private func buildMaps(_ nodes: [ArchiveTreeNode], parent: String) {
        childrenMap[parent] = nodes
        for node in nodes where node.isDirectory {
            buildMaps(node.children, parent: node.path)
        }
    }

    func refreshDetails() {
        let base: [ArchiveTreeNode]
        if flatView {
            base = fullTree.flatMap { [$0] + $0.allDescendants }
        } else {
            base = childrenMap[currentFolder] ?? fullTree
        }
        details = ArchiveSorter.sorted(base, by: sort)
        detailsRevision &+= 1
    }

    /// The nodes currently selected in the details list.
    var selectedNodes: [ArchiveTreeNode] {
        details.filter { selection.contains($0.path) }
    }

    // MARK: - View options (View menu)

    /// Applies a sort key; selecting the active key again flips the direction.
    func sortBy(_ key: SortKey) {
        if sort.key == key {
            sort.ascending.toggle()
        } else {
            sort.key = key
            sort.ascending = true
        }
        refreshDetails()
    }

    /// Called when the user clicks a details column header.
    func applyColumnSort(id: String, ascending: Bool) {
        guard let key = SortKey.allCases.first(where: { $0.columnID == id }) else { return }
        sort.key = key
        sort.ascending = ascending
        refreshDetails()
    }

    func toggleFlatView() {
        flatView.toggle()
        refreshDetails()
    }

    func setColumn(_ column: DetailsColumn, visible: Bool) {
        if visible {
            visibleColumns.insert(column)
        } else {
            visibleColumns.remove(column)
        }
    }

    // MARK: - Selection (Edit menu)

    func selectAllItems() {
        selection = Set(details.map(\.path))
    }

    func deselectAllItems() {
        selection = []
    }

    func invertSelection() {
        let all = Set(details.map(\.path))
        selection = all.subtracting(selection)
    }

    // MARK: - Navigation

    func enter(folder: String) {
        currentFolder = folder
        selection = []
        refreshDetails()
    }

    func goUp() {
        guard !currentFolder.isEmpty else { return }
        let parts = currentFolder.split(separator: "/").dropLast()
        currentFolder = parts.joined(separator: "/")
        selection = []
        refreshDetails()
    }

    func goRoot() {
        currentFolder = ""
        selection = []
        refreshDetails()
    }

    func go(to breadcrumbIndex: Int) {
        let parts = breadcrumb.prefix(breadcrumbIndex + 1)
        currentFolder = parts.joined(separator: "/")
        selection = []
        refreshDetails()
    }

    func activate(_ node: ArchiveTreeNode) {
        if node.isDirectory {
            enter(folder: node.path)
        } else if isArchiveItem(node) {
            openInside(node)
        } else {
            openOutside(node)
        }
    }

    /// True when the item looks like an archive (so "Open Inside" makes sense).
    func isArchiveItem(_ node: ArchiveTreeNode) -> Bool {
        ArchiveTypes.extensions.contains((node.name as NSString).pathExtension.lowercased())
    }

    // MARK: - Open / View / Edit

    /// Extracts a single item to a temporary folder and opens it with the
    /// system default application (7-Zip's "Open" and double-click behaviour).
    func openOutside(_ node: ArchiveTreeNode) {
        extractToTemporary(node, password: nil) { url in
            NSWorkspace.shared.open(url)
        }
    }

    /// "Open Inside": extracts a nested archive and opens it in Mac7Zip.
    func openInside(_ node: ArchiveTreeNode) {
        extractToTemporary(node, password: nil) { [weak self] url in
            self?.open(url: url)
        }
    }

    /// "View": opens the extracted item in TextEdit (7-Zip's internal viewer
    /// equivalent on macOS).
    func viewFile(_ node: ArchiveTreeNode) {
        extractToTemporary(node, password: nil) { url in
            let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: configuration)
        }
    }

    /// "Edit": opens the extracted item in whatever program owns its type.
    func editFile(_ node: ArchiveTreeNode) {
        openOutside(node)
    }

    private func extractToTemporary(
        _ node: ArchiveTreeNode,
        password: String?,
        then handler: @escaping (URL) -> Void
    ) {
        guard let engine, let info = archiveInfo else { return }
        beginBusy(title: L("Extracting…"), total: 1)
        currentTask = Task {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Mac7Zip", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await engine.extract(
                    archive: info.url,
                    options: ExtractOptions(
                        items: [node.path],
                        destination: directory,
                        password: password,
                        overwrite: .overwrite,
                        keepDirectoryStructure: true
                    ),
                    totalHint: 1,
                    progress: nil
                )
                self.endBusy()
                let extracted = directory.appendingPathComponent(node.path)
                if FileManager.default.fileExists(atPath: extracted.path) {
                    handler(extracted)
                } else if let first = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.first {
                    handler(first)
                }
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.passwordPrompt = PasswordPrompt(
                    title: L("Enter Password"),
                    message: L("The archive is encrypted. Enter the password.")
                ) { [weak self] pw in
                    self?.extractToTemporary(node, password: pw, then: handler)
                }
            } catch SevenZipError.cancelled {
                self.endBusy()
                self.statusText = L("Cancelled")
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Rename inside archive

    func beginRename(_ node: ArchiveTreeNode) {
        renameTarget = node
        showRenameSheet = true
    }

    func performRename(to newName: String) {
        showRenameSheet = false
        guard let engine, let info = archiveInfo, let node = renameTarget else { return }
        renameTarget = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.name, !trimmed.contains("/") else { return }
        let parent = node.entry?.parentPath ?? ""
        let newPath = parent.isEmpty ? trimmed : parent + "/" + trimmed
        let folder = currentFolder
        beginBusy(title: L("Renaming…"), total: 1)
        currentTask = Task {
            do {
                try await engine.rename(archive: info.url, pairs: [(node.path, newPath)], password: nil)
                self.endBusy()
                self.statusText = LF("Renamed to %@", trimmed)
                await self.reloadArchive(folder: folder)
                self.selection = [newPath]
                self.refreshDetails()
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.present(SevenZipError.passwordRequired)
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Create folder / file inside archive

    func beginCreate(_ kind: CreateEntryKind) {
        createKind = kind
        showCreateSheet = true
    }

    func performCreateEntry(name: String) {
        showCreateSheet = false
        guard let engine, let info = archiveInfo else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isFolder = createKind == .folder
        let folder = currentFolder
        let relative = folder.isEmpty ? trimmed : folder + "/" + trimmed
        beginBusy(title: L("Adding…"), total: 1)
        currentTask = Task {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Mac7Zip-create-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: workingDirectory) }
            do {
                let itemURL = workingDirectory.appendingPathComponent(relative)
                try FileManager.default.createDirectory(
                    at: itemURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if isFolder {
                    try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: false)
                } else {
                    FileManager.default.createFile(atPath: itemURL.path, contents: Data())
                }
                try await engine.addItems(
                    archive: info.url,
                    relativeItems: [relative],
                    workingDirectory: workingDirectory,
                    password: nil
                )
                self.endBusy()
                self.statusText = LF("Added %@", trimmed)
                await self.reloadArchive(folder: folder)
                self.selection = [relative]
                self.refreshDetails()
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Copy To / Move To

    func copySelectedTo() { transferSelected(move: false) }
    func moveSelectedTo() { transferSelected(move: true) }

    private func transferSelected(move: Bool) {
        guard let engine, let info = archiveInfo else { return }
        guard !selection.isEmpty else {
            alert = AlertMessage(title: L("Notice"), message: L("Please select the items first."))
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Select")
        panel.message = move ? L("Move the selected items to…") : L("Copy the selected items to…")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let items = Self.reduceNested(Array(selection))
        let folder = currentFolder
        let total = fileCount(under: items)
        beginBusy(title: move ? L("Moving…") : L("Copying…"), total: total)
        let handler = makeProgressHandler()
        currentTask = Task {
            do {
                try await engine.extract(
                    archive: info.url,
                    options: ExtractOptions(
                        items: items,
                        destination: destination,
                        password: nil,
                        overwrite: .overwrite,
                        keepDirectoryStructure: true
                    ),
                    totalHint: total,
                    progress: handler
                )
                if move {
                    try await engine.delete(archive: info.url, items: items, password: nil)
                }
                self.endBusy()
                self.statusText = move
                    ? LF("Moved %d items to %@", items.count, destination.path)
                    : LF("Copied %d items to %@", items.count, destination.path)
                await self.reloadArchive(folder: folder)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.present(SevenZipError.passwordRequired)
            } catch SevenZipError.cancelled {
                self.endBusy()
                self.statusText = L("Cancelled")
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Properties

    func showProperties(_ node: ArchiveTreeNode) {
        propertiesTarget = node
        showPropertiesSheet = true
    }

    // MARK: - Checksum

    func checksumArchive(algorithm: String) {
        guard let engine, let info = archiveInfo else { return }
        beginBusy(title: L("Calculating checksum…"), total: 0)
        currentTask = Task {
            do {
                let value = try await engine.checksum(of: info.url, algorithm: algorithm)
                self.endBusy()
                self.alert = AlertMessage(
                    title: algorithm,
                    message: value.isEmpty ? L("Could not compute the checksum.") : value
                )
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard hasArchive else { return }
        let folder = currentFolder
        Task { await reloadArchive(folder: folder) }
    }

    private func reloadArchive(folder: String) async {
        guard let engine, let info = archiveInfo else { return }
        guard let fresh = try? await engine.list(archive: info.url, password: nil) else { return }
        apply(fresh)
        if !folder.isEmpty, childrenMap[folder] != nil {
            currentFolder = folder
            selection = []
            refreshDetails()
        }
    }

    // MARK: - Extract

    func beginExtractAll() {
        guard hasArchive else { return }
        pendingExtractItems = nil
        suggestedExtractDestination = archiveInfo?.url.deletingLastPathComponent()
        showExtractSheet = true
    }

    func beginExtractSelected() {
        guard hasArchive else { return }
        guard !selection.isEmpty else {
            alert = AlertMessage(title: L("Notice"), message: L("Please select the file or folder to extract first."))
            return
        }
        pendingExtractItems = Self.reduceNested(Array(selection))
        suggestedExtractDestination = archiveInfo?.url.deletingLastPathComponent()
        showExtractSheet = true
    }

    func performExtract(destination: URL, password: String?, overwrite: OverwriteMode, keepPaths: Bool) {
        guard let engine, let info = archiveInfo else { return }
        let items = pendingExtractItems
        let total = fileCount(under: items ?? [])
        beginBusy(title: L("Extracting…"), total: total)
        let handler = makeProgressHandler()
        currentTask = Task {
            do {
                try await engine.extract(
                    archive: info.url,
                    options: ExtractOptions(
                        items: items,
                        destination: destination,
                        password: password,
                        overwrite: overwrite,
                        keepDirectoryStructure: keepPaths
                    ),
                    totalHint: total,
                    progress: handler
                )
                self.endBusy()
                self.statusText = LF("Extracted to %@", destination.path)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.passwordPrompt = PasswordPrompt(title: L("Enter Password"), message: L("The archive is encrypted. Enter the password.")) { [weak self] pw in
                    self?.performExtract(destination: destination, password: pw, overwrite: overwrite, keepPaths: keepPaths)
                }
            } catch SevenZipError.cancelled {
                self.endBusy()
                self.statusText = L("Cancelled")
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Test

    func testArchive() {
        guard let engine, let info = archiveInfo else { return }
        beginBusy(title: L("Testing…"), total: info.fileCount)
        let handler = makeProgressHandler()
        currentTask = Task {
            do {
                let result = try await engine.test(
                    archive: info.url,
                    password: nil,
                    totalHint: info.fileCount,
                    progress: handler
                )
                self.endBusy()
                self.alert = AlertMessage(
                    title: L("Test Result"),
                    message: result.ok
                        ? LF("Everything is Ok\n\nFiles: %d\nSize: %@", result.files, Format.bytes(result.size))
                        : result.message
                )
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.passwordPrompt = PasswordPrompt(title: L("Enter Password"), message: L("The archive is encrypted. Enter the password.")) { [weak self] pw in
                    self?.testArchive(password: pw)
                }
            } catch SevenZipError.cancelled {
                self.endBusy()
                self.statusText = L("Cancelled")
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    private func testArchive(password: String) {
        guard let engine, let info = archiveInfo else { return }
        beginBusy(title: L("Testing…"), total: info.fileCount)
        let handler = makeProgressHandler()
        currentTask = Task {
            do {
                let result = try await engine.test(archive: info.url, password: password, totalHint: info.fileCount, progress: handler)
                self.endBusy()
                self.alert = AlertMessage(title: L("Test Result"), message: result.ok ? L("Everything is Ok") : result.message)
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Delete from archive

    func deleteSelected() {
        guard let engine, let info = archiveInfo else { return }
        guard !selection.isEmpty else {
            alert = AlertMessage(title: L("Notice"), message: L("Please select the items to delete first."))
            return
        }
        let items = Self.reduceNested(Array(selection))

        let confirm = NSAlert()
        confirm.messageText = L("Delete")
        confirm.informativeText = LF("Delete %d selected items from the archive? This modifies the archive.", items.count)
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: L("Delete"))
        confirm.addButton(withTitle: L("Cancel"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        beginBusy(title: L("Deleting…"), total: items.count)
        currentTask = Task {
            do {
                try await engine.delete(archive: info.url, items: items, password: nil)
                self.endBusy()
                let refreshed = try await engine.list(archive: info.url, password: nil)
                self.apply(refreshed)
                self.statusText = LF("Deleted %d items", items.count)
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.present(SevenZipError.passwordRequired)
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Create / add

    func openFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Open")
        panel.message = L("Select the archive to open")
        let types = ArchiveTypes.contentTypes
        if !types.isEmpty { panel.allowedContentTypes = types }
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func beginAdd() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Select")
        panel.message = L("Select the files or folders to compress")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        addSources = panel.urls
        suggestedArchiveURL = defaultArchiveURL(for: panel.urls)
        showAddSheet = true
    }

    func performCreate(archiveURL: URL, options: CreateOptions) {
        guard let engine else { presentEngineError(); return }
        let sources = addSources
        guard !sources.isEmpty else { return }
        let total = Self.countFiles(in: sources)
        beginBusy(title: L("Compressing…"), total: total)
        let handler = makeProgressHandler()
        currentTask = Task {
            do {
                try await engine.create(archive: archiveURL, sources: sources, options: options, totalHint: total, progress: handler)
                self.endBusy()
                self.statusText = LF("Created %@", archiveURL.lastPathComponent)
                self.addSources = []
                let refreshed = try await engine.list(archive: archiveURL, password: nil)
                self.apply(refreshed)
            } catch SevenZipError.passwordRequired {
                self.endBusy()
                self.present(SevenZipError.wrongPassword)
            } catch SevenZipError.cancelled {
                self.endBusy()
                self.statusText = L("Cancelled")
            } catch {
                self.endBusy()
                self.present(error)
            }
        }
    }

    // MARK: - Info

    func showInfo() {
        guard hasArchive else { return }
        showInfoSheet = true
    }

    // MARK: - Cancel

    func cancelCurrentOperation() {
        currentTask?.cancel()
    }

    // MARK: - Helpers

    private func defaultArchiveURL(for sources: [URL]) -> URL {
        if let archive = archiveInfo?.url { return archive }
        guard let first = sources.first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Archive.7z")
        }
        let base = first.deletingPathExtension().lastPathComponent
        return first.deletingLastPathComponent().appendingPathComponent(base + ".7z")
    }

    func fileCount(under items: [String]) -> Int {
        guard let info = archiveInfo else { return 0 }
        if items.isEmpty { return info.fileCount }
        var count = 0
        for entry in info.entries where !entry.isDirectory {
            for item in items {
                if entry.path == item || entry.path.hasPrefix(item + "/") {
                    count += 1
                    break
                }
            }
        }
        return count
    }

    private func beginBusy(title: String, total: Int) {
        isBusy = true
        progress = OperationProgress(title: title, detail: "", processed: 0, total: total)
        throttle.reset()
    }

    private func endBusy() {
        isBusy = false
        progress = nil
    }

    private func makeProgressHandler() -> ProgressHandler {
        let throttle = self.throttle
        return { [weak self] update in
            guard throttle.allow() else { return }
            Task { @MainActor in
                self?.progress = update
            }
        }
    }

    private func present(_ error: Error) {
        if let sevenZip = error as? SevenZipError {
            alert = AlertMessage(title: L("Error"), message: sevenZip.localizedDescription)
        } else {
            alert = AlertMessage(title: L("Error"), message: error.localizedDescription)
        }
    }

    private func presentEngineError() {
        alert = AlertMessage(title: L("Error"), message: EngineError.engineNotFound.localizedDescription)
    }

    nonisolated static func reduceNested(_ paths: [String]) -> [String] {
        let sorted = paths.sorted { $0.count < $1.count }
        var result: [String] = []
        for path in sorted {
            if result.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            result.append(path)
        }
        return result.sorted()
    }

    nonisolated static func countFiles(in urls: [URL], cap: Int = 200_000) -> Int {
        let fm = FileManager.default
        var count = 0
        var stack = urls
        while let url = stack.popLast() {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
                    stack.append(contentsOf: children)
                }
            } else {
                count += 1
                if count >= cap { return count }
            }
        }
        return count
    }
}

/// Simple time based throttle so rapid progress callbacks don't flood the UI.
final class ProgressThrottle {
    private var last = Date.distantPast
    private let lock = NSLock()
    private let interval: TimeInterval = 0.05

    func reset() {
        lock.lock(); last = .distantPast; lock.unlock()
    }

    func allow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(last) >= interval {
            last = now
            return true
        }
        return false
    }
}

/// Small helper so background tasks can update the window title safely.
@MainActor
final class WindowTitle {
    static let shared = WindowTitle()

    func update(title: String) {
        for window in NSApplication.shared.windows {
            window.title = title
        }
    }
}
