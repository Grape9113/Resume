import SwiftUI

@main
struct ResumeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Resume", systemImage: "books.vertical.fill") {
            ResumePanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
