import Foundation

/// Решает, можно ли печатать, когда фокус уходит с целевого окна и возвращается.
///
/// Уход фокуса останавливает набор сразу. После возвращения набор продолжается только
/// после `returnDelay` секунд непрерывного фокуса — чтобы не печатать посреди
/// переключения окон и дать пользователю убрать руки с клавиатуры.
public struct FocusDebouncer: Sendable {
    public enum Event: Equatable, Sendable {
        /// Фокус ушёл с целевого окна — набор на паузе.
        case lost
        /// Целевое окно снова активно, идёт ожидание `returnDelay`.
        case returning
        /// Набор можно продолжать.
        case restored
    }

    public let returnDelay: TimeInterval
    public private(set) var isLost = false
    private var returnedAt: TimeInterval?

    public init(returnDelay: TimeInterval = 1) {
        self.returnDelay = returnDelay
    }

    /// Учитывает очередную проверку фокуса в момент `time` (секунды, монотонные часы).
    /// Возвращает, можно ли печатать прямо сейчас, и событие, если состояние изменилось.
    public mutating func update(onTarget: Bool, at time: TimeInterval) -> (canType: Bool, event: Event?) {
        guard onTarget else {
            returnedAt = nil
            if isLost { return (false, nil) }
            isLost = true
            return (false, .lost)
        }
        guard isLost else { return (true, nil) }
        guard let returnedAt else {
            self.returnedAt = time
            return (false, .returning)
        }
        guard time - returnedAt >= returnDelay else { return (false, nil) }
        isLost = false
        self.returnedAt = nil
        return (true, .restored)
    }

    /// Пользователь сам продолжил набор (⌃⌥P) — ждать возвращения не нужно.
    public mutating func reset() {
        isLost = false
        returnedAt = nil
    }
}
