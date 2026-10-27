import Foundation
import JellyfinAPI

/// A playlist the user may change, offered by "Add to playlist".
public struct EditablePlaylist: Hashable, Identifiable, Sendable {
    public let id: MediaItem.ID
    public let name: String
    public let itemCount: Int
    /// The entry of the item being added, when it's in the playlist already. Removing goes by
    /// entry.
    public let entryID: String?

    public init(id: MediaItem.ID, name: String, itemCount: Int, entryID: String? = nil) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
        self.entryID = entryID
    }
}

/// Adding to and removing from the server's playlists, ported from Wholphin's
/// `AddPlaylistViewModel` and the playlist half of its `PlaylistCreator`.
public extension JellyfinSession {
    /// The playlists the user may add `itemID` to, most recently added to first, each saying
    /// whether it holds the item already. Like Wholphin, looks at the 25 newest playlists and
    /// asks about each whether the user may edit it.
    ///
    /// Wholphin doesn't look inside, so the same item can go in twice; here a playlist holding
    /// it offers to take it out instead.
    func editablePlaylists(for itemID: MediaItem.ID, limit: Int = 25) async throws -> [EditablePlaylist] {
        let parameters = Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [.childCount],
            includeItemTypes: [.playlist],
            sortBy: [.dateLastContentAdded],
        )
        let found = try await send(Paths.getItems(parameters: parameters)).items ?? []
        let playlists = found.compactMap { dto in
            dto.id.map { EditablePlaylist(id: $0, name: dto.name ?? "", itemCount: dto.childCount ?? 0) }
        }
        let editable = try await withThrowingTaskGroup(of: EditablePlaylist?.self) { group in
            for playlist in playlists {
                group.addTask {
                    guard try await canEditPlaylist(id: playlist.id) else { return nil }
                    return try await EditablePlaylist(
                        id: playlist.id,
                        name: playlist.name,
                        itemCount: playlist.itemCount,
                        entryID: playlistEntry(for: itemID, in: playlist.id),
                    )
                }
            }
            return try await group.reduce(into: [MediaItem.ID: EditablePlaylist]()) { found, playlist in
                if let playlist {
                    found[playlist.id] = playlist
                }
            }
        }
        return playlists.compactMap { editable[$0.id] }
    }

    /// Adds an item to the end of a playlist. For a series, season or album the server adds what
    /// it holds.
    func addToPlaylist(_ playlistID: MediaItem.ID, itemID: MediaItem.ID) async throws {
        try await send(Paths.addItemToPlaylist(
            playlistID: playlistID,
            parameters: .init(ids: [itemID], userID: userID),
        ))
    }

    /// Takes an entry out of a playlist.
    func removeFromPlaylist(_ playlistID: MediaItem.ID, entryID: String) async throws {
        try await send(Paths.removeItemFromPlaylist(playlistID: playlistID, entryIDs: [entryID]))
    }

    /// The item's entry in a playlist, or `nil` when it isn't in it.
    private func playlistEntry(for itemID: MediaItem.ID, in playlistID: MediaItem.ID) async throws -> String? {
        let parameters = Paths.GetPlaylistItemsParameters(userID: userID, enableImages: false, enableUserData: false)
        let entries = try await send(Paths.getPlaylistItems(playlistID: playlistID, parameters: parameters)).items
        // Wholphin removes by item ID, which servers that don't send entry IDs accept.
        return entries?.first { $0.id == itemID }.map { $0.playlistItemID ?? itemID }
    }
}
