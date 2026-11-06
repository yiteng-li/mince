import SwiftUI

/// S22 (mince+): paste a recipe URL or text; review matches in the recipe editor.
struct RecipeImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @State private var imported: AIService.ImportedRecipe?

    var body: some View {
        if let imported {
            RecipeEditorView(recipe: nil, imported: imported)
        } else {
            NavigationStack {
                Form {
                    Section("Recipe link") {
                        TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("Or paste the recipe") { TextEditor(text: $text).frame(minHeight: 160) }
                    if let error { Section { Text(error).foregroundStyle(Theme.Colors.danger) } }
                    Section {
                        Button("Import") {
                            Task {
                                working = true
                                defer { working = false }
                                do {
                                    imported = try await AIService().importRecipe(url: url.isEmpty ? nil : url, text: text.isEmpty ? nil : text)
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.minced(.primary, loading: working))
                        .disabled((url.isEmpty && text.isEmpty) || working)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                .screenBackground()
                .navigationTitle("Import recipe")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
    }
}
