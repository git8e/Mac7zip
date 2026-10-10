import Foundation

struct ProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var combined: String { stdout + "\n" + stderr }
}

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(Error)

    var errorDescription: String? {
        if case .launchFailed(let error) = self {
            return LF("Failed to launch the 7-Zip engine: %@", error.localizedDescription)
        }
        return nil
    }
}

/// Runs the `7zz` command line tool and streams its output.
///
/// `stdin` is always connected to `/dev/null` so that 7-Zip never blocks
/// waiting for a password typed on a terminal.
enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outCapture = OutputCapture(onLine: onStdoutLine)
        let errCapture = OutputCapture(onLine: onStderrLine)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outCapture.append(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errCapture.append(data) }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                process.terminationHandler = { finished in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    outCapture.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                    errCapture.append(errPipe.fileHandleForReading.readDataToEndOfFile())

                    let output = ProcessOutput(
                        exitCode: finished.terminationStatus,
                        stdout: outCapture.fullString,
                        stderr: errCapture.fullString
                    )
                    continuation.resume(returning: output)
                }

                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Thread-safe accumulator that keeps the full output and also delivers
/// complete lines (split on `\n`) to a callback as they arrive.
private final class OutputCapture {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    private var scanStart = 0
    private let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        bytes.append(contentsOf: data)
        var lines: [String] = []
        var index = scanStart
        let count = bytes.count
        while index < count {
            if bytes[index] == 0x0A {
                lines.append(String(decoding: bytes[scanStart..<index], as: UTF8.self))
                scanStart = index + 1
            }
            index += 1
        }
        lock.unlock()
        if let onLine {
            for line in lines { onLine(line) }
        }
    }

    var fullString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
