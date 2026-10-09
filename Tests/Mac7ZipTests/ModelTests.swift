import Testing
import Foundation
@testable import Mac7Zip

/// Verifies the navigation / selection logic that drives the outline and the
/// details list — the parts of the 7-Zip style UI that do not need a screen.
@Suite("App model navigation")
@MainActor
struct ModelTests {
    private func sampleInfo() -> ArchiveInfo {
        var info = ArchiveInfo(url: URL(fileURLWithPath: "/tmp/sample.7z"))
        info.format = "7z"
        info.entries = [
            entry("folder", dir: true),
            entry("folder/inner.txt", size: 5, crc: "AABBCCDD"),
            entry("folder/deep", dir: true),
            entry("folder/deep/leaf.bin", size: 10),
            entry("root.txt", size: 1),
        ]
        return info
    }

    private func entry(_ path: String, dir: Bool = false, size: UInt64 = 0, crc: String? = nil) -> ArchiveEntry {
        ArchiveEntry(
            path: path,
            isDirectory: dir,
            size: size,
            packedSize: size,
            modified: nil,
            crc: crc,
            method: dir ? nil : "LZMA2:24k",
            encrypted: false,
            attributes: dir ? "D drwxr-xr-x" : "A -rw-r--r--"
        )
    }

    @Test("Root shows top level items and folders are enterable")
    func navigation() {
        let model = AppModel.shared
        model.apply(sampleInfo())

        // At the root: folder, root.txt
        #expect(model.details.map(\.name).sorted() == ["folder", "root.txt"])
        #expect(model.breadcrumb.isEmpty)

        model.enter(folder: "folder")
        #expect(model.details.map(\.name).sorted() == ["deep", "inner.txt"])
        #expect(model.breadcrumb == ["folder"])

        model.enter(folder: "folder/deep")
        #expect(model.details.map(\.name) == ["leaf.bin"])
        #expect(model.breadcrumb == ["folder", "deep"])

        model.go(to: 0)
        #expect(model.currentFolder == "folder")

        model.goUp()
        #expect(model.currentFolder.isEmpty)
        #expect(model.details.count == 2)

        model.goRoot()
        #expect(model.currentFolder.isEmpty)
    }

    @Test("Folder tree only contains directories")
    func folderTree() {
        let model = AppModel.shared
        model.apply(sampleInfo())
        let dirNames = flatten(model.folderRoots).map(\.name)
        #expect(dirNames.contains("folder"))
        #expect(dirNames.contains("deep"))
        #expect(!dirNames.contains("root.txt"))
        #expect(!dirNames.contains("inner.txt"))
    }

    @Test("Counting files under selected items is recursive")
    func fileCountUnderSelection() {
        let model = AppModel.shared
        model.apply(sampleInfo())
        #expect(model.fileCount(under: []) == 3)
        #expect(model.fileCount(under: ["folder"]) == 2)
        #expect(model.fileCount(under: ["folder/deep"]) == 1)
        #expect(model.fileCount(under: ["root.txt"]) == 1)
    }

    @Test("Selecting a folder and its child extracts the folder once")
    func nestedSelectionCollapses() {
        #expect(AppModel.reduceNested(["folder/deep/leaf.bin", "folder"]) == ["folder"])
    }

    private func flatten(_ nodes: [ArchiveTreeNode]) -> [ArchiveTreeNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}
