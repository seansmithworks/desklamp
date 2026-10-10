import IOKit.pwr_mgt

/// Thin wrapper over IOKit power assertions. Holds up to two assertions:
/// system idle sleep, and (optionally) display idle sleep.
final class SleepAssertion {
    private var ids: [IOPMAssertionID] = []

    var isActive: Bool { !ids.isEmpty }

    /// Creates the assertions. Returns false (and holds nothing) on failure.
    @discardableResult
    func activate(reason: String, preventDisplaySleep: Bool) -> Bool {
        deactivate()
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep as String]
        if preventDisplaySleep {
            types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
        }
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                deactivate()
                return false
            }
            ids.append(id)
        }
        return true
    }

    func deactivate() {
        ids.forEach { IOPMAssertionRelease($0) }
        ids.removeAll()
    }

    deinit { deactivate() }
}
