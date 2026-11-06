import Foundation

@MainActor
@Observable
final class DiaryModel {
    var entries: [DiaryEntry] = []
    var isLoading = true
    var error: String?
    var completed = false
    var toast: Toast?

    func load(day: Day, hasPlus: Bool) async {
        error = nil
        do {
            if hasPlus { try? await DiaryService().materializeRepeats(on: day) }
            async let e = DiaryService().entries(on: day)
            async let c = DiaryService().completedDays(since: day)
            let (rows, done) = try await (e, c)
            entries = rows
            completed = done.contains(day)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var consumed: Nutrients { entries.reduce(into: Nutrients()) { $0 += $1.consumed } }
    var exerciseKcal: Double { entries.filter { $0.kind == .exercise }.compactMap(\.energyKcal).reduce(0, +) }

    func entries(in group: DiaryGroup?, sortedByTime: Bool) -> [DiaryEntry] {
        let rows = entries.filter { [.food, .quickAdd, .note].contains($0.kind) && $0.groupId == group?.id }
        return sortedByTime ? rows.sorted { ($0.loggedAt ?? .distantFuture) < ($1.loggedAt ?? .distantFuture) } : rows
    }

    func delete(_ ids: Set<UUID>, app: AppModel) async {
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        do {
            try await DiaryService().delete(ids: Array(ids))
            app.diaryChanged()
            toast = Toast(message: removed.count == 1 ? "Entry deleted" : "\(removed.count) entries deleted") { [weak self] in
                Task {
                    _ = try? await DiaryService().insert(removed)
                    self?.entries += removed
                    app.diaryChanged()
                }
            }
        } catch {
            entries += removed
            app.report(error)
        }
    }

    func paste(_ copied: [DiaryEntry], day: Day, groupId: UUID?, app: AppModel) async {
        do {
            let inserted = try await DiaryService().insert(copied.map { $0.copied(to: day, groupId: groupId) })
            entries += inserted
            app.diaryChanged()
            toast = Toast(message: "Pasted \(inserted.count) item\(inserted.count == 1 ? "" : "s")")
        } catch { app.report(error) }
    }

    func move(_ entry: DiaryEntry, to group: DiaryGroup, app: AppModel) async {
        var e = entry
        e.groupId = group.id
        do {
            let saved = try await DiaryService().update(e)
            if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = saved }
        } catch { app.report(error) }
    }

    func toggleComplete(day: Day, app: AppModel) async {
        do {
            try await DiaryService().setCompleted(!completed, day: day)
            completed.toggle()
            app.diaryChanged()
        } catch { app.report(error) }
    }
}
