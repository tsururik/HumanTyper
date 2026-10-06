import Carbon.HIToolbox
import CoreGraphics

/// Набор через синтетические события клавиатуры Quartz.
///
/// Символы передаются строкой Unicode (`keyboardSetUnicodeString`), а не кодом клавиши,
/// поэтому кириллица, эмодзи и любые символы печатаются независимо от текущей раскладки.
/// Перевод строки и табуляция отправляются настоящими клавишами Return и Tab.
final class CGEventKeyboardOutput: KeyboardOutput, @unchecked Sendable {
    /// Сколько UTF-16 единиц надёжно переносит одно событие.
    private static let maxUnitsPerEvent = 20
    private static let heldModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        // По умолчанию после каждого синтетического события система на 0.25 с глушит
        // реальную клавиатуру — тогда Esc не дошёл бы до монитора экстренной остановки.
        source?.localEventsSuppressionInterval = 0
    }

    func type(_ character: Character) {
        switch character {
        case "\n":
            press(virtualKey: CGKeyCode(kVK_Return))
        case "\t":
            press(virtualKey: CGKeyCode(kVK_Tab))
        default:
            for chunk in Self.chunks(of: character) {
                post(virtualKey: 0, keyDown: true, text: chunk)
                post(virtualKey: 0, keyDown: false, text: chunk)
            }
        }
    }

    func pressBackspace() {
        press(virtualKey: CGKeyCode(kVK_Delete))
    }

    var isModifierKeyHeld: Bool {
        !CGEventSource.flagsState(.hidSystemState).intersection(Self.heldModifiers).isEmpty
    }

    private func press(virtualKey: CGKeyCode) {
        post(virtualKey: virtualKey, keyDown: true, text: nil)
        post(virtualKey: virtualKey, keyDown: false, text: nil)
    }

    private func post(virtualKey: CGKeyCode, keyDown: Bool, text: [UniChar]?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { return }
        // Явно сбрасываем модификаторы, чтобы символ не стал сочетанием клавиш.
        event.flags = []
        if let text {
            event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
        }
        event.post(tap: .cghidEventTap)
    }

    /// Делит символ на куски по ≤ 20 UTF-16 единиц, не разрывая суррогатные пары.
    /// Почти всегда кусок один: даже семейный эмодзи 👨‍👩‍👧‍👦 занимает 11 единиц.
    private static func chunks(of character: Character) -> [[UniChar]] {
        var result: [[UniChar]] = []
        var current: [UniChar] = []
        for scalar in String(character).unicodeScalars {
            let units = Array(String(scalar).utf16)
            if current.count + units.count > maxUnitsPerEvent, !current.isEmpty {
                result.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
