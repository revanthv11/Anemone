import AnemoneCore
import Foundation
import JellyfinAPI

/// A playlist the user may change, offered by "Add to playlist".
public struct EditablePlaylist: Hashable, Identifiable, Sendable {
    public let id: MediaItem.ID
    public let name: String
    public let itemCount: Int
    /// Whether the playlist holds the item being added already. `false` also when that couldn't
    /// be checked, so the playlist is still offered, as Wholphin offers every one.
    public let holdsItem: Bool

    public init(id: MediaItem.ID, name: String, itemCount: Int, holdsItem: Bool = false) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
        self.holdsItem = holdsItem
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
    /// it offers to take it out instead. That check reads only the playlist's item IDs, not its
    /// entries, and a playlist whose check fails is offered as Wholphin offers it.
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
        let checked = await boundedMap(playlists.count, width: 6) { index in
            await attempt { try await editable(playlists[index], holding: itemID) }
        }
        return try checked.compactMap { result in
            if case let .failure(error) = result, error as? SessionError == .signedOut {
                throw SessionError.signedOut
            }
            // Any other failure was a check of whether the user may edit it, which leaves it out.
            return try? result.get()
        }
    }

    /// Adds an item to the end of a playlist. For a series, season or album the server adds what
    /// it holds.
    func addToPlaylist(_ playlistID: MediaItem.ID, itemID: MediaItem.ID) async throws {
        try await send(Paths.addItemToPlaylist(
            playlistID: playlistID,
            parameters: .init(ids: [itemID], userID: userID),
        ))
    }

    /// Takes an item out of a playlist. Only now are the playlist's entries read, to find the
    /// item's, since removing goes by entry.
    ///
    /// - Throws: `PlaylistEditingError.notInPlaylist` when no entry holds the item, such as when
    ///   it was taken out elsewhere since the playlist was checked.
    func removeFromPlaylist(_ playlistID: MediaItem.ID, itemID: MediaItem.ID) async throws {
        guard let entry = try await playlistEntry(for: itemID, in: playlistID) else {
            throw PlaylistEditingError.notInPlaylist
        }
        try await removeFromPlaylist(playlistID, entryID: entry)
    }

    /// Takes an entry out of a playlist.
    func removeFromPlaylist(_ playlistID: MediaItem.ID, entryID: String) async throws {
        try await send(Paths.removeItemFromPlaylist(playlistID: playlistID, entryIDs: [entryID]))
    }

    /// The playlist, saying whether it holds the item, or `nil` when the user may not edit it.
    private func editable(
        _ playlist: EditablePlaylist,
        holding itemID: MediaItem.ID,
    ) async throws -> EditablePlaylist? {
        guard try await canEditPlaylist(id: playlist.id) else { return nil }
        let holdsItem: Bool
        do {
            // Just the IDs of what it holds, however long it is.
            let ids = try await send(Paths.getPlaylist(playlistID: playlist.id)).itemIDs
            holdsItem = ids.contains { Self.isSameItem($0, itemID) }
        } catch SessionError.signedOut {
            throw SessionError.signedOut
        } catch {
            holdsItem = false
        }
        return EditablePlaylist(
            id: playlist.id,
            name: playlist.name,
            itemCount: playlist.itemCount,
            holdsItem: holdsItem,
        )
    }

    /// The item's entry in a playlist, or `nil` when it isn't in it.
    private func playlistEntry(for itemID: MediaItem.ID, in playlistID: MediaItem.ID) async throws -> String? {
        let parameters = Paths.GetPlaylistItemsParameters(userID: userID, enableImages: false, enableUserData: false)
        let entries = try await send(Paths.getPlaylistItems(playlistID: playlistID, parameters: parameters)).items
        // Wholphin removes by item ID, which servers that don't send entry IDs accept.
        return entries?
            .first { $0.id.map { Self.isSameItem($0, itemID) } ?? false }
            .map { $0.playlistItemID ?? $0.id ?? itemID }
    }

    /// Whether two IDs name the same item. The server may write an ID with or without dashes,
    /// and in either case, so membership and the entry lookup compare them alike.
    private static func isSameItem(_ id: String, _ other: String) -> Bool {
        JellyfinID.compact(id) == JellyfinID.compact(other)
    }
}

/// Why a playlist couldn't be changed, beyond a failed request.
public enum PlaylistEditingError: Error, Equatable {
    /// The item to take out isn't in the playlist.
    case notInPlaylist
}
