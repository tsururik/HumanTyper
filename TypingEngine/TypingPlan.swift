import Foundation

/// Один шаг набора: подождать `delay`, затем выполнить `action`.
public struct TypingStep: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Напечатать символ (графемный кластер: буква, эмодзи, перевод строки, табуляция).
        case type(Character)
        /// Нажать Backspace.
        case backspace
        /// Перерыв: ничего не нажимать, `delay` — длительность перерыва.
        case pause
    }

    /// Ожидание перед действием, секунды.
    public var delay: TimeInterval
    public var action: Action
    /// Сколько символов исходного текста набрано окончательно после этого шага.
    public var progress: Int

    public init(delay: TimeInterval, action: Action, progress: Int) {
        self.delay = delay
        self.action = action
        self.progress = progress
    }
}

/// Полный заранее рассчитанный план набора текста.
public struct TypingPlan: Sendable {
    /// Текст, который будет набран (с нормализованными переводами строк).
    public let text: String
    public let steps: [TypingStep]
    /// Количество символов (графем) в тексте.
    public let characterCount: Int
    /// Суммарная длительность всех шагов.
    public let totalDuration: TimeInterval
    /// `remaining[i]` — сколько времени займут шаги после i-го.
    private let remaining: [TimeInterval]

    public init(text: String, steps: [TypingStep]) {
        self.text = text
        self.steps = steps
        self.characterCount = text.count
        var suffix = [TimeInterval](repeating: 0, count: steps.count)
        var sum: TimeInterval = 0
        for index in steps.indices.reversed() {
            suffix[index] = sum
            sum += steps[index].delay
        }
        self.remaining = suffix
        self.totalDuration = sum
    }

    /// Оставшееся время после выполнения шага с индексом `index`.
    public func remainingDuration(afterStep index: Int) -> TimeInterval {
        guard remaining.indices.contains(index) else { return index < 0 ? totalDuration : 0 }
        return remaining[index]
    }

    public var typoCount: Int {
        var count = 0
        for (index, step) in steps.enumerated() where step.action == .backspace {
            // Серия Backspace — одно исправление.
            if index == 0 || steps[index - 1].action != .backspace { count += 1 }
        }
        return count
    }

    public var breakCount: Int {
        steps.filter { $0.action == .pause }.count
    }

    /// Что окажется в поле ввода, если выполнить все шаги в пустом документе.
    public func renderedCharacters() -> [Character] {
        var buffer: [Character] = []
        buffer.reserveCapacity(characterCount)
        for step in steps {
            switch step.action {
            case .type(let character):
                buffer.append(character)
            case .backspace:
                if !buffer.isEmpty { buffer.removeLast() }
            case .pause:
                break
            }
        }
        return buffer
    }
}
