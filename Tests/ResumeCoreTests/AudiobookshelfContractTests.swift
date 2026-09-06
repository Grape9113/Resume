import Foundation
import Testing

@testable import ResumeCore

@Suite("Audiobookshelf response contracts")
struct AudiobookshelfContractTests {
  @Test("current login and refresh envelopes expose rotating tokens under user")
  func decodesTokenEnvelope() throws {
    let fixture = Data(
      #"{"success":true,"user":{"accessToken":"access-2","refreshToken":"refresh-2"}}"#.utf8)

    let tokens = try AudiobookshelfTokenEnvelope.decode(fixture)

    #expect(tokens == AuthenticationTokens(accessToken: "access-2", refreshToken: "refresh-2"))
  }
}
