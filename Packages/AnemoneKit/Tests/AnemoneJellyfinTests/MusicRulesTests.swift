import AnemoneJellyfin
import Testing

/// The music rules ported from Wholphin: card subtitles, the AC3 choice, and sorts.
struct MusicRulesTests {
    // MARK: Album subtitles, ported from upstream 90a2d6d's BaseItemSubtitleTest

    @Test func `an album shows its album artist and year`() {
        #expect(MusicItem.albumSubtitle(albumArtist: "Album Artist", artists: ["A"], year: 2021)
            == "Album Artist - 2021")
    }

    @Test func `an album without an album artist shows its artists and year`() {
        #expect(MusicItem.albumSubtitle(albumArtist: nil, artists: ["A", "B"], year: 2021) == "A, B - 2021")
        #expect(MusicItem.albumSubtitle(albumArtist: " ", artists: ["A", "B"], year: 2021) == "A, B - 2021")
    }

    @Test func `an album without a year shows just its artist`() {
        #expect(MusicItem.albumSubtitle(albumArtist: "Album Artist", artists: [], year: nil) == "Album Artist")
    }

    @Test func `an album without an artist shows just its year, and with neither nothing`() {
        #expect(MusicItem.albumSubtitle(albumArtist: nil, artists: [], year: 2021) == "2021")
        #expect(MusicItem.albumSubtitle(albumArtist: nil, artists: [], year: nil) == nil)
    }

    // MARK: The AC3 choice, with Wholphin's missing && put back

    @Test func `only surround audio that isn't AC3 already takes the AC3 transcode`() {
        let stereo = AudioStreamInfo(codec: "flac", channels: 2)
        let surround = AudioStreamInfo(codec: "flac", channels: 6)
        let ac3 = AudioStreamInfo(codec: "AC3", channels: 6)

        #expect(MusicItem.needsAC3Transcode([surround], prefersAC3Surround: true))
        // Wholphin's check sent this one to the transcode too.
        #expect(!MusicItem.needsAC3Transcode([stereo], prefersAC3Surround: true))
        #expect(!MusicItem.needsAC3Transcode([ac3], prefersAC3Surround: true))
        #expect(!MusicItem.needsAC3Transcode([AudioStreamInfo(codec: "mp3", channels: nil)], prefersAC3Surround: true))
        #expect(!MusicItem.needsAC3Transcode([surround], prefersAC3Surround: false))
    }

    @Test func `an album's songs name each artist when several artists sing on it`() {
        var album = MusicItem(details: ItemDetails(item: MediaItem(id: "al1", name: "Album", kind: .musicAlbum)))
        album.artists = ["Solo"]
        #expect(!album.isVariousArtists)
        album.artists = ["A", "B"]
        #expect(album.isVariousArtists)
        album.artists = ["Solo"]
        album.albumArtist = "Various Artists"
        #expect(album.isVariousArtists)
    }

    @Test func `picking the current sort again reverses it`() {
        let sort = MusicSort(.album)
        #expect(sort.choosing(.album) == MusicSort(.album, .descending))
        #expect(sort.choosing(.artist) == MusicSort(.artist))
    }
}
