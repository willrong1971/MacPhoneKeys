import Foundation

/// Converts macOS virtual key codes to USB HID keyboard usages.
///
/// Physical keys follow the ANSI layout. Text composition, keyboard layout and
/// candidate selection belong to the receiving iPhone's hardware-keyboard input
/// method; a USB keyboard report cannot directly contain arbitrary Unicode text.
enum KeyMapping {
    static let leftControl: UInt8 = 0x01
    static let leftShift: UInt8 = 0x02
    static let leftOption: UInt8 = 0x04
    static let leftCommand: UInt8 = 0x08

    private static let usages: [UInt16: UInt8] = [
        // ANSI letters.
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A,
        6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19, 11: 0x05,
        12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17,
        31: 0x12, 32: 0x18, 34: 0x0C, 35: 0x13,
        37: 0x0F, 38: 0x0D, 40: 0x0E, 45: 0x11, 46: 0x10,
        // ANSI number row and punctuation.
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
        24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D, 28: 0x25, 29: 0x27,
        30: 0x30, 33: 0x2F, 39: 0x34, 41: 0x33, 42: 0x31,
        43: 0x36, 44: 0x38, 47: 0x37, 50: 0x35,
        // Editing and navigation.
        36: 0x28, 48: 0x2B, 49: 0x2C, 51: 0x2A, 53: 0x29,
        115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E,
        123: 0x50, 124: 0x4F, 125: 0x51, 126: 0x52,
        // Function keys.
        122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D,
        96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41,
        101: 0x42, 109: 0x43, 103: 0x44, 111: 0x45,
        // Numeric keypad.
        65: 0x63, 67: 0x55, 69: 0x57, 71: 0x53, 75: 0x54,
        76: 0x58, 78: 0x56, 81: 0x67, 82: 0x62,
        83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D,
        88: 0x5E, 89: 0x5F, 91: 0x60, 92: 0x61,
    ]

    static func usage(forMacKeyCode keyCode: UInt16) -> UInt8? {
        usages[keyCode]
    }

    /// NSEvent.ModifierFlags raw values. Left-side modifier bits are sufficient
    /// for this minimal keyboard. Caps Lock is a lock key, not a modifier bit.
    static func modifierByte(rawFlags: UInt) -> UInt8 {
        var result: UInt8 = 0
        if rawFlags & (1 << 18) != 0 { result |= leftControl }
        if rawFlags & (1 << 17) != 0 { result |= leftShift }
        if rawFlags & (1 << 19) != 0 { result |= leftOption }
        if rawFlags & (1 << 20) != 0 { result |= leftCommand }
        return result
    }

    /// A US-ANSI keystroke for an ASCII character, for connection-test typing.
    /// The recipient must use an English/US hardware-keyboard layout for literal
    /// text. This intentionally refuses Chinese and other Unicode characters.
    static func asciiStroke(_ character: Character) -> (modifier: UInt8, usage: UInt8)? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value < 128 else { return nil }

        let value = scalar.value
        switch value {
        case 0x61...0x7A:
            return (0, UInt8(value - 0x61 + 0x04))
        case 0x41...0x5A:
            return (leftShift, UInt8(value - 0x41 + 0x04))
        case 0x31...0x39:
            return (0, UInt8(value - 0x31 + 0x1E))
        default:
            break
        }

        switch character {
        case "0": return (0, 0x27)
        case "\n", "\r": return (0, 0x28)
        case "\u{08}": return (0, 0x2A)
        case "\t": return (0, 0x2B)
        case "\u{1B}": return (0, 0x29)
        case " ": return (0, 0x2C)
        case "-": return (0, 0x2D)
        case "=": return (0, 0x2E)
        case "[": return (0, 0x2F)
        case "]": return (0, 0x30)
        case "\\": return (0, 0x31)
        case ";": return (0, 0x33)
        case "'": return (0, 0x34)
        case "`": return (0, 0x35)
        case ",": return (0, 0x36)
        case ".": return (0, 0x37)
        case "/": return (0, 0x38)
        case "!": return (leftShift, 0x1E)
        case "@": return (leftShift, 0x1F)
        case "#": return (leftShift, 0x20)
        case "$": return (leftShift, 0x21)
        case "%": return (leftShift, 0x22)
        case "^": return (leftShift, 0x23)
        case "&": return (leftShift, 0x24)
        case "*": return (leftShift, 0x25)
        case "(": return (leftShift, 0x26)
        case ")": return (leftShift, 0x27)
        case "_": return (leftShift, 0x2D)
        case "+": return (leftShift, 0x2E)
        case "{": return (leftShift, 0x2F)
        case "}": return (leftShift, 0x30)
        case "|": return (leftShift, 0x31)
        case ":": return (leftShift, 0x33)
        case "\"": return (leftShift, 0x34)
        case "~": return (leftShift, 0x35)
        case "<": return (leftShift, 0x36)
        case ">": return (leftShift, 0x37)
        case "?": return (leftShift, 0x38)
        default: return nil
        }
    }
}
