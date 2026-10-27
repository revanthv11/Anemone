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
        // 3.3.0's parameters have no sort, so this relies on the server's default order, which is
        // by sort name; the tab's alphabet bar assumes A to Z.
        var parameters = Paths.GetStudiosParameters(parentID: library.id, userID: userID)
        parameters.includeItemTypes = library.gridItemTypes
        parameters.fields = [.sortName]
        return try await send(Paths.getStudios(parameters: parameters)).items.categoryEntries
    }

    /// Artwork for genre cards, as Wholphin picks it: the backdrop of a random title in each
    /// genre, asked for four genres at a time. Genres with no title that has a backdrop, or
    /// whose request fails, are left out. Once the task is cancelled, no more are asked for.
    ///
    /// - Throws: `SessionError.signedOut` from any genre's request, which stops the rest.
    func genreBackdrops(for genreIDs: [String], in library: Library) async throws -> GenreBackdrops {
        try await withThrowingTaskGroup(of: GenreBackdropAnswer.self) { group in
            var pending = genreIDs.dropFirst(4)
            for id in genreIDs.prefix(4) {
                _ = group.addTaskUnlessCancelled { try await genreBackdropAnswer(id, in: library) }
            }
            var images: [String: ItemImage] = [:]
            var failed = false
            for try await answer in group {
                images[answer.genreID] = answer.image
                failed = failed || answer.failed
                if let id = pending.popFirst() {
                    _ = group.addTaskUnlessCancelled { try await genreBackdropAnswer(id, in: library) }
                }
            }
            return GenreBackdrops(images: images, isComplete: !failed && pending.isEmpty && !Task.isCancelled)
        }
    }

    /// One genre's artwork, or that its request failed. A revoked token is thrown instead, so it
    /// reaches the page rather than only leaving the cards plain.
    private func genreBackdropAnswer(_ genreID: String, in library: Library) async throws -> GenreBackdropAnswer {
        do {
            return try await GenreBackdropAnswer(genreID: genreID, image: genreBackdrop(genreID, in: library))
        } catch SessionError.signedOut {
            throw SessionError.signedOut
        } catch {
            return GenreBackdropAnswer(genreID: genreID, image: nil, failed: true)
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

/// Genre cards' artwork, from `JellyfinSession.genreBackdrops(for:in:)`.
public struct GenreBackdrops: Hashable, Sendable {
    /// Each genre's picture. Genres with no title that has a backdrop have none, and neither do
    /// those whose request failed or was never sent.
    public let images: [String: ItemImage]
    /// Whether every genre's request was sent and answered, so the result is worth keeping.
    /// False when one failed or the task was cancelled part way, as when the tab is left while
    /// the artwork loads; keeping that would leave those cards plain until it expired.
    public let isComplete: Bool
}

/// One genre's request for its artwork: the picture, if there is one, or that it failed.
private struct GenreBackdropAnswer {
    let genreID: String
    let image: ItemImage?
    var failed = false
}

private extension [BaseItemDto]? {
    var categoryEntries: [LibraryEntry] {
        (self ?? []).compactMap(LibraryEntry.init)
    }
}
