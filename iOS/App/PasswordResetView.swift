import SwiftUI

/// Resets the ezVille password with a code shown on the household's wall pad (월패드).
struct PasswordResetView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let onReset: (_ email: String, _ password: String) -> Void

  private enum Step { case request, verify, newPassword }

  @State private var form: PasswordResetForm
  @State private var step = Step.request
  @State private var confirmation = ""
  @State private var isWorking = false
  @State private var note: String?
  @State private var error: String?

  init(email: String, onReset: @escaping (_ email: String, _ password: String) -> Void) {
    _form = State(initialValue: PasswordResetForm(email: email))
    self.onReset = onReset
  }

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          Toggle("Dry Run", isOn: $model.dryRun)
        } footer: {
          Text("When on, nothing is sent: each step only shows the request it would make.")
        }

        Section {
          TextField("Building (동)", text: $form.dong)
            .keyboardType(.numberPad)
          TextField("Unit (호)", text: $form.ho)
            .keyboardType(.numberPad)
          TextField("Email", text: $form.email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("A verification code will appear on your home's wall pad.")
        }
        .disabled(step != .request)

        if step != .request {
          Section {
            TextField("Code from Wall Pad", text: $form.code)
              .textContentType(.oneTimeCode)
              .keyboardType(.numberPad)
          } footer: {
            Text("The code expires in 10 minutes.")
          }
          .disabled(step != .verify)
        }

        if step == .newPassword {
          Section {
            SecureField("New Password", text: $form.newPassword)
              .textContentType(.newPassword)
            SecureField("Confirm New Password", text: $confirmation)
              .textContentType(.newPassword)
          } footer: {
            Text("8-20 characters using 3 of uppercase, lowercase, digits and symbols, or 10+ characters using 2 of them.")
          }
        }

        if let note {
          Section { Text(note).font(.footnote.monospaced()).foregroundStyle(.secondary) }
        }

        if let error {
          Section { Text(error).foregroundStyle(.red) }
        }

        Section {
          Button {
            Task { await run() }
          } label: {
            HStack {
              Spacer()
              if isWorking { ProgressView() } else { Text(actionTitle).bold() }
              Spacer()
            }
          }
          .disabled(!canRun || isWorking)
        }
      }
      .navigationTitle("Set Password")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
  }

  private var actionTitle: String {
    switch step {
    case .request: String(localized: "Send Code to Wall Pad")
    case .verify: String(localized: "Verify Code")
    case .newPassword: String(localized: "Set Password")
    }
  }

  private var canRun: Bool {
    switch step {
    case .request: !form.dong.isEmpty && !form.ho.isEmpty && !form.email.isEmpty
    case .verify: !form.code.isEmpty
    case .newPassword: !form.newPassword.isEmpty && !confirmation.isEmpty
    }
  }

  private func run() async {
    isWorking = true
    error = nil
    defer { isWorking = false }
    do {
      switch step {
      case .request:
        note = try await model.sendPasswordResetCode(form)
        step = .verify
      case .verify:
        note = try await model.verifyPasswordResetCode(form)
        step = .newPassword
      case .newPassword:
        guard form.newPassword == confirmation else {
          error = String(localized: "The passwords don't match.")
          return
        }
        guard EzvilleParser.isAcceptedNewPassword(form.newPassword) else {
          error = String(localized: "The password doesn't meet the rules below.")
          return
        }
        note = try await model.resetPassword(form)
        guard note == nil else { return } // dry run: nothing changed
        onReset(form.email.trimmingCharacters(in: .whitespacesAndNewlines), form.newPassword)
        dismiss()
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}
