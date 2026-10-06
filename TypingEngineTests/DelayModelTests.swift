import XCTest
@testable import TypingEngine

final class DelayModelTests: XCTestCase {
    func testBaseDelayFollowsWordsPerMinute() {
        // 60 WPM = 300 символов в минуту = 0.2 с на символ.
        XCTAssertEqual(DelayModel(settings: .init(wordsPerMinute: 60)).baseDelay, 0.2, accuracy: 1e-9)
        XCTAssertEqual(DelayModel(settings: .init(wordsPerMinute: 120)).baseDelay, 0.1, accuracy: 1e-9)
        XCTAssertEqual(DelayModel(settings: .init(wordsPerMinute: 30)).baseDelay, 0.4, accuracy: 1e-9)
        XCTAssertEqual(DelayModel(settings: .init(wordsPerMinute: 150)).baseDelay, 0.08, accuracy: 1e-9)
    }

    func testJitterStaysWithinFortyPercentAndAveragesToBase() {
        let model = DelayModel(settings: .init(wordsPerMinute: 60))
        var rng = SeededRandomNumberGenerator(seed: 1)
        let samples = (0..<20_000).map { _ in model.keystrokeDelay(for: "a", using: &rng) }

        let base = model.baseDelay
        for delay in samples {
            XCTAssertGreaterThanOrEqual(delay, base * 0.6 - 1e-12)
            XCTAssertLessThanOrEqual(delay, base * 1.4 + 1e-12)
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        XCTAssertEqual(mean, base, accuracy: base * 0.02)

        // Разброс действительно есть и он «колокольный»: большинство значений ближе к центру.
        let nearCenter = samples.filter { abs($0 - base) <= base * 0.2 }.count
        XCTAssertGreaterThan(Double(nearCenter) / Double(samples.count), 0.6)
        XCTAssertGreaterThan(Set(samples).count, 1000)
    }

    func testZeroJitterGivesExactBaseDelay() {
        let model = DelayModel(settings: .init(wordsPerMinute: 60, jitter: 0))
        var rng = SeededRandomNumberGenerator(seed: 2)
        XCTAssertEqual(model.keystrokeDelay(for: "a", using: &rng), 0.2, accuracy: 1e-12)
    }

    func testUppercaseAndSpecialCharactersAreSlower() {
        let model = DelayModel(settings: .init(wordsPerMinute: 60, jitter: 0))
        var rng = SeededRandomNumberGenerator(seed: 3)
        let lower = model.keystrokeDelay(for: "a", using: &rng)
        XCTAssertGreaterThan(model.keystrokeDelay(for: "A", using: &rng), lower)
        XCTAssertGreaterThan(model.keystrokeDelay(for: "Ж", using: &rng), lower)
        XCTAssertGreaterThan(model.keystrokeDelay(for: "@", using: &rng), lower)
        XCTAssertGreaterThan(model.keystrokeDelay(for: "{", using: &rng), lower)
        XCTAssertEqual(model.keystrokeDelay(for: "7", using: &rng), lower, accuracy: 1e-12)
        XCTAssertEqual(model.keystrokeDelay(for: ".", using: &rng), lower, accuracy: 1e-12)
        XCTAssertEqual(model.keystrokeDelay(for: " ", using: &rng), lower, accuracy: 1e-12)
    }

    func testWithoutNaturalRhythmAllCharactersCostTheSame() {
        let model = DelayModel(settings: .init(wordsPerMinute: 60, jitter: 0, naturalRhythm: false))
        var rng = SeededRandomNumberGenerator(seed: 4)
        XCTAssertEqual(model.keystrokeDelay(for: "A", using: &rng), 0.2, accuracy: 1e-12)
        XCTAssertEqual(model.keystrokeDelay(for: "@", using: &rng), 0.2, accuracy: 1e-12)
        XCTAssertEqual(model.rhythmPause(after: ".", before: " ", using: &rng), 0)
        XCTAssertEqual(model.rhythmPause(after: "\n", before: "A", using: &rng), 0)
    }

    func testRhythmPausesMatchSpecifiedRanges() {
        let model = DelayModel(settings: .default)
        var rng = SeededRandomNumberGenerator(seed: 5)
        for _ in 0..<500 {
            XCTAssertTrue(Rhythm.spacePause.contains(model.rhythmPause(after: " ", before: "w", using: &rng)))
            XCTAssertTrue(Rhythm.clausePause.contains(model.rhythmPause(after: ",", before: " ", using: &rng)))
            XCTAssertTrue(Rhythm.sentencePause.contains(model.rhythmPause(after: ".", before: " ", using: &rng)))
            XCTAssertTrue(Rhythm.sentencePause.contains(model.rhythmPause(after: "?", before: "\n", using: &rng)))
            XCTAssertTrue(Rhythm.paragraphPause.contains(model.rhythmPause(after: "\n", before: "T", using: &rng)))
        }
        XCTAssertEqual(Rhythm.spacePause, 0.05...0.15)
        XCTAssertEqual(Rhythm.clausePause, 0.2...0.5)
        XCTAssertEqual(Rhythm.sentencePause, 0.4...1.2)
        XCTAssertEqual(Rhythm.paragraphPause, 1.0...3.0)
    }

    func testNoRhythmPauseInsideWordsNumbersAndNewlineRuns() {
        let model = DelayModel(settings: .default)
        var rng = SeededRandomNumberGenerator(seed: 6)
        XCTAssertEqual(model.rhythmPause(after: nil, before: "a", using: &rng), 0)
        XCTAssertEqual(model.rhythmPause(after: "a", before: "b", using: &rng), 0)
        XCTAssertEqual(model.rhythmPause(after: ".", before: "1", using: &rng), 0, "3.14 — не конец предложения")
        XCTAssertEqual(model.rhythmPause(after: ",", before: "5", using: &rng), 0, "1,5 — не перечисление")
        XCTAssertEqual(model.rhythmPause(after: "\n", before: "\n", using: &rng), 0, "пауза абзаца — один раз")
    }

    func testGaussianHasZeroMeanAndUnitVariance() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let samples = (0..<50_000).map { _ in rng.nextGaussian() }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(samples.count)
        XCTAssertEqual(mean, 0, accuracy: 0.02)
        XCTAssertEqual(variance, 1, accuracy: 0.03)
    }
}
