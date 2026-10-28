import Foundation

/// Wholphin's "Max bitrate" in the player's settings dialog (`PlaybackDialogType.BITRATE`): the
/// streaming limit for this player, the Streaming setting to begin with. Picking another asks the
/// server for the entry again under it (`reload()`), which plays on from the same position, as
/// Wholphin's `changeMaxBitrate` does; the entries after it in the queue keep the pick, and a new
/// player starts from the setting again. A live stream has no menu: reopening one for a limit
/// isn't tried.
@MainActor
public final class MaxBitrateMenu: PlaybackFeature {
    static let menuID = "maxBitrate"

    /// The limit picked in this player, if any; the Streaming setting applies until then.
    public private(set) var pickedBitrate: Int?
    /// The Streaming setting, read for each request.
    private let setting: @MainActor () -> Int

    public convenience init() {
        self.init { AVPlayerProfile.maxBitrate }
    }

    init(setting: @escaping @MainActor () -> Int) {
        self.setting = setting
    }

    public func prepare(_ request: inout StreamRequest) async {
        request.maxBitrate = pickedBitrate ?? setting()
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, _), let .reloaded(stream):
            if stream.liveStreamID == nil {
                show(in: controller)
            } else {
                controller.accessories.removeMenu(Self.menuID)
            }
        default:
            break
        }
    }

    private func show(in controller: PlaybackController) {
        let current = pickedBitrate ?? setting()
        // A limit set by launch argument is offered too, so the menu always marks one.
        var choices = AVPlayerProfile.bitrateChoices
        if !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }
        controller.accessories.show(PlayerMenu(
            id: Self.menuID,
            title: String(localized: "Max bitrate", bundle: .module),
            systemImage: "gauge.with.dots.needle.33percent",
            options: choices.map { bitrate in
                PlayerMenu.Option(
                    id: "\(Self.menuID).\(bitrate)",
                    title: bitrate.bitrateText,
                    isSelected: bitrate == current,
                ) { [weak self, weak controller] in
                    guard let self, let controller, bitrate != current else { return }
                    pickedBitrate = bitrate
                    show(in: controller)
                    controller.reload()
                }
            },
        ))
    }
}
