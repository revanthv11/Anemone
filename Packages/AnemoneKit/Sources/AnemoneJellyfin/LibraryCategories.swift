import Foundation
import JellyfinAPI

/// What a library's Genres and Studios tabs list, from Wholphin's `GenreCardGrid` and
/// `StudioCardGrid`. Genres and studios come as entries like a grid's titles, so they page,
/// focus and jump the same way.
public extension JellyfinSession {
    /// The genres of the library's titles, A to Z, for its Genres tab.
    func libraryGenres(in library: Library) async throws -> [LibraryEntry] {
        var parameters = Paths.GetGenresParameters(parentID: library.id, userID: userID)
        parameters.includeItemTypes = library.gridItemTypes
        parameters.fields = [.sortName]
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
        return try await send(Paths.getGenres(parameters: parameters)).items.categoryEntries
    }

    /// The studios and networks behind the library's titles, A to Z, for a TV library's Studios
    /// tab. Each has its own thumb image when the server has one.
    func libraryStudios(in library: Library) async throws -> [LibraryEntry] {
        var parameters = Paths.GetStudiosParameters(parentID: library.id, userID: userID)
        parameters.includeItemTypes = library.gridItemTypes
        parameters.fields = [.sortName]
        return try await send(Paths.getStudios(parameters: parameters)).items.categoryEntries
    }

    /// Artwork for genre cards, as Wholphin picks it: the backdrop of a random title in each
    /// genre, asked for four genres at a time. Genres with no title that has a backdrop, or
    /// whose request fails, are left out.
    func genreBackdrops(for genreIDs: [String], in library: Library) async -> [String: ItemImage] {
        await withTaskGroup(of: (String, ItemImage?).self) { group in
            var pending = genreIDs.dropFirst(4)
            for id in genreIDs.prefix(4) {
                group.addTask { await (id, try? genreBackdrop(id, in: library)) }
            }
            var images: [String: ItemImage] = [:]
            for await (id, image) in group {
                images[id] = image
                if let id = pending.popFirst() {
                    group.addTask { await (id, try? genreBackdrop(id, in: library)) }
                }
            }
            return images
        }
    }

    private func genreBackdrop(_ genreID: String, in library: Library) async throws -> ItemImage? {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = library.id
        parameters.includeItemTypes = library.gridItemTypes
        parameters.isRecursive = true
        parameters.genreIDs = [genreID]
        parameters.imageTypes = [.backdrop]
        parameters.imageTypeLimit = 1
        parameters.sortBy = [.random]
        parameters.limit = 1
        parameters.enableUserData = false
        parameters.enableTotalRecordCount = false
        let item = try await send(Paths.getItems(parameters: parameters)).items?.first
        return ItemImage(itemID: item?.id, kind: .backdrop, tag: item?.backdropImageTags?.first)
    }
}

private extension [BaseItemDto]? {
    var categoryEntries: [LibraryEntry] {
        (self ?? []).compactMap(LibraryEntry.init)
    }
}
