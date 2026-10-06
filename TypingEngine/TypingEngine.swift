import Foundation

/// Строит план «человеческого» набора текста: задержки, опечатки с исправлениями, перерывы.
///
/// Движок не нажимает клавиши сам — он только описывает последовательность шагов.
/// Это делает его детерминированным (при заданном генераторе) и тестируемым:
/// применив все шаги к пустому буферу, получаем исходный текст.
public struct TypingEngine: Sendable {
    public var settings: TypingSettings

    public init(settings: TypingSettings = .default) {
        self.settings = settings
    }

    /// Приводит переводы строк к `\n`: в Swift `"\r\n"` — одна графема, а набирать
    /// нужно ровно одно нажатие Return.
    public static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public func makePlan(for text: String) -> TypingPlan {
        var rng = SystemRandomNumberGenerator()
        return makePlan(for: text, using: &rng)
    }

    public func makePlan<R: RandomNumberGenerator>(for rawText: String, using rng: inout R) -> TypingPlan {
        let text = Self.normalize(rawText)
        let chars = Array(text)
        let delays = DelayModel(settings: settings)
        var builder = PlanBuilder(settings: settings, rng: &rng)
        // Цифры есть на обеих раскладках: опечатку в цифре берём с раскладки последней буквы.
        var currentLayout = KeyboardLayout.qwerty

        var index = 0
        while index < chars.count {
            let character = chars[index]
            let previous: Character? = index > 0 ? chars[index - 1] : nil
            if let layout = KeyboardLayout.letterLayout(for: character) {
                currentLayout = layout
            }

            builder.insertBreakIfDue(previous: previous, progress: index, using: &rng)

            let leadPause = delays.rhythmPause(after: previous, before: character, using: &rng)

            if rng.chance(settings.typoRate), let typo = currentLayout.typo(for: character, using: &rng) {
                // 1. Промахнулись по соседней клавише.
                builder.add(.type(typo), delay: leadPause + delays.keystrokeDelay(for: typo, using: &rng), progress: index)

                // 2. Иногда замечаем ошибку не сразу и успеваем набрать ещё 1–3 символа.
                //    Через перевод строки и табуляцию не «пролетаем»: Return может отправить
                //    сообщение, а Tab — перевести фокус.
                var tail = 0
                if rng.chance(settings.delayedCorrectionRate) {
                    let wanted = Int.random(in: Rhythm.delayedNoticeLength, using: &rng)
                    while tail < wanted, index + 1 + tail < chars.count, !Self.isHardBreak(chars[index + 1 + tail]) {
                        tail += 1
                    }
                    for offset in 0..<tail {
                        let next = chars[index + 1 + offset]
                        let delay = delays.rhythmPause(after: chars[index + offset], before: next, using: &rng)
                            + delays.keystrokeDelay(for: next, using: &rng)
                        builder.add(.type(next), delay: delay, progress: index)
                    }
                }

                // 3. Заметили: пауза, затем стираем опечатку и всё, что набрали после неё.
                for erased in 0...tail {
                    let delay = erased == 0 ? rng.uniform(Rhythm.typoNoticePause) : delays.backspaceDelay(using: &rng)
                    builder.add(.backspace, delay: delay, progress: index)
                }

                // 4. Правильный символ. Стёртый «хвост» наберётся заново в следующих итерациях.
                builder.add(.type(character), delay: delays.keystrokeDelay(for: character, using: &rng), progress: index + 1)
            } else {
                builder.add(.type(character), delay: leadPause + delays.keystrokeDelay(for: character, using: &rng), progress: index + 1)
            }
            index += 1
        }

        return TypingPlan(text: text, steps: builder.steps)
    }

    private static func isHardBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\t"
    }
}

/// Накапливает шаги и следит, когда пора сделать перерыв.
private struct PlanBuilder {
    private let settings: TypingSettings
    private(set) var steps: [TypingStep] = []
    /// Время набора с последнего перерыва (без учёта самих перерывов).
    private var typingSinceBreak: TimeInterval = 0
    private var nextBreakAfter: TimeInterval = .infinity

    /// Если подходящей границы слова долго нет (например, текст без пробелов),
    /// перерыв всё равно случится через столько секунд после назначенного момента.
    private static let wordBoundaryGrace: TimeInterval = 10

    init<R: RandomNumberGenerator>(settings: TypingSettings, rng: inout R) {
        self.settings = settings
        if settings.breaksEnabled {
            nextBreakAfter = rng.uniform(settings.breakInterval)
        }
    }

    mutating func add(_ action: TypingStep.Action, delay: TimeInterval, progress: Int) {
        let delay = max(delay, 0)
        steps.append(TypingStep(delay: delay, action: action, progress: progress))
        typingSinceBreak += delay
    }

    /// Перерыв делается только между словами и никогда не посреди исправления опечатки.
    mutating func insertBreakIfDue<R: RandomNumberGenerator>(previous: Character?, progress: Int, using rng: inout R) {
        guard settings.breaksEnabled, typingSinceBreak >= nextBreakAfter else { return }
        let atWordBoundary = previous?.isWhitespace ?? true
        guard atWordBoundary || typingSinceBreak >= nextBreakAfter + Self.wordBoundaryGrace else { return }

        steps.append(TypingStep(delay: rng.uniform(settings.breakDuration), action: .pause, progress: progress))
        typingSinceBreak = 0
        nextBreakAfter = rng.uniform(settings.breakInterval)
    }
}
