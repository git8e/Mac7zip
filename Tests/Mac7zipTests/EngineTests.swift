import Testing
import Foundation
@testable import Mac7zip

/// End-to-end checks against the bundled official 7-Zip engine.
@Suite("Mac7zip engine")
struct EngineTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mac7zipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSourceTree(in root: URL) throws -> URL {
        let fm = FileManager.default
        let src = root.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("sub/deep"), withIntermediateDirectories: true)
        try "hello world".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "中文内容测试".write(to: src.appendingPathComponent("sub/b 空格.txt"), atomically: true, encoding: .utf8)
        return src
    }

    @Test("Bundled engine is locatable and executable")
    func engineIsAvailable() throws {
        #expect(SevenZipEngine.isAvailable)
        let engine = try SevenZipEngine.detect()
        #expect(FileManager.default.isExecutableFile(atPath: engine.executable.path))
    }

    @Test("Create, list, extract a single file, and test")
    func createListExtractTest() async throws {
        let fm = FileManager.default
        let root = try makeWorkspace()
        defer { try? fm.removeItem(at: root) }

        let engine = try SevenZipEngine.detect()
        let src = try makeSourceTree(in: root)
        let archive = root.appendingPathComponent("sample.7z")

        try await engine.create(
            archive: archive,
            sources: [src],
            options: CreateOptions(format: .sevenZip, level: .fast),
            totalHint: nil,
            progress: nil
        )
        #expect(fm.fileExists(atPath: archive.path))

        let info = try await engine.list(archive: archive, password: nil)
        #expect(info.format == "7z")
        let paths = info.entries.map(\.path)
        #expect(paths.contains { $0.hasSuffix("a.txt") })
        #expect(paths.contains { $0.hasSuffix("b 空格.txt") })

        let out = root.appendingPathComponent("out")
        try await engine.extract(
            archive: archive,
            options: ExtractOptions(
                items: ["src/sub/b 空格.txt"],
                destination: out,
                password: nil,
                overwrite: .overwrite,
                keepDirectoryStructure: true
            ),
            totalHint: nil,
            progress: nil
        )
        #expect(fm.fileExists(atPath: out.appendingPathComponent("src/sub/b 空格.txt").path))
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("src/a.txt").path))

        let result = try await engine.test(archive: archive, password: nil, totalHint: nil, progress: nil)
        #expect(result.ok)
    }

    @Test("Encrypted archive asks for a password instead of hanging")
    func encryptedArchiveRequiresPassword() async throws {
        let fm = FileManager.default
        let root = try makeWorkspace()
        defer { try? fm.removeItem(at: root) }

        let engine = try SevenZipEngine.detect()
        let src = try makeSourceTree(in: root)
        let archive = root.appendingPathComponent("secret.7z")

        try await engine.create(
            archive: archive,
            sources: [src],
            options: CreateOptions(
                format: .sevenZip,
                level: .fastest,
                password: "Secret123",
                encryptFileNames: true
            ),
            totalHint: nil,
            progress: nil
        )

        await #expect(throws: SevenZipError.self) {
            _ = try await engine.list(archive: archive, password: nil)
        }

        let info = try await engine.list(archive: archive, password: "Secret123")
        #expect(!info.entries.isEmpty)
    }

    @Test("Listing parser reads archive header and entries")
    func listingParserReadsHeaderAndEntries() {
        let text = """
        Listing archive: sample.7z

        --
        Path = sample.7z
        Type = 7z
        Physical Size = 20283
        Headers Size = 248
        Method = LZMA2:24k
        Solid = +
        Blocks = 1

        ----------
        Path = sample
        Size = 0
        Attributes = D drwxr-xr-x

        Path = sample/a.txt
        Size = 12
        Modified = 2026-10-10 04:06:28.2778634
        Attributes = A -rw-r--r--
        CRC = AF083B2D
        Encrypted = -
        Method = LZMA2:24k
        """
        let info = ArchiveListingParser.parse(text, url: URL(fileURLWithPath: "/tmp/sample.7z"))
        #expect(info.format == "7z")
        #expect(info.solid)
        #expect(info.physicalSize == 20283)
        #expect(info.entries.count == 2)
        #expect(info.entries.first?.isDirectory == true)
        #expect(info.entries.last?.crc == "AF083B2D")
        #expect(info.entries.last?.size == 12)
    }

    @Test("Nested selections collapse to their top most ancestor")
    func reduceNestedPaths() {
        let reduced = AppModel.reduceNested(["a/b/c.txt", "a/b", "a/x", "y.txt"])
        #expect(reduced == ["a/b", "a/x", "y.txt"])
    }

    @Test("Compression method and update options are honoured")
    func methodAndUpdateOptions() async throws {
        let fm = FileManager.default
        let root = try makeWorkspace()
        defer { try? fm.removeItem(at: root) }

        let engine = try SevenZipEngine.detect()
        let src = try makeSourceTree(in: root)
        let archive = root.appendingPathComponent("ppmd.7z")

        var options = CreateOptions(format: .sevenZip, level: .fast)
        options.method = "PPMd"
        options.threads = .one
        try await engine.create(archive: archive, sources: [src], options: options, totalHint: nil, progress: nil)

        let info = try await engine.list(archive: archive, password: nil)
        #expect((info.method ?? "").uppercased().contains("PPMD"))
    }

    @Test("Eliminate root folder drops a duplicated top directory")
    func eliminateRootFolder() async throws {
        let fm = FileManager.default
        let root = try makeWorkspace()
        defer { try? fm.removeItem(at: root) }

        let engine = try SevenZipEngine.detect()
        let src = try makeSourceTree(in: root)
        let archive = root.appendingPathComponent("root.7z")
        try await engine.create(
            archive: archive,
            sources: [src],
            options: CreateOptions(format: .sevenZip, level: .fastest),
            totalHint: nil,
            progress: nil
        )

        // Destination last component matches the archive root ("src").
        let out = root.appendingPathComponent("out/src")
        try await engine.extract(
            archive: archive,
            options: ExtractOptions(
                items: nil,
                destination: out,
                password: nil,
                overwrite: .overwrite,
                keepDirectoryStructure: true,
                eliminateRoot: true
            ),
            totalHint: nil,
            progress: nil
        )
        #expect(fm.fileExists(atPath: out.appendingPathComponent("a.txt").path))
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("src/a.txt").path))
    }
}
