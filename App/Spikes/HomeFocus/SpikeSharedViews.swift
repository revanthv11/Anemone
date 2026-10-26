import SwiftUI

/// The focused-item header above the rows, like Wholphin's home page.
struct SpikeHeader: View {
    let item: SpikeItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item?.title ?? " ")
                .font(.title2.bold())
            Text(item.flatMap { SpikeData.row(id: $0.rowID)?.title } ?? " ")
                .foregroundStyle(.secondary)
            Text(item?.id ?? "none")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("spike.focusedID")
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .bottomLeading)
        .padding(.horizontal, SpikeLayout.horizontalInset)
    }
}

struct SpikeDetail: View {
    let item: SpikeItem

    var body: some View {
        VStack(spacing: 40) {
            Text(item.title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("detail.title")
            Button("Play") {}
        }
    }
}
