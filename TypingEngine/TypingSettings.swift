import Foundation

/// Параметры имитации набора. Чистая модель без зависимостей от AppKit.
public struct TypingSettings: Equatable, Sendable {
    /// Скорость набора в словах в минуту (1 слово = 5 символов).
    public var wordsPerMinute: Double
    /// Вероятность опечатки на каждый символ, 0...1.
    public var typoRate: Double
    /// Доля опечаток, которые замечаются не сразу, а через 1–3 символа.
    public var delayedCorrectionRate: Double
    /// Относительный разброс задержки между символами (0.4 = ±40%).
    public var jitter: Double
    /// Дополнительные паузы после пробелов, знаков препинания и абзацев,
    /// замедление на заглавных буквах и спецсимволах.
    public var naturalRhythm: Bool
    /// Периодические перерывы «отвлёкся».
    public var breaksEnabled: Bool
    /// Через сколько секунд набора делать перерыв.
    public var breakInterval: ClosedRange<TimeInterval>
    /// Длительность перерыва в секундах.
    public var breakDuration: ClosedRange<TimeInterval>

    public init(
        wordsPerMinute: Double = 60,
        typoRate: Double = 0.03,
        delayedCorrectionRate: Double = 0.2,
        jitter: Double = 0.4,
        naturalRhythm: Bool = true,
        breaksEnabled: Bool = true,
        breakInterval: ClosedRange<TimeInterval> = 30...120,
        breakDuration: ClosedRange<TimeInterval> = 3...15
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.typoRate = typoRate
        self.delayedCorrectionRate = delayedCorrectionRate
        self.jitter = jitter
        self.naturalRhythm = naturalRhythm
        self.breaksEnabled = breaksEnabled
        self.breakInterval = breakInterval
        self.breakDuration = breakDuration
    }

    public static let `default` = TypingSettings()

    public static let wordsPerMinuteRange: ClosedRange<Double> = 30...150
    public static let typoRateRange: ClosedRange<Double> = 0...0.2
}

/// Константы «живого» ритма. Вынесены отдельно, чтобы тесты проверяли те же границы.
public enum Rhythm {
    /// Пауза после пробела.
    public static let spacePause: ClosedRange<TimeInterval> = 0.05...0.15
    /// Пауза после запятой, точки с запятой, двоеточия.
    public static let clausePause: ClosedRange<TimeInterval> = 0.2...0.5
    /// Пауза после точки, восклицательного и вопросительного знака.
    public static let sentencePause: ClosedRange<TimeInterval> = 0.4...1.2
    /// Пауза после абзаца (перевода строки).
    public static let paragraphPause: ClosedRange<TimeInterval> = 1.0...3.0
    /// Пауза между опечаткой и первым Backspace — «заметил ошибку».
    public static let typoNoticePause: ClosedRange<TimeInterval> = 0.15...0.6
    /// Интервал между повторными нажатиями Backspace.
    public static let backspaceInterval: ClosedRange<TimeInterval> = 0.06...0.14
    /// Сколько символов успевает набрать человек, прежде чем заметит опечатку.
    public static let delayedNoticeLength: ClosedRange<Int> = 1...3

    /// Замедление для заглавных букв (нужен Shift).
    public static let uppercaseFactor = 1.35
    /// Замедление для спецсимволов (@, #, скобки, кавычки и т. п.).
    public static let specialCharacterFactor = 1.5

    public static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    public static let clauseEnders: Set<Character> = [",", ";", ":"]
}

extension ClosedRange where Bound: Comparable {
    /// Диапазон из двух границ в любом порядке (защита от min > max из настроек).
    public static func ordered(_ a: Bound, _ b: Bound) -> ClosedRange<Bound> {
        a <= b ? a...b : b...a
    }
}
