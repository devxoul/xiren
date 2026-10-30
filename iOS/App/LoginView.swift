import SwiftUI

struct LoginView: View {
  @Environment(AppModel.self) private var model
  @State private var email = ""
  @State private var password = ""
  @State private var isSigningIn = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("Password", text: $password)
            .textContentType(.password)
        } footer: {
          Text("Your ezVille (S&D 스마트홈) account. Stored only in this device's Keychain.")
        }

        if let error {
          Section { Text(error).foregroundStyle(.red) }
        }

        Section {
          Button {
            Task { await signIn() }
          } label: {
            HStack {
              Spacer()
              if isSigningIn { ProgressView() } else { Text("Sign In").bold() }
              Spacer()
            }
          }
          .disabled(email.isEmpty || password.isEmpty || isSigningIn)
        }
      }
      .navigationTitle("Xiren")
    }
  }

  private func signIn() async {
    isSigningIn = true
    error = nil
    defer { isSigningIn = false }
    do {
      try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
    } catch {
      self.error = error.localizedDescription
    }
  }
}
