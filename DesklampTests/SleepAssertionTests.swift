import XCTest
import IOKit.pwr_mgt

/// Integration-style: exercises the real IOKit calls and counts what this process holds.
@MainActor
final class SleepAssertionTests: XCTestCase {
    /// Counts assertions of `type` held by this process, via IOPMCopyAssertionsByProcess.
    private func held(_ type: String) -> Int {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPid = dict?.takeRetainedValue() as? [Int: [[String: Any]]],
              let mine = byPid[Int(getpid())] else { return 0 }
        return mine.filter { ($0["AssertType"] as? String) == type }.count
    }
    private var system: Int { held(kIOPMAssertionTypePreventUserIdleSystemSleep as String) }
    private var display: Int { held(kIOPMAssertionTypePreventUserIdleDisplaySleep as String) }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AwakeController.allowDisplaySleepKey)
    }

    func testActivateCreatesAndDeactivateReleases() {
        let a = SleepAssertion()
        XCTAssertTrue(a.activate(reason: "DesklampTests", preventDisplaySleep: true))
        XCTAssertEqual(system, 1); XCTAssertEqual(display, 1)
        a.deactivate()
        XCTAssertEqual(system, 0); XCTAssertEqual(display, 0)
    }

    func testReactivateDoesNotLeak() {
        let a = SleepAssertion()
        a.activate(reason: "DesklampTests", preventDisplaySleep: true)
        a.activate(reason: "DesklampTests", preventDisplaySleep: true)
        XCTAssertEqual(system, 1); XCTAssertEqual(display, 1)
        a.deactivate()
    }

    func testLiveDisplaySleepChangeOnFirstToggle() async throws {
        UserDefaults.standard.allowDisplaySleep = false
        let c = AwakeController()
        c.activate()
        XCTAssertEqual(display, 1)
        UserDefaults.standard.allowDisplaySleep = true
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(display, 0); XCTAssertEqual(system, 1)
        UserDefaults.standard.allowDisplaySleep = false
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(display, 1); XCTAssertEqual(system, 1)
        c.deactivate()
        XCTAssertEqual(system, 0); XCTAssertEqual(display, 0)
    }

    func testPreferenceChangedWhileInactiveIsHonoredOnActivate() {
        UserDefaults.standard.allowDisplaySleep = true
        let c = AwakeController()
        c.activate()
        XCTAssertEqual(system, 1); XCTAssertEqual(display, 0)
        c.deactivate()
    }

    func testTimerExpiryDeactivates() async throws {
        let c = AwakeController()
        c.activate(for: 0.3)
        XCTAssertEqual(system, 1)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(system, 0); XCTAssertEqual(display, 0)
    }

    func testToggleOffReleases() {
        let c = AwakeController()
        c.toggle(); XCTAssertEqual(system, 1)
        c.toggle(); XCTAssertEqual(system, 0)
    }
}
