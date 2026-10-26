#!/usr/bin/env swift
import Foundation

// Keep lookup keys unchanged: Swift sources use the Simplified Chinese key.
// Only resource values are converted with macOS's built-in ICU transform.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = project.appendingPathComponent("Resources/zh-Hans.lproj")
let destination = project.appendingPathComponent("Resources/zh-Hant.lproj")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func quoted(_ string: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return String(data: data, encoding: .utf8)!
}

for table in ["Localizable", "Transport"] {
    let input = try Data(contentsOf: source.appendingPathComponent(table + ".strings"))
    guard let values = try PropertyListSerialization.propertyList(from: input, options: [], format: nil) as? [String: String] else {
        fatalError("Expected a string dictionary for \(table)")
    }
    var output = "/* Generated from zh-Hans values; lookup keys are unchanged. */\n"
    for key in values.keys.sorted() {
        let value = values[key]!
        guard let traditional = value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) else {
            fatalError("Hans-Hant transform is unavailable")
        }
        output += try quoted(key) + " = " + quoted(traditional) + ";\n"
    }
    try output.write(to: destination.appendingPathComponent(table + ".strings"), atomically: true, encoding: .utf8)
    print("Generated zh-Hant \(table): \(values.count) keys")
}
