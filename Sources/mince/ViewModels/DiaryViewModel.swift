import Foundation

@MainActor
final class DiaryViewModel: ObservableObject {
    @Published var entries: [DiaryEntryWithFood] = []
    @Published var totals: MacroTotals = MacroTotals()
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let diaryService = DiaryService()

    func load(userId: UUID, day: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await diaryService.entries(for: userId, on: day)
            // TODO: MacroTotals.from(_:) is a stub — see Models/MacroTotals.swift.
            totals = MacroTotals.from(entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
