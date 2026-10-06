import AppKit
import Combine
import TypingEngine

/// Состояние приложения и оркестрация набора: обратный отсчёт, запуск исполнителя,
/// пауза/продолжение, экстренная остановка, автопауза при смене активного приложения.
@MainActor
final class TypingController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case countdown(secondsLeft: Int, resuming: Bool)
        case typing
        case paused(PauseReason)
        case finished
    }

    enum PauseReason: Equatable {
        case user
        case appSwitched(to: String)
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
    @Published private(set) var targetAppName: String?
    /// Последнее сообщение для пользователя (ошибка, итог набора, подсказка).
    @Published private(set) var notice: String?
    @Published private(set) var hotkeyWarning: String?

    let permission: AccessibilityPermission

    private let defaults = UserDefaults.standard
    private let output: KeyboardOutput = CGEventKeyboardOutput()
    private let hotkeys = HotkeyManager()
    private let escapeMonitor = EscapeMonitor()

    private var runner: TypingRunner?
    private var eventsTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var targetPID: pid_t?
    private var pausedReason: PauseReason = .user
    private var activationObserver: NSObjectProtocol?

    init(permission: AccessibilityPermission) {
        self.permission = permission
        text = UserDefaults.standard.string(forKey: SettingsKey.sourceText) ?? ""
        reloadHotkeys()
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
        targetAppName = nil
        escapeMonitor.start { [weak self] in self?.stop() }
        if isOwnAppFrontmost {
            runCountdown(resuming: false)
        } else {
            beginTyping()
        }
    }

    func pause() {
        pause(reason: .user)
    }

    func resume() {
        guard case .paused(let reason) = phase else { return }
        pausedReason = reason
        if isOwnAppFrontmost {
            runCountdown(resuming: true)
        } else {
            continueTyping()
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

    private func runCountdown(resuming: Bool) {
        // Скрываем HumanTyper: macOS сама вернёт фокус приложению, которое было активно до него.
        if hideWindowOnStart { NSApp.hide(nil) }
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for second in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                self?.phase = .countdown(secondsLeft: second, resuming: resuming)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            if resuming {
                self?.continueTyping()
            } else {
                self?.beginTyping()
            }
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

        targetPID = target.processIdentifier
        targetAppName = target.localizedName ?? "приложение"

        let plan = TypingEngine(settings: AppDefaults.typingSettings(from: defaults)).makePlan(for: text)
        totalCount = plan.characterCount
        typedCount = 0
        remainingTime = plan.totalDuration
        breakSecondsLeft = nil

        let runner = TypingRunner(plan: plan, output: output)
        self.runner = runner
        observeAppActivation()
        phase = .typing

        eventsTask = Task { [weak self] in
            for await event in runner.events {
                self?.handle(event)
            }
        }
        runner.start()
    }

    /// Продолжение после паузы — только если снова активно целевое приложение,
    /// иначе текст ушёл бы в чужое окно.
    private func continueTyping() {
        guard let targetPID, NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            phase = .paused(pausedReason)
            notice = "Чтобы продолжить, вернитесь в «\(targetAppName ?? "целевое приложение")» и нажмите \(pauseHotkey.displayString)."
            return
        }
        notice = nil
        phase = .typing
        runner?.resume()
    }

    private func pause(reason: PauseReason) {
        guard phase == .typing else { return }
        runner?.pause()
        phase = .paused(reason)
        switch reason {
        case .user:
            notice = nil
        case .appSwitched(let name):
            notice = "Активным стало «\(name)» — набор на паузе, чтобы текст не ушёл в чужое окно."
        }
    }

    private func handle(_ event: TypingRunnerEvent) {
        guard runner != nil else { return }
        switch event {
        case .progress(let typed, let remaining):
            typedCount = typed
            remainingTime = remaining
        case .breakChanged(let secondsLeft):
            breakSecondsLeft = secondsLeft
        case .completed:
            typedCount = totalCount
            remainingTime = 0
            endSession(phase: .finished, notice: "Готово! Набрано в «\(targetAppName ?? "приложение")»: \(Formatting.characters(totalCount)).")
        case .cancelled:
            break
        }
    }

    private func endSession(phase newPhase: Phase, notice message: String) {
        countdownTask?.cancel()
        countdownTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        runner = nil
        targetPID = nil
        breakSecondsLeft = nil
        escapeMonitor.stop()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        phase = newPhase
        notice = message
    }

    private func observeAppActivation() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let name = app?.localizedName ?? "другое приложение"
            MainActor.assumeIsolated {
                self?.applicationActivated(pid: pid, name: name)
            }
        }
    }

    private func applicationActivated(pid: pid_t?, name: String) {
        guard phase == .typing, let targetPID, pid != targetPID else { return }
        pause(reason: .appSwitched(to: name))
    }
}
