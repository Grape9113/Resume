import AppKit
import ResumeCore
import SwiftUI

struct ResumePanel: View {
  @Bindable var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @FocusState private var panelFocused: Bool
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 8) {
      if let message = model.errorMessage {
        ScrollView {
          Label(message, systemImage: "exclamationmark.circle")
            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 48)
        .padding(6)
        .background(.black.opacity(0.18), in: .rect(cornerRadius: 6))
      }
      Group {
        switch model.mode {
        case .connection: connection
        case .library: library
        case .player: player
        case .search: search
        case .chapters: chapterList
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(12)
    .frame(width: 280, height: 306)
    .foregroundStyle(ResumeStyle.ink)
    .tint(ResumeStyle.highlight)
    .background(ResumeStyle.background(dark: colorScheme == .dark))
    .clipShape(.rect(cornerRadius: 12))
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
      if press.key == ",", press.modifiers == .command {
        showSettings()
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
      } else if model.mode == .chapters {
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
    VStack(spacing: 8) {
      GeometryReader { geometry in
        cover(for: model.activeBook)
          .frame(width: min(142, geometry.size.height), height: min(142, geometry.size.height))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
        .progressViewStyle(BookProgressStyle())
        .accessibilityLabel("Book progress")
        .accessibilityValue(time(model.position) + " of " + time(model.duration))
      HStack {
        Text(time(model.position))
        Spacer()
        Text("−" + time(max(model.duration - model.position, 0)))
      }.font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
      HStack(spacing: 22) {
        Button { model.skip(-15) } label: {
          Image(systemName: "gobackward.15").font(.system(size: 25))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Back 15 seconds")
        .buttonStyle(TransportStyle())
        ZStack {
          Button { Task { await model.togglePlayback() } } label: {
            Image(systemName: (model.isPlaying || model.wantsPlayback) ? "pause.fill" : "play.fill")
              .font(.system(size: 25, weight: .semibold))
              .frame(width: 56, height: 56)
          }
          .buttonStyle(TransportStyle(primary: true))
          .accessibilityLabel((model.isPlaying || model.wantsPlayback) ? "Pause" : "Play")
          if model.isLoadingPlayback {
            ProgressView().controlSize(.mini)
              .offset(y: 21).allowsHitTesting(false)
              .accessibilityLabel("Loading playback")
          }
        }
        Button { model.skip(30) } label: {
          Image(systemName: "goforward.30").font(.system(size: 25))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Forward 30 seconds")
        .buttonStyle(TransportStyle())
      }
      HStack(spacing: 10) {
        Menu {
          ForEach([0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { value in
            Button("\(value.formatted())×") { model.setSpeed(value) }
          }
        } label: {
          HStack(spacing: 12) {
            Text("\(model.speed.formatted())×")
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
          }.frame(maxWidth: .infinity).frame(height: 30)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(maxWidth: .infinity).frame(height: 30)
        .padding(.horizontal, 6)
        .background(.black.opacity(0.16), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ResumeStyle.outline, lineWidth: 1))
        .accessibilityLabel("Playback speed, \(model.speed.formatted()) times")
        if !model.chapters.isEmpty {
          Rectangle().fill(ResumeStyle.ink.opacity(0.45)).frame(width: 1, height: 22)
          Button { model.mode = .chapters } label: {
            Label("Chapters", systemImage: "list.bullet")
              .frame(maxWidth: .infinity).frame(height: 30)
          }.buttonStyle(ResumeButtonStyle())
        }
      }.font(.system(size: 12, weight: .medium))
      if model.needsPositionRecovery {
        ScrollView { PositionRecoveryChoices(model: model) }.frame(height: 76)
      }
    }
  }

  private var search: some View {
    VStack(spacing: 10) {
      SearchInput(
        text: $model.query, changed: { model.updateSearch() },
        submit: { Task { await model.acceptSearch() } }, cancel: { model.cancelSearch() },
        settings: { showSettings() }, quit: { model.quit() }
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

  private func showSettings() {
    model.prepareForSettings()
    openSettings()
    NSApplication.shared.activate()
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
      RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.16))
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

}

struct ResumeSettings: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings").font(.headline)
      LabeledContent("Server", value: model.server)
      LabeledContent("Username", value: model.username)
      LabeledContent("Library", value: model.selectedLibraryName)
      Toggle(
        "Launch at Login",
        isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
      if !model.knownPositions.isEmpty {
        Divider()
        PositionRecoveryChoices(model: model)
      }
      Divider()
      Text(buildIdentity)
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        .accessibilityIdentifier("build-information")
      Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
    }
    .padding(20)
    .frame(width: 340)
    .onAppear { model.prepareForSettings() }
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

private struct PositionRecoveryChoices: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(
          model.needsPositionRecovery ? "Choose listening position" : "Other listening positions"
        )
        .font(.subheadline.weight(.medium))
        if model.isResolvingPosition { ProgressView().controlSize(.mini) }
      }
      ForEach(model.knownPositions) { known in
        Button {
          Task { await model.recover(known) }
        } label: {
          HStack {
            Text(known.source == .thisMac ? "This Mac" : "Audiobookshelf")
            Spacer()
            Text(Duration.seconds(known.position).formatted(.time(pattern: .hourMinuteSecond)))
              .monospacedDigit()
          }
          .frame(maxWidth: .infinity)
        }
        .disabled(model.isResolvingPosition || model.isLoadingPlayback)
      }
      if let message = model.recoveryError {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(8)
    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
  }
}

private struct ArtworkImage: View {
  let model: AppModel
  let book: Audiobook
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit()
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
    if event.charactersIgnoringModifiers == ",", modifiers == .command {
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

// Shared visual vocabulary for the compact native panel.
private enum ResumeStyle {
  static let ink = Color(red: 1, green: 0.97, blue: 0.94)
  static let highlight = Color(red: 1, green: 0.57, blue: 0.59)
  static let outline = Color(red: 1, green: 0.23, blue: 0.29)
  static func background(dark: Bool) -> LinearGradient {
    LinearGradient(
      colors: [Color(red: dark ? 0.62 : 0.78, green: 0.025, blue: 0.055),
               Color(red: dark ? 0.25 : 0.38, green: 0.005, blue: 0.015)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

private struct ResumeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(ResumeStyle.ink)
      .background(.black.opacity(configuration.isPressed ? 0.35 : 0.16), in: .rect(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(ResumeStyle.outline, lineWidth: 1))
  }
}

private struct TransportStyle: ButtonStyle {
  var primary = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(ResumeStyle.ink)
      .background {
        Circle().fill(primary
          ? AnyShapeStyle(LinearGradient(colors: [.red, Color(red: 0.68, green: 0, blue: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
          : AnyShapeStyle(.black.opacity(0.13)))
      }
      .overlay(Circle().stroke(primary ? ResumeStyle.highlight.opacity(0.7) : ResumeStyle.outline, lineWidth: 1))
      .brightness(configuration.isPressed ? -0.12 : 0)
  }
}

private struct BookProgressStyle: ProgressViewStyle {
  func makeBody(configuration: Configuration) -> some View {
    GeometryReader { geometry in
      Capsule().fill(ResumeStyle.ink.opacity(0.18))
        .overlay(alignment: .leading) {
          Capsule().fill(ResumeStyle.highlight)
            .frame(width: geometry.size.width * min(max(configuration.fractionCompleted ?? 0, 0), 1))
        }
    }.frame(height: 6)
  }
}
