import Foundation
import JellyfinAPI

/// Cinema-mode intros, as Wholphin's `PlaybackViewModel` asks for them: what the server plays
/// before an item, such as the pre-rolls the Local Intros plugin offers.
public extension JellyfinSession {
    /// The intros to play before `itemID`, in the server's order; empty when it has none.
    func intros(for itemID: MediaItem.ID) async throws -> [MediaItem] {
        let result = try await send(Paths.getIntros(itemID: itemID, userID: userID))
        return (result.items ?? []).compactMap(MediaItem.init)
    }
}
