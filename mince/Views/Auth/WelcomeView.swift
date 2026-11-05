import AuthenticationServices
import SwiftUI

/// S01 / S02: create an account, sign in, reset a password.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var mode = Mode.signUp
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var info: String?

    enum Mode: String, CaseIterable { case signUp = "Create account", signIn = "Sign in" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("mince").font(Theme.Fonts.display)
                        Text("Track every nutrient, not just calories.").foregroundStyle(Theme.Colors.textMuted)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    SignInWithAppleButton(.continue) { app.prepare($0) } onCompletion: { result in
                        Task { await run { try await app.completeApple(result) } }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                } footer: {
                    if mode == .signUp { Text("At least 8 characters.") }
                }

                if let message {
                    Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(Theme.Colors.danger) }
                }
                if let info {
                    Section { Label(info, systemImage: "envelope").foregroundStyle(Theme.Colors.success) }
                }

                Section {
                    Button(mode.rawValue) {
                        Task {
                            await run {
                                if mode == .signUp { try await app.signUp(email: email, password: password) }
                                else { try await app.signIn(email: email, password: password) }
                            }
                        }
                    }
                    .buttonStyle(.minced(.primary, loading: busy))
                    .disabled(busy || email.isEmpty || password.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            Task {
                                await run {
                                    try await app.resetPassword(email: email)
                                    info = "If that email has an account, a reset link is on its way."
                                }
                            }
                        }
                        .disabled(email.isEmpty || busy)
                    }
                }
            }
            .screenBackground()
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        message = nil
        info = nil
        defer { busy = false }
        do { try await work() } catch {
            let text = error.localizedDescription
            if text.contains("inbox") { info = text } else { message = text }
        }
    }
}
