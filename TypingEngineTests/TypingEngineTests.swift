import XCTest
@testable import TypingEngine

final class TypingEngineTests: XCTestCase {
    private let samples = [
        "Hello, world! This is a simple test.",
        "Привет, мир! Съешь же ещё этих мягких французских булок, да выпей чаю.",
        "Mixed текст: version 2.0, цена 1 500 ₽ — ok?\nВторая строка.\n\n\tС табуляцией.",
        "Emoji 👨‍👩‍👧‍👦 and flags 🇧🇾🇺🇸, accents: café, naïve, Ёлка.",
        "UPPER CASE AND lower case; symbols @#$%^&*()[]{}<>/\\|~`",
        "a",
        "",
    ]

    // MARK: - Итоговый текст

    func testRenderedTextMatchesSourceForManySeedsAndTypoRates() {
        for rate in [0.0, 0.03, 0.1, 0.2] {
            let engine = TypingEngine(settings: .init(typoRate: rate))
            for (sampleIndex, text) in samples.enumerated() {
                for seed in 0..<40 {
                    var rng = SeededRandomNumberGenerator(seed: UInt64(seed * 100 + sampleIndex))
                    let plan = engine.makePlan(for: text, using: &rng)
                    XCTAssertEqual(String(plan.renderedCharacters()), text,
                                   "rate=\(rate) seed=\(seed) sample=\(sampleIndex)")
                }
            }
        }
    }

    func testRenderedTextMatchesForExtremeTypoRates() {
        // Даже если ошибаться почти в каждой букве и всегда замечать поздно — текст должен совпасть.
        let engine = TypingEngine(settings: .init(typoRate: 1, delayedCorrectionRate: 1))
        for text in samples {
            var rng = SeededRandomNumberGenerator(seed: 99)
            XCTAssertEqual(String(engine.makePlan(for: text, using: &rng).renderedCharacters()), text)
        }
    }

