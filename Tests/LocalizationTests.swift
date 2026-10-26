import Foundation

/// Offline resource audit and actual Foundation bundle-selection tests.
/// Build with Sources/Localization.swift; no AppKit or Bluetooth framework is used.
/// --audit-only [project] reads resources/source only, without creating test bundles.
@main enum LocalizationTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]
    private static let tables = ["Localizable", "Transport", "InfoPlist"]
    private static let requiredInfoKeys: Set<String> = [
        "CFBundleName", "CFBundleDisplayName",
        "NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription"
    ]
    private static let uiProbe = "__localization_test_ui__"
    private static let transportProbe = "__localization_test_transport__"
    private static let missingKey = "__localization_test_English_fallback__"
    private static let formatProbe = "测试格式：%@ / %ld"

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "--localization-probe" {
                try runProbe()
                return
            }
            let auditOnly = arguments.first == "--audit-only"
            let projectArgument = auditOnly ? arguments.dropFirst().first : arguments.first
            let project = projectArgument.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let resources = project.appendingPathComponent("Resources", isDirectory: true)
            let catalogues = try audit(project: project)
            if !auditOnly {
                try testFormatValidation()
                try testLanguageSelection(resources: resources, catalogues: catalogues)
            }
            print(auditOnly
                ? "PASS: localization resource/source audit (read-only)."
                : "PASS: localization audit, format validation, and isolated-process Bundle language selection.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func dictionary(at url: URL) throws -> [String: String] {
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
        guard let dictionary = object as? [String: String] else {
            throw Failure("Not a string dictionary: \(url.path)")
        }
        return dictionary
    }

    /// Positional translations may reorder arguments, but cannot change their
    /// C vararg types, drop an argument, or introduce a malformed percent escape.
    private static func formatSignature(_ text: String) throws -> [String] {
        let regex = try NSRegularExpression(
            pattern: #"%(?:(\d+)\$)?[-+ #0']*(?:\d+)?(?:\.\d+)?(hh|ll|[hlLzjtq])?([@diuoxXfFeEgGaAcCsSpn%])"#
        )
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var matchedPercentOffsets = Set<Int>()
        var signature: [String] = []
        var nextArgument = 1
        var positional = false
        var sequential = false
        for match in matches {
            matchedPercentOffsets.insert(match.range.location)
            let conversion = ns.substring(with: match.range(at: 3))
            if conversion == "%" {
                matchedPercentOffsets.insert(match.range.location + 1)
                continue
            }
            try require(conversion != "n", "Disallowed %n format conversion")
            let position: Int
            if match.range(at: 1).location != NSNotFound {
                position = Int(ns.substring(with: match.range(at: 1))) ?? 0
                positional = true
                try require(position > 0, "Format argument positions are one-based")
            } else {
                position = nextArgument
                nextArgument += 1
                sequential = true
            }
            let length = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            signature.append("\(position):\(length)\(conversion)")
        }
        try require(!(positional && sequential), "Do not mix positional and sequential format arguments")
        for offset in 0..<ns.length where ns.character(at: offset) == 0x25 {
            try require(matchedPercentOffsets.contains(offset), "Malformed percent escape in: \(text)")
        }
        return signature.sorted()
    }

    private static func containsFormatArgument(_ text: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0']*(?:\d+)?(?:\.\d+)?(?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSpn]"#)
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private struct SourceUse {
        let table: String
        let key: String
        let formatted: Bool
        let location: String
    }

    private static func sourceUses(project: URL) throws -> [SourceUse] {
        let sourceDirectory = project.appendingPathComponent("Sources", isDirectory: true)
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])(TLF|TL|LF|L)\s*\(\s*"((?:\\.|[^"\\])*)""#)
        let unicodeEscape = try NSRegularExpression(pattern: #"\\u\{([0-9A-Fa-f]+)\}"#)
        var result: [SourceUse] = []
        for url in try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
            where url.pathExtension == "swift" && url.lastPathComponent != "Localization.swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let ns = source as NSString
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                let function = ns.substring(with: match.range(at: 1))
                var literal = ns.substring(with: match.range(at: 2))
                try require(!literal.contains(#"\("#), "Use LF/TLF placeholders instead of interpolated keys in \(url.lastPathComponent)")
                for escape in unicodeEscape.matches(in: literal, range: NSRange(literal.startIndex..., in: literal)).reversed() {
                    let hex = (literal as NSString).substring(with: escape.range(at: 1))
                    guard let value = UInt32(hex, radix: 16), UnicodeScalar(value) != nil else { throw Failure("Invalid Swift Unicode escape") }
                    let replacement: String
                    if value <= 0xFFFF { replacement = String(format: "\\u%04X", value) }
                    else {
                        let scalar = value - 0x10000
                        replacement = String(format: "\\u%04X\\u%04X", 0xD800 + (scalar >> 10), 0xDC00 + (scalar & 0x3FF))
                    }
                    literal = (literal as NSString).replacingCharacters(in: escape.range, with: replacement)
                }
                literal = literal.replacingOccurrences(of: #"\0"#, with: #"\u0000"#)
                let key = try JSONDecoder().decode(String.self, from: Data(("\"" + literal + "\"").utf8))
                let line = ns.substring(to: match.range.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                result.append(SourceUse(table: function.hasPrefix("T") ? "Transport" : "Localizable",
                                        key: key, formatted: function.hasSuffix("F"),
                                        location: "\(url.lastPathComponent):\(line)"))
            }
        }
        return result
    }

    private static func audit(project: URL) throws -> [String: [String: [String: String]]] {
        let resources = project.appendingPathComponent("Resources", isDirectory: true)
        var catalogues: [String: [String: [String: String]]] = [:]
        for language in languages {
            var localized: [String: [String: String]] = [:]
            for table in tables {
                let url = resources.appendingPathComponent("\(language).lproj/\(table).strings")
                localized[table] = try dictionary(at: url)
                try require(!(localized[table]?.isEmpty ?? true), "Empty table: \(language)/\(table)")
                try require(localized[table]!.values.allSatisfy { !$0.isEmpty }, "Empty translation: \(language)/\(table)")
            }
            catalogues[language] = localized
        }
        let source = try sourceUses(project: project)
        for table in tables {
            let english = catalogues["en"]![table]!
            for language in languages {
                let actual = catalogues[language]![table]!
                let missing = Set(english.keys).subtracting(actual.keys).sorted()
                let extra = Set(actual.keys).subtracting(english.keys).sorted()
                try require(missing.isEmpty && extra.isEmpty,
                            "Key mismatch \(language)/\(table): missing=\(missing), extra=\(extra)")
                for (key, translation) in actual where containsFormatArgument(key) || source.contains(where: { $0.table == table && $0.key == key && $0.formatted }) {
                    let expected = try formatSignature(key)
                    let actualSignature = try formatSignature(translation)
                    try require(expected == actualSignature, "Format mismatch \(language)/\(table): \(key)")
                }
            }
        }
        for use in source {
            try require(catalogues["en"]![use.table]![use.key] != nil,
                        "Missing \(use.table) key at \(use.location): \(use.key)")
        }
        for language in languages {
            let info = catalogues[language]!["InfoPlist"]!
            try require(requiredInfoKeys.isSubset(of: Set(info.keys)), "Missing localized identity/Bluetooth prompt: \(language)")
            if let prefix = catalogues[language]!["Localizable"]!["BLE 实验："] {
                for (key, translation) in catalogues[language]!["Transport"]! where key.hasPrefix("BLE 实验：") {
                    try require(translation.hasPrefix(prefix), "BLE status prefix differs between UI and Transport: \(language), \(key)")
                }
            }
        }
        let infoObject = try PropertyListSerialization.propertyList(from: Data(contentsOf: resources.appendingPathComponent("Info.plist")), options: [], format: nil)
        guard let info = infoObject as? [String: Any] else { throw Failure("Invalid Info.plist") }
        try require(info["CFBundleDevelopmentRegion"] as? String == "en", "English must be the bundle development language")
        try require(Set(info["CFBundleLocalizations"] as? [String] ?? []) == Set(languages), "Info.plist must advertise all supported app languages")
        for key in requiredInfoKeys {
            try require(info[key] as? String == catalogues["en"]!["InfoPlist"]![key], "Base Info.plist fallback must match English: \(key)")
        }
        print("Audited \(source.count) source lookups; \(catalogues["en"]!["Localizable"]!.count) UI and \(catalogues["en"]!["Transport"]!.count) transport keys in three languages.")
        return catalogues
    }

    private static func testFormatValidation() throws {
        try require(try formatSignature("%@ %ld") == formatSignature("%2$ld: %1$@"), "Positional translations should preserve vararg types")
        try require(try formatSignature("0x%04X") == formatSignature("%X"), "Format width is not an argument-type change")
        try require(try formatSignature("%ld") != formatSignature("%@"), "Format validation must catch type changes")
        try require(try formatSignature("100%%") == [], "Escaped percent has no argument")
        var rejectedMalformed = false
        do { _ = try formatSignature("%@ %") }
        catch { rejectedMalformed = true }
        try require(rejectedMalformed, "Format validation must reject a dangling percent escape")
    }

    private static func runProbe() throws {
        var output: [String: Any] = [
            "preferred": Bundle.main.preferredLocalizations,
            "ui": L(uiProbe), "transport": TL(transportProbe),
            "uiFallback": L(missingKey), "transportFallback": TL(missingKey),
            "uiFormat": LF(formatProbe, "Mac", 7), "transportFormat": TLF(formatProbe, "Mac", 7),
            "realUI": L("开始输入"), "unknown": L("__unregistered_key__")
        ]
        for key in requiredInfoKeys { output[key] = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
    }

    private static func testLanguageSelection(resources: URL, catalogues: [String: [String: [String: String]]]) throws {
        let files = FileManager.default
        let temporary = files.temporaryDirectory.appendingPathComponent("MacPhoneKeys-Localization-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("LocalizationProbe.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let copiedResources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try files.createDirectory(at: macOS, withIntermediateDirectories: true)
        try files.createDirectory(at: copiedResources, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("LocalizationTests")
        try files.copyItem(at: Bundle.main.executableURL!, to: executable)
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: resources.appendingPathComponent("Info.plist")), options: [], format: nil) as! [String: Any]
        info["CFBundleIdentifier"] = "local.MacPhoneKeys.LocalizationProbe"
        info["CFBundleExecutable"] = "LocalizationTests"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        for language in languages {
            let directory = copiedResources.appendingPathComponent("\(language).lproj", isDirectory: true)
            try files.copyItem(at: resources.appendingPathComponent("\(language).lproj"), to: directory)
            for table in ["Localizable", "Transport"] {
                var values = catalogues[language]![table]!
                values[table == "Localizable" ? uiProbe : transportProbe] = "\(table)/\(language)"
                values[formatProbe] = language == "en" ? "Item %2$ld: %1$@" : (language == "zh-Hans" ? "项目 %2$ld：%1$@" : "項目 %2$ld：%1$@")
                if language == "en" { values[missingKey] = "English fallback/\(table)" }
                try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
                    .write(to: directory.appendingPathComponent("\(table).strings"))
            }
        }
        let cases: [([String], String)] = [
            (["en"], "en"), (["en-US"], "en"), (["en-GB"], "en"),
            (["zh-Hans"], "zh-Hans"), (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"),
            (["zh-Hant"], "zh-Hant"), (["zh-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"),
            (["fr-FR"], "en"), (["de-DE", "zh-Hant"], "zh-Hant")
        ]
        for (preferences, expectedLanguage) in cases {
            let process = Process()
            process.executableURL = executable
            let languagesArgument = "(" + preferences.map { "\"\($0)\"" }.joined(separator: ",") + ")"
            process.arguments = ["--localization-probe", "-AppleLanguages", languagesArgument]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "Probe failed for \(preferences): \(String(data: errorData, encoding: .utf8) ?? "")")
            guard let actual = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("Invalid probe response") }
            let label = preferences.joined(separator: ",")
            try require((actual["preferred"] as? [String])?.first == expectedLanguage, "Bundle language selection for \(label): \(actual)")
            try require(actual["ui"] as? String == "Localizable/\(expectedLanguage)", "UI table language for \(label)")
            try require(actual["transport"] as? String == "Transport/\(expectedLanguage)", "Transport table language for \(label)")
            try require(actual["uiFallback"] as? String == "English fallback/Localizable", "Per-key UI English fallback for \(label)")
            try require(actual["transportFallback"] as? String == "English fallback/Transport", "Per-key Transport English fallback for \(label)")
            let formatted = expectedLanguage == "en" ? "Item 7: Mac" : (expectedLanguage == "zh-Hans" ? "项目 7：Mac" : "項目 7：Mac")
            try require(actual["uiFormat"] as? String == formatted && actual["transportFormat"] as? String == formatted, "Actual LF/TLF positional formatting for \(label)")
            try require(actual["realUI"] as? String == catalogues[expectedLanguage]!["Localizable"]!["开始输入"], "Production UI resource lookup for \(label)")
            try require(actual["unknown"] as? String == "__unregistered_key__", "Unknown key must remain readable")
            for key in requiredInfoKeys {
                try require(actual[key] as? String == catalogues[expectedLanguage]!["InfoPlist"]![key], "Actual localized Info.plist \(key) for \(label)")
            }
        }
        print("Verified \(cases.count) isolated process language/region preferences, actual LF/TLF formatting, English fallback, and localized Info.plist prompts.")
    }
}
