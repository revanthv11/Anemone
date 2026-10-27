import Foundation

/// Wholphin's playback speeds (`playbackSpeedOptions`), as a menu in Anemone's overlay. The speed
/// carries on to the next entry, as the engines keep it. The system player is left alone, since
/// it has its own controls.
@MainActor
public final class PlaybackSpeedMenu: PlaybackFeature {
    static let speeds: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    static let menuID = "speed"

    public init() {}

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        guard case .loaded = event else { return }
        if controller.engine.showsInSystemPlayer {
            controller.accessories.removeMenu(Self.menuID)
        } else {
            show(in: controller)
        }
    }

    private func show(in controller: PlaybackController) {
        let current = controller.engine.rate
        controller.accessories.show(PlayerMenu(
            id: Self.menuID,
            title: "Speed",
            systemImage: "gauge.with.dots.needle.67percent",
            options: Self.speeds.map { speed in
                PlayerMenu.Option(
                    id: Self.label(speed),
                    title: speed == 1 ? "Normal" : Self.label(speed),
                    isSelected: abs(speed - current) < 0.01,
                ) { [weak self, weak controller] in
                    guard let controller else { return }
                    controller.engine.rate = speed
                    self?.show(in: controller)
                }
            },
        ))
    }

    /// Such as "1.5×".
    static func label(_ speed: Float) -> String {
        let text = String(format: "%.2f", speed)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return "\(text)×"
    }
}
