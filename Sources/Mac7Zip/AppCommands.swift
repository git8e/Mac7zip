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