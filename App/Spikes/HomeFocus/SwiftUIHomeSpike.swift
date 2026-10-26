import SwiftUI

/// Spike variant A: a SwiftUI `LazyVStack` of horizontal `LazyHStack` rows.
///
/// Row memory (re-entering a row focuses the item you left it on) relies on one
/// `defaultFocus(_:_:priority: .userInitiated)` per row.
///
/// `LazyVStack` discards rows that scroll off screen, which resets their horizontal scroll, so
/// the remembered item no longer exists when focus comes back. `Strategy` picks how to cope.
struct SwiftUIHomeSpike: View {
    enum Strategy {
        /// `LazyVStack`, nothing extra.
        case naive
        /// `LazyVStack`, with each row's scroll position kept here and restored.
        case rememberScroll
        /// Plain `VStack`, so rows are never discarded. Fine for ~10–20 home rows.
        case eagerRows
    }

    var strategy = Strategy.eagerRows

    private let rows = SpikeData.rows

    @FocusState private var focusedID: SpikeItem.ID?
    @State private var lastFocusedByRow: [SpikeRow.ID: SpikeItem.ID] = [:]
    @State private var scrollPositionByRow: [SpikeRow.ID: SpikeItem.ID] = [:]
    @State private var headerItem: SpikeItem?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                SpikeHeader(item: headerItem)
                ScrollView(.vertical) {
                    Group {
                        if strategy == .eagerRows {
                            VStack(alignment: .leading, spacing: SpikeLayout.rowSpacing) { rowViews }
                        } else {
                            LazyVStack(alignment: .leading, spacing: SpikeLayout.rowSpacing) { rowViews }
                        }
                    }
                    .padding(.horizontal, SpikeLayout.horizontalInset)
                }
            }
            .navigationDestination(for: SpikeItem.self) { SpikeDetail(item: $0) }
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let item = SpikeData.item(id: id) else { return }
            lastFocusedByRow[item.rowID] = id
        }
        .task(id: focusedID) {
            // Debounced, the way Wholphin debounces its backdrop.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let focusedID else { return }
            headerItem = SpikeData.item(id: focusedID)
        }
    }

    private var rowViews: some View {
        ForEach(rows) { row in
            SwiftUISpikeRow(
                row: row,
                focusedID: $focusedID,
                scrollPosition: strategy == .rememberScroll ? scrollPositionBinding(for: row) : nil,
            )
            .defaultFocus(
                $focusedID,
                lastFocusedByRow[row.id] ?? row.items.first?.id,
                priority: .userInitiated,
            )
        }
    }

    private func scrollPositionBinding(for row: SpikeRow) -> Binding<SpikeItem.ID?> {
        Binding(
            get: { scrollPositionByRow[row.id] },
            set: { scrollPositionByRow[row.id] = $0 },
        )
    }
}

private struct SwiftUISpikeRow: View {
    let row: SpikeRow
    let focusedID: FocusState<SpikeItem.ID?>.Binding
    /// The leading visible item, kept by the parent so it survives the row being recreated.
    let scrollPosition: Binding<SpikeItem.ID?>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
            if let scrollPosition {
                scroller
                    .scrollPosition(id: scrollPosition, anchor: .leading)
            } else {
                scroller
            }
        }
        .focusSection()
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: SpikeLayout.posterSpacing) {
                ForEach(row.items) { item in
                    NavigationLink(value: item) {
                        SwiftUIPoster(item: item)
                    }
                    .buttonStyle(.borderless)
                    .focused(focusedID, equals: item.id)
                    .accessibilityIdentifier(item.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, SpikeLayout.focusPadding)
        }
        .scrollClipDisabled()
    }
}

private struct SwiftUIPoster: View {
    let item: SpikeItem
    @State private var image: UIImage?

    init(item: SpikeItem) {
        self.item = item
        _image = State(initialValue: PosterImageCache.shared.cachedImage(for: item))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(width: SpikeLayout.posterSize.width, height: SpikeLayout.posterSize.height)
        .task(id: item.id) {
            guard image == nil else { return }
            image = await PosterImageCache.shared.image(for: item)
        }
    }
}
