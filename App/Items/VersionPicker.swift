import AnemoneJellyfin
import SwiftUI

/// Wholphin's Version button and dialog (`PlayButtons` and `chooseVersionParams`): for an item
/// kept in several versions, which one plays. The choice is remembered for the item
/// (`MediaVersionChoices`), as Wholphin remembers it, so Play, Resume and Restart all use it,
/// and so does the item when a queue reaches it. Shows nothing for the usual item, with one.
///
/// The versions come with the item the page loaded (`ItemDetails.versions`), as Wholphin's
/// pages ask for media sources with the item, so the picker asks the server nothing itself.
struct VersionPicker: View {
    let itemID: MediaItem.ID
    let versions: [MediaVersion]

    @Environment(BrowseModel.self) private var browse
    /// The version that plays.
    @State private var chosenID: String?
    @State private var isChoosing = false

    init(item: ItemDetails) {
        itemID = item.id
        #if DEBUG
            versions = MediaVersion.withLaunchArgumentFakes(item.versions)
        #else
            versions = item.versions
        #endif
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
            if versions.count > 1 {
                ActionButton(title: String(localized: "Version"), systemImage: "square.stack") {
                    isChoosing = true
                }
                // "Version, 1080p": the one that plays.
                .accessibilityValue(versions.first { $0.id == chosenID }?.name ?? "")
                .accessibilityIdentifier("action.version")
            }
        }
        // Again when the page reloads the item, or the season page's focus moves to another
        // episode.
        .onChange(of: [itemID] + versions.map(\.id), initial: true) {
            refreshChoice()
        }
        .sheet(isPresented: $isChoosing) {
            VersionList(versions: versions, chosenID: chosenID, choose: choose)
        }
    }

    /// The version picked for the item, or the server's first. A version gone from the server is
    /// forgotten, so Play goes back to the first.
    private func refreshChoice() {
        let userID = browse.session.userID
        let choices = MediaVersionChoices.standard
        var chosen = choices.choice(for: itemID, userID: userID)
        if let current = chosen, !versions.isEmpty, !versions.contains(where: { $0.id == current }) {
            choices.forget(itemID, userID: userID)
            chosen = nil
        }
        chosenID = chosen ?? versions.first?.id
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
                                // The row says it's selected instead.
                                .accessibilityHidden(true)
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
                    name: String(localized: "\(first.name) (copy \(number))"),
                    bitrate: first.bitrate,
                    runtime: first.runtime,
                    video: first.video,
                )
            }
        }
    }
#endif
