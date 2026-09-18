import Foundation
import ResumeCore

struct LocalState: Codable, Sendable {
  var books: [Audiobook] = []
  var activeBookID: String?
  var activeBookSelectedAt: Date?
  var playback = PlaybackLedger()

  private enum CodingKeys: String, CodingKey {
    case books, activeBookID, activeBookSelectedAt, playback
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    books = try container.decodeIfPresent([Audiobook].self, forKey: .books) ?? []
    activeBookID = try container.decodeIfPresent(String.self, forKey: .activeBookID)
    activeBookSelectedAt = try container.decodeIfPresent(Date.self, forKey: .activeBookSelectedAt)
    playback = try container.decodeIfPresent(PlaybackLedger.self, forKey: .playback) ?? .init()
  }
}

protocol LocalStatePersisting: Sendable {
  func load() async -> LocalState?
  func save(_ state: LocalState) async throws
  func clear() async
}

actor LocalStateStore: LocalStatePersisting {
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
