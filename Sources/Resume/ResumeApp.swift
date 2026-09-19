import AppKit
import SwiftUI

@main
struct ResumeApp: App {
  @State private var model = makeModel()

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
        if ProcessInfo.processInfo.arguments.contains("--position-conflict") {
          model.position = 300
          model.wantsPlayback = true
          model.receiveExternalProgress(
            .init(
              itemID: "book", sessionID: nil,
              progress: .init(currentTime: 100, duration: 1_000, isFinished: false, lastUpdate: 1)))
          model.wantsPlayback = false
        }
        NSApplication.shared.setActivationPolicy(.regular)
        return model
      }
    #endif
    return AppModel()
  }

  var body: some Scene {
    #if DEBUG
      Window("Resume UI Test Panel", id: "ui-test-player") {
        ResumePanel(model: model)
          .onAppear { NSApplication.shared.activate() }
      }
      .windowResizability(.contentSize)
      .defaultLaunchBehavior(
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .presented : .suppressed
      )
      .restorationBehavior(.disabled)
    #endif
    playerScene
    Settings {
      ResumeSettings(model: model)
    }
  }

  private var playerScene: some Scene {
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
