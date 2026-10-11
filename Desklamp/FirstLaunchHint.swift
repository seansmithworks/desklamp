import AppKit

extension UserDefaults {
    /// KVO-observable accessor; the property name is the defaults key.
    @objc dynamic var hasShownFirstLaunchHint: Bool {
        get { bool(forKey: "hasShownFirstLaunchHint") }
        set { set(newValue, forKey: "hasShownFirstLaunchHint") }
    }
}

/// One-time popover under the menu bar item on the very first launch.
@MainActor
final class FirstLaunchHint {
    private let popover = NSPopover()
    private var monitors: [Any] = []

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        // Headless testing (`-activateOnLaunch YES`) must not get a popover in the way.
        if defaults.bool(forKey: "activateOnLaunch") { return false }
        #endif
        return !defaults.hasShownFirstLaunchHint
    }

    /// Shows the hint anchored to `button` once, then records that it was shown.
    func showIfNeeded(from button: NSStatusBarButton?) {
        guard Self.shouldShow(), let button else { return }
        // The status item has no window until the next runloop pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, button.window != nil else { return }
            UserDefaults.standard.hasShownFirstLaunchHint = true

            let label = NSTextField(wrappingLabelWithString:
                "Desklamp lives here. Click to keep your Mac awake. Right-click for timers and Launch at Login.")
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.preferredMaxLayoutWidth = 240
            let size = label.sizeThatFits(NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
            label.frame = NSRect(x: 14, y: 12, width: 240, height: size.height)

            let content = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: size.height + 24))
            content.addSubview(label)
            let controller = NSViewController()
            controller.view = content

            self.popover.contentViewController = controller
            self.popover.behavior = .transient
            NSApp.activate(ignoringOtherApps: true)
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.watchForClicks()
        }
    }

    /// `.transient` alone misses clicks for an accessory app, so watch every mouse-down.
    /// The local monitor passes events through, so a click on the status item still toggles.
    private func watchForClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.close()
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.close() }
        } as Any)
    }

    private func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        popover.close()
    }
}
