#if DEBUG
    import AnemoneJellyfin
    import Foundation

    /// Made-up segments for trying segment skipping on a server without any, such as the demo
    /// server. Debug builds only.
    ///
    /// Launching with `-fakeSegments "intro:5-20,outro:60-75"` gives every item played those
    /// segments, in seconds, in place of the server's. Launch arguments such as
    /// `-skipIntros autoSkip` set the behaviour for that run without changing the saved setting.
    extension MediaSegment {
        static var launchArgumentFakes: [MediaSegment]? {
            UserDefaults.standard.string(forKey: "fakeSegments").flatMap(fakes)
        }

        /// `nil` unless every part of `description` is a kind and a range of whole seconds.
        static func fakes(_ description: String) -> [MediaSegment]? {
            let segments = description.split(separator: ",").map { part -> MediaSegment? in
                let fields = part.trimmingCharacters(in: .whitespaces).split(separator: ":")
                guard fields.count == 2, let kind = Kind(rawValue: String(fields[0])) else { return nil }
                let range = fields[1].split(separator: "-").compactMap { Int($0) }
                guard range.count == 2, range[0] >= 0, range[1] > range[0] else { return nil }
                return MediaSegment(
                    id: "fake-\(kind.rawValue)-\(range[0])",
                    kind: kind,
                    start: .seconds(range[0]),
                    end: .seconds(range[1]),
                )
            }
            guard !segments.isEmpty, !segments.contains(nil) else { return nil }
            return segments.compactMap(\.self).sorted { $0.start < $1.start }
        }
    }
#endif
