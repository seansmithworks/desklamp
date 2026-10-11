import SwiftUI

@main
struct DesklampApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self) private var statusItemController

    // The status item lives in AppKit (MenuBarExtra can't tell a click from a right-click).
    var body: some Scene {
        Settings { EmptyView() }
    }
}
