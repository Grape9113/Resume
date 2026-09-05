import SwiftUI
import AppKit

@main
struct ResumeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Resume", systemImage: "books.vertical.fill") {
            ResumePanel(model: model)
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    model.systemWillSleep()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task { await model.systemDidWake() }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
