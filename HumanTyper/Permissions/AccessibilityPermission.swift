import AppKit
import ApplicationServices
import Combine

/// Доступ к «Универсальному доступу» — без него macOS не пропустит синтетические нажатия
/// в другие приложения и не даст глобальному монитору видеть Esc.
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted: Bool

    private var timer: Timer?

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    init() {
        isGranted = Self.check(prompt: false)
        // Разрешение могут выдать или отозвать в любой момент — опрашиваем раз в секунду.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let granted = Self.check(prompt: false)
        if granted != isGranted { isGranted = granted }
    }

    /// Показывает системный запрос и добавляет HumanTyper в список «Универсальный доступ».
    func request() {
        isGranted = Self.check(prompt: true)
    }

    /// Открывает «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ».
    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private static func check(prompt: Bool) -> Bool {
        // Строковое значение kAXTrustedCheckOptionPrompt — не зависит от того, как SDK импортирует константу.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
