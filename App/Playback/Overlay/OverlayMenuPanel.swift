import AnemonePlayback
import SwiftUI

/// A feature's menu, such as Audio or Subtitles, as a list over the controls. Wholphin shows these
/// as a dialog at the bottom of the screen; a list of our own, rather than SwiftUI's `Menu`, keeps
/// the controls up while it's open. A long list, such as Max bitrate's 23 limits, scrolls within
/// the screen, the focused option kept in view, as Wholphin's `BottomDialog` scrolls to the
/// current choice; a `VStack` alone put the top options off the screen, where focus couldn't reach.
struct MenuPanel: View {
    let menu: PlayerMenu
    var focus: FocusState<OverlayFocus?>.Binding
    let close: () -> Void

    /// Room for about eight options under the title, as Wholphin's dialog shows.
    private static let maxListHeight: CGFloat = 640
    /// The options' height, measured: the overlay proposes the panel only the controls' height,
    /// which a scroll view would take as its own.
    @State private var listHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(menu.title)
                .font(.headline)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(menu.options) { option in
                        Button {
                            option.select()
                            close()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "checkmark")
                                    .opacity(option.isSelected ? 1 : 0)
                                    .accessibilityHidden(true)
                                Text(option.title)
                                Spacer(minLength: 0)
                            }
                            .frame(width: 520, alignment: .leading)
                        }
                        .focused(focus, equals: .option(menu: menu.id, option: option.id))
                        // The check, for VoiceOver.
                        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                        .accessibilityIdentifier("player.option.\(menu.id).\(option.id)")
                    }
                }
                // Room for the focused button's lift, which the scroll view would clip.
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { listHeight = $0 })
            }
            .frame(height: listHeight.map { min($0, Self.maxListHeight) })
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .focusSection()
    }
}
