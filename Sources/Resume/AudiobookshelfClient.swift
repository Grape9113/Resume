import Foundation
import ResumeCore

struct ABSLibrary: Codable, Identifiable, Sendable {
  let id: String
  let name: String
  let mediaType: String
}

struct PlaybackSession: Sendable {
  let id: String
  let currentTime: TimeInterval
  let duration: TimeInterval
  let chapters: [Chapter]
  let streamURLs: [URL]
}

struct ABSProgress: Decodable, Sendable {
  let currentTime: Double
  let duration: Double
  let isFinished: Bool
  let lastUpdate: Int64
}

enum AudiobookshelfClientError: Error {
  case authenticationRequired
}

struct AuthenticatedMediaResponse: @unchecked Sendable {
  let data: Data
  let statusCode: Int
  let expectedContentLength: Int64
  let mimeType: String?
  let contentRange: String?
  let acceptsRanges: Bool
}

actor AudiobookshelfClient {
  private let vault: KeychainStore
  private let session: URLSession
  private var sessionRecoveryTask: Task<AuthenticationTokens, Error>?

  init(vault: KeychainStore, session: URLSession = .shared) {
    self.vault = vault
    self.session = session
  }

  func login(server: URL, username: String, password: String) async throws {
    var request = URLRequest(url: server.appending(path: "login"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("true", forHTTPHeaderField: "x-return-tokens")
    request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
    let data = try await sendData(request)
    let tokens = try AudiobookshelfTokenEnvelope.decode(data)
    try await vault.save(
      connection: .init(server: server, username: username, password: password), tokens: tokens)
  }

  func accessToken() async -> String? { try? await vault.loadTokens()?.accessToken }

  func libraries() async throws -> [ABSLibrary] {
    try await authorized(path: "api/libraries")
  }

  func items(libraryID: String) async throws -> [Audiobook] {
    let response: ItemsResponse = try await authorized(
      path: "api/libraries/\(libraryID)/items?limit=0&minified=1")
    let progressResponse: AllProgressResponse = try await authorized(path: "api/me/progress")
    var progressByItem: [String: AllProgressResponse.Progress] = [:]
    for progress in progressResponse.mediaProgress {
      guard let itemID = progress.libraryItemId else { continue }
      if progress.lastUpdate > (progressByItem[itemID]?.lastUpdate ?? 0) {
        progressByItem[itemID] = progress
      }
    }
    return response.results.map { item in
      let progress = progressByItem[item.id]
      return Audiobook(
        id: item.id,
        title: item.media.metadata.title ?? "Untitled",
        authors: item.media.metadata.authors?.map(\.name) ?? item.media.metadata.authorName.map {
          [$0]
        } ?? [],
        series: item.media.metadata.series?.map(\.name) ?? item.media.metadata.seriesName.map {
          [$0]
        } ?? [],
        lastPlayedAt: progress.map { Date(timeIntervalSince1970: Double($0.lastUpdate) / 1_000) },
        duration: item.media.duration ?? 0,
        coverRevision: String(item.updatedAt ?? 0)
      )
    }
  }

  func startPlayback(itemID: String) async throws -> PlaybackSession {
    let body: [String: Any] = [
      "deviceInfo": ["clientName": "Resume", "deviceId": Host.current().localizedName ?? "Mac"],
      "mediaPlayer": "avplayer",
      "supportedMimeTypes": [
        "audio/mpeg", "audio/mp4", "audio/aac", "application/vnd.apple.mpegurl",
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: body)
    let response: PlayResponse = try await authorized(
      path: "api/items/\(itemID)/play", method: "POST", body: data)
    guard let connection = try await vault.loadConnection() else {
      throw URLError(.badServerResponse)
    }
    let streamURLs = response.audioTracks.compactMap {
      URL(string: $0.contentUrl, relativeTo: connection.server)?.absoluteURL
    }
    guard !streamURLs.isEmpty else { throw URLError(.badServerResponse) }
    return PlaybackSession(
      id: response.id,
      currentTime: response.currentTime,
      duration: response.duration,
      chapters: response.chapters.enumerated().map {
        .init(id: String($0.offset), title: $0.element.title, start: $0.element.start)
      },
      streamURLs: streamURLs
    )
  }

  func progress(itemID: String) async throws -> ABSProgress {
    do {
      return try await authorized(path: "api/me/progress/\(itemID)")
    } catch APIError.status(404) {
      return .init(currentTime: 0, duration: 0, isFinished: false, lastUpdate: 0)
    }
  }

  func coverData(itemID: String) async throws -> Data {
    try await authorizedData(path: "api/items/\(itemID)/cover?width=640&height=640&format=jpeg")
  }

  func mediaData(url: URL, range: String?) async throws -> AuthenticatedMediaResponse {
    guard let connection = try await vault.loadConnection(),
      let token = try await vault.loadTokens()?.accessToken,
      url.scheme == connection.server.scheme,
      url.host == connection.server.host
    else { throw AuthenticationError.missingCredentials }
    func request(_ accessToken: String) -> URLRequest {
      var request = URLRequest(url: url)
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      if let range { request.setValue(range, forHTTPHeaderField: "Range") }
      return request
    }
    do { return try await sendMedia(request(token)) } catch APIError.unauthorized {
      let replacement = try await recoverSession(connection: connection)
      return try await sendMedia(request(replacement.accessToken))
    }
  }

  func pushProgress(
    itemID: String, position: TimeInterval, duration: TimeInterval, isFinished: Bool
  ) async throws {
    let body = try JSONEncoder().encode(
      ProgressBody(currentTime: position, duration: duration, isFinished: isFinished))
    let _: EmptyResponse = try await authorized(
      path: "api/me/progress/\(itemID)", method: "PATCH", body: body)
  }

  func sync(
    sessionID: String, position: TimeInterval, duration: TimeInterval, timeListened: TimeInterval
  ) async throws {
    let body = try JSONEncoder().encode(
      SyncBody(currentTime: position, timeListened: timeListened, duration: duration))
    let _: EmptyResponse = try await authorized(
      path: "api/session/\(sessionID)/sync", method: "POST", body: body)
  }

  func close(
    sessionID: String, position: TimeInterval, duration: TimeInterval, timeListened: TimeInterval
  ) async throws {
    let body = try JSONEncoder().encode(
      SyncBody(currentTime: position, timeListened: timeListened, duration: duration))
    let _: EmptyResponse = try await authorized(
      path: "api/session/\(sessionID)/close", method: "POST", body: body)
  }

  func logout() async throws {
    guard let connection = try await vault.loadConnection(),
      let refresh = try await vault.loadTokens()?.refreshToken
    else { return }
    var request = URLRequest(url: connection.server.appending(path: "logout"))
    request.httpMethod = "POST"
    request.setValue(refresh, forHTTPHeaderField: "x-refresh-token")
    _ = try? await session.data(for: request)
  }

  private func authorized<T: Decodable>(path: String, method: String = "GET", body: Data? = nil)
    async throws -> T
  {
    guard let connection = try await vault.loadConnection(),
      let token = try await vault.loadTokens()?.accessToken
    else { throw AuthenticationError.missingCredentials }
    guard let url = URL(string: path, relativeTo: connection.server)?.absoluteURL else {
      throw URLError(.badURL)
    }
    func request(with accessToken: String) -> URLRequest {
      var request = URLRequest(url: url)
      request.httpMethod = method
      request.httpBody = body
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
      return request
    }
    do { return try await send(request(with: token)) } catch APIError.unauthorized {
      let replacement = try await recoverSession(connection: connection)
      return try await send(request(with: replacement.accessToken))
    }
  }

  private func authorizedData(path: String) async throws -> Data {
    guard let connection = try await vault.loadConnection(),
      let token = try await vault.loadTokens()?.accessToken,
      let url = URL(string: path, relativeTo: connection.server)?.absoluteURL
    else { throw AuthenticationError.missingCredentials }
    func request(_ accessToken: String) -> URLRequest {
      var request = URLRequest(url: url)
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      return request
    }
    do { return try await sendData(request(token)) } catch APIError.unauthorized {
      let replacement = try await recoverSession(connection: connection)
      return try await sendData(request(replacement.accessToken))
    }
  }

  private func recoverSession(connection: StoredCredentials) async throws -> AuthenticationTokens {
    if let sessionRecoveryTask { return try await sessionRecoveryTask.value }
    let task = Task { try await self.performSessionRecovery(connection: connection) }
    sessionRecoveryTask = task
    defer { sessionRecoveryTask = nil }
    return try await task.value
  }

  private func performSessionRecovery(connection: StoredCredentials) async throws
    -> AuthenticationTokens
  {
    if let refresh = try await vault.loadTokens()?.refreshToken {
      var request = URLRequest(url: connection.server.appending(path: "auth/refresh"))
      request.httpMethod = "POST"
      request.setValue(refresh, forHTTPHeaderField: "x-refresh-token")
      do {
        let data = try await sendData(request)
        let tokens = try AudiobookshelfTokenEnvelope.decode(data)
        try await vault.save(tokens: tokens)
        return tokens
      } catch APIError.unauthorized {
        try await vault.clearTokens()
      }
    }
    do {
      var request = URLRequest(url: connection.server.appending(path: "login"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("true", forHTTPHeaderField: "x-return-tokens")
      request.httpBody = try JSONEncoder().encode([
        "username": connection.username, "password": connection.password,
      ])
      let data = try await sendData(request)
      let tokens = try AudiobookshelfTokenEnvelope.decode(data)
      try await vault.save(tokens: tokens)
      return tokens
    } catch APIError.unauthorized {
      throw AudiobookshelfClientError.authenticationRequired
    }
  }

  private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
    let data = try await sendData(request)
    if T.self == EmptyResponse.self, data.isEmpty || data == Data("OK".utf8) {
      return EmptyResponse() as! T
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func sendData(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    if http.statusCode == 401 { throw APIError.unauthorized }
    guard 200..<300 ~= http.statusCode else { throw APIError.status(http.statusCode) }
    return data
  }

  private func sendMedia(_ request: URLRequest) async throws -> AuthenticatedMediaResponse {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    if http.statusCode == 401 { throw APIError.unauthorized }
    guard 200..<300 ~= http.statusCode else { throw APIError.status(http.statusCode) }
    return .init(
      data: data,
      statusCode: http.statusCode,
      expectedContentLength: http.expectedContentLength,
      mimeType: http.mimeType,
      contentRange: http.value(forHTTPHeaderField: "Content-Range"),
      acceptsRanges: http.value(forHTTPHeaderField: "Accept-Ranges") != nil
    )
  }
}

private enum APIError: Error {
  case unauthorized
  case status(Int)
  case invalidResponse
}
private struct ItemsResponse: Decodable { let results: [Item] }
private struct AllProgressResponse: Decodable {
  let mediaProgress: [Progress]
  struct Progress: Decodable {
    let libraryItemId: String?
    let lastUpdate: Int64
  }
}
private struct Item: Decodable {
  let id: String
  let media: Media
  let updatedAt: Int64?
  struct Media: Decodable {
    let metadata: Metadata
    let duration: Double?
  }
  struct Metadata: Decodable {
    let title: String?
    let authors: [Named]?
    let series: [Named]?
    let authorName: String?
    let seriesName: String?
  }
  struct Named: Decodable { let name: String }
}
private struct PlayResponse: Decodable {
  let id: String
  let currentTime: Double
  let duration: Double
  let chapters: [RemoteChapter]
  let audioTracks: [Track]
  struct RemoteChapter: Decodable {
    let title: String
    let start: Double
  }
  struct Track: Decodable { let contentUrl: String }
}
private struct ProgressBody: Encodable {
  let currentTime: Double
  let duration: Double
  let isFinished: Bool
}
private struct SyncBody: Encodable {
  let currentTime: Double
  let timeListened: Double
  let duration: Double
}
private struct EmptyResponse: Codable { init() {} }
