import AnemoneCore
import SwiftUI

/// What it takes to switch to this profile: nothing, a PIN, or signing in again.
struct ProfileLockView: View {
    let user: SavedUser

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isSettingPIN = false
    @State private var didSetPIN = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Profile lock")
                .font(.largeTitle.bold())
            Text("Controls what it takes to switch to \(user.name) on this Apple TV.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 20) {
                option("No lock", isSelected: user.lock == .unlocked) {
                    model.setLock(.unlocked)
                    dismiss()
                }
                option("PIN", isSelected: isPINLocked) {
                    isSettingPIN = true
                }
                option("Require sign-in", isSelected: user.lock == .requireSignIn) {
                    model.setLock(.requireSignIn)
                    dismiss()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(80)
        // Leave this screen only once the PIN sheet has finished dismissing itself.
        .sheet(isPresented: $isSettingPIN, onDismiss: {
            if didSetPIN {
                dismiss()
            }
        }, content: {
            NewPINView { hash in
                model.setLock(.pin(hash))
                didSetPIN = true
            }
        })
    }

    private var isPINLocked: Bool {
        if case .pin = user.lock {
            true
        } else {
            false
        }
    }

    private func option(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
        }
    }
}

/// Asks for a PIN and checks it.
struct PINEntryView: View {
    let title: String
    /// Returns `false` when the PIN is wrong.
    let submit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var isWrong = false

    var body: some View {
        VStack(spacing: 32) {
            Text(title)
                .font(.title2.bold())
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .frame(maxWidth: 500)
                .onSubmit(check)
                .accessibilityIdentifier("pin.field")
            if isWrong {
                NoticeText("Wrong PIN.")
            }
            Button("Cancel") {
                dismiss()
            }
        }
        .padding(80)
    }

    private func check() {
        Task {
            if await submit(pin) {
                dismiss()
            } else {
                isWrong = true
                pin = ""
            }
        }
    }
}

/// Asks for a new PIN twice.
private struct NewPINView: View {
    let save: (PINHash) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var pin = ""
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 32) {
            Text(first == nil ? "Choose a \(PINHash.length)-digit PIN" : "Enter the PIN again")
                .font(.title2.bold())
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .frame(maxWidth: 500)
                .onSubmit(next)
            if let problem {
                NoticeText(problem)
            }
            Button("Cancel") {
                dismiss()
            }
        }
        .padding(80)
    }

    private func next() {
        defer { pin = "" }
        guard let first else {
            guard PINHash.isValid(pin) else {
                problem = "Use exactly \(PINHash.length) digits."
                return
            }
            first = pin
            problem = nil
            return
        }
        guard pin == first else {
            self.first = nil
            problem = "The PINs didn't match. Start again."
            return
        }
        save(PINHash(pin: pin))
        dismiss()
    }
}
