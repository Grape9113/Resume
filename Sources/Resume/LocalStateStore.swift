import Foundation
import ResumeCore

struct LocalState: Codable, Sendable {
    var books: [Audiobook] = []
    var activeBookID: String?
    var positions: [String: TimeInterval] = [:]
    var speeds: [String: Double] = [:]
    var knownPositions: [String: [KnownPosition]] = [:]
    var recentlyFinishedAt: [String: Date] = [:]
}

actor LocalStateStore {
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "Resume", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "state.json")
    }

    func load() -> LocalState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LocalState.self, from: data)
    }

    func save(_ state: LocalState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}
