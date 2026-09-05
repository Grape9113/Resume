import AppKit
import ResumeCore
import SwiftUI

struct ResumePanel: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
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
        .frame(width: 320)
        .padding(14)
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                Text(message).font(.caption).padding(8).background(.regularMaterial).clipShape(.rect(cornerRadius: 8)).padding(8)
            }
        }
        .onKeyPress(.space) {
            guard model.mode == .player else { return .ignored }
            Task { await model.togglePlayback() }
            return .handled
        }
        .onKeyPress(.escape) {
            if model.mode == .search { model.cancelSearch() }
            else if model.mode != .player { model.mode = .player }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters)) { press in
            guard model.mode == .player, press.modifiers.isEmpty else { return .ignored }
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
               let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                model.beginSearch(with: text)
                return .handled
            }
            return .ignored
        }
        .onDisappear { if model.mode == .search { model.cancelSearch() } }
        .onAppear { NSApplication.shared.setActivationPolicy(.accessory) }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Audiobookshelf").font(.headline)
            TextField("https://your-pod.pikapod.net", text: $model.server).textFieldStyle(.roundedBorder)
            TextField("Username", text: $model.username).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $model.password).textFieldStyle(.roundedBorder)
            Button("Connect") { Task { await model.connect() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose audiobook library").font(.headline)
            ForEach(model.libraries) { library in
                Button(library.name) { Task { try? await model.chooseLibrary(library) } }.buttonStyle(.plain)
            }
        }
    }

    private var player: some View {
        VStack(spacing: 12) {
            cover(for: model.activeBook)
            ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
                .accessibilityLabel("Book progress")
                .accessibilityValue(time(model.position) + " of " + time(model.duration))
            HStack { Text(time(model.position)); Spacer(); Text("−" + time(max(model.duration - model.position, 0))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button { model.skip(-15) } label: { Image(systemName: "gobackward.15") }
                Button { Task { await model.togglePlayback() } } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title2) }
                Button { model.skip(30) } label: { Image(systemName: "goforward.30") }
            }.buttonStyle(.borderless).controlSize(.large)
            HStack {
                Menu("\(model.speed.formatted())×") { ForEach([0.75,1,1.25,1.5,1.75,2,2.5,3], id: \.self) { value in Button("\(value.formatted())×") { model.setSpeed(value) } } }
                Spacer()
                if !model.chapters.isEmpty { Button("Chapters") { model.mode = .chapters }.buttonStyle(.borderless) }
                Menu {
                    Button("Force Fetch") { Task { await model.forceFetch() } }
                    Button("Force Push") { Task { await model.forcePush() } }
                    if !model.knownPositions.isEmpty {
                        Divider()
                        Section("Choose Position") {
                            ForEach(model.knownPositions) { known in
                                Button("\(known.source == .thisMac ? "This Mac" : "Audiobookshelf") · \(time(known.position))") { model.recover(known) }
                            }
                        }
                    }
                } label: { Image(systemName: model.knownPositions.isEmpty ? "arrow.triangle.2.circlepath" : "exclamationmark.arrow.triangle.2.circlepath") }
            }
        }
    }

    private var search: some View {
        VStack(spacing: 10) {
            TextField("Search", text: $model.query).textFieldStyle(.roundedBorder).focused($searchFocused).onChange(of: model.query) { model.updateSearch() }.onSubmit { model.acceptSearch() }
            if let result = model.searchResult { cover(for: result); Text(result.title).font(.headline).lineLimit(1); Text(result.authors.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1) }
            else { ContentUnavailableView("No match", systemImage: "books.vertical") }
        }.onAppear { searchFocused = true }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            LabeledContent("Server", value: model.server)
            LabeledContent("Username", value: model.username)
            LabeledContent("Library", value: model.selectedLibraryName)
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Divider()
            Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
        }
    }

    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Chapters").font(.headline)
            ScrollView { LazyVStack(alignment: .leading) { ForEach(model.chapters) { chapter in Button { model.selectChapter(chapter) } label: { HStack { Text(chapter.title); Spacer(); Text(time(chapter.start)).foregroundStyle(.secondary) } }.buttonStyle(.plain).padding(.vertical, 5) } } }
        }.frame(maxHeight: 360)
    }

    private func cover(for book: Audiobook?) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let book { ArtworkImage(model: model, book: book) }
            else { Image(systemName: "book.closed.fill").font(.system(size: 54)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let book, model.isRecentlyFinished(book) {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.white, .green).padding(8).accessibilityLabel("Recently finished")
            }
        }
            .aspectRatio(1, contentMode: .fit).accessibilityLabel(book.map { "Cover of \($0.title)" } ?? "No active audiobook")
    }

    private func time(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0); return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }
}

private struct ArtworkImage: View {
    let model: AppModel
    let book: Audiobook
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "book.closed.fill").font(.system(size: 54)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 8))
        .task(id: book.id + (book.coverRevision ?? "")) { image = await model.artwork(for: book) }
    }
}
