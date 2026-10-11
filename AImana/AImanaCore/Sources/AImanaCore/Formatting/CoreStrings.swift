import Foundation

/// Localized copy owned by the package, independent of the app and widget bundles.
public enum CoreStrings {
    #if os(Linux)
    // SwiftPM copies string catalogs as resources on Linux, but does not compile them into .lproj bundles.
    private static let catalog: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let strings = root["strings"] as? [String: [String: Any]] ?? [:]
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { localization in
                (localization["stringUnit"] as? [String: Any])?["value"] as? String
            }
        }
    }()
    #endif

    public static func text(_ key: String, locale: Locale? = nil) -> String {
        let language = locale?.identifier ?? Locale.preferredLanguages.first ?? "en"
        let candidates = [language, language.replacingOccurrences(of: "_", with: "-"),
                          String(language.prefix(2)), "en"]
        #if os(Linux)
        for candidate in candidates {
            if let value = catalog[key]?[candidate] { return value }
        }
        return key
        #else
        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle.localizedString(forKey: key, value: key, table: nil)
            }
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        #endif
    }

    public static func format(_ key: String, locale: Locale? = nil, _ arguments: CVarArg...) -> String {
        let resolved = locale ?? Locale(identifier: Locale.preferredLanguages.first ?? "en")
        return String(format: text(key, locale: resolved), locale: resolved, arguments: arguments)
    }
}
