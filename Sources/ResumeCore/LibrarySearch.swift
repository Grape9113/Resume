import Foundation

public struct Audiobook: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var title: String
  public var authors: [String]
  public var series: [String]
  public var lastPlayedAt: Date?
  public var duration: TimeInterval
  public var coverRevision: String?
  public var chapters: [Chapter]

  private enum CodingKeys: String, CodingKey {
    case id, title, authors, series, lastPlayedAt, duration, coverRevision, chapters
  }

  public init(
    id: String,
    title: String,
    authors: [String],
    series: [String],
    lastPlayedAt: Date?,
    duration: TimeInterval = 0,
    coverRevision: String? = nil,
    chapters: [Chapter] = []
  ) {
    self.id = id
    self.title = title
    self.authors = authors
    self.series = series
    self.lastPlayedAt = lastPlayedAt
    self.duration = duration
    self.coverRevision = coverRevision
    self.chapters = chapters
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
    series = try container.decodeIfPresent([String].self, forKey: .series) ?? []
    lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
    coverRevision = try container.decodeIfPresent(String.self, forKey: .coverRevision)
    chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
  }
}

public enum LibrarySearch {
  public static func bestMatch(for rawQuery: String, in books: [Audiobook]) -> Audiobook? {
    let query = normalize(rawQuery)
    guard query.count >= 2 else { return nil }

    let ranked = books.compactMap { book -> (Audiobook, Double)? in
      let title = normalize(book.title)
      let authors = book.authors.map(normalize)
      let series = book.series.map(normalize)
      let score = max(
        relevance(query, title) * 1.15,
        authors.map { relevance(query, $0) }.max() ?? 0,
        series.map { relevance(query, $0) }.max() ?? 0
      )
      return score >= 0.48 ? (book, score) : nil
    }

    return ranked.max { lhs, rhs in
      if abs(lhs.1 - rhs.1) > 0.02 { return lhs.1 < rhs.1 }
      return (lhs.0.lastPlayedAt ?? .distantPast) < (rhs.0.lastPlayedAt ?? .distantPast)
    }?.0
  }

  static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current
    )
    .unicodeScalars
    .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
    .joined()
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")
  }

  private static func relevance(_ query: String, _ candidate: String) -> Double {
    if query == candidate { return 1 }
    if candidate.hasPrefix(query) { return 0.95 }
    if candidate.contains(query) { return 0.88 }

    let queryTokens = query.split(separator: " ").map(String.init)
    let candidateTokens = candidate.split(separator: " ").map(String.init)
    guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

    let tokenScores = queryTokens.map { queryToken in
      candidateTokens.map { candidateToken in
        if candidateToken.hasPrefix(queryToken) { return 1.0 }
        let distance = editDistance(queryToken, candidateToken)
        return max(0, 1 - Double(distance) / Double(max(queryToken.count, candidateToken.count)))
      }.max() ?? 0
    }
    return tokenScores.reduce(0, +) / Double(tokenScores.count)
  }

  private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs)
    let b = Array(rhs)
    var previous = Array(0...b.count)
    for (i, left) in a.enumerated() {
      var current = [i + 1]
      for (j, right) in b.enumerated() {
        current.append(
          min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
      }
      previous = current
    }
    return previous[b.count]
  }
}
