import Testing
import Foundation
@testable import Mac7zip

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

    @Test("Address bar navigation accepts known folders and rejects unknown ones")
    func addressBarNavigation() {
        let model = AppModel.shared
        model.apply(sampleInfo())

        #expect(model.navigate(toPath: "folder/deep"))
        #expect(model.currentFolder == "folder/deep")

        // Trailing slashes and backslashes are tolerated.
        #expect(model.navigate(toPath: "/folder/"))
        #expect(model.currentFolder == "folder")

        // An empty path returns to the root.
        #expect(model.navigate(toPath: ""))
        #expect(model.currentFolder == "")

        // Unknown folders leave the current folder unchanged.
        #expect(!model.navigate(toPath: "does/not/exist"))
        #expect(model.currentFolder == "")
    }

    private func flatten(_ nodes: [ArchiveTreeNode]) -> [ArchiveTreeNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}

/// Sorting and flat-view behaviour of the details list (Stage 1 port).
@Suite("Details list sorting")
struct SortingTests {
    private func node(_ name: String, dir: Bool = false, size: UInt64 = 0) -> ArchiveTreeNode {
        let entry = dir ? nil : ArchiveEntry(
            path: name,
            isDirectory: false,
            size: size,
            packedSize: size,
            modified: nil,
            crc: nil,
            method: nil,
            encrypted: false,
            attributes: nil
        )
        return ArchiveTreeNode(path: name, name: name, isDirectory: dir, entry: entry, children: [])
    }

    @Test("Folders sort before files, then by name")
    func foldersFirst() {
        let nodes = [node("b.txt"), node("a", dir: true), node("a.txt"), node("z", dir: true)]
        let sorted = ArchiveSorter.sorted(nodes, by: SortState(key: .name, ascending: true))
        #expect(sorted.map(\.name) == ["a", "z", "a.txt", "b.txt"])
    }

    @Test("Size sort orders numerically and flips with direction")
    func sizeSort() {
        let nodes = [node("small", size: 1), node("big", size: 100), node("mid", size: 50)]
        let ascending = ArchiveSorter.sorted(nodes, by: SortState(key: .size, ascending: true))
        #expect(ascending.map(\.name) == ["small", "mid", "big"])
        let descending = ArchiveSorter.sorted(nodes, by: SortState(key: .size, ascending: false))
        #expect(descending.map(\.name) == ["big", "mid", "small"])
    }

    @Test("Unsorted keeps the original order")
    func unsortedKeepsOrder() {
        let nodes = [node("b.txt"), node("a", dir: true), node("c.txt")]
        let sorted = ArchiveSorter.sorted(nodes, by: SortState(key: .unsorted))
        #expect(sorted.map(\.name) == ["b.txt", "a", "c.txt"])
    }

    @Test("Flatten returns every node depth first")
    @MainActor
    func allDescendants() {
        let leaf = node("leaf.bin", size: 10)
        let deep = ArchiveTreeNode(path: "deep", name: "deep", isDirectory: true, entry: nil, children: [leaf])
        let folder = ArchiveTreeNode(path: "folder", name: "folder", isDirectory: true, entry: nil, children: [deep])
        #expect(folder.allDescendants.map(\.name) == ["deep", "leaf.bin"])
    }

    @Test("Flat view flattens the whole tree and sorting reapplies")
    @MainActor
    func flatView() {
        let model = AppModel.shared
        var info = ArchiveInfo(url: URL(fileURLWithPath: "/tmp/flat.7z"))
        info.format = "7z"
        info.entries = [
            ArchiveEntry(path: "folder", isDirectory: true, size: nil, packedSize: nil, modified: nil, crc: nil, method: nil, encrypted: false, attributes: nil),
            ArchiveEntry(path: "folder/leaf.bin", isDirectory: false, size: 10, packedSize: 10, modified: nil, crc: nil, method: nil, encrypted: false, attributes: nil),
            ArchiveEntry(path: "root.txt", isDirectory: false, size: 1, packedSize: 1, modified: nil, crc: nil, method: nil, encrypted: false, attributes: nil),
        ]
        model.apply(info)
        #expect(model.details.map(\.name).sorted() == ["folder", "root.txt"])

        model.toggleFlatView()
        #expect(Set(model.details.map(\.name)) == Set(["folder", "leaf.bin", "root.txt"]))
        #expect(model.details.first?.isDirectory == true)

        model.toggleFlatView()
        #expect(model.details.map(\.name).sorted() == ["folder", "root.txt"])
    }
}

