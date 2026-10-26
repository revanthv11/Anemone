import Foundation

/// Which libraries the sidebar shows and in what order, like Wholphin's nav drawer pins. The rest
/// go under More.
///
/// Libraries are matched by ID, so libraries added on the server later are pinned and go last,
/// and ones the user lost access to are skipped.
public struct LibraryPins: Codable, Hashable, Sendable {
    /// Library IDs in the user's order. Libraries not listed go after these, in the server's order.
    public private(set) var order: [String] = []
    public private(set) var unpinned: Set<String> = []

    public init() {}

    /// `libraries` (in the server's order) in the user's order, pinned or not.
    public func ordered<Item>(_ libraries: [Item], id: (Item) -> String) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        return libraries.enumerated()
            .sorted { (rank[id($0.element)] ?? Int.max, $0.offset) < (rank[id($1.element)] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// Splits `libraries` (in the server's order) into the pinned ones and the rest, each in the
    /// user's order.
    public func arrange<Item>(_ libraries: [Item], id: (Item) -> String) -> (pinned: [Item], unpinned: [Item]) {
        let all = ordered(libraries, id: id)
        return (all.filter { isPinned(id($0)) }, all.filter { !isPinned(id($0)) })
    }

    public func isPinned(_ id: String) -> Bool {
        !unpinned.contains(id)
    }

    public mutating func setPinned(_ pinned: Bool, _ id: String) {
        if pinned {
            unpinned.remove(id)
        } else {
            unpinned.insert(id)
        }
    }

    /// Moves a library one place up (`offset` -1) or down (+1) among `current`, the IDs in the
    /// order `ordered` gives, and keeps that whole order.
    public mutating func move(_ id: String, by offset: Int, in current: [String]) {
        guard let index = current.firstIndex(of: id), current.indices.contains(index + offset) else { return }
        var reordered = current
        reordered.swapAt(index, index + offset)
        order = reordered
    }
}
