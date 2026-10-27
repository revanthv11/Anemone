#if DEBUG
    import AnemoneJellyfin
    import Foundation

    /// Made-up collections for the Collections tab, for checking it against a server that has
    /// none, such as the demo server. Launch with `-libraryMockCollections YES`; Debug builds only.
    enum MockCollections {
        static var isOn: Bool {
            UserDefaults.standard.bool(forKey: "libraryMockCollections")
        }

        static let loader: LibraryPager.Loader = { startIndex, limit, includeTotalCount in
            try await Task.sleep(for: .milliseconds(300))
            let names = ["Classic Horror", "Llama Shorts", "Public Domain Gems", "Space Race", "Westerns"]
            let entries = names.indices.dropFirst(startIndex).prefix(limit).map { index in
                let item = MediaItem(id: "mock-collection-\(index)", name: names[index], kind: .collection)
                return LibraryEntry(
                    item: item,
                    sortName: names[index].lowercased(),
                    details: ItemDetails(
                        item: item,
                        childCount: index + 2,
                        userState: ItemDetails.UserState(unplayedCount: index),
                    ),
                )
            }
            return LibraryPage(items: entries, totalCount: includeTotalCount ? names.count : nil)
        }
    }
#endif
