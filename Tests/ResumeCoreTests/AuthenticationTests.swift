import Foundation
import Testing
@testable import ResumeCore

@Suite("Authentication recovery")
struct AuthenticationTests {
    @Test("a rejected refresh rebuilds the session once with the saved password")
    func rebuildsExpiredSession() async throws {
        let gateway = AuthenticationGatewaySpy(
            refreshResult: .failure(AuthenticationError.rejected),
            loginResult: .success(.init(accessToken: "fresh-access", refreshToken: "fresh-refresh"))
        )
        let credentials = MemoryCredentialVault(
            credentials: .init(server: URL(string: "https://example.pikapod.net")!, username: "listener", password: "secret"),
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
            credentials: .init(server: URL(string: "https://example.pikapod.net")!, username: "listener", password: "secret"),
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

    init(refreshResult: Result<AuthenticationTokens, Error>, loginResult: Result<AuthenticationTokens, Error>) {
        self.refreshResult = refreshResult
        self.loginResult = loginResult
    }

    func refresh(server: URL, refreshToken: String) async throws -> AuthenticationTokens { try refreshResult.get() }
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
