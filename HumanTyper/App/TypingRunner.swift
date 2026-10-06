import Foundation
import os
import TypingEngine

/// События исполнителя для интерфейса.
enum TypingRunnerEvent: Sendable {
    /// Сколько символов набрано и сколько времени осталось по плану.
    case progress(typed: Int, remaining: TimeInterval)
    /// Идёт перерыв, осталось столько секунд; `nil` — перерыв закончился.
    case breakChanged(secondsLeft: TimeInterval?)
    case completed
    case cancelled
}

/// Выполняет готовый план набора в фоновой задаче, не блокируя интерфейс.
/// Пауза и отмена — потокобезопасные флаги, которые проверяются каждые 50 мс.
final class TypingRunner: Sendable {
    private struct Flags {
        var isPaused = false
        var isCancelled = false
    }

    let events: AsyncStream<TypingRunnerEvent>

    private let plan: TypingPlan
    private let output: KeyboardOutput
    private let flags = OSAllocatedUnfairLock(initialState: Flags())
    private let continuation: AsyncStream<TypingRunnerEvent>.Continuation

    private static let slice: TimeInterval = 0.05
    private static let tickInterval: TimeInterval = 0.25

    init(plan: TypingPlan, output: KeyboardOutput) {
        self.plan = plan
        self.output = output
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
    func resume() { flags.withLock { $0.isPaused = false } }
    func cancel() { flags.withLock { $0.isCancelled = true } }

    private var isPaused: Bool { flags.withLock { $0.isPaused } }
    private var isCancelled: Bool { flags.withLock { $0.isCancelled } }

    private func run() async {
        var typed = 0
        for (index, step) in plan.steps.enumerated() {
            let remainingAfter = plan.remainingDuration(afterStep: index)
            let isBreak = step.action == .pause

            guard await wait(step.delay, typed: typed, remainingAfter: remainingAfter, isBreak: isBreak) else {
                return finish(with: .cancelled)
            }

            switch step.action {
            case .type(let character):
                guard await waitUntilReadyToPress() else { return finish(with: .cancelled) }
                output.type(character)
            case .backspace:
                guard await waitUntilReadyToPress() else { return finish(with: .cancelled) }
                output.pressBackspace()
            case .pause:
                continuation.yield(.breakChanged(secondsLeft: nil))
            }

            typed = step.progress
            continuation.yield(.progress(typed: typed, remaining: remainingAfter))
        }
        finish(with: .completed)
    }

    /// Ждёт `duration` секунд рабочего времени: пока стоит пауза, отсчёт не идёт.
    /// Возвращает `false`, если набор отменили.
    private func wait(_ duration: TimeInterval, typed: Int, remainingAfter: TimeInterval, isBreak: Bool) async -> Bool {
        let clock = ContinuousClock()
        var left = duration
        var sinceTick: TimeInterval = 0
        if isBreak { continuation.yield(.breakChanged(secondsLeft: left)) }

        while left > 0 {
            if isCancelled { return false }
            if isPaused {
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

    /// Перед нажатием ждём снятия паузы и отпускания модификаторов.
    private func waitUntilReadyToPress() async -> Bool {
        while !isCancelled {
            if !isPaused, !output.isModifierKeyHeld { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
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
