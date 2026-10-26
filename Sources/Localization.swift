import Foundation

/// Uses Foundation's normal bundle language selection, including macOS's
/// per-app language preference. No preferred-language defaults are changed here.
/// English is the development language and the fallback for a missing key.
private enum AppLocalization {
    private static let englishBundle: Bundle? = {
        guard let url = Bundle.main.url(forResource: "en", withExtension: "lproj") else { return nil }
        return Bundle(url: url)
    }()

    static func text(_ source: String, table: String) -> String {
        let fallback = englishBundle?.localizedString(forKey: source, value: source, table: table) ?? source
        return Bundle.main.localizedString(forKey: source, value: fallback, table: table)
    }

    static func format(_ source: String, table: String, arguments: [CVarArg]) -> String {
        String(format: text(source, table: table), locale: Locale.current, arguments: arguments)
    }
}

/// App interface text. The original Chinese string is the stable resource key.
func L(_ sourceChinese: String) -> String {
    AppLocalization.text(sourceChinese, table: "Localizable")
}

func LF(_ sourceChinese: String, _ arguments: CVarArg...) -> String {
    AppLocalization.format(sourceChinese, table: "Localizable", arguments: arguments)
}

/// Bluetooth transport status and diagnostics use a separate table.
func TL(_ sourceChinese: String) -> String {
    AppLocalization.text(sourceChinese, table: "Transport")
}

func TLF(_ sourceChinese: String, _ arguments: CVarArg...) -> String {
    AppLocalization.format(sourceChinese, table: "Transport", arguments: arguments)
}
