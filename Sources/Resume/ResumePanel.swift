import AppKit
import ResumeCore
import SwiftUI

struct ResumePanel: View {
  @Bindable var model: AppModel
  @FocusState private var panelFocused: Bool

  var body: some View {
    VStack(spacing: 6) {
      Group {
        switch model.mode {
        case .connection: connection
        case .library: library
        case .player: player
        case .search: search
        case .settings: settings
        case .chapters: chapterList
        }
      }
      Divider()
      Text(buildIdentity)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Running \(buildIdentity)")
    }
    .frame(width: 280)
    .padding(12)
    .overlay(alignment: .top) {
      if let message = model.errorMessage {
        Text(message).font(.caption).padding(8).background(.regularMaterial).clipShape(
          .rect(cornerRadius: 8)
        ).padding(8)
      }
    }
    .background {
      // This is only the keyboard landing target. Real controls keep their native focus effects.
      Color.clear.frame(width: 1, height: 1)
        .focusable().focusEffectDisabled().focused($panelFocused)
        .accessibilityHidden(true)
    }
    .onChange(of: model.mode) {
      panelFocused = model.mode != .search
    }
    .onKeyPress(.space) {
      guard model.mode == .player else { return .ignored }
      Task { await model.togglePlayback() }
      return .handled
    }
    .onKeyPress(.escape) {
      if model.mode == .search {
        model.cancelSearch()
      } else if model.mode != .player {
        model.mode = .player
      }
      return .handled
    }
    .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.symbols)) { press in
      guard model.mode == .player, press.modifiers.intersection([.command, .control]).isEmpty else {
        return .ignored
      }
      model.beginSearch(with: String(press.characters))
      return .handled
    }
    .onKeyPress(keys: [",", "v", "q"]) { press in
      if press.key == ",", press.modifiers == .control {
        model.showSettings()
        return .handled
      }
      if press.key == "q", press.modifiers == .command {
        model.quit()
        return .handled
      }
      if press.key == "v", press.modifiers == .command, model.mode == .player,
        let text = NSPasteboard.general.string(forType: .string), !text.isEmpty
      {
        model.beginSearch(with: text)
        return .handled
      }
      return .ignored
    }
    .onDisappear {
      if model.mode == .search {
        model.cancelSearch()
      } else if model.mode == .settings || model.mode == .chapters {
        model.mode = .player
      }
    }
    .onAppear {
      if model.mode == .player { panelFocused = true }
    }
  }

  private var connection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect to Audiobookshelf").font(.headline)
      TextField("https://your-pod.pikapod.net", text: $model.server).textFieldStyle(.roundedBorder)
      TextField("Username", text: $model.username).textFieldStyle(.roundedBorder)
      SecureField("Password", text: $model.password).textFieldStyle(.roundedBorder)
      Button("Connect") { Task { await model.connect() } }.buttonStyle(.borderedProminent).frame(
        maxWidth: .infinity, alignment: .trailing)
    }
  }

  private var library: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Choose audiobook library").font(.headline)
      ForEach(model.libraries) { library in
        Button(library.name) {
          Task {
            do { try await model.chooseLibrary(library) } catch {
              model.errorMessage = "That library could not be loaded."
            }
          }
        }.buttonStyle(.plain)
      }
    }
  }

  private var player: some View {
    VStack(spacing: 6) {
      cover(for: model.activeBook)
      ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
        .accessibilityLabel("Book progress")
        .accessibilityValue(time(model.position) + " of " + time(model.duration))
      HStack {
        Text(time(model.position))
        Spacer()
        Text("−" + time(max(model.duration - model.position, 0)))
      }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      HStack(spacing: 24) {
        Button {
          model.skip(-15)
        } label: {
          Image(systemName: "gobackward.15")
        }.accessibilityLabel("Back 15 seconds")
        ZStack {
          Button {
            Task { await model.togglePlayback() }
          } label: {
            Image(systemName: (model.isPlaying || model.wantsPlayback) ? "pause.fill" : "play.fill")
              .font(.title2)
              .frame(width: 36, height: 36)
          }
          .accessibilityLabel((model.isPlaying || model.wantsPlayback) ? "Pause" : "Play")
          if model.isLoadingPlayback {
            ProgressView().controlSize(.small)
              .offset(x: 30)
              .accessibilityLabel("Loading playback")
          }
        }
        Button {
          model.skip(30)
        } label: {
          Image(systemName: "goforward.30")
        }.accessibilityLabel("Forward 30 seconds")
      }.buttonStyle(.borderless).controlSize(.large)
      HStack {
        Menu("\(model.speed.formatted())×") {
          ForEach([0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { value in
            Button("\(value.formatted())×") { model.setSpeed(value) }
          }
        }
        .accessibilityLabel("Playback speed, \(model.speed.formatted()) times")
        Spacer()
        if !model.chapters.isEmpty {
          Button("Chapters") { model.mode = .chapters }.buttonStyle(.borderless)
        }
        Menu {
          Button("Force Fetch") { Task { await model.forceFetch() } }
          if !model.knownPositions.isEmpty {
            Divider()
            Section("Choose Position") {
              ForEach(model.knownPositions) { known in
                Button(
                  "\(known.source == .thisMac ? "This Mac" : "Audiobookshelf") · \(time(known.position))"
                ) { model.recover(known) }
              }
            }
          }
        } label: {
          Image(
            systemName: model.knownPositions.isEmpty
              ? "arrow.triangle.2.circlepath" : "exclamationmark.arrow.triangle.2.circlepath")
        }
        .accessibilityLabel(
          model.knownPositions.isEmpty
            ? "Synchronization" : "Synchronization, another position is available")
      }
    }
  }

  private var search: some View {
    VStack(spacing: 10) {
      SearchInput(
        text: $model.query, changed: { model.updateSearch() },
        submit: { Task { await model.acceptSearch() } }, cancel: { model.cancelSearch() },
        settings: { model.showSettings() }, quit: { model.quit() }
      )
      .frame(height: 24)
      if let result = model.searchResult {
        cover(for: result)
        Text(result.title).font(.headline).lineLimit(1)
        Text(result.authors.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
      } else {
        ContentUnavailableView("No match", systemImage: "books.vertical")
      }
    }
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings").font(.headline)
      LabeledContent("Server", value: model.server)
      LabeledContent("Username", value: model.username)
      LabeledContent("Library", value: model.selectedLibraryName)
      Toggle(
        "Launch at Login",
        isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
      Divider()
      Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
    }
  }

  private var chapterList: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Chapters").font(.headline)
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(model.chapters) { chapter in
            Button {
              model.selectChapter(chapter)
            } label: {
              HStack {
                Text(chapter.title)
                Spacer()
                Text(time(chapter.start)).foregroundStyle(.secondary)
              }
            }.buttonStyle(.plain).padding(.vertical, 5)
          }
        }
      }
    }.frame(maxHeight: 360)
  }

  private func cover(for book: Audiobook?) -> some View {
    ZStack(alignment: .topTrailing) {
      RoundedRectangle(cornerRadius: 8).fill(.quaternary)
      if let book {
        ArtworkImage(model: model, book: book)
      } else {
        Image(systemName: "book.closed.fill").font(.system(size: 54)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let book, model.isRecentlyFinished(book) {
        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.white, .green)
          .padding(8).accessibilityLabel("Recently finished")
      }
    }
    .aspectRatio(1, contentMode: .fit).accessibilityLabel(
      book.map { "Cover of \($0.title)" } ?? "No active audiobook")
  }

  private func time(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds), 0)
    return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
  }

  private var buildIdentity: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "unknown"
    let build =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "unknown"
    let builtAt =
      (try? Bundle.main.executableURL?.resourceValues(
        forKeys: [.contentModificationDateKey]
      ).contentModificationDate) ?? nil
    let developmentBuild =
      builtAt.map {
        $0.formatted(date: .abbreviated, time: .shortened)
      } ?? "unknown time"
    return "Resume \(version) (build \(build)) · built \(developmentBuild)"
  }
}

