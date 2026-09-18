import Foundation
import Synchronization
import Testing

@testable import ResumeCore

@Suite("Authentication recovery")
struct AuthenticationTests {
  @Test("a copied PikaPods hostname becomes a secure server address")
  func normalizesCopiedPikaPodsAddress() {
    #expect(
      ServerAddress.normalized("  quixotic-platypus.pikapod.net  ")
        == URL(string: "https://quixotic-platypus.pikapod.net")
    )
  }

  @Test("an existing secure server address keeps its hostname")
  func preservesSecureServerAddress() {
    #expect(
      ServerAddress.normalized("https://quixotic-platypus.pikapod.net/")
        == URL(string: "https://quixotic-platypus.pikapod.net")
    )
  }

  @Test("an accidental www prefix is removed from a PikaPods hostname")
  func removesPikaPodsWWWPrefix() {
    #expect(
      ServerAddress.normalized("https://www.quixotic-platypus.pikapod.net")
        == URL(string: "https://quixotic-platypus.pikapod.net")
    )
  }

  @Test("a rejected refresh rebuilds the session once with the saved password")
  func rebuildsExpiredSession() async throws {
    let gateway = AuthenticationGatewaySpy(
      refreshResult: .failure(AuthenticationError.rejected),
      loginResult: .success(.init(accessToken: "fresh-access", refreshToken: "fresh-refresh"))
    )
    let credentials = MemoryCredentialVault(
      credentials: .init(
        server: URL(string: "https://example.pikapod.net")!, username: "listener",
        password: "secret"),
      tokens: .init(accessToken: "old-access", refreshToken: "old-refresh")
    )
    let authenticator = Authenticator(gateway: gateway, vault: credentials)

    let token = try await authenticator.validAccessToken(afterRejection: true)

    #expect(token == "fresh-access")
    #expect(await gateway.loginCount == 1)
    #expect(await credentials.tokens?.refreshToken == "fresh-refresh")
  }

  @Test("transport failure never triggers password login")
  func networkFailureDoesNotChurnSession() async {
    let gateway = AuthenticationGatewaySpy(
      refreshResult: .failure(AuthenticationError.transport),
      loginResult: .failure(AuthenticationError.rejected)
    )
    let credentials = MemoryCredentialVault(
      credentials: .init(
        server: URL(string: "https://example.pikapod.net")!, username: "listener",
        password: "secret"),
      tokens: .init(accessToken: "old", refreshToken: "refresh")
    )
    let authenticator = Authenticator(gateway: gateway, vault: credentials)

    await #expect(throws: AuthenticationError.transport) {
      try await authenticator.validAccessToken(afterRejection: true)
    }
    #expect(await gateway.loginCount == 0)
  }
}

private actor AuthenticationGatewaySpy: AuthenticationGateway {
  var loginCount = 0
  let refreshResult: Result<AuthenticationTokens, Error>
  let loginResult: Result<AuthenticationTokens, Error>

  init(
    refreshResult: Result<AuthenticationTokens, Error>,
    loginResult: Result<AuthenticationTokens, Error>
  ) {
    self.refreshResult = refreshResult
    self.loginResult = loginResult
  }

  func refresh(server: URL, refreshToken: String) async throws -> AuthenticationTokens {
    try refreshResult.get()
  }
  func login(credentials: StoredCredentials) async throws -> AuthenticationTokens {
    loginCount += 1
    return try loginResult.get()
  }
}

private actor MemoryCredentialVault: CredentialVault {
  var credentials: StoredCredentials?
  var tokens: AuthenticationTokens?

  init(credentials: StoredCredentials?, tokens: AuthenticationTokens?) {
    self.credentials = credentials
    self.tokens = tokens
  }

  func loadCredentials() async throws -> StoredCredentials? { credentials }
  func loadTokens() async throws -> AuthenticationTokens? { tokens }
  func save(tokens: AuthenticationTokens) async throws { self.tokens = tokens }
  func clearTokens() async throws { tokens = nil }
}

