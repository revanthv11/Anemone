import Foundation

/// Wholphin's Video Scale choice, as a menu of the overlay's own beside the features' menus.
public extension PlayerOverlay {
    static let videoScaleMenuID = "videoScale"

    /// The features' menus, then the overlay's own.
    var menus: [PlayerMenu] {
        controller.accessories.menus + [videoScaleMenu]
    }

    /// Fit, None, Crop and the rest, the one in use marked. A pick lasts for this player, as
    /// Wholphin's does; the setting it started from stays as it is.
    var videoScaleMenu: PlayerMenu {
        PlayerMenu(
            id: Self.videoScaleMenuID,
            title: String(localized: "Video scale", bundle: .module),
            systemImage: "aspectratio",
            options: VideoScale.allCases.map { scale in
                PlayerMenu.Option(id: scale.rawValue, title: scale.title, isSelected: scale == videoScale) { [weak self] in
                    self?.videoScale = scale
                    self?.pulse()
                }
            },
        )
    }
}
