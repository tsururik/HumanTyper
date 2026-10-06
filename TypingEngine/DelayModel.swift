import Foundation

/// Расчёт задержек между нажатиями.
public struct DelayModel: Sendable {
    public var settings: TypingSettings

    public init(settings: TypingSettings) {
        self.settings = settings
    }

    /// Средняя задержка между символами без разброса: 60 / (WPM × 5) секунд.
    public var baseDelay: TimeInterval {
        60.0 / (max(settings.wordsPerMinute, 1) * 5.0)
    }

    /// Задержка перед нажатием символа: база × случайный разброс × сложность символа.
    public func keystrokeDelay<R: RandomNumberGenerator>(for character: Character, using rng: inout R) -> TimeInterval {
        let difficulty = settings.naturalRhythm ? Self.difficultyFactor(for: character) : 1
        return baseDelay * jitterFactor(using: &rng) * difficulty
    }

    /// Множитель разброса из нормального распределения. ±jitter соответствует 2σ,
    /// хвосты обрезаются, поэтому множитель всегда лежит в [1 − jitter, 1 + jitter].
    public func jitterFactor<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let jitter = settings.jitter
        guard jitter > 0 else { return 1 }
        let factor = 1 + rng.nextGaussian() * jitter / 2
        return min(max(factor, 1 - jitter), 1 + jitter)
    }

    /// Пауза «на подумать» перед символом `current`, если перед ним стоял `previous`.
    public func rhythmPause<R: RandomNumberGenerator>(
        after previous: Character?,
        before current: Character,
        using rng: inout R
    ) -> TimeInterval {
        guard settings.naturalRhythm, let previous else { return 0 }

        if previous == "\n" {
            // Пауза после абзаца — один раз, после последнего перевода строки подряд.
            return current == "\n" ? 0 : rng.uniform(Rhythm.paragraphPause)
        }
        if Rhythm.sentenceEnders.contains(previous) {
            // «3.14» — не конец предложения, пауза только перед пробелом или переводом строки.
            return current.isWhitespace ? rng.uniform(Rhythm.sentencePause) : 0
        }
        if Rhythm.clauseEnders.contains(previous) {
            return current.isWhitespace ? rng.uniform(Rhythm.clausePause) : 0
        }
        if previous == " " || previous == "\t" {
            return rng.uniform(Rhythm.spacePause)
        }
        return 0
    }

    /// Задержка между повторными нажатиями Backspace.
    public func backspaceDelay<R: RandomNumberGenerator>(using rng: inout R) -> TimeInterval {
        rng.uniform(Rhythm.backspaceInterval)
    }

    /// Насколько медленнее набирается символ: заглавные требуют Shift, спецсимволы — поиска клавиши.
    public static func difficultyFactor(for character: Character) -> Double {
        if character.isUppercase { return Rhythm.uppercaseFactor }
        if isSpecial(character) { return Rhythm.specialCharacterFactor }
        return 1
    }

    /// Спецсимвол — всё, кроме букв, цифр, пробельных символов, точки и запятой.
    public static func isSpecial(_ character: Character) -> Bool {
        !(character.isLetter || character.isNumber || character.isWhitespace || character == "." || character == ",")
    }
}
