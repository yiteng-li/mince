import SwiftUI

/// S11 (mince+): say what you ate; AI turns it into foods and amounts.
struct VoiceLogView: View {
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    var initialText: String?
    @State private var speech = SpeechService()
    @State private var text = ""
    @State private var parsing = false
    @State private var items: [AIService.Item] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if !items.isEmpty {
                    AIReviewList(groupId: groupId, items: $items, source: .voice)
                } else {
                    VStack(spacing: Theme.Space.md) {
                        Text("Say something like “two scrambled eggs, a slice of sourdough and a black coffee”.")
                            .foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(Theme.Space.xs)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .accessibilityLabel("What you ate")
                        Button {
                            if speech.isRecording { speech.stop() } else { Task { await speech.start() } }
                        } label: {
                            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(speech.isRecording ? Theme.Colors.danger : Theme.Colors.accent)
                        }
                        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start recording")
                        if parsing { ProgressView("Working it out…") }
                        if let e = error ?? speech.errorMessage { Text(e).foregroundStyle(Theme.Colors.danger) }
                        Spacer()
                        Button("Find foods") { Task { await parse() } }
                            .buttonStyle(.minced(.primary, loading: parsing))
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || parsing)
                    }
                    .padding(Theme.Space.md)
                }
            }
            .background(Theme.Colors.bg)
            .navigationTitle("Voice log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.stop(); dismiss() } } }
            .onChange(of: speech.transcript) { _, t in text = t }
            .task {
                if let initialText, !initialText.isEmpty { text = initialText; await parse() }
            }
        }
    }

    private func parse() async {
        speech.stop()
        parsing = true
        error = nil
        defer { parsing = false }
        do {
            items = try await AIService().parse(text: text).items
            if items.isEmpty { error = "Couldn't pick out any foods. Try naming them with amounts." }
        } catch { self.error = error.localizedDescription }
    }
}
