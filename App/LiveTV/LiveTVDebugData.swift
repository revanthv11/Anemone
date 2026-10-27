#if DEBUG
    import AnemoneJellyfin
    import Foundation

    /// A made-up guide for the server's own channels, for checking the guide when a server has
    /// channels but no listings, like the `-homeMockLiveTV` rows. Launch with
    /// `-liveTVMockGuide YES`. Recording needs real listings, so the server refuses these.
    enum LiveTVDebugData {
        static var isOn: Bool {
            UserDefaults.standard.bool(forKey: "liveTVMockGuide")
        }

        /// For each channel, programmes from a little before the guide to its end, of lengths that
        /// differ from channel to channel. The first channel has a series every third programme.
        static func programs(for channels: [LiveTVChannel], in guide: LiveTVGuide) -> [LiveTVProgram] {
            channels.enumerated().flatMap { index, channel in
                programs(channel: channel, index: index, guide: guide)
            }
        }

        private static let minutes = [30, 60, 15, 90, 45, 120, 30]
        private static let categories: [LiveTVProgram.Category?] = [nil, .news, .sports, .kids, .movie]

        private static func programs(channel: LiveTVChannel, index: Int, guide: LiveTVGuide) -> [LiveTVProgram] {
            var programs: [LiveTVProgram] = []
            var start = guide.start.addingTimeInterval(-15 * 60)
            var number = 0
            while start < guide.end {
                let isPatrol = index == 0 && number.isMultiple(of: 3)
                let length = isPatrol ? 30 : minutes[(number + index) % minutes.count]
                let end = start.addingTimeInterval(Double(length) * 60)
                var program = LiveTVProgram(
                    id: "mock-\(channel.id)-\(number)",
                    channelID: channel.id,
                    name: isPatrol ? "Pattern Patrol" : "\(channel.name) \(number + 1)",
                    start: start,
                    end: end,
                    episodeTitle: isPatrol ? "Patrol #\(number / 3 + 1)" : nil,
                    overview: "Made-up listings for checking the guide.",
                    seasonNumber: isPatrol ? 1 : nil,
                    episodeNumber: isPatrol ? number / 3 + 1 : nil,
                    category: categories[index % categories.count],
                    isSeries: isPatrol,
                )
                program.channelName = channel.name
                programs.append(program)
                start = end
                number += 1
            }
            return programs
        }
    }
#endif
