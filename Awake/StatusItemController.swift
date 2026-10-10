import AppKit
import ServiceManagement

/// Owns the menu bar item. Left-click toggles keep-awake; right-click or Control-click opens the menu.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = AwakeController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private static let appName =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Awake"

    private static let durations: [(String, TimeInterval?)] = [
        ("Indefinitely", nil),
        ("5 minutes", 5 * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("5 hours", 5 * 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    // MARK: Icon

    /// Template SF Symbol, so the system tints it for light/dark menu bars.
    private func updateIcon() {
        let active = controller.isActive
        let image = NSImage(
            systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
            accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("\(Self.appName): \(active ? "on" : "off")")
        // Re-arm: observation tracking fires once per change.
        withObservationTracking { _ = controller.isActive } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    // MARK: Clicks

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            controller.toggle()
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item(toggleTitle, #selector(toggleAwake)))

        let submenu = NSMenu()
        for (index, duration) in Self.durations.enumerated() {
            let entry = item(duration.0, #selector(keepAwakeFor(_:)))
            entry.tag = index
            submenu.addItem(entry)
        }
        let forItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        forItem.submenu = submenu
        menu.addItem(forItem)

        menu.addItem(.separator())

        let display = item("Allow Display Sleep", #selector(toggleDisplaySleep))
        display.state = UserDefaults.standard.allowDisplaySleep ? .on : .off
        menu.addItem(display)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        menu.addItem(item("Quit \(Self.appName)", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private var toggleTitle: String {
        guard controller.isActive else { return "Keep Awake" }
        if let left = controller.timeLeftText { return "Awake — \(left)" }
        return "Stop Keeping Awake"
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = target ?? self
        return entry
    }

    @objc private func toggleAwake() { controller.toggle() }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        controller.activate(for: Self.durations[sender.tag].1)
    }

    @objc private func toggleDisplaySleep() {
        UserDefaults.standard.allowDisplaySleep.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
    }
}
