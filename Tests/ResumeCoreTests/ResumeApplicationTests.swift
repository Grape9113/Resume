import Foundation
import Testing
@testable import ResumeCore

@Suite("Resume application")
struct ResumeApplicationTests {
    @Test("printable input starts Search without losing the first character")
    func printableInputStartsSearch() {
        var application = ResumeApplication(mode: .player)

        application.send(.typed("m"))

        #expect(application.mode == .search(query: "m"))
    }

    @Test("Space controls playback only in Player mode")
    func spaceHasModeSpecificMeaning() {
        var player = ResumeApplication(mode: .player)
        player.send(.space)
        #expect(player.playbackIntent == .playing)

        var search = ResumeApplication(mode: .search(query: "ranger"))
        search.send(.space)
        #expect(search.mode == .search(query: "ranger "))
        #expect(search.playbackIntent == .paused)
    }

    @Test("Book progress is whole-book and read-only")
    func bookProgressIsReadOnly() {
        var application = ResumeApplication(
            mode: .player,
            playback: .init(position: 3_600, duration: 14_400)
        )

        application.send(.progressPointerInteraction(proposedPosition: 7_200))

        #expect(application.playback.position == 3_600)
        #expect(application.bookProgress == 0.25)
    }

    @Test("chapter navigation deliberately changes position without autoplay")
    func chapterNavigationIsDeliberate() {
        var application = ResumeApplication(
            mode: .player,
            playback: .init(position: 120, duration: 7_200),
            chapters: [.init(id: "chapter-2", title: "Chapter 2", start: 900)]
        )

        application.send(.selectChapter(id: "chapter-2"))

        #expect(application.playback.position == 900)
        #expect(application.playbackIntent == .paused)
    }
}
