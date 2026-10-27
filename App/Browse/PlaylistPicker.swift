import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's playlist dialog (`PlaylistDialog`): the playlists the user may change, newest
/// first. Choosing one adds the item; a playlist that already holds it has a check, and choosing
/// it takes the item out again.
struct PlaylistPicker: View {
    let item: MediaItem

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var playlists: [EditablePlaylist]?
    @State private var problem: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Add \(item.name) to a playlist")
                .font(.title2.bold())
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            if let problem {
                Text(problem)
                    .foregroundStyle(theme.secondaryText)
            }
            if let playlists {
                if playlists.isEmpty {
                    Text("You have no playlists you can change.")
                        .foregroundStyle(theme.secondaryText)
                        .focusable()
                }
                // A sheet takes its content's size, which a `List` doesn't have.
                ScrollView(.vertical) {
                    VStack(spacing: 16) {
                        ForEach(playlists) { playlist in
                            Button {
                                Task { await choose(playlist) }
                            } label: {
                                PlaylistLabel(playlist: playlist)
                            }
                            .disabled(isSaving)
                            .accessibilityValue(playlist.holdsItem ? "Has this item" : "")
                            .accessibilityIdentifier("playlist.\(playlist.id)")
                        }
                    }
                    .padding(.vertical, ItemLayout.focusPadding)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 600)
            } else if problem == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 1100, alignment: .topLeading)
        .padding(60)
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            playlists = try await browse.session.editablePlaylists(for: item.id)
        } catch {
            problem = browse.problem(with: error, doing: "load your playlists")
        }
    }

    private func choose(_ playlist: EditablePlaylist) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if playlist.holdsItem {
                try await browse.session.removeFromPlaylist(playlist.id, itemID: item.id)
            } else {
                try await browse.session.addToPlaylist(playlist.id, itemID: item.id)
            }
            dismiss()
        } catch PlaylistEditingError.notInPlaylist {
            // Taken out elsewhere since the list loaded: says so, and shows the playlists as
            // they are now.
            problem = "\(item.name) isn't in \(playlist.name.isEmpty ? "that playlist" : playlist.name) any more."
            await load()
        } catch {
            problem = browse.problem(with: error, doing: "change \(playlist.name)")
        }
    }
}

/// A playlist in the picker. Its check or plus is left to the button's value, "Has this item".
private struct PlaylistLabel: View {
    let playlist: EditablePlaylist

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: playlist.holdsItem ? "checkmark" : "plus")
                .frame(width: 40)
                .accessibilityHidden(true)
            Text(playlist.name.isEmpty ? "Untitled" : playlist.name)
            Spacer()
            Text(playlist.itemCount == 1 ? "1 item" : "\(playlist.itemCount) items")
                .foregroundStyle(.secondary)
        }
    }
}
