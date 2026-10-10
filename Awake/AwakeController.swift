import Foundation
import Observation

@MainActor
@Observable
final class AwakeController {
    static let allowDisplaySleepKey = "allowDisplaySleep"

    private(set) var isActive = false
    /// Nil means indefinite.
    private(set) var endDate: Date?
    /// Refreshed periodically so "time left" text stays current.
    private(set) var now = Date()

    private let assertion = SleepAssertion()
    private var expiryTimer: Timer?
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private var allowDisplaySleep: Bool {
        UserDefaults.standard.bool(forKey: Self.allowDisplaySleepKey)
    }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyIfActive() }
        })
        observers.append(center.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deactivate() }
        })
        #if DEBUG
        // Headless testing: launch with `-activateOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "activateOnLaunch") { activate() }
        #endif
    }

    var assertionHeld: Bool { assertion.isActive }

    /// Activates immediately. `duration` nil means indefinitely.
    func activate(for duration: TimeInterval? = nil) {
        guard assertion.activate(reason: "Keeping the Mac awake", preventDisplaySleep: !allowDisplaySleep) else {
            deactivate()
            return
        }
        isActive = true
        now = Date()
        endDate = duration.map { Date().addingTimeInterval($0) }
        expiryTimer?.invalidate()
        tickTimer?.invalidate()
        expiryTimer = nil
        tickTimer = nil
        if let duration {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.deactivate() }
            }
            tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.now = Date() }
            }
        }
    }

    func deactivate() {
        expiryTimer?.invalidate()
        tickTimer?.invalidate()
        expiryTimer = nil
        tickTimer = nil
        assertion.deactivate()
        endDate = nil
        isActive = false
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    /// e.g. "42 min left", "1 hr 5 min left"; nil when indefinite or inactive.
    var timeLeftText: String? {
        guard isActive, let endDate else { return nil }
        let minutes = max(1, Int((endDate.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) hr left" : "\(h) hr \(m) min left"
        }
        return "\(minutes) min left"
    }

    // Re-create the assertion when "Allow Display Sleep" changes, keeping the existing timer.
    private var appliedAllowDisplaySleep: Bool?
    private func reapplyIfActive() {
        guard isActive else { return }
        let current = allowDisplaySleep
        if appliedAllowDisplaySleep == nil { appliedAllowDisplaySleep = current }
        guard current != appliedAllowDisplaySleep else { return }
        appliedAllowDisplaySleep = current
        assertion.activate(reason: "Keeping the Mac awake", preventDisplaySleep: !current)
    }
}
