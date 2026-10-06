import AppKit
import Carbon.HIToolbox

/// Экстренная остановка по Esc через глобальный (и локальный) монитор событий `NSEvent`.
///
/// Глобальный монитор видит нажатия в других приложениях, но только если у HumanTyper есть
/// доступ к Универсальному доступу. Локальный — нажатия в собственных окнах (например,
/// во время обратного отсчёта). Мониторы включены только на время набора.
@MainActor
final class EscapeMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool { globalMonitor != nil || localMonitor != nil }

    func start(onEscape: @escaping @MainActor () -> Void) {
        stop()
        let escape = UInt16(kVK_Escape)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == escape else { return }
            MainActor.assumeIsolated { onEscape() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == escape else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
