import SwiftUI

/// Fix a past fast's start/end.
struct FastEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var fast: Fast
    var onSave: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Started", selection: $fast.startedAt)
                DatePicker("Ended", selection: Binding(get: { fast.endedAt ?? Date() }, set: { fast.endedAt = $0 }), in: fast.startedAt...)
                Stepper("Goal \(fast.targetMinutes / 60) h", value: $fast.targetMinutes, in: 60...10080, step: 60)
            }
            .navigationTitle("Edit fast")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { do { try await PlusService().save(fast); await onSave(); dismiss() } catch { app.report(error) } } }
                        .disabled((fast.endedAt ?? Date()) <= fast.startedAt)
                }
            }
        }
    }
}

struct FastScheduleEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onSave: () async -> Void
    @State private var weekdays: Set<Int> = Set(0...6)
    @State private var start = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
    @State private var hours = 16

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start at", selection: $start, displayedComponents: .hourAndMinute)
                Stepper("Length \(hours) h", value: $hours, in: 1...168)
                Section("Days") {
                    ForEach(0..<7) { d in
                        Toggle(Calendar.current.weekdaySymbols[d], isOn: Binding(get: { weekdays.contains(d) }, set: { on in
                            if on { weekdays.insert(d) } else if weekdays.count > 1 { weekdays.remove(d) }
                        }))
                    }
                }
            }
            .navigationTitle("Fasting schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            let c = Calendar.current.dateComponents([.hour, .minute], from: start)
                            let s = FastSchedule(userId: uid, weekdays: weekdays.sorted(),
                                                 startTime: String(format: "%02d:%02d:00", c.hour ?? 20, c.minute ?? 0), targetMinutes: hours * 60)
                            do { try await PlusService().save(s); await onSave(); dismiss() } catch { app.report(error) }
                        }
                    }
                }
            }
        }
    }
}
