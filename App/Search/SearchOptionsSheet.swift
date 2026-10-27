import AnemoneJellyfin
import SwiftUI

/// Wholphin's search view options (`SearchViewOptionsDialog`), with its choice of kinds to
/// search for (`SearchTypeOptionsDialog`) a level down. Changes apply as they're made. Wholphin's
/// voice search button setting is left out: dictation is part of the tvOS keyboard.
struct SearchOptionsSheet: View {
    @Binding var isCombined: Bool
    /// The kinds the user's libraries hold, whether included or not.
    let kinds: [SearchKind]
    let preferences: SearchPreferences

    var body: some View {
        NavigationStack {
            List {
                Toggle(isOn: $isCombined) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Combined search results")
                        Text(isCombined ? "Show all results in a single grid" : "Show results by type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("search.options.combined")
                NavigationLink(value: KindsPage()) {
                    LabeledContent("Include types", value: "\(includedCount) of \(kinds.count)")
                }
                .accessibilityIdentifier("search.options.types")
            }
            .navigationTitle("View Options")
            .navigationDestination(for: KindsPage.self) { _ in
                List(kinds, id: \.self) { kind in
                    Toggle(kind.title, isOn: included(kind))
                        .accessibilityIdentifier("search.options.type.\(kind.rowID)")
                }
                .navigationTitle("Include Types")
            }
        }
    }

    private struct KindsPage: Hashable {}

    private var includedCount: Int {
        kinds.count { !preferences.excludedKinds.contains($0) }
    }

    private func included(_ kind: SearchKind) -> Binding<Bool> {
        Binding {
            !preferences.excludedKinds.contains(kind)
        } set: { isIncluded in
            preferences.setIncluded(isIncluded, kind)
        }
    }
}
