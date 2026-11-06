import Charts
import SwiftUI

@MainActor
@Observable
final class TrendsModel {
    var daily: [Day: Nutrients] = [:]
    var loading = false
    var error: String?

    func load(from: Day, to: Day) async {
        loading = true
        defer { loading = false }
        do {
            daily = try await DiaryService().totals(from: from, to: to)
            error = nil
        } catch {
            daily = [:]
            self.error = error.localizedDescription
        }
    }

    /// Average over days that have anything logged.
    var average: Nutrients {
        let logged = daily.values.filter { ($0["energy"] ?? 0) > 0 }
        guard !logged.isEmpty else { return [:] }
        return logged.reduce(into: Nutrients()) { $0 += $1 }.scaled(by: 1 / Double(logged.count))
    }
}

/// S23 / S24 / S25 / S34: averages vs targets over a range, charts, scores, export.
struct TrendsView: View {
    @Environment(AppModel.self) private var app
    @State private var model = TrendsModel()
    @State private var range = 7
    @State private var customFrom = Day.today.adding(days: -29)
    @State private var customTo = Day.today
    @State private var detail: Nutrient?
    @State private var exporting = false

    /// The scores the user picked, or the overall score if they haven't picked any.
    private var shownScores: [NutritionScore] {
        let picked = app.profile?.selectedScores ?? []
        return NutritionScore.all.filter { picked.isEmpty ? $0.id == "overall" : picked.contains($0.id) }
    }

    private var to: Day { range == 0 ? customTo : .today }
    private var from: Day { range == 0 ? customFrom : Day.today.adding(days: -(range - 1)) }

    var body: some View {
        let targets = app.targets(for: .today)
        let avg = model.average
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: Binding(get: { range }, set: { r in
                        if r == 7 || app.hasPlus { range = r } else { app.showPaywall = true }
                    })) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("Custom").tag(0)
                    }
                    .pickerStyle(.segmented)
                    if range == 0 {
                        DatePicker("From", selection: Binding(get: { customFrom.date }, set: { customFrom = Day($0) }), displayedComponents: .date)
                        DatePicker("To", selection: Binding(get: { customTo.date }, set: { customTo = Day($0) }), in: customFrom.date..., displayedComponents: .date)
                    }
                    if !app.hasPlus {
                        PlusRow(action: {}) { Text("Look back further than 7 days").font(Theme.Fonts.footnote) }
                    }
                }

                if let e = model.error {
                    Section { Text(e).foregroundStyle(Theme.Colors.danger) }
                }

                Section("Energy") {
                    EnergyChart(daily: model.daily, from: from, to: to, target: targets.energyTarget)
                        .frame(height: 180)
                    LabeledContent("Daily average", value: Units.energy(avg[.energy], app.energyUnit))
                    LabeledContent("Days logged", value: "\(model.daily.values.filter { ($0["energy"] ?? 0) > 0 }.count) of \(from.distance(to: to) + 1)")
                }

                Section("Average macros") { MacroBars(totals: avg, targets: targets) }

                if app.hasPlus {
                    Section("Scores") {
                        ForEach(shownScores) { score in
                            let value = score.score(totals: avg.withDerived, goals: targets.goals) ?? 0
                            NutrientBar(name: score.name, amount: Double(value), unit: "", target: 100, tint: Theme.Colors.success)
                        }
                    }
                    Section {
                        NavigationLink { SuggestionsView(totals: avg, goals: targets.goals) } label: { Label("What to eat more of", systemImage: "lightbulb") }
                        NavigationLink { CustomChartsView() } label: { Label("Custom charts", systemImage: "chart.line.uptrend.xyaxis") }
                        NavigationLink { BiometricChartsView() } label: { Label("Biometric charts", systemImage: "waveform.path.ecg") }
                    }
                } else {
                    Section {
                        PlusRow(action: {}) { Label("Nutrition scores", systemImage: "rosette") }
                        PlusRow(action: {}) { Label("Food suggestions", systemImage: "lightbulb") }
                        PlusRow(action: {}) { Label("Custom charts", systemImage: "chart.line.uptrend.xyaxis") }
                    }
                }

                NutrientTargetsView(totals: avg, goals: targets.goals) { detail = $0 }
            }
            .screenBackground()
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { app.requirePlus { exporting = true } } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Export report")
                }
            }
            .overlay { if model.loading && model.daily.isEmpty { ProgressView() } }
            .task(id: "\(from)-\(to)-\(app.diaryVersion)") { await model.load(from: from, to: to) }
            .refreshable { await model.load(from: from, to: to) }
            .sheet(item: $detail) { NutrientDetailView(nutrient: $0, from: from, to: to) }
            .sheet(isPresented: $exporting) { ExportView(from: from, to: to, daily: model.daily, targets: targets) }
        }
    }
}

struct EnergyChart: View {
    @Environment(AppModel.self) private var app
    let daily: [Day: Nutrients]
    let from: Day
    let to: Day
    let target: Double

    var body: some View {
        let days = (0...max(from.distance(to: to), 0)).map { from.adding(days: $0) }
        Chart {
            ForEach(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Energy", Units.energyValue(daily[d]?["energy"] ?? 0, app.energyUnit)))
                    .foregroundStyle(Theme.Colors.energy)
            }
            RuleMark(y: .value("Target", Units.energyValue(target, app.energyUnit)))
                .foregroundStyle(Theme.Colors.warning)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .top, alignment: .leading) { Text("Target").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted) }
        }
        .accessibilityLabel("Daily energy compared with your target")
    }
}

/// mince+: foods that fill the biggest gaps in the selected period.
struct SuggestionsView: View {
    @Environment(AppModel.self) private var app
    let totals: Nutrients
    let goals: [String: NutrientGoal]
    @State private var picks: [(NK, [Food])] = []
    @State private var loading = true
    @State private var logging: Food?

    var body: some View {
        List {
            if loading { ProgressView() }
            else if picks.isEmpty { Text("You're meeting your targets. Nice.").foregroundStyle(Theme.Colors.textMuted) }
            ForEach(picks, id: \.0) { key, foods in
                Section("More \(app.nutrient(key.rawValue)?.name.lowercased() ?? key.rawValue)") {
                    ForEach(foods.prefix(5)) { f in
                        Button { logging = f } label: { FoodResultRow(food: f) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Suggestions")
        .sheet(item: $logging) { f in NavigationStack { FoodLogDetail(food: f, groupId: nil) { logging = nil } } }
        .task {
            let gaps = NutritionScore.all[0].gaps(totals: totals.withDerived, goals: goals).prefix(4)
            var out: [(NK, [Food])] = []
            for k in gaps { out.append((k, (try? await FoodService().oracle(nutrient: k.rawValue, perKcal: true)) ?? [])) }
            picks = out
            loading = false
        }
    }
}