/// The advanced Add/Extract dialog options map onto the right 7-Zip switches.
@Suite("Add and Extract options")
struct OptionArgumentTests {
    @Test("Default create options add no extra switches")
    func defaultCreateOptions() {
        #expect(CreateOptions().extraArguments.isEmpty)
    }

    @Test("Method, dictionary and threads become switches")
    func methodDictionaryThreads() {
        var options = CreateOptions()
        options.method = "LZMA2"
        options.dictionary = "64m"
        options.threads = .four
        #expect(options.extraArguments == ["-m0=LZMA2", "-md=64m", "-mmt=4"])
    }

    @Test("Dictionary is ignored for methods that do not accept it")
    func dictionaryIgnoredForPpmd() {
        var options = CreateOptions()
        options.method = "PPMd"
        options.dictionary = "64m"
        #expect(options.extraArguments == ["-m0=PPMd"])
    }

    @Test("Zip only takes a dictionary with LZMA")
    func zipDictionary() {
        var options = CreateOptions(format: .zip)
        options.method = "Deflate"
        options.dictionary = "1m"
        #expect(options.extraArguments == ["-m0=Deflate"])
        options.method = "LZMA"
        #expect(options.extraArguments == ["-m0=LZMA", "-md=1m"])
    }

    @Test("Update, path mode and delete-after switches")
    func updatePathDelete() {
        var options = CreateOptions()
        options.updateMode = .synchronize
        options.pathMode = .absolute
        options.deleteAfterCompression = true
        #expect(options.extraArguments == ["-up1q0r2x1y2z1w2", "-spf", "-sdel"])
    }

    @Test("All update modes map to distinct valid strings")
    func updateModeStrings() {
        #expect(UpdateMode.addAndReplace.switchValue == nil)
        #expect(UpdateMode.updateAndAdd.switchValue == "-up1q1r2x1y2z1w2")
        #expect(UpdateMode.freshen.switchValue == "-up1q1r0x1y2z1w2")
        #expect(UpdateMode.synchronize.switchValue == "-up1q0r2x1y2z1w2")
    }

    @Test("Eliminate root folder adds -spe")
    func eliminateRootSwitch() {
        var options = ExtractOptions(items: nil, destination: URL(fileURLWithPath: "/tmp"))
        #expect(options.extraArguments.isEmpty)
        options.eliminateRoot = true
        #expect(options.extraArguments == ["-spe"])
    }

    @Test("Word size maps to fast bytes for LZMA and order for PPMd")
    func wordSizeSwitches() {
        var options = CreateOptions()
        options.method = "LZMA2"
        options.wordSize = "64"
        #expect(options.extraArguments == ["-m0=LZMA2", "-mfb=64"])
        options.method = "PPMd"
        #expect(options.extraArguments == ["-m0=PPMd", "-mo=64"])
    }

    @Test("Solid block size maps to -ms")
    func solidBlockSwitches() {
        var options = CreateOptions()
        options.solidBlock = .nonSolid
        #expect(options.extraArguments == ["-ms=off"])
        options.solidBlock = .mb64
        #expect(options.extraArguments == ["-ms=64m"])
    }

    @Test("Zip password defaults to AES-256 and honours an explicit method")
    func zipEncryptionMethods() {
        var options = CreateOptions(format: .zip)
        options.password = "secret"
        #expect(options.extraArguments == ["-mem=AES256"])
        options.encryptionMethod = .zipCrypto
        #expect(options.extraArguments == ["-mem=ZipCrypto"])
    }

    @Test("Shared files flag and free-form parameters are appended last")
    func sharedAndParameters() {
        var options = CreateOptions()
        options.compressSharedFiles = true
        options.deleteAfterCompression = true
        options.parameters = "-mtc=off  -ssp"
        #expect(options.extraArguments == ["-ssw", "-sdel", "-mtc=off", "-ssp"])
    }

    @Test("Extract path modes map to -e and -spf")
    func extractPathModes() {
        #expect(ExtractPathMode.fullPaths.switchValue == nil)
        #expect(ExtractPathMode.noPaths.switchValue == "-e")
        #expect(ExtractPathMode.absolutePaths.switchValue == "-spf")
    }

    @Test("Split volume presets keep only the size token")
    func volumeSizeArgument() {
        #expect(VolumeSize.argument(from: "") == nil)
        #expect(VolumeSize.argument(from: "   ") == nil)
        #expect(VolumeSize.argument(from: "100m") == "100m")
        #expect(VolumeSize.argument(from: "100 m") == "100m")
        #expect(VolumeSize.argument(from: "650M - CD") == "650M")
        #expect(VolumeSize.argument(from: "8128M - DVD DL") == "8128M")
        #expect(VolumeSize.presets.first == "10M")
    }
}
