import Foundation
import Testing

@testable import ResumeCore

@Suite("Library Search")
struct LibrarySearchTests {
  @Test("cached audiobook metadata from before chapter caching remains readable")
  func decodesCacheWithoutChapters() throws {
    let data = Data(
      #"{"id":"book","title":"Title","authors":[],"series":[],"duration":100}"#.utf8)

    let book = try JSONDecoder().decode(Audiobook.self, from: data)

    #expect(book.chapters.isEmpty)
  }

  private let books = [
    Audiobook(
      id: "rangers", title: "Ranger's Apprentice", authors: ["John Flanagan"],
      series: ["Ranger's Apprentice"], lastPlayedAt: nil),
    Audiobook(
      id: "hobbit", title: "The Hobbit", authors: ["J. R. R. Tolkien"], series: ["Middle-earth"],
      lastPlayedAt: Date(timeIntervalSince1970: 200)),
    Audiobook(
      id: "history", title: "A History of Denmark", authors: ["Knud J. V. Jespersen"], series: [],
      lastPlayedAt: Date(timeIntervalSince1970: 300)),
  ]

  @Test("misspelled author identifies the obvious audiobook")
  func misspelledAuthor() {
    #expect(LibrarySearch.bestMatch(for: "Jon Flanagan", in: books)?.id == "rangers")
  }

  @Test("incomplete normalized title identifies the obvious audiobook")
  func incompleteTitle() {
    #expect(LibrarySearch.bestMatch(for: "ranger appren", in: books)?.id == "rangers")
  }

  @Test("weak query does not invent a result")
  func weakQuery() {
    #expect(LibrarySearch.bestMatch(for: "zxqv", in: books) == nil)
  }

  @Test("recency breaks a textual tie rather than defeating relevance")
  func recencyOnlyBreaksTies() {
    let similar = [
      Audiobook(
        id: "old", title: "Dune", authors: ["Frank Herbert"], series: [],
        lastPlayedAt: Date(timeIntervalSince1970: 100)),
      Audiobook(
        id: "new", title: "Dune", authors: ["Frank Herbert"], series: [],
        lastPlayedAt: Date(timeIntervalSince1970: 200)),
    ]

    #expect(LibrarySearch.bestMatch(for: "dune", in: similar)?.id == "new")
    #expect(LibrarySearch.bestMatch(for: "hobbit", in: books)?.id == "hobbit")
  }
}
