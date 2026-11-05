import SwiftUI
import UserNotifications

/// S17 (Gold): start, end, edit and schedule fasts.
struct FastingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var fasts: [Fast] = []
    @State private var schedules: [FastSchedule] = []
    @State private var targetHours = 16.0
    @State private var editing: Fast?
    @State private var addingSchedule = false
    @State private var loading = true

    private var open: Fast? { fasts.first { $0.isOpen } }

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: Theme.Space.md) {
                        FastRing(fast: open, now: ctx.date, targetHours: targetHours)
                        if open == nil {
                            Picker("Length", selection: $targetHours) {
                                ForEach([12.0, 14, 16, 18, 20, 24, 36], id: \.self) { Text("\(Int($0)) h").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Button("Start fast") { Task { await start() } }.buttonStyle(.minced)
                        } else {
                            Button("End fast") { Task { await end() } }.buttonStyle(.minced(.secondary))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(schedules) { s in
                    VStack(alignment: .leading) {
                        Text("\(s.targetMinutes / 60) h fast at \(String(format: "%02d:%02d", s.hour, s.minute))")
                        Text(RepeatRule.cadence(s.weekdays))
                            .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                .onDelete { idx in
                    let gone = idx.map { schedules[$0] }
                    schedules.remove(atOffsets: idx)
                    Task {
                        for s in gone { try? await GoldService().delete(s) }
                        await FastReminders.sync(schedules)
                    }
                }
                Button { addingSchedule = true } label: { Label("Add a schedule", systemImage: "calendar.badge.plus") }
            } header: { Text("Schedule") } footer: { Text("You'll get a reminder when a scheduled fast should start and when it's done.") }

            Section("History") {
                if loading { ProgressView() }
                else if fasts.filter({ !$0.isOpen }).isEmpty { Text("Finished fasts show up here.").foregroundStyle(Theme.Colors.textMuted) }
                ForEach(fasts.filter { !$0.isOpen }) { f in
                    Button { editing = f } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(f.startedAt, format: .dateTime.weekday().day().month().hour().minute())
                                Text("Goal \(f.targetMinutes / 60) h").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                            }
                            Spacer()
                            Text(Self.duration(f.elapsed())).monospacedDigit()
                                .foregroundStyle(f.elapsed() >= f.target ? Theme.Colors.success : Theme.Colors.text)
                        }
                    }
                    .foregroundStyle(Theme.Colors.text)
                }
                .onDelete { idx in
                    let done = fasts.filter { !$0.isOpen }
                    let gone = idx.map { done[$0] }
                    fasts.removeAll { f in gone.contains { $0.id == f.id } }
                    Task { for f in gone { try? await GoldService().delete(f) } }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Fasting")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .task { await load() }
        .sheet(item: $editing) { f in FastEditor(fast: f) { await load() } }
        .sheet(isPresented: $addingSchedule) { FastScheduleEditor { await load(); await FastReminders.sync(schedules) } }
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return "\(m / 60)h \(String(format: "%02d", m % 60))m"
    }

    private func load() async {
        do {
            async let f = GoldService().fasts()
            async let s = GoldService().fastSchedules()
            (fasts, schedules) = try await (f, s)
        } catch { app.report(error) }
        loading = false
    }

    private func start() async {
        guard let uid = app.userId else { return }
        let fast = Fast(userId: uid, startedAt: Date(), targetMinutes: Int(targetHours * 60))
        do {
            try await GoldService().save(fast)
            fasts.insert(fast, at: 0)
            await FastReminders.notifyEnd(of: fast)
            app.diaryChanged()
        } catch { app.report(error) }
    }

    private func end() async {
        guard var f = open else { return }
        f.endedAt = Date()
        do {
            try await GoldService().save(f)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["fast-end-\(f.id)"])
            await load()
            app.diaryChanged()
        } catch { app.report(error) }
    }
}

struct FastRing: View {
    let fast: Fast?
    let now: Date
    let targetHours: Double

    var body: some View {
        let target = fast?.target ?? targetHours * 3600
        let elapsed = fast?.elapsed(now: now) ?? 0
        ZStack {
            Circle().stroke(Theme.Colors.track, lineWidth: Theme.Layout.ringLine)
            Circle().trim(from: 0, to: min(elapsed / target, 1))
                .stroke(elapsed >= target ? Theme.Colors.success : Theme.Colors.accent, style: StrokeStyle(lineWidth: Theme.Layout.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack {
                Text(fast == nil ? "Not fasting" : FastingView.duration(elapsed)).font(Theme.Fonts.metric)
                if let fast {
                    Text(elapsed >= target ? "Goal reached" : "\(FastingView.duration(target - elapsed)) to go")
                        .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    Text("Ends \(fast.startedAt.addingTimeInterval(target).formatted(date: .omitted, time: .shortened))")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
        .frame(width: Theme.Layout.ringSize, height: Theme.Layout.ringSize)
        .accessibilityElement(children: .combine)
    }
}

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
                    Button("Save") { Task { do { try await GoldService().save(fast); await onSave(); dismiss() } catch { app.report(error) } } }
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
                            do { try await GoldService().save(s); await onSave(); dismiss() } catch { app.report(error) }
                        }
                    }
                }
            }
        }
    }
}

/// Local notifications for fasts (no server jobs needed).
enum FastReminders {
    static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func notifyEnd(of fast: Fast) async {
        guard await authorize() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Fast complete"
        content.body = "You reached your \(fast.targetMinutes / 60)-hour goal."
        let fireAt = fast.startedAt.addingTimeInterval(fast.target).timeIntervalSinceNow
        guard fireAt > 0 else { return }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fast-end-\(fast.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireAt, repeats: false)))
    }

    /// One repeating reminder per scheduled weekday.
    static func sync(_ schedules: [FastSchedule]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("fast-schedule-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !schedules.isEmpty, await authorize() else { return }
        for s in schedules {
            for d in s.weekdays {
                let content = UNMutableNotificationContent()
                content.title = "Time to start your fast"
                content.body = "\(s.targetMinutes / 60)-hour fast. Open mince to start the timer."
                var when = DateComponents()
                (when.weekday, when.hour, when.minute) = (d + 1, s.hour, s.minute)
                try? await center.add(UNNotificationRequest(identifier: "fast-schedule-\(s.id)-\(d)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
            }
        }
    }
}
