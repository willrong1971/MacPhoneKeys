import Foundation

@main
enum KeyMappingTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        // These expected values come from the USB HID Keyboard/Keypad usage page.
        let physicalKeys: [(UInt16, UInt8)] = [
            (0, 0x04), (11, 0x05), (8, 0x06), (2, 0x07),
            (14, 0x08), (3, 0x09), (5, 0x0A), (4, 0x0B),
            (34, 0x0C), (38, 0x0D), (40, 0x0E), (37, 0x0F),
            (46, 0x10), (45, 0x11), (31, 0x12), (35, 0x13),
            (12, 0x14), (15, 0x15), (1, 0x16), (17, 0x17),
            (32, 0x18), (9, 0x19), (13, 0x1A), (7, 0x1B),
            (16, 0x1C), (6, 0x1D),
            (18, 0x1E), (19, 0x1F), (20, 0x20), (21, 0x21),
            (23, 0x22), (22, 0x23), (26, 0x24), (28, 0x25),
            (25, 0x26), (29, 0x27),
            (36, 0x28), (53, 0x29), (51, 0x2A), (48, 0x2B), (49, 0x2C),
            (27, 0x2D), (24, 0x2E), (33, 0x2F), (30, 0x30),
            (42, 0x31), (41, 0x33), (39, 0x34), (50, 0x35),
            (43, 0x36), (47, 0x37), (44, 0x38),
            (124, 0x4F), (123, 0x50), (125, 0x51), (126, 0x52),
            (115, 0x4A), (116, 0x4B), (117, 0x4C), (119, 0x4D), (121, 0x4E),
            (122, 0x3A), (111, 0x45), (76, 0x58), (82, 0x62),
        ]
        for (keyCode, usage) in physicalKeys {
            expect(KeyMapping.usage(forMacKeyCode: keyCode) == usage,
                   "mac key \(keyCode) must map to HID \(usage)")
        }
        expect(KeyMapping.usage(forMacKeyCode: 0xFFFF) == nil, "unknown key is refused")
        expect(KeyMapping.usage(forMacKeyCode: 55) == nil, "Command is encoded as modifier")

        let flags: [(UInt, UInt8)] = [
            (0, 0), (1 << 18, 0x01), (1 << 17, 0x02),
            (1 << 19, 0x04), (1 << 20, 0x08),
            ((1 << 17) | (1 << 20), 0x0A),
            ((1 << 17) | (1 << 18) | (1 << 19) | (1 << 20), 0x0F),
            ((1 << 16) | (1 << 21) | (1 << 23), 0),
        ]
        for (rawFlags, expected) in flags {
            expect(KeyMapping.modifierByte(rawFlags: rawFlags) == expected,
                   "modifier flags \(rawFlags) must encode \(expected)")
        }

        func expectStroke(_ character: Character, modifier: UInt8, usage: UInt8) {
            guard let actual = KeyMapping.asciiStroke(character) else {
                expect(false, "expected stroke for \(character)")
                return
            }
            expect(actual.modifier == modifier && actual.usage == usage,
                   "incorrect ASCII stroke for \(character)")
        }
        for (index, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            expectStroke(letter, modifier: 0, usage: UInt8(index + 4))
        }
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            expectStroke(letter, modifier: 0x02, usage: UInt8(index + 4))
        }
        for (index, digit) in "1234567890".enumerated() {
            expectStroke(digit, modifier: 0, usage: UInt8(index + 0x1E))
        }
        for (index, symbol) in "!@#$%^&*()".enumerated() {
            expectStroke(symbol, modifier: 0x02, usage: UInt8(index + 0x1E))
        }
        let punctuation: [(Character, Character, UInt8)] = [
            ("-", "_", 0x2D), ("=", "+", 0x2E), ("[", "{", 0x2F),
            ("]", "}", 0x30), ("\\", "|", 0x31), (";", ":", 0x33),
            ("'", "\"", 0x34), ("`", "~", 0x35), (",", "<", 0x36),
            (".", ">", 0x37), ("/", "?", 0x38),
        ]
        for (plain, shifted, usage) in punctuation {
            expectStroke(plain, modifier: 0, usage: usage)
            expectStroke(shifted, modifier: 0x02, usage: usage)
        }
        expectStroke("\n", modifier: 0, usage: 0x28)
        expectStroke("\r", modifier: 0, usage: 0x28)
        expectStroke("\t", modifier: 0, usage: 0x2B)
        expectStroke(" ", modifier: 0, usage: 0x2C)
        expectStroke("\u{08}", modifier: 0, usage: 0x2A)
        expectStroke("\u{1B}", modifier: 0, usage: 0x29)
        for character: Character in ["中", "文", "é", "😀", "\u{00}"] {
            expect(KeyMapping.asciiStroke(character) == nil,
                   "unsupported character must not become a keystroke: \(character)")
        }
        print("PASS: \(checks) keyboard mapping checks")
    }
}
