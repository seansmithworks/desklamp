import AppKit
import Observation

extension UserDefaults {
    /// KVO-observable accessor; the property name is the defaults key.
    @objc dynamic var allowDisplaySleep: Bool {
        get { bool(forKey: "allowDisplaySleep") }
        set { set(newValue, forKey: "allowDisplaySleep") }
    }
}

@MainActor
@Observable
final class AwakeController {
    static let allowDisplaySleepKey = "allowDisplaySleep"

    private(set) var isActive = false
    /// Nil means indefinite.
    private(set) var endDate: Date?
    /// Beam aging for the menu bar lamp; nil while inactive.
    private(set) var lampStage: LampStage?

    /// When the current activation began; reset on deactivate.
    @ObservationIgnored private var activatedAt: Date?
    @ObservationIgnored private var stageTimer: Timer?

    @ObservationIgnored private let assertion = SleepAssertion()
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var defaultsObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private var allowDisplaySleep: Bool { UserDefaults.standard.allowDisplaySleep }

    init() {
        defaultsObservation = UserDefaults.standard.observe(\.allowDisplaySleep) { [weak self] _, _ in
            Task { @MainActor in self?.syncDisplaySleep() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deactivate() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expireIfDue()
                self?.updateLampStage()
            }
        })
        #if DEBUG
        // Headless testing: launch with `-activateOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "activateOnLaunch") { activate() }
        #endif
    }

    /// Activates immediately. `duration` nil means indefinitely.
    func activate(for duration: TimeInterval? = nil) {
        stopTimers()
        guard assertion.activate(reason: "Keeping the Mac awake", preventDisplaySleep: !allowDisplaySleep) else {
            deactivate()
            return
        }
        if !isActive { activatedAt = Date() }
        isActive = true
        endDate = duration.map { Date().addingTimeInterval($0) }
        updateLampStage()
        // Low-frequency tick so the icon ages with the menu closed.
        stageTimer = schedule(after: 60, repeats: true) { $0.updateLampStage() }
        if let duration {
            expiryTimer = schedule(after: duration, repeats: false) { $0.expireIfDue() }
            tickTimer = schedule(after: 15, repeats: true) { $0.expireIfDue() }
        }
    }

    func deactivate() {
        stopTimers()
        assertion.deactivate()
        endDate = nil
        activatedAt = nil
        isActive = false
        updateLampStage()
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    /// e.g. "42 min left", "1 hr 5 min left"; nil when indefinite or inactive.
    var timeLeftText: String? {
        guard isActive, let endDate else { return nil }
        let minutes = max(1, Int((endDate.timeIntervalSinceNow / 60).rounded(.up)))
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) hr left" : "\(h) hr \(m) min left"
        }
        return "\(minutes) min left"
    }

    /// Makes the live assertion match the current preference; the assertion itself is the source of truth.
    func syncDisplaySleep() {
        guard isActive else { return }
        let wantsDisplay = !allowDisplaySleep
        guard assertion.preventsDisplaySleep != wantsDisplay else { return }
        if !assertion.setPreventDisplaySleep(wantsDisplay) { deactivate() }
    }

    private func updateLampStage() {
        let stage = activatedAt.map { LampStage.for(elapsed: Date().timeIntervalSince($0)) }
        if stage != lampStage { lampStage = stage }
    }

    private func expireIfDue() {
        if let endDate, endDate <= Date() { deactivate() }
    }

    private func schedule(after interval: TimeInterval, repeats: Bool,
                          _ fire: @escaping @MainActor (AwakeController) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated { if let self { fire(self) } }
        }
        // .common keeps timers firing while the menu is open (event-tracking mode).
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func stopTimers() {
        expiryTimer?.invalidate()
        tickTimer?.invalidate()
        stageTimer?.invalidate()
        expiryTimer = nil
        tickTimer = nil
        stageTimer = nil
    }
}
