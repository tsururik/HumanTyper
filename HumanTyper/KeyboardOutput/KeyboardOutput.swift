import Foundation

/// Куда отправляются нажатия клавиш. Протокол отделяет логику набора от способа вывода.
protocol KeyboardOutput: Sendable {
    /// Напечатать один символ (графемный кластер). `\n` — Return, `\t` — Tab.
    func type(_ character: Character)
    /// Нажать Backspace.
    func pressBackspace()
    /// Удерживает ли пользователь сейчас ⌘, ⌃, ⌥ или ⇧. Пока удерживает — печатать нельзя:
    /// символ превратится в сочетание клавиш (например, после нажатия ⌃⌥T).
    var isModifierKeyHeld: Bool { get }
}
