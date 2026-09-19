import AppKit
import SwiftUI

@main
struct ResumeApp: App {
  @State private var model = makeModel()
  #if DEBUG
    @MainActor private static var testWindow: NSWindow?
  #endif

  private static func makeModel() -> AppModel {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        let player = TestPlayer()
        if ProcessInfo.processInfo.arguments.contains("--delayed-playback") {
          player.loadLatency = .seconds(3)
        }
        let model = AppModel(
          client: TestAudiobookshelf(), player: player,
          stateStore: MemoryStateStore(), vault: TestConnectionStore(), startsAutomatically: false)
        player.onPlaybackChange = { [weak model] position, playing in
          Task {
            await model?.receivePlayerUpdate(position: position, duration: 1_000, playing: playing)
          }
        }
        model.books = [fixtureBook()]
        model.activeBook = model.books.first
        model.duration = 1_000
        model.position = 100
        model.chapters = [.init(id: "chapter", title: "Chapter Two", start: 500)]
        model.mode = .player
        DispatchQueue.main.async {
          NSApplication.shared.setActivationPolicy(.regular)
          let window = NSWindow(
            contentViewController: NSHostingController(rootView: ResumePanel(model: model)))
          window.title = "Resume UI Test Panel"
          window.setContentSize(window.contentView!.fittingSize)
          window.center()
          window.makeKeyAndOrderFront(nil)
          NSApplication.shared.activate()
          testWindow = window
        }
        return model
      }
    #endif
    return AppModel()
  }

  var body: some Scene {
    MenuBarExtra("Resume", systemImage: "books.vertical.fill") {
      ResumePanel(model: model)
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
        ) { _ in
          model.systemWillSleep()
        }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ) { _ in
          Task { await model.systemDidWake() }
        }
    }
    .menuBarExtraStyle(.window)
  }
}
