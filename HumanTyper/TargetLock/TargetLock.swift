import ApplicationServices
import Foundation
import os

/// Привязка набора к одному окну целевого приложения, а в браузерах — к одной вкладке.
///
/// В момент старта запоминается активное окно. Перед каждым нажатием `check()` через
/// Универсальный доступ сверяет: активно ли то же приложение, то же окно и (в браузерах)
/// та же вкладка. Вкладки браузеров живут внутри одного окна, поэтому их смена
/// определяется по заголовку окна — он всегда равен заголовку активной вкладки.
/// Вызовы AX потокобезопасны, поэтому проверка выполняется прямо в фоновом исполнителе.
final class TargetLock: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case onTarget
        case otherApp(String)
        case otherWindow
        case otherTab
        case ownMenu
        case unknown
    }

    let pid: pid_t
    let appName: String
    /// Заголовок окна (вкладки) в момент старта — для подписи в интерфейсе.
    let windowTitle: String?

    private let appElement: AXUIElement
    private let systemWide = AXUIElementCreateSystemWide()
    private let window: AXUIElement?
    private let tracksTabs: Bool
    private let state: OSAllocatedUnfairLock<State>

    private struct State {
        var expectedTitle: String?
        var isOwnMenuOpen = false
    }

    /// Браузеры, у которых вкладки — внутри одного окна.
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
        "ru.yandex.desktop.yandex-browser", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "app.zen-browser.zen", "com.kagi.kagimacOS",
    ]

    /// Не дольше этого ждём ответа от целевого приложения: зависшее приложение
    /// не должно останавливать проверку на секунды.
    private static let messagingTimeout: Float = 0.25

    init(pid: pid_t, appName: String, bundleID: String?, isOwnMenuOpen: Bool) {
        self.pid = pid
        self.appName = appName
        appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)

        let window = Self.element(appElement, kAXFocusedWindowAttribute)
        self.window = window
        let title = window.flatMap(Self.title(of:))
        windowTitle = title
        tracksTabs = window != nil && Self.browserBundleIDs.contains(bundleID ?? "")
        state = OSAllocatedUnfairLock(initialState: State(
            expectedTitle: tracksTabs ? title : nil,
            isOwnMenuOpen: isOwnMenuOpen
        ))
    }

    /// Где сейчас фокус клавиатуры относительно привязанного окна.
    func check() -> Status {
        let snapshot = state.withLock { $0 }
        if snapshot.isOwnMenuOpen { return .ownMenu }

        // Системный «фокус» точнее NSWorkspace: учитывает Spotlight, всплывающие панели и т. п.
        guard let focusedApp = Self.element(systemWide, kAXFocusedApplicationAttribute) else { return .unknown }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focusedApp, &focusedPID) == .success else { return .unknown }
        guard focusedPID == pid else {
            return .otherApp(Self.title(of: focusedApp) ?? "другое приложение")
        }

        guard let window else { return .onTarget }
        guard let current = Self.element(appElement, kAXFocusedWindowAttribute), CFEqual(current, window) else {
            return .otherWindow
        }
        if let expected = snapshot.expectedTitle, Self.title(of: current) != expected {
            return .otherTab
        }
        return .onTarget
    }

    /// Пользователь явно продолжил набор, находясь в привязанном окне: если заголовок
    /// вкладки за это время изменился (страница сама переименовалась), принимаем новый.
    func acceptCurrentTab() {
        guard tracksTabs,
              let window,
              let current = Self.element(appElement, kAXFocusedWindowAttribute),
              CFEqual(current, window)
        else { return }
        let title = Self.title(of: current)
        state.withLock { $0.expectedTitle = title }
    }

    /// Пока открыто меню HumanTyper, нажатия ушли бы в него (выбор пунктов по буквам).
    func setOwnMenuOpen(_ isOpen: Bool) {
        state.withLock { $0.isOwnMenuOpen = isOpen }
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
