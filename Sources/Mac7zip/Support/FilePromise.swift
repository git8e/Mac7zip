import AppKit
import ObjectiveC
import UniformTypeIdentifiers

/// Provides a dragged archive item to Finder as a file promise: on drop the
/// item is extracted to a temporary folder and then copied to the promised URL.
/// This is what makes dragging an item out of the archive extract it, like the
/// Windows 7-Zip File Manager.
final class ArchiveItemPromise: NSObject, NSFilePromiseProviderDelegate {
    private let engine: SevenZipEngine
    private let archive: URL
    private let itemPath: String
    private let itemName: String
    private let password: String?

    init(engine: SevenZipEngine, archive: URL, itemPath: String, itemName: String, password: String?) {
        self.engine = engine
        self.archive = archive
        self.itemPath = itemPath
        self.itemName = itemName
        self.password = password
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        itemName
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let engine = self.engine
        let archive = self.archive
        let itemPath = self.itemPath
        let password = self.password
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mac7zipDrag-\(UUID().uuidString)")

        let semaphore = DispatchSemaphore(value: 0)
        let box = ErrorBox()
        Task.detached {
            do {
                try await engine.extract(
                    archive: archive,
                    options: ExtractOptions(
                        items: [itemPath],
                        destination: temp,
                        password: password,
                        overwrite: .overwrite,
                        pathMode: .fullPaths
                    ),
                    totalHint: nil,
                    progress: nil
                )
            } catch {
                box.error = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        defer { try? FileManager.default.removeItem(at: temp) }

        if let error = box.error {
            completionHandler(error)
            return
        }

        let produced = temp.appendingPathComponent(itemPath)
        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: produced, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

/// Tiny reference box so the detached task can hand the error back.
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Builds the `NSFilePromiseProvider` used as the pasteboard writer for a row,
/// keeping the delegate alive for the lifetime of the provider.
enum ArchiveItemPasteboard {
    private static var key: UInt8 = 0

    static func writer(for node: ArchiveTreeNode, engine: SevenZipEngine, archive: URL, password: String?) -> NSPasteboardWriting? {
        let promise = ArchiveItemPromise(
            engine: engine,
            archive: archive,
            itemPath: node.path,
            itemName: node.name,
            password: password
        )
        let fileType: String
        if node.isDirectory {
            fileType = UTType.folder.identifier
        } else {
            let ext = (node.name as NSString).pathExtension
            fileType = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
        }
        let provider = NSFilePromiseProvider(fileType: fileType, delegate: promise)
        objc_setAssociatedObject(provider, &key, promise, .OBJC_ASSOCIATION_RETAIN)
        return provider
    }
}
