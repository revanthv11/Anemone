import AnemoneJellyfin
import Foundation
import Testing

struct ItemDetailsTests {
    private func series(year: Int?, isContinuing: Bool?, ended: String? = nil) -> ItemDetails {
        ItemDetails(
            item: MediaItem(id: "s", name: "Show", kind: .series, year: year),
            endDate: ended.flatMap { try? Date($0, strategy: .iso8601) },
            isContinuing: isContinuing,
        )
    }

    @Test func `series years follow Wholphin`() {
        #expect(series(year: 2008, isContinuing: true).seriesYears == "2008 - Present")
        #expect(series(year: 2008, isContinuing: false, ended: "2013-09-29T00:00:00Z").seriesYears == "2008 - 2013")
        #expect(series(year: 2008, isContinuing: false, ended: "2008-12-01T00:00:00Z").seriesYears == "2008")
        #expect(series(year: 2008, isContinuing: false).seriesYears == "2008")
        #expect(series(year: 2008, isContinuing: nil).seriesYears == "2008")
        #expect(series(year: nil, isContinuing: true).seriesYears == nil)
    }

    @Test func `time remaining needs a resume position inside the runtime`() {
        var movie = ItemDetails(item: MediaItem(id: "m", name: "Film", kind: .movie, runtime: .seconds(600)))
        #expect(movie.timeRemaining == nil)

        movie.userState.resumePosition = .seconds(150)
        #expect(movie.timeRemaining == .seconds(450))

        movie.userState.resumePosition = .seconds(900)
        #expect(movie.timeRemaining == nil)
    }

    @Test func `finds seasons and episodes by id, then by number`() {
        let episodes = [1, 2, 4].map { (number: Int) in
            ItemDetails(item: MediaItem(
                id: "e\(number)",
                name: "Episode \(number)",
                kind: .episode,
                episode: .init(seriesID: "s", seriesName: "Show", seasonNumber: 1, episodeNumber: number),
            ))
        }

        #expect(episodes.index(ofID: "e4", number: 1) == 2)
        #expect(episodes.index(ofID: "gone", number: 2) == 1)
        // Episode 3 is missing, as in Wholphin's `findIndexByNumberOrId` example.
        #expect(episodes.index(ofID: nil, number: 3) == 0)
        #expect([ItemDetails]().index(ofID: "e1", number: 1) == 0)
    }

    @Test func `a person's age stops at their death`() throws {
        let born = try Date("1950-06-15T00:00:00Z", strategy: .iso8601)
        let now = try Date("2026-06-14T00:00:00Z", strategy: .iso8601)
        var person = ItemDetails(item: MediaItem(id: "p", name: "Someone", kind: .person), premiereDate: born)

        #expect(person.age(now: now) == 75)

        person.endDate = try Date("2001-06-15T00:00:00Z", strategy: .iso8601)
        #expect(person.age(now: now) == 51)

        person.premiereDate = nil
        #expect(person.age(now: now) == nil)
    }

    @Test func `a person's rows are skipped only when the server says they're empty`() {
        let counts = ItemDetails.CreditCounts(movies: 3, series: 0, episodes: nil)

        #expect(counts.mayHave(.movies))
        #expect(!counts.mayHave(.series))
        #expect(counts.mayHave(.episodes))
    }

    @Test func `collection rows drop types without a row`() {
        let items = [MediaItem.Kind.photo, .musicVideo, .movie].enumerated().map { index, kind in
            ItemDetails(item: MediaItem(id: "\(index)", name: "Item", kind: kind))
        }

        #expect(CollectionSection.sections(items).map(\.kind) == [.movie, .musicVideo])
    }
}
