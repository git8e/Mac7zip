import Foundation
import Combine

/// Languages the app can show. `system` follows the macOS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// The concrete `.lproj` code used for string lookup.
    var resolvedCode: String {
        switch self {
        case .system:
            let code = Locale.preferredLanguages.first ?? "en"
            return code.hasPrefix("zh") ? "zh-Hans" : "en"
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .system: return L("System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

/// Resolves localized strings from the chosen `.lproj` bundle.
///
/// English is the development language, so the base strings in code are already
/// English; only `zh-Hans.lproj` needs a translation table. Lookups are
/// thread-safe because engine errors can be described off the main thread.
final class Localization: ObservableObject {
    static let shared = Localization()
    private static let defaultsKey = "Mac7zip.language"

    @Published private(set) var language: AppLanguage = .system

    private let lock = NSLock()
    private var bundle: Bundle = .main

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        let initial = AppLanguage(rawValue: stored) ?? .system
        language = initial
        lock.lock()
        bundle = Self.resolve(initial)
        lock.unlock()
    }

    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
        let resolved = Self.resolve(newValue)
        lock.lock()
        bundle = resolved
        lock.unlock()
    }

    func string(_ key: String) -> String {
        lock.lock()
        let current = bundle
        lock.unlock()
        return current.localizedString(forKey: key, value: key, table: nil)
    }

    private static func resolve(_ language: AppLanguage) -> Bundle {
        let code = language.resolvedCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized
        }
        return .main
    }
}

/// Convenience accessor used throughout the UI and model layer.
func L(_ key: String) -> String {
    Localization.shared.string(key)
}

/// Localized `String(format:)` helper.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localization.shared.string(key), arguments: arguments)
}
