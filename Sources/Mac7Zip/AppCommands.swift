import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreServices

/// Menu bar mirroring the Windows 7-Zip File Manager commands, plus a
/// Language menu and a command that makes Mac7Zip the default opener for
/// archive types.
struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var localization = Localization.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("Open…")) { model.openFromPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button(L("Add to Archive…")) { model.beginAdd() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button(L("Open Inside")) { if let node = openInsideNode { model.openInside(node) } }
                .disabled(openInsideNode == nil)
            Button(L("Open Outside")) { if let node = singleFileNode { model.openOutside(node) } }
                .disabled(singleFileNode == nil)
            Button(L("View")) { if let node = singleFileNode { model.viewFile(node) } }
                .disabled(singleFileNode == nil)
            Button(L("Edit")) { if let node = singleFileNode { model.editFile(node) } }
                .disabled(singleFileNode == nil)
            Divider()
            Button(L("Rename")) { if let node = singleNode { model.beginRename(node) } }
                .disabled(singleNode == nil)
            Button(L("Copy To…")) { model.copySelectedTo() }
                .disabled(model.selection.isEmpty)
            Button(L("Move To…")) { model.moveSelectedTo() }
                .disabled(model.selection.isEmpty)
            Divider()
            Button(L("Create Folder")) { model.beginCreate(.folder) }
                .disabled(!model.hasArchive)
            Button(L("Create File")) { model.beginCreate(.file) }
                .disabled(!model.hasArchive)
            Divider()
            Button(L("Delete")) { model.deleteSelected() }
                .disabled(model.selection.isEmpty)
            Button(L("Properties")) { if let node = singleNode { model.showProperties(node) } }
                .disabled(singleNode == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button(L("Select All")) { model.selectAllItems() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(!model.hasArchive)
            Button(L("Deselect All")) { model.deselectAllItems() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Button(L("Invert Selection")) { model.invertSelection() }
                .disabled(!model.hasArchive)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Menu(L("Sort By")) {
                ForEach(SortKey.allCases) { key in
                    Toggle(key.title, isOn: Binding(
                        get: { model.sort.key == key },
                        set: { if $0 { model.sortBy(key) } }
                    ))
                }
            }
            .disabled(!model.hasArchive)
            Toggle(L("Ascending"), isOn: Binding(
                get: { model.sort.ascending },
                set: { _ in model.sortBy(model.sort.key) }
            ))
            .disabled(!model.hasArchive || model.sort.key == .unsorted)
            Toggle(L("Flat View"), isOn: Binding(
                get: { model.flatView },
                set: { _ in model.toggleFlatView() }
            ))
            .disabled(!model.hasArchive)
            Menu(L("Select Columns")) {
                ForEach(DetailsColumn.allCases) { column in
                    Toggle(column.title, isOn: Binding(
                        get: { model.visibleColumns.contains(column) },
                        set: { model.setColumn(column, visible: $0) }
                    ))
                }
            }
            Divider()
            Button(L("Refresh")) { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.hasArchive)
        }

        CommandMenu(L("Operations")) {
            Button(L("Extract All…")) { model.beginExtractAll() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!model.hasArchive)
            Button(L("Extract Selected…")) { model.beginExtractSelected() }
                .disabled(!model.hasArchive || model.selection.isEmpty)
            Divider()
            Button(L("Test")) { model.testArchive() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!model.hasArchive)
            Button(L("Delete")) { model.deleteSelected() }
                .disabled(!model.hasArchive || model.selection.isEmpty)
            Divider()
            Button(L("Info")) { model.showInfo() }
                .disabled(!model.hasArchive)
        }

        CommandMenu(L("Tools")) {
            Menu(L("Checksum")) {
                ForEach(["CRC32", "CRC64", "SHA1", "SHA256", "BLAKE2sp"], id: \.self) { algorithm in
                    Button(algorithm) { model.checksumArchive(algorithm: algorithm) }
                }
            }
            .disabled(!model.hasArchive)
        }

        CommandMenu(L("Go")) {
            Button(L("Go Up One Level")) { model.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(model.currentFolder.isEmpty)
            Button(L("Root")) { model.goRoot() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                .disabled(!model.hasArchive)
        }

        CommandMenu(L("Language")) {
            Picker("", selection: Binding(
                get: { localization.language },
                set: { localization.setLanguage($0) }
            )) {
                Text(L("System")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("简体中文").tag(AppLanguage.simplifiedChinese)
            }
            .pickerStyle(.inline)
        }

        CommandMenu(L("Associate")) {
            Button(L("Open Archives with Mac7Zip by Default")) {
                AssociateDefaults.setMac7ZipAsDefaultHandler()
            }
            .disabled(!model.engineAvailable)
            Button(L("Restore System Default Handlers")) {
                AssociateDefaults.restoreSystemHandlers()
            }
        }

        CommandGroup(replacing: .help) {
            Button(L("About Mac7Zip")) {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .credits: NSAttributedString(
                        string: L("Mac7Zip — a macOS GUI built on the official 7-Zip engine.\n7-Zip © Igor Pavlov.")
                    )
                ])
            }
        }
    }

    // MARK: - Selection helpers

    private var singleNode: ArchiveTreeNode? {
        model.selection.count == 1 ? model.selectedNodes.first : nil
    }

    private var singleFileNode: ArchiveTreeNode? {
        guard let node = singleNode, !node.isDirectory else { return nil }
        return node
    }

    private var openInsideNode: ArchiveTreeNode? {
        guard let node = singleFileNode else { return nil }
        return ArchiveTypes.extensions.contains((node.name as NSString).pathExtension.lowercased()) ? node : nil
    }
}

/// Updates Launch Services so double-clicking an archive opens it in Mac7Zip
/// instead of extracting it. The change is intentionally user-triggered.
enum AssociateDefaults {
    /// The archive content types this app declares itself as a candidate for.
    /// Mirrors the UTIs in `Scripts/Info.plist` (both imported and system).
    static let contentTypes: [UTType] = [
        "org.7-zip.7z",
        "org.7-zip.7z-001",
        "com.rarlab.rar-archive",
        "public.zip-archive",
        "public.tar-archive",
        "org.gnu.gnu-zip-archive",
        "org.gnu.gnu-zip-tar-archive",
        "public.bzip2-archive",
        "public.bzip2-tar-archive",
        "org.tukaani.xz",
        "org.tukaani.xz-tar",
        "org.zstandard.zst",
        "org.7-zip.lzma",
        "org.7-zip.lzh",
        "org.7-zip.arj",
        "org.7-zip.aes",
        "com.microsoft.cabarchive",
        "com.microsoft.wim",
        "public.iso-image",
        "com.apple.disk-image",
        "com.sun.java-archive",
        "com.google.android.apk-archive",
        "com.redhat.rpm-archive",
        "org.debian.deb-archive",
        "public.cpio-archive",
        "org.squashfs.squashfs",
    ].compactMap(UTType.init)

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "cn.mac7zip.app"
    }

    /// Shows an alert telling what happens next, then registers the app as the
    /// default handler for every supported archive UTI.
    static func setMac7ZipAsDefaultHandler() {
        let types = contentTypes
        var succeeded = 0
        for type in types {
            let result = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleIdentifier as CFString)
            if result == noErr { succeeded += 1 }
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        if succeeded > 0 {
            alert.messageText = L("Mac7Zip is now the default opener")
            alert.informativeText = LF(
                "Double-clicking %d archive types will now open them in Mac7Zip instead of extracting them.",
                succeeded
            )
        } else {
            alert.messageText = L("Could not update associations")
            alert.informativeText = L("Launch Services refused the change. Try again from the Associations menu.")
        }
        alert.runModal()
    }

    /// Restores macOS defaults (most types go back to Archive Utility).
    static func restoreSystemHandlers() {
        var restored = 0
        for type in contentTypes {
            let result = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, "com.apple.archiveutility" as CFString)
            if result == noErr { restored += 1 }
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("System default handlers restored")
        alert.informativeText = LF(
            "%d archive types were handed back to the system default programs.",
            restored
        )
        alert.runModal()
    }
}