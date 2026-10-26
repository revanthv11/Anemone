import Foundation
import Get
import JellyfinAPI

public enum SessionError: Error, Equatable {
    /// The server no longer accepts the access token, so the user has to sign in again.
    case signedOut
    /// The server answered without data it should have sent.
    case unexpectedResponse
}

/// A signed-in user's connection to their server, used for everything after sign-in.
public struct JellyfinSession: Sendable {
    /// How long to wait for each request. Longer than sign-in's, because a large library can
    /// take the server a few seconds to answer Recently Added.
    public static let timeout: TimeInterval = 20

    public let serverURL: URL
    public let userID: String
    public let accessToken: String
    private let client: JellyfinClient

    /// - Parameter sessionConfiguration: makes a configuration for this session alone; it gets
    ///   this type's `timeout`.
    public init(
        serverURL: URL,
        userID: String,
        accessToken: String,
        identity: ClientIdentity,
        sessionConfiguration: () -> URLSessionConfiguration = { .default },
    ) {
        self.serverURL = serverURL
        self.userID = userID
        self.accessToken = accessToken
        let configuration = sessionConfiguration()
        configuration.timeoutIntervalForRequest = Self.timeout
        client = identity.makeClient(
            serverURL: serverURL,
            accessToken: accessToken,
            sessionConfiguration: configuration,
        )
    }

    /// The libraries Anemone supports, in the order the user arranged them in Jellyfin.
    public func libraries() async throws -> [Library] {
        let views = try await send(Paths.getUserViews(parameters: .init(userID: userID)))
        return (views.items ?? []).compactMap(Library.init).filter(\.isSupported)
    }

    /// Partly watched videos, most recently watched first.
    public func continueWatching(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: userID,
            limit: limit,
            fields: Self.fields,
            mediaTypes: [.video],
            imageTypeLimit: 1,
            enableTotalRecordCount: false,
        )
        return try await send(Paths.getResumeItems(parameters: parameters)).items.mediaItems
    }

    /// The next episode of each series in progress. Partly watched episodes are left to Continue
    /// Watching, and finished series aren't offered again, matching Wholphin's defaults.
    public func nextUp(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetNextUpParameters(
            userID: userID,
            limit: limit,
            fields: Self.fields,
            imageTypeLimit: 1,
            enableUserData: true,
            enableTotalRecordCount: false,
            enableResumable: false,
            enableRewatching: false,
        )
        return try await send(Paths.getNextUp(parameters: parameters)).items.mediaItems
    }

    /// The newest items in a library, with new episodes shown as their series.
    public func recentlyAdded(in libraryID: Library.ID, limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetLatestMediaParameters(
            userID: userID,
            parentID: libraryID,
            fields: Self.fields,
            imageTypeLimit: 1,
            limit: limit,
            isGroupItems: true,
        )
        return try await MediaItem.groupedBySeries(send(Paths.getLatestMedia(parameters: parameters)).mediaItems)
    }

    public func item(id: MediaItem.ID) async throws -> MediaItem {
        guard let item = try await MediaItem(send(Paths.getItem(itemID: id, userID: userID))) else {
            throw SessionError.unexpectedResponse
        }
        return item
    }

    public func imageURL(for image: ItemImage, maxWidth: Int) -> URL? {
        JellyfinURLs.itemImage(on: serverURL, image: image, maxWidth: maxWidth)
    }

    /// Extra fields for cards and the home header.
    private static let fields: [ItemFields] = [.overview]

    func send<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        do {
            return try await client.send(request).value
        } catch APIError.unacceptableStatusCode(401) {
            throw SessionError.signedOut
        }
    }
}

private extension [BaseItemDto] {
    var mediaItems: [MediaItem] {
        compactMap(MediaItem.init)
    }
}

private extension [BaseItemDto]? {
    var mediaItems: [MediaItem] {
        self?.mediaItems ?? []
    }
}
