import Foundation

enum EngineError: Error, LocalizedError {
    case engineNotFound

    var errorDescription: String? {
        L("The bundled 7-Zip engine (7zz) was not found. Please reinstall the app.")
    }
}

/// Locates a usable `7zz` executable, whether we run from an assembled
/// `.app` bundle, from `swift run`, or with an explicit override.
enum EngineLocator {
    static let engineURL: URL? = locate()

    static func requireEngine() throws -> URL {
        if let url = engineURL { return url }
        throw EngineError.engineNotFound
    }

    private static func locate() -> URL? {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["MAC7ZIP_ENGINE"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        // Copy inside the assembled .app: Contents/Resources/7zz
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("7zz"))
        }

        // Next to the running executable.
        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent("7zz"))
        }

        // Development fallback: the vendored copy in the package.
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Engine
            .deletingLastPathComponent()   // Mac7Zip
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Vendor/7zz")
        candidates.append(devPath)

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            if let ready = makeExecutableIfNeeded(candidate) {
                return ready
            }
        }
        return nil
    }

    /// If `7zz` is already executable we use it in place. Otherwise (for
    /// example a read-only mounted bundle) we copy it to a writable cache and
    /// fix its permissions there.
    private static func makeExecutableIfNeeded(_ url: URL) -> URL? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: url.path) { return url }

        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("Mac7Zip", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("7zz")
        try? fm.removeItem(at: destination)
        do {
            try fm.copyItem(at: url, to: destination)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }
}
