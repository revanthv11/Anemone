import AnemoneJellyfin
import SwiftUI

/// Wholphin's Version button and dialog (`PlayButtons` and `chooseVersionParams`): for an item
/// kept in several versions, which one plays. The choice is remembered for the item
/// (`MediaVersionChoices`), as Wholphin remembers it, so Play, Resume and Restart all use it,
/// and so does the item when a queue reaches it. Shows nothing for the usual item, with one.
struct VersionPicker: View {
    let itemID: MediaItem.ID

    @Environment(BrowseModel.self) private var browse
    @State private var versions: [MediaVersion] = []
    /// The version that plays.
    @State private var chosenID: String?
    @State private var isChoosing = false

    var body: some View {
        // A container that stays put, so the task isn't restarted when the button appears.
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
            if versions.count > 1 {
                ActionButton(title: "Version", systemImage: "square.stack") {
                    isChoosing = true
                }
                .accessibilityIdentifier("action.version")
            }
        }
        .task(id: itemID) {
            await load()
        }
        .sheet(isPresented: $isChoosing) {
            VersionList(versions: versions, chosenID: chosenID, choose: choose)
        }
    }

    private func load() async {
        versions = []
        // The season page moves from episode to episode as focus does; only ask about the one
        // focus stays on.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let session = browse.session
        let id = itemID
        // Without versions, the button stays hidden and the first plays.
        guard let fetched = await browse.optional(attempt { try await session.mediaVersions(of: id) }),
              !Task.isCancelled
        else { return }
        #if DEBUG
            let loaded = MediaVersion.withLaunchArgumentFakes(fetched)
        #else
            let loaded = fetched
        #endif
        let choices = MediaVersionChoices.standard
        var chosen = choices.choice(for: id, userID: session.userID)
        // A version gone from the server is forgotten, so Play goes back to the first.
        if let current = chosen, !loaded.isEmpty, !loaded.contains(where: { $0.id == current }) {
            choices.forget(id, userID: session.userID)
            chosen = nil
        }
        versions = loaded
        chosenID = chosen ?? loaded.first?.id
    }

    private func choose(_ version: MediaVersion) {
        MediaVersionChoices.standard.choose(version.id, for: itemID, userID: browse.session.userID)
        chosenID = version.id
        isChoosing = false
    }
}

/// Wholphin's "Choose Version" dialog: each version's name, its video and bitrate, and length,
/// with a check by the one that plays.
private struct VersionList: View {
    let versions: [MediaVersion]
    let chosenID: String?
    let choose: (MediaVersion) -> Void

    var body: some View {
        NavigationStack {
            List(versions) { version in
                Button {
                    choose(version)
                } label: {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(version.name)
                            if let details = version.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if version.id == chosenID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("version.\(version.id)")
                .accessibilityAddTraits(version.id == chosenID ? .isSelected : [])
            }
            .navigationTitle("Choose Version")
        }
    }
}

private extension MediaVersion {
    /// Like Wholphin's line under each version: "1080p H264 SDR · 8.5 Mbps · 1h 52m".
    var details: String? {
        let parts = [
            video?.title,
            bitrate.map(\.bitrateText),
            runtime.flatMap { $0 > .zero ? $0.roundedToMinutes.lengthText : nil },
        ]
        let text = parts.compactMap(\.self).joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

#if DEBUG
    extension MediaVersion {
        /// Launching with `-fakeVersions <n>` gives every item at least n versions, copies of its
        /// first, for trying the picker on a server without any. Debug builds only. The server
        /// doesn't know the copies, so playing one plays the first instead and forgets the pick,
        /// as for a version gone from the server.
        static func withLaunchArgumentFakes(_ versions: [MediaVersion]) -> [MediaVersion] {
            let count = UserDefaults.standard.integer(forKey: "fakeVersions")
            guard let first = versions.first, count > versions.count else { return versions }
            return versions + (versions.count + 1 ... count).map { number in
                MediaVersion(
                    id: "\(first.id)-fake\(number)",
                    name: "\(first.name) (copy \(number))",
                    bitrate: first.bitrate,
                    runtime: first.runtime,
                    video: first.video,
                )
            }
        }
    }
#endif
