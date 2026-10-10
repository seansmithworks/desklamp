import IOKit.pwr_mgt

/// Thin wrapper over IOKit power assertions. Holds up to two assertions:
/// system idle sleep, and (optionally) display idle sleep.
final class SleepAssertion {
    private var systemID: IOPMAssertionID?
    private var displayID: IOPMAssertionID?

    var isActive: Bool { systemID != nil }
    /// What the live assertion actually holds; the source of truth for the display-sleep mode.
    var preventsDisplaySleep: Bool { displayID != nil }

    /// Creates the assertions, releasing any previously held ones first.
    /// Returns false (and holds nothing) on failure.
    @discardableResult
    func activate(reason: String, preventDisplaySleep: Bool) -> Bool {
        deactivate()
        guard let id = Self.create(kIOPMAssertionTypePreventUserIdleSystemSleep, reason) else { return false }
        systemID = id
        guard setPreventDisplaySleep(preventDisplaySleep, reason: reason) else {
            deactivate()
            return false
        }
        return true
    }

    /// Adds or drops only the display assertion; the system assertion is untouched.
    @discardableResult
    func setPreventDisplaySleep(_ prevent: Bool, reason: String = "Keeping the Mac awake") -> Bool {
        guard isActive else { return false }
        if prevent, displayID == nil {
            guard let id = Self.create(kIOPMAssertionTypePreventUserIdleDisplaySleep, reason) else { return false }
            displayID = id
        } else if !prevent, let id = displayID {
            IOPMAssertionRelease(id)
            displayID = nil
        }
        return true
    }

    func deactivate() {
        if let id = displayID { IOPMAssertionRelease(id) }
        if let id = systemID { IOPMAssertionRelease(id) }
        displayID = nil
        systemID = nil
    }

    private static func create(_ type: String, _ reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }

    deinit { deactivate() }
}
