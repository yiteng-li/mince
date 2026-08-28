import SwiftUI

struct LogInView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)

                if let message = authViewModel.errorMessage {
                    Text(message).foregroundStyle(.red)
                }

                Button("Log In") {
                    Task { await authViewModel.logIn(email: email, password: password) }
                }
                .disabled(authViewModel.isLoading)
            }
            .navigationTitle("mince")
            .safeAreaInset(edge: .bottom) {
                Button("Need an account? Sign Up") { showingSignUp = true }
                    .padding()
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
        }
    }
}
