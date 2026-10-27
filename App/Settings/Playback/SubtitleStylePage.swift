import AnemoneCore
import AnemonePlayback
import SwiftUI

/// Wholphin's subtitle style page (`SubtitleStylePage`): font, edge, background and margin, with
/// its ranges as lists of steps, since tvOS has no slider. Edits one style, the standard one or
/// the one for HDR video.
struct SubtitleStylePage: View {
    let preference: Preference<SubtitleStyle>
    let title: String

    /// The style as JSON, which `@AppStorage` keeps in sync with the setting.
    @AppStorage private var stored: String

    init(preference: Preference<SubtitleStyle>, title: String) {
        self.preference = preference
        self.title = title
        _stored = AppStorage(wrappedValue: "", preference.key)
    }

    private var style: Binding<SubtitleStyle> {
        Binding {
            SubtitleStyle(json: stored) ?? preference.defaultValue
        } set: { style in
            stored = style.json
        }
    }

    var body: some View {
        List {
            Section {
                SubtitlePreview(style: style.wrappedValue)
            }
            Section("Font") {
                steps("Size", \.fontSize, Array(stride(from: 8, through: 70, by: 2))) { "\($0)" }
                colors("Color", \.fontColor)
                Toggle("Bold", isOn: style.isBold)
                Toggle("Italic", isOn: style.isItalic)
                steps("Opacity", \.fontOpacity, Array(stride(from: 10, through: 100, by: 10))) { "\($0)%" }
            }
            Section("Edge") {
                Picker("Style", selection: style.edge) {
                    Text("None").tag(SubtitleEdge.none)
                    Text("Outline").tag(SubtitleEdge.solid)
                    Text("Drop shadow").tag(SubtitleEdge.shadow)
                }
                colors("Color", \.edgeColor)
                steps("Size", \.edgeThickness, Array(1 ... 32)) { String(format: "%g", Double($0) / 2) }
            }
            Section("Background") {
                Picker("Style", selection: style.background) {
                    Text("None").tag(SubtitleBackground.none)
                    Text("Behind each line").tag(SubtitleBackground.wrap)
                    Text("One box").tag(SubtitleBackground.boxed)
                }
                colors("Color", \.backgroundColor)
                steps("Opacity", \.backgroundOpacity, Array(stride(from: 10, through: 100, by: 10))) { "\($0)%" }
            }
            Section("More") {
                steps("Margin", \.margin, Array(stride(from: 0, through: 100, by: 2))) { "\($0)%" }
                Button("Reset") {
                    stored = preference.defaultValue.json
                }
                .accessibilityIdentifier("settings.subtitleStyle.reset")
            }
        }
        .pickerStyle(.navigationLink)
        .navigationTitle(title)
    }

    private func steps(
        _ title: String,
        _ keyPath: WritableKeyPath<SubtitleStyle, Int>,
        _ values: [Int],
        label: @escaping (Int) -> String,
    ) -> some View {
        Picker(title, selection: style[dynamicMember: keyPath]) {
            ForEach(values, id: \.self) { value in
                Text(label(value)).tag(value)
            }
        }
    }

    private func colors(_ title: String, _ keyPath: WritableKeyPath<SubtitleStyle, SubtitleColor>) -> some View {
        Picker(title, selection: style[dynamicMember: keyPath]) {
            ForEach(SubtitleColor.allCases, id: \.self) { color in
                Text(color.name).tag(color)
            }
        }
    }
}

/// A line of text in the style, roughly as MPV draws it.
private struct SubtitlePreview: View {
    let style: SubtitleStyle

    var body: some View {
        Text("The quick brown fox jumps over the lazy dog")
            .font(.system(size: CGFloat(style.fontSize) * 1.6 * 1.5, weight: style.isBold ? .bold : .regular))
            .italic(style.isItalic)
            .foregroundStyle(color(style.fontColor, style.fontOpacity))
            .shadow(color: edge(radius: false), radius: style.edge == .solid ? 1 : 0)
            .shadow(color: edge(radius: true), radius: 0, x: 4, y: 4)
            .padding(.horizontal, style.background == .none ? 0 : 12)
            .background(style.background == .none ? .clear : color(style.backgroundColor, style.backgroundOpacity))
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("settings.subtitleStyle.preview")
    }

    private func edge(radius isShadow: Bool) -> Color {
        let shows = isShadow ? style.edge == .shadow : style.edge == .solid
        return shows ? color(style.edgeColor, style.fontOpacity) : .clear
    }

    private func color(_ color: SubtitleColor, _ opacity: Int) -> Color {
        Color(
            red: Double(color.rgb >> 16 & 0xFF) / 255,
            green: Double(color.rgb >> 8 & 0xFF) / 255,
            blue: Double(color.rgb & 0xFF) / 255,
        )
        .opacity(Double(opacity) / 100)
    }
}
