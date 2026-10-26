import TVServices

/// Supplies the Top Shelf row shown above Anemone on the Apple TV home screen.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        // Continue Watching / Next Up arrive in Phase 5, once the app shares credentials
        // with this extension through an App Group and a Keychain access group.
        completionHandler(nil)
    }
}
