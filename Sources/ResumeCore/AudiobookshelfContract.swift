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

public struct AudiobookshelfLibrary: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let mediaType: String

  public init(id: String, name: String, mediaType: String) {
    self.id = id
    self.name = name
    self.mediaType = mediaType
  }
}

public struct AudiobookshelfLibrariesEnvelope: Decodable, Sendable {
  private let libraries: [AudiobookshelfLibrary]

  public static func decode(_ data: Data) throws -> [AudiobookshelfLibrary] {
    try JSONDecoder().decode(Self.self, from: data).libraries
  }
}
