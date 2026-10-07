import XCTest
@testable import TypingEngine

final class FocusDebouncerTests: XCTestCase {
    func testTypesFreelyWhileFocused() {
        var debouncer = FocusDebouncer(returnDelay: 1)
        for t in stride(from: 0.0, to: 5, by: 0.1) {
            let result = debouncer.update(onTarget: true, at: t)
            XCTAssertTrue(result.canType)
            XCTAssertNil(result.event)
        }
    }

    func testLosingFocusStopsImmediatelyAndReportsOnce() {
        var debouncer = FocusDebouncer(returnDelay: 1)
        XCTAssertEqual(debouncer.update(onTarget: false, at: 0).event, .lost)
        XCTAssertFalse(debouncer.update(onTarget: false, at: 0).canType)
        XCTAssertNil(debouncer.update(onTarget: false, at: 0.5).event, "о потере сообщаем один раз")
        XCTAssertTrue(debouncer.isLost)
    }

    func testResumesOnlyAfterDelayOfContinuousFocus() {
        var debouncer = FocusDebouncer(returnDelay: 1)
        _ = debouncer.update(onTarget: false, at: 0)

        let back = debouncer.update(onTarget: true, at: 2)
        XCTAssertFalse(back.canType)
        XCTAssertEqual(back.event, .returning)

        XCTAssertFalse(debouncer.update(onTarget: true, at: 2.5).canType)
        XCTAssertFalse(debouncer.update(onTarget: true, at: 2.99).canType)

        let restored = debouncer.update(onTarget: true, at: 3.0)
        XCTAssertTrue(restored.canType)
        XCTAssertEqual(restored.event, .restored)
        XCTAssertFalse(debouncer.isLost)

        XCTAssertEqual(debouncer.update(onTarget: true, at: 3.1).event, nil)
    }

    func testFlickeringFocusRestartsTheWait() {
        var debouncer = FocusDebouncer(returnDelay: 1)
        _ = debouncer.update(onTarget: false, at: 0)
        _ = debouncer.update(onTarget: true, at: 1)        // вернулись…
        XCTAssertEqual(debouncer.update(onTarget: false, at: 1.5).event, nil, "уже на паузе — повторно не сообщаем")
        XCTAssertEqual(debouncer.update(onTarget: true, at: 1.6).event, .returning)
        XCTAssertFalse(debouncer.update(onTarget: true, at: 2.4).canType, "отсчёт начался заново с 1.6")
        XCTAssertTrue(debouncer.update(onTarget: true, at: 2.7).canType)
    }

    func testResetSkipsTheWait() {
        var debouncer = FocusDebouncer(returnDelay: 1)
        _ = debouncer.update(onTarget: false, at: 0)
        debouncer.reset()
        let result = debouncer.update(onTarget: true, at: 0.1)
        XCTAssertTrue(result.canType)
        XCTAssertNil(result.event)
    }
}
