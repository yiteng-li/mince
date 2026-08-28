import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

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

                Button("Sign Up") {
                    Task {
                        await authViewModel.signUp(email: email, password: password)
                        if authViewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
                .disabled(authViewModel.isLoading)
            }
            .navigationTitle("Create Account")
        }
    }
}
