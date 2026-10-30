import AnemoneCore
import AnemoneJellyfin
import SwiftUI

extension Preferences {
    /// Wholphin's "Show media management options" (`enableMediaManagement`): whether Delete
    /// shows, on item pages and in card menus, where the server lets the user delete the item.
    /// Off, as in Wholphin.
    static let enableMediaManagement = Preference("enableMediaManagement", default: false)
}

/// Deletes the item after asking, for items the server lets the user delete (`CanDelete`) while
/// "Show media management options" is on, like Wholphin's `DeleteButton`, `ConfirmDeleteDialog`
/// and `MediaManagementService`. Hidden otherwise.
struct DeleteButton: View {
    let item: ItemDetails
    let canDelete: Bool
    /// What the page does once the item is gone. By default it goes back, as Wholphin does.
    var deleted: (() -> Void)?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.enableMediaManagement) private var showsManagement
    /// The item while Delete asks about it.
    @State private var asking: ItemDetails?
    @State private var isDeleting = false
    @State private var problem: ItemAlert?

    var body: some View {
        if canDelete, showsManagement {
            ActionButton(title: String(localized: "Delete"), systemImage: "trash") {
                asking = item
            }
            .accessibilityIdentifier("action.delete")
            .disabled(isDeleting)
            .deleteConfirmation(for: $asking) { _ in
                Task { await delete() }
            }
            .itemAlert($problem)
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await browse.delete(item)
            if let deleted {
                deleted()
            } else {
                dismiss()
            }
        } catch {
            problem = browse.problem(with: error, failure: "Couldn't delete \(item.item.name).").map(ItemAlert.failed)
        }
    }
}

extension BrowseModel {
    /// Deletes an item from the server, then tells the pages showing it, so they drop it before
    /// Back shows them: what an item page's Delete and a card menu's both do.
    func delete(_ item: ItemDetails) async throws {
        try await session.deleteItem(id: item.id)
        noteDeleted(item.id)
    }
}

extension View {
    /// Wholphin's `ConfirmDeleteDialog`: asks about `item` while it's set, and runs `delete`
    /// with it once confirmed, or `cancelled` when the user backs out.
    func deleteConfirmation(
        for item: Binding<ItemDetails?>,
        cancelled: @escaping () -> Void = {},
        delete: @escaping (ItemDetails) -> Void,
    ) -> some View {
        modifier(DeleteConfirmation(item: item, delete: delete, cancelled: cancelled))
    }
}

private struct DeleteConfirmation: ViewModifier {
    @Binding var item: ItemDetails?
    let delete: (ItemDetails) -> Void
    let cancelled: () -> Void

    @Environment(BrowseModel.self) private var browse
    /// The item last asked about, so the title keeps its name while the alert goes away.
    @State private var asked: ItemDetails?

    func body(content: Content) -> some View {
        content
            .onChange(of: item, initial: true) { _, item in
                if let item {
                    asked = item
                }
            }
            .alert(
                Text("Delete \((item ?? asked)?.item.name ?? "")?"),
                isPresented: Binding(get: { item != nil }, set: {
                    if !$0 {
                        item = nil
                    }
                }),
                presenting: item ?? asked,
            ) { shown in
                Button("Delete", role: .destructive) {
                    delete(shown)
                }
                .accessibilityIdentifier("delete.confirm")
                Button("Cancel", role: .cancel, action: cancelled)
            } message: { _ in
                Text("This deletes it from \(browse.server.name) for everyone, and can't be undone.")
            }
    }
}
