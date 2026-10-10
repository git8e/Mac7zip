import Foundation

typealias ProgressHandler = (OperationProgress) -> Void

struct ExtractOptions {
    /// Archive-internal paths to extract. `nil` means "everything".
    var items: [String]?
    var destination: URL
    var password: String?
    var overwrite: OverwriteMode = .overwrite
    var keepDirectoryStructure: Bool = true
}

enum SevenZipError: Error, LocalizedError {
    case passwordRequired
    case wrongPassword
    case cancelled
    case notAnArchive(String)
    case failed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return L("This archive is encrypted. A password is required.")
        case .wrongPassword:
            return L("Wrong password, or the archive is corrupted.")
        case .cancelled:
            return L("Operation cancelled.")
        case .notAnArchive(let message):
            return message.isEmpty
                ? L("Cannot open the archive. The file may not be an archive or the format is unsupported.")
                : message
        case .failed(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? LF("7-Zip returned an error (code %d).", code) : trimmed
        }
    }
}

/// Thin wrapper around the bundled `7zz` console tool. All heavy lifting
/// (parsing formats, codecs, encryption) is done by the official 7-Zip engine
/// so behaviour matches the Windows build.
final class SevenZipEngine {
    let executable: URL

    init(executable: URL) {
        self.executable = executable
    }

    static func detect() throws -> SevenZipEngine {
        SevenZipEngine(executable: try EngineLocator.requireEngine())
    }

    static var isAvailable: Bool { EngineLocator.engineURL != nil }

    // MARK: - Version

