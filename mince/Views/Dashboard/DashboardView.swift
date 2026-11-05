import Charts
import SwiftUI

/// S04: today at a glance.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var entries: [DiaryEntry] = []
    @State private var streak = 0
    @State private var weights: [DiaryEntry] = []
    @State private var openFast: Fast?
    @State private var pinned: [CustomChart] = []
    @State private var tips: [String] = []
    @State private var loadingTips = false

    var body: some View {
        let day = Day.today
        let targets = app.targets(for: day)
        let consumed = entries.reduce(into: Nutrients()) { $0 += $1.consumed }
        let exercise = entries.filter { $0.kind == .exercise }.compactMap(\.energyKcal).reduce(0, +)
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    if let name = app.profile?.displayName, !name.isEmpty {
                        Text("Hi, \(name)").font(Theme.Fonts.title).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    EnergySummaryCard(balance: EnergyBalance(consumed: consumed[.energy], exercise: exercise, targets: targets))
                    MacroBars(totals: consumed, targets: targets).card()

                    HStack(spacing: Theme.Space.md) {
                        statTile(title: "Streak", value: "\(streak) day\(streak == 1 ? "" : "s")", symbol: "flame.fill")
                        statTile(title: "Water", value: "\(Int(consumed[.water])) mL", symbol: "drop.fill")
                    }

                    if let openFast {
                        Button { app.open(.fasting) } label: {
                            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                                HStack {
                                    Label("Fasting", systemImage: "timer").font(Theme.Fonts.heading)
                                    Spacer()
                                    Text("\(FastingView.duration(openFast.elapsed(now: ctx.date))) of \(openFast.targetMinutes / 60) h").monospacedDigit()
                                }
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }

                    scoresCard(totals: consumed, goals: targets.goals)
                    weightCard
                    ForEach(pinned) { CustomChartCard(chart: $0) }
                    coachCard
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .navigationTitle("Today")
            .toolbar { ToolbarItem(placement: .primaryAction) { PlusButton() } }
            .refreshable { await load() }
            .task(id: app.diaryVersion) { await load() }
        }
    }

    private func statTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Label(title, systemImage: symbol).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            Text(value).font(Theme.Fonts.title.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func scoresCard(totals: Nutrients, goals: [String: NutrientGoal]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Nutrition scores").font(Theme.Fonts.heading)
                Spacer()
                if !app.isGold { GoldBadge() }
            }
            if app.isGold {
                let ids = app.profile?.selectedScores.isEmpty == false ? app.profile!.selectedScores : ["overall", "vitamins", "minerals"]
                ForEach(NutritionScore.all.filter { ids.contains($0.id) }) { s in
                    let value = s.score(totals: totals.withDerived, goals: goals)
                    NutrientBar(name: s.name, amount: Double(value ?? 0), unit: "", target: 100, tint: Theme.Colors.success)
                }
                NavigationLink("Choose scores") { ScoresPickerView() }.font(Theme.Fonts.label)
            } else {
                Button("See how today scores for vitamins, minerals, heart and more") { app.showPaywall = true }
                    .font(Theme.Fonts.label)
            }
        }
        .card()
    }

    @ViewBuilder private var weightCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Weight").font(Theme.Fonts.heading)
                Spacer()
                if let w = app.currentWeightKg { Text(Units.weight(w, app.unitSystem)).monospacedDigit() }
                Button { app.open(.biometric(typeKey: "weight")) } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Log weight")
            }
            if weights.count < 2 {
                Text("Log your weight a few times to see the trend.").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            } else {
                Chart(weights) { e in
                    LineMark(x: .value("Day", e.day.date), y: .value("Weight", Units.weightValue(e.value ?? 0, app.unitSystem)))
                        .foregroundStyle(Theme.Colors.accent)
                    PointMark(x: .value("Day", e.day.date), y: .value("Weight", Units.weightValue(e.value ?? 0, app.unitSystem)))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                .accessibilityLabel("Weight over the last \(app.isGold ? 90 : 7) days")
            }
        }
        .card()
    }

    @ViewBuilder private var coachCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Label("Coach", systemImage: "sparkles").font(Theme.Fonts.heading)
                Spacer()
                if !app.isGold { GoldBadge() }
            }
            if tips.isEmpty {
                Button(loadingTips ? "Thinking…" : "Get suggestions from your last week") {
                    app.requireGold {
                        Task {
                            loadingTips = true
                            defer { loadingTips = false }
                            do { tips = try await AIService().coach(days: 7) } catch { app.report(error) }
                        }
                    }
                }
                .disabled(loadingTips)
            }
            ForEach(tips, id: \.self) { Text("• \($0)").font(Theme.Fonts.body) }
        }
        .card()
    }

    private func load() async {
        async let e = DiaryService().entries(on: .today)
        async let done = DiaryService().completedDays(since: Day.today.adding(days: -400))
        entries = (try? await e) ?? entries
        streak = DiaryService.streak(completed: (try? await done) ?? [])
        if let w = app.biometricType("weight") {
            weights = (try? await DiaryService().entries(from: Day.today.adding(days: app.isGold ? -90 : -6), to: .today, kind: .biometric, biometricTypeId: w.id)) ?? []
        }
        if app.isGold {
            openFast = (try? await GoldService().fasts(limit: 1))?.first { $0.isOpen }
            pinned = ((try? await GoldService().charts()) ?? []).filter(\.pinned)
        }
    }
}

/// Gold: pick up to eight nutrition scores.
struct ScoresPickerView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List(NutritionScore.all) { s in
            let selected = app.profile?.selectedScores.contains(s.id) ?? false
            Button {
                guard var p = app.profile else { return }
                if selected { p.selectedScores.removeAll { $0 == s.id } }
                else if p.selectedScores.count < NutritionScore.maxSelected { p.selectedScores.append(s.id) }
                Task { await app.saveProfile(p) }
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(s.name).foregroundStyle(Theme.Colors.text)
                        Text(s.summary).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    }
                    Spacer()
                    if selected { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .navigationTitle("Scores (up to \(NutritionScore.maxSelected))")
    }
}
