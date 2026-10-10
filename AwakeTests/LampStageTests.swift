import XCTest

final class LampStageTests: XCTestCase {
    func testStageBoundaries() {
        let h: TimeInterval = 60 * 60
        XCTAssertEqual(LampStage.for(elapsed: 0), .fresh)
        XCTAssertEqual(LampStage.for(elapsed: 3 * h - 1), .fresh)
        XCTAssertEqual(LampStage.for(elapsed: 3 * h), .dimmer)
        XCTAssertEqual(LampStage.for(elapsed: 6 * h - 1), .dimmer)
        XCTAssertEqual(LampStage.for(elapsed: 6 * h), .flicker)
    }
}
