import Foundation
import os
import TypingEngine

/// События исполнителя для интерфейса.
enum TypingRunnerEvent: Sendable {
    /// Сколько символов набрано и сколько времени осталось по плану.
    case progress(typed: Int, remaining: TimeInterval)
    /// Идёт перерыв, осталось столько секунд; `nil` — перерыв закончился.
    case breakChanged(secondsLeft: TimeInterval?)
    /// Фокус ушёл с привязанного окна — набор стоит.
    case focusLost(TargetLock.Status)
    /// Привязанное окно снова активно — набор продолжится через `returnDelay`.
    case focusReturning
    /// Набор продолжается.
    case focusRestored
    case completed
    case cancelled
}

/// Выполняет готовый план набора в фоновой задаче, не блокируя интерфейс.
///
/// Пауза и отмена — потокобезопасные флаги, которые проверяются каждые 50 мс.
/// Перед каждым нажатием исполнитель сверяется с `TargetLock`: если фокус ушёл
/// с привязанного окна или вкладки, набор встаёт и продолжается сам, когда окно
/// снова активно `returnDelay` секунд.
final class TypingRunner: Sendable {
    static let returnDelay: TimeInterval = 1

    private struct Flags {
        var isPaused = false
        var isCancelled = false
        /// Пользователь сам продолжил набор — не ждать `returnDelay`.
        var skipReturnDelay = false
    }

    /// Состояние слежения за фокусом внутри цикла набора.
    private struct FocusTracking {
        let origin = ContinuousClock.now
        var debouncer = FocusDebouncer(returnDelay: TypingRunner.returnDelay)
        var reported: TargetLock.Status = .onTarget
        var lastCheck: ContinuousClock.Instant?
        var lastResult = true
    }

    let events: AsyncStream<TypingRunnerEvent>

    private let plan: TypingPlan
    private let output: KeyboardOutput
    private let target: TargetLock
    private let flags = OSAllocatedUnfairLock(initialState: Flags())
    private let continuation: AsyncStream<TypingRunnerEvent>.Continuation

    private static let slice: TimeInterval = 0.05
    private static let tickInterval: TimeInterval = 0.25
    /// Между нажатиями фокус проверяется не чаще, чем раз в 100 мс; перед нажатием — всегда.
    private static let focusCheckInterval: Duration = .milliseconds(100)

    init(plan: TypingPlan, output: KeyboardOutput, target: TargetLock) {
        self.plan = plan
        self.output = output
        self.target = target
        var continuation: AsyncStream<TypingRunnerEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    func start() {
        Task.detached(priority: .userInitiated) { [self] in
            await run()
        }
    }

    func pause() { flags.withLock { $0.isPaused = true } }

    func resume() {
        flags.withLock {
            $0.isPaused = false
            $0.skipReturnDelay = true
        }
    }

    func cancel() { flags.withLock { $0.isCancelled = true } }

    private var isCancelled: Bool { flags.withLock { $0.isCancelled } }

    private func run() async {
        var typed = 0
        var focus = FocusTracking()
        for (index, step) in plan.steps.enumerated() {
            let remainingAfter = plan.remainingDuration(afterStep: index)
            let isBreak = step.action == .pause

            guard await wait(step.delay, typed: typed, remainingAfter: remainingAfter, isBreak: isBreak, focus: &focus) else {
                return finish(with: .cancelled)
            }

            switch step.action {
            case .type(let character):
                guard await waitUntilReadyToPress(focus: &focus) else { return finish(with: .cancelled) }
                output.type(character)
            case .backspace:
                guard await waitUntilReadyToPress(focus: &focus) else { return finish(with: .cancelled) }
                output.pressBackspace()
            case .pause:
                continuation.yield(.breakChanged(secondsLeft: nil))
            }

            typed = step.progress
            continuation.yield(.progress(typed: typed, remaining: remainingAfter))
        }
        finish(with: .completed)
    }

    /// Ждёт `duration` секунд рабочего времени: на паузе и без фокуса отсчёт не идёт.
    /// Возвращает `false`, если набор отменили.
    private func wait(
        _ duration: TimeInterval,
        typed: Int,
        remainingAfter: TimeInterval,
        isBreak: Bool,
        focus: inout FocusTracking
    ) async -> Bool {
        let clock = ContinuousClock()
        var left = duration
        var sinceTick: TimeInterval = 0
        if isBreak { continuation.yield(.breakChanged(secondsLeft: left)) }

        while left > 0 {
            if isCancelled { return false }
            guard canProceed(&focus, forceCheck: false) else {
                try? await Task.sleep(for: .seconds(Self.slice))
                continue
            }
            let started = clock.now
            try? await Task.sleep(for: .seconds(min(left, Self.slice)))
            let elapsed = (clock.now - started).seconds
            left -= elapsed
            sinceTick += elapsed

            // Длинные паузы (абзац, перерыв) не должны «замораживать» таймер в интерфейсе.
            if sinceTick >= Self.tickInterval, left > 0 {
                sinceTick = 0
                continuation.yield(.progress(typed: typed, remaining: remainingAfter + left))
                if isBreak { continuation.yield(.breakChanged(secondsLeft: left)) }
            }
        }
        return !isCancelled
    }

    /// Перед нажатием ждём снятия паузы, фокуса на привязанном окне и отпускания модификаторов.
    private func waitUntilReadyToPress(focus: inout FocusTracking) async -> Bool {
        while !isCancelled {
            if canProceed(&focus, forceCheck: true), !output.isModifierKeyHeld { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    /// Можно ли сейчас печатать: нет ручной паузы и фокус на привязанном окне.
    /// Сообщает интерфейсу об уходе с окна, возвращении и продолжении.
    private func canProceed(_ focus: inout FocusTracking, forceCheck: Bool) -> Bool {
        let current = flags.withLock { flags -> Flags in
            let snapshot = flags
            flags.skipReturnDelay = false
            return snapshot
        }
        if current.isPaused { return false }
        if current.skipReturnDelay {
            focus.debouncer.reset()
            focus.reported = .onTarget
            focus.lastCheck = nil
        }

        let now = ContinuousClock.now
        if !forceCheck, let last = focus.lastCheck, now - last < Self.focusCheckInterval {
            return focus.lastResult
        }
        focus.lastCheck = now

        let status = target.check()
        let (canType, event) = focus.debouncer.update(onTarget: status == .onTarget, at: (now - focus.origin).seconds)
        if status != .onTarget, status != focus.reported {
            focus.reported = status
            continuation.yield(.focusLost(status))
        }
        switch event {
        case .returning:
            // Если пользователь снова уйдёт, о потере нужно сообщить заново.
            focus.reported = .onTarget
            continuation.yield(.focusReturning)
        case .restored:
            continuation.yield(.focusRestored)
        case .lost, nil:
            break
        }
        focus.lastResult = canType
        return canType
    }

    private func finish(with event: TypingRunnerEvent) {
        continuation.yield(event)
        continuation.finish()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
