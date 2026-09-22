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
        let portrait = ProcessInfo.processInfo.arguments.contains("--portrait-artwork")
        let hasArtwork = portrait || ProcessInfo.processInfo.arguments.contains("--square-artwork")
        let model = AppModel(
          client: TestAudiobookshelf(
            coverData: hasArtwork ? fixtureCover(portrait: portrait) : nil), player: player,
          stateStore: MemoryStateStore(), vault: TestConnectionStore(), startsAutomatically: false)
        player.onPlaybackChange = { [weak model] position, playing in
          Task {
            await model?.receivePlayerUpdate(position: position, duration: 1_000, playing: playing)
          }
        }
        model.books = [
          fixtureBook(hasArtwork ? (portrait ? "portrait-preview" : "square-preview") : "book")
        ]
        model.server = "https://books.example.test"
        model.username = "Listener"
        model.selectedLibraryName = "Audiobooks"
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
        if ProcessInfo.processInfo.arguments.contains("--connection-mode") {
          model.activeBook = nil
          model.server = ""
          model.username = ""
          model.mode = .connection
        }
        if ProcessInfo.processInfo.arguments.contains("--library-mode") {
          model.mode = .library
          model.libraries = [
            .init(id: "one", name: "Audiobooks", mediaType: "book"),
            .init(
              id: "two", name: "A library with a long name for checking wrapping", mediaType: "book"
            ),
          ]
        }
        if ProcessInfo.processInfo.arguments.contains("--empty-player") { model.activeBook = nil }
        if ProcessInfo.processInfo.arguments.contains("--player-error") {
          model.errorMessage = "Playback could not start. Check your connection and try again."
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
          .preferredColorScheme(
            ProcessInfo.processInfo.arguments.contains("--dark-appearance") ? .dark : .light
          )
          .onAppear { NSApplication.shared.activate() }
      }
      .windowResizability(.contentSize)
      .defaultLaunchBehavior(
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .presented : .suppressed
      )
      .restorationBehavior(.disabled)
    #endif
    playerScene
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            model.prepareForSettings()
            NSApplication.shared.activate()
          }.keyboardShortcut(",", modifiers: .command)
        }
      }
  }

  private var playerScene: some Scene {
    MenuBarExtra("Resume", systemImage: "book.fill") {
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
