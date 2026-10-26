import Foundation
import Get
import JellyfinAPI

/// Absolute URLs for the SDK's generated requests, built the way its client builds them, but
/// without creating a `JellyfinClient` (and its URLSession) for every image.
public enum JellyfinURLs {
    public static func userImage(on server: URL, userID: String, tag: String) -> URL? {
        url(for: Paths.getUserImage(parameters: .init(userID: userID, tag: tag)), on: server)
    }

    /// The server scales the image down to `maxWidth` pixels, keeping its aspect ratio. Quality
    /// 96 matches Wholphin.
    public static func itemImage(on server: URL, image: ItemImage, maxWidth: Int) -> URL? {
        let parameters = Paths.GetItemImageParameters(maxWidth: maxWidth, quality: 96, tag: image.tag)
        return url(
            for: Paths.getItemImage(itemID: image.itemID, imageType: image.kind.rawValue, parameters: parameters),
            on: server,
        )
    }

    /// Mirrors Get's `APIClient`: appends the request path to the server URL, keeping any
    /// reverse-proxy path, then adds the query.
    static func url(for request: Request<some Any>, on server: URL) -> URL? {
        guard let path = request.url?.absoluteString,
              var components = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { return nil }
        if let query = request.query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components.url
    }
}
