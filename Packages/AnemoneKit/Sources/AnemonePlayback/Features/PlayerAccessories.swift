import Foundation
import Observation

/// The controls features add to the player, kept as data so both the system player and
/// Anemone's own overlay can show them. The system player maps actions to its contextual
/// actions, menus to its transport bar, and the card to an overlay.
///
/// Each feature names what it shows with its own IDs, and showing something again with the
/// same ID replaces it.
@MainActor
@Observable
public final class PlayerAccessories {
    /// Buttons over the video for a moment, such as "Skip Intro" or "Next Episode".
    public private(set) var actions: [PlayerAction] = []
    /// Menus above the transport bar, such as Audio, Subtitles or Speed.
    public private(set) var menus: [PlayerMenu] = []
    /// A card asking for a decision, such as Up Next or "Still watching?". One at a time.
    public private(set) var card: PlayerCard?

    public init() {}

    public func show(_ action: PlayerAction) {
        Self.upsert(action, in: &actions)
    }

    public func removeAction(_ id: PlayerAction.ID) {
        actions.removeAll { $0.id == id }
    }

    public func show(_ menu: PlayerMenu) {
        Self.upsert(menu, in: &menus)
    }

    public func removeMenu(_ id: PlayerMenu.ID) {
        menus.removeAll { $0.id == id }
    }

    /// Replaces any card showing.
    public func show(_ card: PlayerCard) {
        self.card = card
    }

    /// Only if it's the card showing, so a feature doesn't dismiss another's.
    public func dismissCard(_ id: PlayerCard.ID) {
        if card?.id == id {
            card = nil
        }
    }

    private static func upsert<Element: Identifiable>(_ element: Element, in elements: inout [Element]) {
        if let index = elements.firstIndex(where: { $0.id == element.id }) {
            elements[index] = element
        } else {
            elements.append(element)
        }
    }
}

/// A button a feature adds to the player.
public struct PlayerAction: Identifiable {
    public let id: String
    public var title: String
    /// An SF Symbol.
    public var systemImage: String?
    public var perform: @MainActor () -> Void

    public init(id: String, title: String, systemImage: String? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.perform = perform
    }
}

/// A menu of choices, one of them selected, such as the audio tracks.
public struct PlayerMenu: Identifiable {
    public struct Option: Identifiable {
        public let id: String
        public var title: String
        public var isSelected: Bool
        public var select: @MainActor () -> Void

        public init(id: String, title: String, isSelected: Bool, select: @escaping @MainActor () -> Void) {
            self.id = id
            self.title = title
            self.isSelected = isSelected
            self.select = select
        }
    }

    public let id: String
    public var title: String
    /// An SF Symbol.
    public var systemImage: String?
    public var options: [Option]

    public init(id: String, title: String, systemImage: String? = nil, options: [Option]) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.options = options
    }
}

/// A card over the video with a few buttons; the first has focus.
public struct PlayerCard: Identifiable {
    public let id: String
    public var title: String
    /// A line under the title, such as "Playing in 10 s"; a feature updates it as it counts down.
    public var message: String?
    public var imageURL: URL?
    public var actions: [PlayerAction]

    public init(id: String, title: String, message: String? = nil, imageURL: URL? = nil, actions: [PlayerAction]) {
        self.id = id
        self.title = title
        self.message = message
        self.imageURL = imageURL
        self.actions = actions
    }
}
