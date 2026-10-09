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

    // Pending operation inputs
    @Published var addSources: [URL] = []
    @Published var suggestedArchiveURL: URL?
    @Published var pendingExtractItems: [String]?
    @Published var suggestedExtractDestination: URL?

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
        details = childrenMap[currentFolder] ?? fullTree
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
