import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш: код физической клавиши + модификаторы.
/// Хранится в UserDefaults строкой `"код:модификаторы"`, поэтому подходит для `@AppStorage`.
struct Hotkey: Equatable, Sendable, RawRepresentable {
    static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let defaultStart = Hotkey(keyCode: UInt32(kVK_ANSI_T), modifiers: [.control, .option])
    static let defaultPause = Hotkey(keyCode: UInt32(kVK_ANSI_P), modifiers: [.control, .option])

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let code = UInt32(parts[0]), let flags = UInt(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    var rawValue: String { "\(keyCode):\(modifiers.rawValue)" }

    /// Модификаторы в формате Carbon для `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Глобальное сочетание обязано содержать ⌘, ⌃ или ⌥, иначе оно перехватит обычный набор.
    var isValidGlobalHotkey: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// Отображение в стиле macOS: ⌃⌥⇧⌘ + клавиша.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + Self.keyName(for: Int(keyCode))
    }

    /// Названия клавиш по коду физической клавиши (US-раскладка, как в системных меню).
    static func keyName(for keyCode: Int) -> String {
        if let name = keyNames[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
