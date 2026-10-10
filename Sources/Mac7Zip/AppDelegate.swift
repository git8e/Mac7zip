import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if handleDiagnosticsIfNeeded() { return }

        NSApp.activate(ignoringOtherApps: true)

        // Allow launching with an archive path: `open -a Mac7Zip file.7z`
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument)
            if FileManager.default.fileExists(atPath: url.path) {
                Task { @MainActor in AppModel.shared.open(url: url) }
                break
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in AppModel.shared.open(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Diagnostic flags used to verify a packaged build without a GUI:
    ///   Mac7Zip --check-engine
    ///   Mac7Zip --list <archive>
    private func handleDiagnosticsIfNeeded() -> Bool {
        let args = CommandLine.arguments

        if args.contains("--strings") {
            print("Open=\(L("Open"))")
            print("OpenEllipsis=\(L("Open…"))")
            print("Password=\(L("Password"))")
            print("FilesFolders=\(LF("%d files, %d folders", 3, 2))")
            print("Ready=\(L("Ready"))")
            print("OpenOutside=\(L("Open Outside"))")
            print("CreateFolder=\(L("Create Folder"))")
            print("InvertSelection=\(L("Invert Selection"))")
            print("FlatView=\(L("Flat View"))")
            print("ChecksumMenu=\(L("Checksum"))")
            print("CompMethod=\(L("Compression method:"))")
            print("Dictionary=\(L("Dictionary size:"))")
            print("UpdateMode=\(L("Synchronize files"))")
            print("Auto=\(L("Automatic"))")
            print("EliminateRoot=\(L("Eliminate duplication of root folder"))")
            print("DeleteAfter=\(L("Delete files after compression"))")
            print("ShowPassword=\(L("Show password"))")
            print("ViewModes=\(L("Icons"))/\(L("List"))/\(L("Details"))")
            print("ViewMode=\(L("View Mode"))")
            print("ShowTree=\(L("Show Folder Tree"))")
            print("RenamedTo=\(LF("Renamed to %@", "x.txt"))")
            print("CopiedItems=\(LF("Copied %d items to %@", 2, "/tmp"))")
            print("localePackage=\(Locale.preferredLanguages.first ?? "?")")
            exit(0)
        }

        if args.contains("--check-engine") {
            if let url = EngineLocator.engineURL {
                print("engine=\(url.path)")
                print("executable=\(FileManager.default.isExecutableFile(atPath: url.path))")
                let process = Process()
                process.executableURL = url
                process.arguments = []
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                if (try? process.run()) != nil {
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let banner = String(decoding: data, as: UTF8.self)
                        .split(separator: "\n").first.map(String.init) ?? ""
                    print("version=\(banner)")
                }
            } else {
                print("engine=NOT FOUND")
            }
            exit(0)
        }

        if let index = args.firstIndex(of: "--list"), args.count > index + 1 {
            let archive = URL(fileURLWithPath: args[index + 1])
            let semaphore = DispatchSemaphore(value: 0)
            var output = "listing failed"
            Task.detached {
                do {
                    let engine = try SevenZipEngine.detect()
                    let info = try await engine.list(archive: archive, password: nil)
                    var lines = ["format=\(info.format) files=\(info.fileCount) folders=\(info.folderCount) entries=\(info.entries.count)"]
                    for entry in info.entries {
                        lines.append("\(entry.isDirectory ? "D" : "F") \(entry.path) (\(entry.size ?? 0))")
                    }
                    output = lines.joined(separator: "\n")
                } catch {
                    output = "error: \(error.localizedDescription)"
                }
                semaphore.signal()
            }
            semaphore.wait()
            print(output)
            exit(0)
        }

        return false
    }
}
