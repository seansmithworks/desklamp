import SwiftUI
import ServiceManagement

@main
struct AwakeApp: App {
    @State private var controller = AwakeController()
    @AppStorage(AwakeController.allowDisplaySleepKey) private var allowDisplaySleep = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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

    init() {
        #if DEBUG
        // Headless testing: launch with `-activateOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "activateOnLaunch") {
            _controller.wrappedValue.activate()
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            Button(toggleTitle) { controller.toggle() }

            Menu("Keep Awake For") {
                ForEach(Self.durations, id: \.0) { title, duration in
                    Button(title) { controller.activate(for: duration) }
                }
            }

            Divider()

            Toggle("Allow Display Sleep", isOn: $allowDisplaySleep)

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))

            Divider()

            Button("Quit \(Self.appName)") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.menu)
    }

    private var toggleTitle: String {
        guard controller.isActive else { return "Keep Awake" }
        if let left = controller.timeLeftText { return "Awake — \(left)" }
        return "Stop Keeping Awake"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