@Suite("Shipped Audiobookshelf authentication")
struct AudiobookshelfClientAuthenticationTests {
  @Test(
    "a rejected saved password continues to request inline authentication without retrying login")
  func rejectedPasswordRemainsAuthenticationRequired() async {
    let scenario = RejectedAuthHTTPScenario()
    let host = UUID().uuidString.lowercased() + ".test"
    HTTPFixture.routes.withLock { $0[host] = { request in await scenario.respond(request) } }
    defer { _ = HTTPFixture.routes.withLock { $0.removeValue(forKey: host) } }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HTTPFixture.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let vault = TestConnectionStore()
    await vault.save(
      connection: .init(
        server: URL(string: "https://\(host)")!, username: "fixture", password: "fixture"),
      tokens: .init(accessToken: "old", refreshToken: "refresh"))
    let client = AudiobookshelfClient(vault: vault, session: session)
    for _ in 0..<2 {
      do {
        _ = try await client.libraries()
        Issue.record("Rejected password must require authentication")
      } catch AudiobookshelfClientError.authenticationRequired {
      } catch { Issue.record("Wrong recovery state: \(error)") }
    }
    #expect(await scenario.loginCount == 1)
    #expect(await vault.tokens == nil)
  }

  @Test("late concurrent access rejection reuses rotated tokens instead of refreshing twice")
  func lateRejectionUsesRotatedTokens() async throws {
    let scenario = AuthenticationHTTPScenario()
    let host = UUID().uuidString.lowercased() + ".test"
    HTTPFixture.routes.withLock { $0[host] = { request in await scenario.respond(request) } }
    defer { _ = HTTPFixture.routes.withLock { $0.removeValue(forKey: host) } }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HTTPFixture.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let vault = TestConnectionStore()
    await vault.save(
      connection: .init(
        server: URL(string: "https://\(host)")!, username: "fixture", password: "fixture"),
      tokens: .init(accessToken: "old", refreshToken: "refresh"))
    let client = AudiobookshelfClient(vault: vault, session: session)
    async let first = client.libraries()
    async let second = client.libraries()
    let results = try await (first, second)
    #expect(results.0.isEmpty && results.1.isEmpty)
    #expect(await scenario.refreshCount == 1)
    #expect(await vault.tokens?.accessToken == "new")
  }
}

private actor AuthenticationHTTPScenario {
  var refreshCount = 0
  var oldRequests = 0
  var freshServed = false
  var waitingForFresh: CheckedContinuation<Void, Never>?
  func respond(_ request: URLRequest) async -> (Int, Data) {
    if request.url?.path == "/auth/refresh" {
      refreshCount += 1
      return (200, Data(#"{"user":{"accessToken":"new","refreshToken":"rotated"}}"#.utf8))
    }
    if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
      oldRequests += 1
      if oldRequests > 1, !freshServed {
        await withCheckedContinuation { waitingForFresh = $0 }
      }
      return (401, Data())
    }
    freshServed = true
    waitingForFresh?.resume()
    waitingForFresh = nil
    return (200, Data(#"{"libraries":[]}"#.utf8))
  }
}

final class HTTPFixture: URLProtocol, @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) async -> (Int, Data)
  static let routes = Mutex<[String: Handler]>([:])
  private var responseTask: Task<Void, Never>?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let handler = Self.routes.withLock { $0[request.url!.host!] }
    responseTask = Task {
      guard let handler else {
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        return
      }
      let (status, data) = await handler(request)
      guard !Task.isCancelled else { return }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { responseTask?.cancel() }
}

private actor RejectedAuthHTTPScenario {
  var loginCount = 0
  func respond(_ request: URLRequest) -> (Int, Data) {
    if request.url?.path == "/login" { loginCount += 1 }
    return (401, Data())
  }
}
