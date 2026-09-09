import Combine
import Foundation

/// Lightweight in-app language selection for the production SwiftUI surfaces.
/// Legacy feature-copy dictionaries are intentionally not compiled into the
/// release binary; every current product string is colocated with its view.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var currentLanguage: String

    private static let supportedLanguages: Set<String> = ["en", "zh"]
    private static let defaultsKey = "app_language"

    private init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        let preferred = locale.language.languageCode?.identifier == "zh" ? "zh" : "en"
        let stored = defaults.string(forKey: Self.defaultsKey)
        currentLanguage = stored.flatMap {
            Self.supportedLanguages.contains($0) ? $0 : nil
        } ?? preferred
    }

    func setLanguage(_ language: String) {
        guard Self.supportedLanguages.contains(language),
              language != currentLanguage else {
            return
        }
        currentLanguage = language
        UserDefaults.standard.set(language, forKey: Self.defaultsKey)
    }
}
