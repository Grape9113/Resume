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
    let streamURL: URL
}

struct ABSProgress: Decodable, Sendable {
    let currentTime: Double
    let duration: Double
    let isFinished: Bool
    let lastUpdate: Int64
}

actor AudiobookshelfClient {
    private let vault: KeychainStore
    private let session: URLSession

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
        let response: LoginResponse = try await send(request)
        let tokens = AuthenticationTokens(accessToken: response.user.accessToken, refreshToken: response.user.refreshToken)
        try await vault.save(connection: .init(server: server, username: username, password: password), tokens: tokens)
    }

    func accessToken() async -> String? { try? await vault.loadTokens()?.accessToken }

    func libraries() async throws -> [ABSLibrary] {
        try await authorized(path: "api/libraries")
    }

    func items(libraryID: String) async throws -> [Audiobook] {
        let response: ItemsResponse = try await authorized(path: "api/libraries/\(libraryID)/items?limit=0&minified=1")
        return response.results.map { item in
            Audiobook(
                id: item.id,
                title: item.media.metadata.title ?? "Untitled",
                authors: item.media.metadata.authors?.map(\.name) ?? [],
                series: item.media.metadata.series?.map(\.name) ?? [],
                lastPlayedAt: item.userMediaProgress.map { Date(timeIntervalSince1970: Double($0.lastUpdate) / 1000) },
                duration: item.media.duration ?? 0,
                coverRevision: String(item.updatedAt ?? 0)
            )
        }
    }

    func startPlayback(itemID: String) async throws -> PlaybackSession {
        let body: [String: Any] = [
            "deviceInfo": ["clientName": "Resume", "deviceId": Host.current().localizedName ?? "Mac"],
            "mediaPlayer": "avplayer",
            "supportedMimeTypes": ["audio/mpeg", "audio/mp4", "audio/aac", "application/vnd.apple.mpegurl"],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let response: PlayResponse = try await authorized(path: "api/items/\(itemID)/play", method: "POST", body: data)
        guard let connection = try await vault.loadConnection(),
              let path = response.audioTracks.first?.contentUrl,
              let streamURL = URL(string: path, relativeTo: connection.server)?.absoluteURL else { throw URLError(.badServerResponse) }
        return PlaybackSession(
            id: response.id,
            currentTime: response.currentTime,
            duration: response.duration,
            chapters: response.chapters.enumerated().map { .init(id: String($0.offset), title: $0.element.title, start: $0.element.start) },
            streamURL: streamURL
        )
    }

    func progress(itemID: String) async throws -> ABSProgress {
        try await authorized(path: "api/me/progress/\(itemID)")
    }

    func pushProgress(itemID: String, position: TimeInterval, duration: TimeInterval, isFinished: Bool) async throws {
        let body = try JSONEncoder().encode(ProgressBody(currentTime: position, duration: duration, isFinished: isFinished))
        let _: EmptyResponse = try await authorized(path: "api/me/progress/\(itemID)", method: "PATCH", body: body)
    }

    func sync(sessionID: String, position: TimeInterval, duration: TimeInterval, timeListened: TimeInterval) async throws {
        let body = try JSONEncoder().encode(SyncBody(currentTime: position, timeListened: timeListened, duration: duration))
        let _: EmptyResponse = try await authorized(path: "api/session/\(sessionID)/sync", method: "POST", body: body)
    }

    func logout() async throws {
        guard let connection = try await vault.loadConnection(), let refresh = try await vault.loadTokens()?.refreshToken else { return }
        var request = URLRequest(url: connection.server.appending(path: "logout"))
        request.httpMethod = "POST"
        request.setValue(refresh, forHTTPHeaderField: "x-refresh-token")
        _ = try? await session.data(for: request)
    }

    private func authorized<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let connection = try await vault.loadConnection(), let token = try await vault.loadTokens()?.accessToken else { throw AuthenticationError.missingCredentials }
        guard let url = URL(string: path, relativeTo: connection.server)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.userAuthenticationRequired) }
        if T.self == EmptyResponse.self, data.isEmpty || data == Data("OK".utf8) { return EmptyResponse() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct LoginResponse: Decodable { let user: User; struct User: Decodable { let accessToken: String; let refreshToken: String } }
private struct ItemsResponse: Decodable { let results: [Item] }
private struct Item: Decodable {
    let id: String; let media: Media; let updatedAt: Int64?; let userMediaProgress: Progress?
    struct Media: Decodable { let metadata: Metadata; let duration: Double? }
    struct Metadata: Decodable { let title: String?; let authors: [Named]?; let series: [Named]? }
    struct Named: Decodable { let name: String }
    struct Progress: Decodable { let lastUpdate: Int64 }
}
private struct PlayResponse: Decodable {
    let id: String; let currentTime: Double; let duration: Double; let chapters: [RemoteChapter]; let audioTracks: [Track]
    struct RemoteChapter: Decodable { let title: String; let start: Double }
    struct Track: Decodable { let contentUrl: String }
}
private struct ProgressBody: Encodable { let currentTime: Double; let duration: Double; let isFinished: Bool }
private struct SyncBody: Encodable { let currentTime: Double; let timeListened: Double; let duration: Double }
private struct EmptyResponse: Codable { init() {} }
