import Foundation

public struct AuthenticationTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct StoredCredentials: Codable, Equatable, Sendable {
    public let server: URL
    public let username: String
    public let password: String

    public init(server: URL, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }
}

public enum AuthenticationError: Error, Equatable, Sendable {
    case rejected
    case transport
    case missingCredentials
}

public protocol AuthenticationGateway: Sendable {
    func refresh(server: URL, refreshToken: String) async throws -> AuthenticationTokens
    func login(credentials: StoredCredentials) async throws -> AuthenticationTokens
}

public protocol CredentialVault: Sendable {
    func loadCredentials() async throws -> StoredCredentials?
    func loadTokens() async throws -> AuthenticationTokens?
    func save(tokens: AuthenticationTokens) async throws
    func clearTokens() async throws
}

public actor Authenticator {
    private let gateway: any AuthenticationGateway
    private let vault: any CredentialVault

    public init(gateway: any AuthenticationGateway, vault: any CredentialVault) {
        self.gateway = gateway
        self.vault = vault
    }

    public func validAccessToken(afterRejection: Bool) async throws -> String {
        guard let credentials = try await vault.loadCredentials() else {
            throw AuthenticationError.missingCredentials
        }
        guard afterRejection else {
            guard let token = try await vault.loadTokens()?.accessToken else {
                throw AuthenticationError.rejected
            }
            return token
        }

        if let refreshToken = try await vault.loadTokens()?.refreshToken {
            do {
                let refreshed = try await gateway.refresh(server: credentials.server, refreshToken: refreshToken)
                try await vault.save(tokens: refreshed)
                return refreshed.accessToken
            } catch AuthenticationError.transport {
                throw AuthenticationError.transport
            } catch {
                // A rejected refresh is the only condition that falls through to one password login.
            }
        }

        try await vault.clearTokens()
        let replacement = try await gateway.login(credentials: credentials)
        try await vault.save(tokens: replacement)
        return replacement.accessToken
    }
}
