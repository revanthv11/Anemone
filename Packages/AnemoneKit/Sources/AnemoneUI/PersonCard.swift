import SwiftUI

/// A round photo with a name and role under it, for cast and crew rows, like Wholphin's
/// `PersonCard`.
///
/// Put it in a button styled `.personCard`: the photo lifts itself when focused, staying round,
/// with a ring and a glow in the theme's focus colours. tvOS's own focus effects draw a square
/// platter around it.
public struct PersonCard: View {
    private let name: String
    private let role: String?
    private let imageURL: URL?
    private let width: CGFloat

    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    public init(name: String, role: String?, imageURL: URL?, width: CGFloat) {
        self.name = name
        self.role = role
        self.imageURL = imageURL
        self.width = width
    }

    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.surfaceVariant)
                Image(systemName: "person.fill")
                    .font(.system(size: width / 3))
                    .foregroundStyle(theme.onSurfaceVariant)
                ArtworkImage(url: imageURL)
            }
            .frame(width: width, height: width)
            .clipShape(.circle)
            .overlay {
                // Wholphin's focused person card: a 3 dp ring in the focus colour.
                Circle()
                    .strokeBorder(theme.focusRing, lineWidth: Theme.focusRingWidth)
                    .opacity(isFocused ? 1 : 0)
            }
            .scaleEffect(isFocused ? 1.12 : 1)
            .shadow(color: isFocused ? theme.focusGlow.color : .clear, radius: 16, y: 10)
            VStack(spacing: 2) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(1)
                Text(role ?? " ")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: width + 40)
            .offset(y: isFocused ? 10 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

/// A button style that leaves focus to a `PersonCard`.
public struct PersonCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

public extension ButtonStyle where Self == PersonCardButtonStyle {
    static var personCard: PersonCardButtonStyle {
        PersonCardButtonStyle()
    }
}