private struct ArtworkImage: View {
  let model: AppModel
  let book: Audiobook
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "book.closed.fill").font(.system(size: 54)).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipShape(.rect(cornerRadius: 8))
    .task(id: book.id + (book.coverRevision ?? "")) { image = await model.artwork(for: book) }
  }
}

private struct SearchInput: NSViewRepresentable {
  @Binding var text: String
  let changed: () -> Void
  let submit: () -> Void
  let cancel: () -> Void
  let settings: () -> Void
  let quit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> SearchTextField {
    let field = SearchTextField()
    field.placeholderString = "Search"
    field.setAccessibilityLabel("Search")
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.font = .systemFont(ofSize: NSFont.systemFontSize)
    field.delegate = context.coordinator
    return field
  }
  func updateNSView(_ field: SearchTextField, context: Context) {
    context.coordinator.input = self
    if field.stringValue != text { field.stringValue = text }
    field.settings = settings
    field.quit = quit
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var input: SearchInput
    init(_ input: SearchInput) { self.input = input }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      input.text = field.stringValue
      input.changed()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool
    {
      if command == #selector(NSResponder.insertNewline(_:)) {
        input.submit()
        return true
      }
      if command == #selector(NSResponder.cancelOperation(_:)) {
        input.cancel()
        return true
      }
      return false
    }
  }
}

private final class SearchTextField: NSTextField {
  var settings: (() -> Void)?
  var quit: (() -> Void)?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window else { return }
      window.makeFirstResponder(self)
      if let editor = self.currentEditor() {
        editor.selectedRange = NSRange(location: self.stringValue.utf16.count, length: 0)
      }
    }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.charactersIgnoringModifiers == ",", modifiers == .control {
      settings?()
      return true
    }
    if event.charactersIgnoringModifiers == "q", modifiers == .command {
      quit?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
