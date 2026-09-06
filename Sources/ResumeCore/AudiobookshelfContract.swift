import Foundation

public struct AudiobookshelfTokenEnvelope: Decodable, Sendable {
  private let user: User

  private struct User: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
  }

  public static func decode(_ data: Data) throws -> AuthenticationTokens {
    let envelope = try JSONDecoder().decode(Self.self, from: data)
    return AuthenticationTokens(
      accessToken: envelope.user.accessToken,
      refreshToken: envelope.user.refreshToken)
  }
}
