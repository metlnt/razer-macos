import Foundation

/// USB HID keyboard usages, with macOS virtual key codes (kVK_*) for recording shortcuts.
public enum HIDKeys {
    public struct Key {
        public let hid: UInt8
        public let vk: UInt16?
        public let name: String
    }

    public static let modCtrl: UInt8 = 0x01, modShift: UInt8 = 0x02, modAlt: UInt8 = 0x04, modCmd: UInt8 = 0x08

    public static let all: [Key] = {
        var k: [Key] = []
        let letters: [(String, UInt16)] = [
            ("A", 0x00), ("B", 0x0B), ("C", 0x08), ("D", 0x02), ("E", 0x0E), ("F", 0x03), ("G", 0x05),
            ("H", 0x04), ("I", 0x22), ("J", 0x26), ("K", 0x28), ("L", 0x25), ("M", 0x2E), ("N", 0x2D),
            ("O", 0x1F), ("P", 0x23), ("Q", 0x0C), ("R", 0x0F), ("S", 0x01), ("T", 0x11), ("U", 0x20),
            ("V", 0x09), ("W", 0x0D), ("X", 0x07), ("Y", 0x10), ("Z", 0x06),
        ]
        for (i, (n, vk)) in letters.enumerated() { k.append(Key(hid: 0x04 + UInt8(i), vk: vk, name: n)) }
        let digits: [(String, UInt16)] = [
            ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17),
            ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19), ("0", 0x1D),
        ]
        for (i, (n, vk)) in digits.enumerated() { k.append(Key(hid: 0x1E + UInt8(i), vk: vk, name: n)) }
        k += [
            Key(hid: 0x28, vk: 0x24, name: "↩"), Key(hid: 0x29, vk: 0x35, name: "Esc"),
            Key(hid: 0x2A, vk: 0x33, name: "⌫"), Key(hid: 0x2B, vk: 0x30, name: "⇥"),
            Key(hid: 0x2C, vk: 0x31, name: "Space"), Key(hid: 0x2D, vk: 0x1B, name: "-"),
            Key(hid: 0x2E, vk: 0x18, name: "="), Key(hid: 0x2F, vk: 0x21, name: "["),
            Key(hid: 0x30, vk: 0x1E, name: "]"), Key(hid: 0x31, vk: 0x2A, name: "\\"),
            Key(hid: 0x33, vk: 0x29, name: ";"), Key(hid: 0x34, vk: 0x27, name: "'"),
            Key(hid: 0x35, vk: 0x32, name: "`"), Key(hid: 0x36, vk: 0x2B, name: ","),
            Key(hid: 0x37, vk: 0x2F, name: "."), Key(hid: 0x38, vk: 0x2C, name: "/"),
        ]
        let fkeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (i, vk) in fkeys.enumerated() { k.append(Key(hid: 0x3A + UInt8(i), vk: vk, name: "F\(i + 1)")) }
        k += [
            Key(hid: 0x4A, vk: 0x73, name: "Home"), Key(hid: 0x4B, vk: 0x74, name: "PgUp"),
            Key(hid: 0x4C, vk: 0x75, name: "⌦"), Key(hid: 0x4D, vk: 0x77, name: "End"),
            Key(hid: 0x4E, vk: 0x79, name: "PgDn"), Key(hid: 0x4F, vk: 0x7C, name: "→"),
            Key(hid: 0x50, vk: 0x7B, name: "←"), Key(hid: 0x51, vk: 0x7D, name: "↓"),
            Key(hid: 0x52, vk: 0x7E, name: "↑"),
        ]
        let f13: [UInt16?] = [0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
        for (i, vk) in f13.enumerated() { k.append(Key(hid: 0x68 + UInt8(i), vk: vk, name: "F\(i + 13)")) }
        k += [
            Key(hid: 0x7F, vk: 0x4A, name: "Mute"), Key(hid: 0x80, vk: 0x48, name: "Vol+"),
            Key(hid: 0x81, vk: 0x49, name: "Vol−"),
        ]
        return k
    }()

    private static let byHID = Dictionary(uniqueKeysWithValues: all.map { ($0.hid, $0) })
    private static let byVK = Dictionary(all.compactMap { k in k.vk.map { ($0, k) } }, uniquingKeysWith: { a, _ in a })

    public static func key(hid: UInt8) -> Key? { byHID[hid] }
    public static func key(virtualKeyCode: UInt16) -> Key? { byVK[virtualKeyCode] }

    public static func describe(modifiers m: UInt8, key: UInt8) -> String {
        var s = ""
        if m & 0x11 != 0 { s += "⌃" }
        if m & 0x44 != 0 { s += "⌥" }
        if m & 0x22 != 0 { s += "⇧" }
        if m & 0x88 != 0 { s += "⌘" }
        return s + (byHID[key]?.name ?? String(format: "0x%02X", key))
    }
}
