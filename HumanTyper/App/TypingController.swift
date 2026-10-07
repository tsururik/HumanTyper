import AppKit
import Combine
import TypingEngine

/// Состояние приложения и оркестрация набора: обратный отсчёт, запуск исполнителя,
/// пауза/продолжение, экстренная остановка, привязка к окну и вкладке.
@MainActor
final class TypingController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case countdown(secondsLeft: Int)
        case typing
        case paused(PauseReason)
        case finished
    }

    enum PauseReason: Equatable {
        /// Пауза по ⌃⌥P или кнопке — продолжается только вручную.
        case user
        /// Фокус ушёл с привязанного окна или вкладки.
        case focusLost
    }

    static let countdownSeconds = 3

    @Published var text: String {
        didSet { defaults.set(text, forKey: SettingsKey.sourceText) }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var typedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var breakSecondsLeft: TimeInterval?
    /// К чему привязан набор: «Google Chrome — «Документ»».
    @Published private(set) var targetDescription: String?
    /// Последнее сообщение для пользователя (ошибка, итог набора, подсказка).
    @Published private(set) var notice: String?
    @Published private(set) var hotkeyWarning: String?

    let permission: AccessibilityPermission

    private let defaults = UserDefaults.standard
    private let output: KeyboardOutput = CGEventKeyboardOutput()
    private let hotkeys = HotkeyManager()
    private let escapeMonitor = EscapeMonitor()

    private var runner: TypingRunner?
    private var targetLock: TargetLock?
    private var eventsTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var isOwnMenuOpen = false
    private var menuObservers: [NSObjectProtocol] = []

    init(permission: AccessibilityPermission) {
        self.permission = permission
        text = UserDefaults.standard.string(forKey: SettingsKey.sourceText) ?? ""
        reloadHotkeys()
        observeOwnMenus()
    }

    // MARK: - Состояние для интерфейса

    /// Идёт сеанс набора: отсчёт, набор или пауза.
    var isSessionActive: Bool {
        switch phase {
        case .countdown, .typing, .paused: true
        case .idle, .finished: false
        }
    }

    var canStart: Bool {
        !isSessionActive && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var progress: Double {
        totalCount > 0 ? Double(typedCount) / Double(totalCount) : 0
    }

    var startHotkey: Hotkey { AppDefaults.hotkey(SettingsKey.startHotkey, fallback: .defaultStart) }
    var pauseHotkey: Hotkey { AppDefaults.hotkey(SettingsKey.pauseHotkey, fallback: .defaultPause) }

    // MARK: - Управление

    /// Старт набора. Если активно окно HumanTyper — сначала обратный отсчёт, чтобы успеть
    /// переключиться в нужное поле. Если пользователь уже в целевом приложении
    /// (нажал ⌃⌥T или выбрал пункт в строке меню) — набор начинается сразу.
    func start() {
        guard !isSessionActive else { return }
        notice = nil
        guard permission.isGranted else {
            notice = "Нет доступа к Универсальному доступу — набор невозможен."
            permission.request()
            return
        }
        guard canStart else {
            notice = "Вставьте текст, который нужно набрать."
            return
        }
        typedCount = 0
        totalCount = 0
        targetDescription = nil
        escapeMonitor.start { [weak self] in self?.stop() }
        if isOwnAppFrontmost {
            runCountdown()
        } else {
            beginTyping()
        }
    }

    /// Ручная пауза. Работает и когда набор уже стоит из-за ухода из окна —
    /// тогда он не продолжится сам при возвращении.
    func pause() {
        switch phase {
        case .typing, .paused(.focusLost):
            runner?.pause()
            phase = .paused(.user)
            notice = nil
        default:
            break
        }
    }

    /// Продолжение после любой паузы. Печатать набор всё равно будет только в привязанное
    /// окно: если активно другое, он дождётся возвращения.
    func resume() {
        guard case .paused = phase, let runner, let targetLock else { return }
        if isOwnAppFrontmost, hideWindowOnStart {
            // Фокус вернётся в приложение, где шёл набор.
            NSApp.hide(nil)
        }
        // ⌃⌥P в привязанном окне — подтверждение «курсор на месте», даже если
        // страница сама сменила заголовок вкладки.
        targetLock.acceptCurrentTab()
        runner.resume()
        let status = targetLock.check()
        if status == .onTarget {
            phase = .typing
            notice = nil
        } else {
            showFocusLost(status)
        }
    }

    func togglePause() {
        switch phase {
        case .typing: pause()
        case .paused: resume()
        default: break
        }
    }

    /// Экстренная остановка (Esc, кнопка, пункт меню).
    func stop() {
        guard isSessionActive else { return }
        countdownTask?.cancel()
        runner?.cancel()
        let summary = totalCount > 0 && typedCount > 0
            ? "Остановлено: набрано \(typedCount) из \(totalCount)."
            : "Набор остановлен."
        endSession(phase: .idle, notice: summary)
    }

    // MARK: - Горячие клавиши

    func reloadHotkeys() {
        var failed: [String] = []
        let start = startHotkey
        let pause = pauseHotkey
        if !hotkeys.register(start, for: .start, handler: { [weak self] in self?.start() }) {
            failed.append(start.displayString)
        }
        if pause == start {
            hotkeys.unregister(.pause)
            failed.append(pause.displayString)
        } else if !hotkeys.register(pause, for: .pause, handler: { [weak self] in self?.togglePause() }) {
            failed.append(pause.displayString)
        }
        hotkeyWarning = failed.isEmpty
            ? nil
            : "Не удалось назначить \(failed.joined(separator: ", ")) — сочетание занято или повторяется."
    }

    /// На время записи нового сочетания старые не должны срабатывать.
    func suspendHotkeys() {
        hotkeys.unregisterAll()
    }

    // MARK: - Сеанс набора

    private var isOwnAppFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private var hideWindowOnStart: Bool {
        defaults.bool(forKey: SettingsKey.hideWindowOnStart)
    }

    private var autoResume: Bool {
        defaults.bool(forKey: SettingsKey.autoResume)
    }

    private func runCountdown() {
        // Скрываем HumanTyper: macOS сама вернёт фокус приложению, которое было активно до него.
        if hideWindowOnStart { NSApp.hide(nil) }
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for second in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                self?.phase = .countdown(secondsLeft: second)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.beginTyping()
        }
    }

    private func beginTyping() {
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            endSession(
                phase: .idle,
                notice: "Активно окно HumanTyper. Нажмите «Старт» и за \(Self.countdownSeconds) с поставьте курсор в нужное поле другого приложения."
            )
            return
        }

        let lock = TargetLock(
            pid: target.processIdentifier,
            appName: target.localizedName ?? "приложение",
            bundleID: target.bundleIdentifier,
            isOwnMenuOpen: isOwnMenuOpen
        )
        targetLock = lock
        targetDescription = lock.windowTitle.map { "\(lock.appName) — «\($0)»" } ?? lock.appName

        let plan = TypingEngine(settings: AppDefaults.typingSettings(from: defaults)).makePlan(for: text)
        totalCount = plan.characterCount
        typedCount = 0
        remainingTime = plan.totalDuration
        breakSecondsLeft = nil

        let runner = TypingRunner(plan: plan, output: output, target: lock)
        self.runner = runner
        phase = .typing

        eventsTask = Task { [weak self] in
            for await event in runner.events {
                self?.handle(event)
            }
        }
        runner.start()
    }

    private func handle(_ event: TypingRunnerEvent) {
        guard runner != nil else { return }
        switch event {
        case .progress(let typed, let remaining):
            typedCount = typed
            remainingTime = remaining
        case .breakChanged(let secondsLeft):
            breakSecondsLeft = secondsLeft
        case .focusLost(let status):
            // Ручную паузу не подменяем: она снимается только пользователем.
            guard phase == .typing || phase == .paused(.focusLost) else { return }
            if !autoResume { runner?.pause() }
            showFocusLost(status)
        case .focusReturning:
            if phase == .paused(.focusLost), autoResume {
                notice = "Вы вернулись — продолжу через секунду…"
            }
        case .focusRestored:
            if phase == .paused(.focusLost) {
                phase = .typing
                notice = nil
            }
        case .completed:
            typedCount = totalCount
            remainingTime = 0
            endSession(phase: .finished, notice: "Готово! Набрано в «\(targetLock?.appName ?? "приложение")»: \(Formatting.characters(totalCount)).")
        case .cancelled:
            break
        }
    }

    private func showFocusLost(_ status: TargetLock.Status) {
        phase = .paused(.focusLost)
        let place = targetLock.map { "«\($0.appName)»" } ?? "нужное окно"
        let reason: String
        switch status {
        case .otherApp(let name): reason = "Активно «\(name)»."
        case .otherWindow: reason = "Открыто другое окно \(place)."
        case .otherTab: reason = "Открыта другая вкладка в \(place)."
        case .ownMenu: reason = "Открыто меню HumanTyper."
        case .unknown: reason = "Не удалось определить активное окно."
        case .onTarget: reason = ""
        }
        let next = autoResume
            ? "Вернитесь в то же окно — продолжу сам."
            : "Вернитесь в то же окно и нажмите \(pauseHotkey.displayString)."
        notice = "\(reason) Набор на паузе, чтобы текст не ушёл не туда. \(next)"
    }

    private func endSession(phase newPhase: Phase, notice message: String) {
        countdownTask?.cancel()
        countdownTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        runner = nil
        targetLock = nil
        breakSecondsLeft = nil
        escapeMonitor.stop()
        phase = newPhase
        notice = message
    }

    /// Пока открыто меню HumanTyper (в строке меню), нажатия попали бы в него.
    private func observeOwnMenus() {
        let center = NotificationCenter.default
        for (name, isOpen) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            menuObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isOwnMenuOpen = isOpen
                    self?.targetLock?.setOwnMenuOpen(isOpen)
                }
            })
        }
    }
}
