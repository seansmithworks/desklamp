import XCTest

/// Integration-style: exercises the real IOKit calls and reads back `pmset`-visible state.
@MainActor
final class SleepAssertionTests: XCTestCase {
    func testActivateCreatesAndDeactivateReleases() {
        let assertion = SleepAssertion()
        XCTAssertFalse(assertion.isActive)
        XCTAssertTrue(assertion.activate(reason: "AwakeTests", preventDisplaySleep: true))
        XCTAssertTrue(assertion.isActive)
        assertion.deactivate()
        XCTAssertFalse(assertion.isActive)
    }

    func testTimerExpiryDeactivates() async throws {
        let controller = AwakeController()
        controller.activate(for: 0.3)
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.assertionHeld)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.assertionHeld)
    }

    func testToggleOffReleases() {
        let controller = AwakeController()
        controller.toggle()
        XCTAssertTrue(controller.assertionHeld)
        controller.toggle()
        XCTAssertFalse(controller.assertionHeld)
    }
}