    func testLineEndingsAreNormalized() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let plan = TypingEngine().makePlan(for: "one\r\ntwo\rthree\n", using: &rng)
        XCTAssertEqual(plan.text, "one\ntwo\nthree\n")
        XCTAssertEqual(String(plan.renderedCharacters()), "one\ntwo\nthree\n")
        XCTAssertFalse(plan.steps.contains { $0.action == .type("\r\n") || $0.action == .type("\r") })
    }

    // MARK: - Опечатки

    func testNoTyposMeansOneStepPerCharacter() {
        let engine = TypingEngine(settings: .init(typoRate: 0, breaksEnabled: false))
        var rng = SeededRandomNumberGenerator(seed: 2)
        let text = samples[1]
        let plan = engine.makePlan(for: text, using: &rng)
        XCTAssertEqual(plan.steps.count, text.count)
        XCTAssertEqual(plan.typoCount, 0)
        XCTAssertEqual(plan.steps.map(\.action), text.map { .type($0) })
    }

    func testTypoRateIsRoughlyRespected() {
        let engine = TypingEngine(settings: .init(typoRate: 0.1, breaksEnabled: false))
        var rng = SeededRandomNumberGenerator(seed: 3)
        let text = String(repeating: "lorem ipsum dolor sit amet ", count: 200)
        let letters = text.filter(\.isLetter).count
        let plan = engine.makePlan(for: text, using: &rng)
        let observed = Double(plan.typoCount) / Double(letters)
        XCTAssertEqual(observed, 0.1, accuracy: 0.02)
    }

    func testTypoIsNeighborThenCorrected() {
        let engine = TypingEngine(settings: .init(typoRate: 0.2, delayedCorrectionRate: 0, breaksEnabled: false))
        var rng = SeededRandomNumberGenerator(seed: 4)
        let text = "the quick brown fox jumps over the lazy dog съешь же ещё этих булок"
        let plan = engine.makePlan(for: text, using: &rng)
        let steps = plan.steps
        var checked = 0
        for i in steps.indices where steps[i].action == .backspace {
            // При немедленном исправлении: опечатка → Backspace → правильный символ.
            guard case .type(let wrong) = steps[i - 1].action, case .type(let right) = steps[i + 1].action else {
                return XCTFail("неожиданная последовательность около шага \(i)")
            }
            XCTAssertNotEqual(wrong, right)
            let layout = KeyboardLayout.letterLayout(for: right) ?? .qwerty
            XCTAssertTrue(layout.neighbors[right]?.contains(wrong) == true, "\(wrong) не сосед \(right)")
            XCTAssertTrue(Rhythm.typoNoticePause.contains(steps[i].delay), "пауза перед Backspace")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 3)
    }

    func testDelayedCorrectionErasesOneToThreeExtraCharacters() {
        let engine = TypingEngine(settings: .init(typoRate: 0.15, delayedCorrectionRate: 1, breaksEnabled: false))
        var rng = SeededRandomNumberGenerator(seed: 5)
        let text = String(repeating: "человек печатает текст быстро ", count: 20)
        let plan = engine.makePlan(for: text, using: &rng)

        var runs: [Int] = []
        var current = 0
        for step in plan.steps {
            if step.action == .backspace {
                current += 1
            } else if current > 0 {
                runs.append(current)
                current = 0
            }
        }
        XCTAssertFalse(runs.isEmpty)
        // Стирается сама опечатка + 1–3 символа после неё (у конца текста может быть меньше).
        XCTAssertTrue(runs.allSatisfy { (1...4).contains($0) }, "\(runs)")
        XCTAssertTrue(runs.contains { $0 >= 2 })
        XCTAssertEqual(String(plan.renderedCharacters()), text)
    }

    func testDelayedCorrectionIsAboutTwentyPercentByDefault() {
        let engine = TypingEngine(settings: .init(typoRate: 0.2, breaksEnabled: false))
        var rng = SeededRandomNumberGenerator(seed: 6)
        let text = String(repeating: "typing like a human being ", count: 300)
        let plan = engine.makePlan(for: text, using: &rng)

        var immediate = 0
        var delayed = 0
        var current = 0
        for step in plan.steps + [TypingStep(delay: 0, action: .pause, progress: 0)] {
            if step.action == .backspace {
                current += 1
            } else if current > 0 {
                if current == 1 { immediate += 1 } else { delayed += 1 }
                current = 0
            }
        }
        let share = Double(delayed) / Double(immediate + delayed)
        XCTAssertEqual(share, 0.2, accuracy: 0.05)
    }

    func testDelayedCorrectionNeverSpansLineBreaksOrTabs() {
        let engine = TypingEngine(settings: .init(typoRate: 0.5, delayedCorrectionRate: 1, breaksEnabled: false))
        let text = "ab\ncd\tef\ngh\n\nij\tkl"
        for seed in 0..<200 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let plan = engine.makePlan(for: text, using: &rng)
            var buffer: [Character] = []
            for step in plan.steps {
                switch step.action {
                case .type(let c):
                    buffer.append(c)
                case .backspace:
                    let erased = buffer.removeLast()
                    XCTAssertNotEqual(erased, "\n", "seed \(seed): стёрли перевод строки")
                    XCTAssertNotEqual(erased, "\t", "seed \(seed): стёрли табуляцию")
                case .pause:
                    break
                }
            }
            XCTAssertEqual(String(plan.renderedCharacters()), text)
        }
    }

    // MARK: - Задержки, прогресс, перерывы

    func testAllDelaysArePositiveAndTotalMatchesSum() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let plan = TypingEngine(settings: .init(typoRate: 0.2)).makePlan(for: samples[2], using: &rng)
        XCTAssertTrue(plan.steps.allSatisfy { $0.delay > 0 })
        XCTAssertEqual(plan.totalDuration, plan.steps.map(\.delay).reduce(0, +), accuracy: 1e-9)
        XCTAssertEqual(plan.remainingDuration(afterStep: -1), plan.totalDuration, accuracy: 1e-9)
        XCTAssertEqual(plan.remainingDuration(afterStep: plan.steps.count - 1), 0)
        XCTAssertEqual(plan.remainingDuration(afterStep: 0), plan.totalDuration - plan.steps[0].delay, accuracy: 1e-9)
    }

    func testAverageSpeedMatchesWordsPerMinute() {
        // Без ритма, опечаток и перерывов средняя скорость должна совпадать с заданной.
        let settings = TypingSettings(wordsPerMinute: 90, typoRate: 0, naturalRhythm: false, breaksEnabled: false)
        var rng = SeededRandomNumberGenerator(seed: 8)
        let text = String(repeating: "abcdefghij", count: 500)
        let plan = TypingEngine(settings: settings).makePlan(for: text, using: &rng)
        let wpm = Double(text.count) / 5 / (plan.totalDuration / 60)
        XCTAssertEqual(wpm, 90, accuracy: 2)
    }

    func testNaturalRhythmAddsPausesAfterPunctuationAndParagraphs() {
        let rhythmic = TypingSettings(typoRate: 0, jitter: 0, naturalRhythm: true, breaksEnabled: false)
        var rng = SeededRandomNumberGenerator(seed: 9)
        let plan = TypingEngine(settings: rhythmic).makePlan(for: "Hi. Ok\nNew", using: &rng)
        let base = 0.2
        // Шаги: H i . ␠ O k ↩ N e w
        XCTAssertTrue(Rhythm.sentencePause.contains(plan.steps[3].delay - base), "\(plan.steps[3].delay)")
        XCTAssertTrue(Rhythm.spacePause.contains(plan.steps[4].delay - base * Rhythm.uppercaseFactor))
        XCTAssertTrue(Rhythm.paragraphPause.contains(plan.steps[7].delay - base * Rhythm.uppercaseFactor))
        XCTAssertEqual(plan.steps[8].delay, base, accuracy: 1e-9)
    }

    func testProgressIsMonotonicAndReachesCharacterCount() {
        var rng = SeededRandomNumberGenerator(seed: 10)
        let plan = TypingEngine(settings: .init(typoRate: 0.2, breakInterval: 2...3, breakDuration: 1...2))
            .makePlan(for: samples[1], using: &rng)
        var last = 0
        for step in plan.steps {
            XCTAssertGreaterThanOrEqual(step.progress, last)
            last = step.progress
        }
        XCTAssertEqual(last, plan.characterCount)
    }

    func testBreaksAreInsertedWithinConfiguredRanges() {
        let settings = TypingSettings(typoRate: 0.05, breaksEnabled: true, breakInterval: 5...8, breakDuration: 2...4)
        var rng = SeededRandomNumberGenerator(seed: 11)
        let text = String(repeating: "Это проверка перерывов в наборе. ", count: 40)
        let plan = TypingEngine(settings: settings).makePlan(for: text, using: &rng)

        XCTAssertGreaterThan(plan.breakCount, 5)
        var typingSinceBreak: TimeInterval = 0
        var previousCharacter: Character?
        for step in plan.steps {
            if step.action == .pause {
                XCTAssertTrue(settings.breakDuration.contains(step.delay), "длительность \(step.delay)")
                XCTAssertGreaterThanOrEqual(typingSinceBreak, settings.breakInterval.lowerBound)
                XCTAssertTrue(previousCharacter?.isWhitespace ?? true, "перерыв посреди слова")
                typingSinceBreak = 0
            } else {
                typingSinceBreak += step.delay
                if case .type(let c) = step.action { previousCharacter = c }
            }
        }
        XCTAssertEqual(String(plan.renderedCharacters()), text)
    }

    func testBreaksDisabledProducesNoPauses() {
        var rng = SeededRandomNumberGenerator(seed: 12)
        let settings = TypingSettings(breaksEnabled: false, breakInterval: 1...1, breakDuration: 1...1)
        let plan = TypingEngine(settings: settings).makePlan(for: String(repeating: "word ", count: 300), using: &rng)
        XCTAssertEqual(plan.breakCount, 0)
    }

    func testSameSeedGivesSamePlan() {
        let engine = TypingEngine(settings: .init(typoRate: 0.1))
        var a = SeededRandomNumberGenerator(seed: 42)
        var b = SeededRandomNumberGenerator(seed: 42)
        XCTAssertEqual(engine.makePlan(for: samples[2], using: &a).steps, engine.makePlan(for: samples[2], using: &b).steps)
    }

    func testOrderedRangeHelper() {
        XCTAssertEqual(ClosedRange.ordered(5.0, 2.0), 2.0...5.0)
        XCTAssertEqual(ClosedRange.ordered(1.0, 3.0), 1.0...3.0)
    }
}
