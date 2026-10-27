import AnemoneJellyfin
import SwiftUI

/// Deletes the item after asking, for items the server lets the user delete (`CanDelete`), like
/// Wholphin's `DeleteButton`, `ConfirmDeleteDialog` and `MediaManagementService`. Hidden otherwise.
struct DeleteButton: View {
    let item: ItemDetails
    let canDelete: Bool
    /// What the page does once the item is gone. By default it goes back, as Wholphin does.
    var deleted: (() -> Void)?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var problem: ItemAlert?

    var body: some View {
        if canDelete {
            ActionButton(title: String(localized: "Delete"), systemImage: "trash") {
                confirming = true
            }
            .accessibilityIdentifier("action.delete")
            .disabled(isDeleting)
            .alert("Delete \(item.item.name)?", isPresented: $confirming) {
                Button("Delete", role: .destructive) {
                    Task { await delete() }
                }
                .accessibilityIdentifier("delete.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes it from \(browse.server.name) for everyone, and can't be undone.")
            }
            .itemAlert($problem)
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await browse.session.deleteItem(id: item.id)
            // So the pages behind this one, Home and the rest, drop it before Back shows them.
            browse.noteDeleted(item.id)
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