    func version() async -> String? {
        guard let output = try? await ProcessRunner.run(executable: executable, arguments: []) else {
            return nil
        }
        return output.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("7-Zip") }
    }

    // MARK: - Listing

    func list(archive: URL, password: String?) async throws -> ArchiveInfo {
        var arguments = ["l", "-slt", "-sccUTF-8", "-bd"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(archive.path)

        let output = try await runChecked(arguments, passwordProvided: password != nil)
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: password != nil)
        }
        return ArchiveListingParser.parse(output.stdout, url: archive)
    }

    // MARK: - Extract

    func extract(
        archive: URL,
        options: ExtractOptions,
        totalHint: Int?,
        progress: ProgressHandler?
    ) async throws {
        var arguments = ["x", "-y", "-sccUTF-8", "-bb1", "-bsp0", options.overwrite.switchValue]
        if !options.keepDirectoryStructure { arguments.append("-e") }
        arguments.append("-o" + options.destination.path)
        if let password = options.password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(archive.path)
        if let items = options.items { arguments.append(contentsOf: items) }

        let counter = ProgressCounter(title: L("Extracting…"), total: totalHint ?? 0)
        let output = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            onStdoutLine: { line in Self.report(line, counter: counter, progress: progress) }
        )
        if Task.isCancelled { throw SevenZipError.cancelled }
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: options.password?.isEmpty == false)
        }
    }

    // MARK: - Create / add

    func create(
        archive: URL,
        sources: [URL],
        options: CreateOptions,
        totalHint: Int?,
        progress: ProgressHandler?
    ) async throws {
        guard !sources.isEmpty else { return }

        let workingDirectory = Self.commonParent(of: sources) ?? sources[0].deletingLastPathComponent()
        let relativeSources = sources.map { Self.relativePath(of: $0, from: workingDirectory) }

        var arguments = ["a", "-y", "-sccUTF-8", "-bb1", "-bsp0", options.format.typeSwitch, options.level.switchValue]

        if options.format.supportsSolid, !options.solid {
            arguments.append("-ms=off")
        }
        if let password = options.password, !password.isEmpty {
            arguments.append("-p" + password)
            if options.format == .zip {
                arguments.append("-mem=AES256")
            }
            if options.encryptFileNames && options.format.supportsEncryptNames {
                arguments.append("-mhe=on")
            }
        }
        if let volume = options.volumeSize?.trimmingCharacters(in: .whitespaces), !volume.isEmpty,
           options.format.supportsMultiVolume {
            arguments.append("-v" + volume)
        }

        arguments.append(archive.path)
        arguments.append(contentsOf: relativeSources)

        let counter = ProgressCounter(title: L("Compressing…"), total: totalHint ?? 0)
        let output = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: workingDirectory,
            onStdoutLine: { line in Self.report(line, counter: counter, progress: progress, prefixes: ["+", "-"]) }
        )
        if Task.isCancelled { throw SevenZipError.cancelled }
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: options.password?.isEmpty == false)
        }
    }

    // MARK: - Test

    @discardableResult
    func test(
        archive: URL,
        password: String?,
        totalHint: Int?,
        progress: ProgressHandler?
    ) async throws -> TestResult {
        var arguments = ["t", "-y", "-sccUTF-8", "-bb1", "-bsp0"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(archive.path)

        let counter = ProgressCounter(title: L("Testing…"), total: totalHint ?? 0)
        let output = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            onStdoutLine: { line in Self.report(line, counter: counter, progress: progress) }
        )
        if Task.isCancelled { throw SevenZipError.cancelled }

        let combined = output.combined
        let ok = output.exitCode == 0 && combined.contains("Everything is Ok")
        if !ok {
            try throwForExit(output, passwordProvided: password?.isEmpty == false)
        }
        let summary = Self.summary(from: combined)
        return TestResult(
            ok: ok,
            message: ok ? "Everything is Ok" : Self.tailError(from: combined),
            files: summary.files,
            size: summary.size
        )
    }

    // MARK: - Delete entries

    func delete(archive: URL, items: [String], password: String?) async throws {
        guard !items.isEmpty else { return }
        var arguments = ["d", "-y", "-sccUTF-8", "-bb1", "-bso0"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(archive.path)
        arguments.append(contentsOf: items)

        let output = try await runChecked(arguments, passwordProvided: password?.isEmpty == false)
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: password?.isEmpty == false)
        }
    }

    // MARK: - Rename inside archive

    /// Renames one or more items inside the archive. 7-Zip's `rn` command takes
    /// a single old/new pair per invocation, so pairs are applied in turn.
    func rename(archive: URL, pairs: [(from: String, to: String)], password: String?) async throws {
        for pair in pairs where pair.from != pair.to {
            var arguments = ["rn", "-y", "-sccUTF-8", "-bso0", "-bsp0"]
            if let password, !password.isEmpty { arguments.append("-p" + password) }
            arguments.append(archive.path)
            arguments.append(pair.from)
            arguments.append(pair.to)
            let output = try await runChecked(arguments, passwordProvided: password?.isEmpty == false)
            if output.exitCode != 0 {
                try throwForExit(output, passwordProvided: password?.isEmpty == false)
            }
        }
    }

    // MARK: - Add items to an existing archive

    /// Adds items (paths relative to `workingDirectory`) to an existing archive
    /// without changing its format or settings. Used for Create Folder/File and
    /// for dropping files into an open archive.
    func addItems(
        archive: URL,
        relativeItems: [String],
        workingDirectory: URL,
        password: String?
    ) async throws {
        guard !relativeItems.isEmpty else { return }
        var arguments = ["a", "-y", "-sccUTF-8", "-bso0", "-bsp0"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(archive.path)
        arguments.append(contentsOf: relativeItems)

        let output = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: workingDirectory
        )
        if Task.isCancelled { throw SevenZipError.cancelled }
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: password?.isEmpty == false)
        }
    }

    // MARK: - Checksum

    /// Computes a checksum of a file on disk using 7-Zip's `h` command.
    func checksum(of url: URL, algorithm: String) async throws -> String {
        let arguments = ["h", "-scrc" + algorithm, "-bsp0", url.path]
        let output = try await runChecked(arguments, passwordProvided: true)
        if output.exitCode != 0 {
            try throwForExit(output, passwordProvided: true)
        }
        for raw in output.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix(algorithm.lowercased() + " for data:") {
                guard let colon = line.lastIndex(of: ":") else { continue }
                return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    // MARK: - Helpers

    @discardableResult
    private func runChecked(_ arguments: [String], passwordProvided: Bool) async throws -> ProcessOutput {
        let output = try await ProcessRunner.run(executable: executable, arguments: arguments)
        if Task.isCancelled { throw SevenZipError.cancelled }
        try detectPasswordProblem(output, passwordProvided: passwordProvided)
        return output
    }

    private static func report(
        _ rawLine: String,
        counter: ProgressCounter,
        progress: ProgressHandler?,
        prefixes: [String] = ["-"]
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        for prefix in prefixes where line.hasPrefix(prefix + " ") {
            let name = String(line.dropFirst(prefix.count + 1))
            let processed = counter.increment()
            progress?(OperationProgress(
                title: counter.title,
                detail: name,
                processed: processed,
                total: counter.total
            ))
            return
        }
    }

    private func detectPasswordProblem(_ output: ProcessOutput, passwordProvided: Bool) throws {
        let lower = output.combined.lowercased()
        if lower.contains("wrong password") {
            throw SevenZipError.wrongPassword
        }
        if lower.contains("enter password") || lower.contains("password is required") {
            throw SevenZipError.passwordRequired
        }
        if output.exitCode == 255 && !passwordProvided {
            throw SevenZipError.passwordRequired
        }
    }

    private func throwForExit(_ output: ProcessOutput, passwordProvided: Bool) throws {
        try detectPasswordProblem(output, passwordProvided: passwordProvided)
        if output.exitCode == 0 { return }
        let message = Self.firstErrorLine(from: output.combined) ?? ""
        if output.exitCode == 2 {
            throw SevenZipError.notAnArchive(message)
        }
        throw SevenZipError.failed(code: output.exitCode, message: message)
    }

    private static func firstErrorLine(from text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("ERROR") || $0.hasPrefix("Can't open") || $0.hasPrefix("Cannot open") }
    }

    private static func tailError(from text: String) -> String {
        firstErrorLine(from: text) ?? L("The archive has problems.")
    }

    private static func summary(from text: String) -> (files: Int, size: UInt64) {
        var files = 0
        var size: UInt64 = 0
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Files:") {
                files = Int(line.dropFirst("Files:".count).trimmingCharacters(in: .whitespaces)) ?? files
            } else if line.hasPrefix("Size:") {
                let value = line.dropFirst("Size:".count).trimmingCharacters(in: .whitespaces)
                size = UInt64(value) ?? size
            }
        }
        return (files, size)
    }

    static func commonParent(of urls: [URL]) -> URL? {
        guard var common = urls.first?.deletingLastPathComponent() else { return nil }
        for url in urls.dropFirst() {
            let parent = url.deletingLastPathComponent()
            while !parent.path.hasPrefix(common.path) {
                let next = common.deletingLastPathComponent()
                if next.path == common.path { return common }
                common = next
            }
        }
        return common
    }

    static func relativePath(of url: URL, from base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        if url.path.hasPrefix(basePath) {
            return String(url.path.dropFirst(basePath.count))
        }
        return url.lastPathComponent
    }
}

/// Thread-safe counter used to turn "one line per processed file" into progress.
final class ProgressCounter {
    let title: String
    let total: Int
    private var value = 0
    private let lock = NSLock()

    init(title: String, total: Int) {
        self.title = title
        self.total = total
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
