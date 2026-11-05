import Charts
import SwiftUI

/// Gold: user-defined charts of any nutrient or biometric, up to two series (dual axis), pinnable to the dashboard.
struct CustomChartsView: View {
    @Environment(AppModel.self) private var app
    @State private var charts: [CustomChart] = []
    @State private var editing: CustomChart?
    @State private var creating = false

    var body: some View {
        List {
            if charts.isEmpty {
                EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: "No custom charts",
                               hint: "Plot any nutrient against any biometric, like magnesium and sleep.").listRowBackground(Color.clear)
            }
            ForEach(charts) { c in
                CustomChartCard(chart: c)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    .contextMenu {
                        Button("Edit") { editing = c }
                        Button(c.pinned ? "Unpin from dashboard" : "Pin to dashboard") {
                            var x = c; x.pinned.toggle()
                            Task { try? await GoldService().save(x); await load() }
                        }
                        Button("Delete", role: .destructive) { Task { try? await GoldService().delete(c); await load() } }
                    }
            }
        }
        .screenBackground()
        .navigationTitle("Custom charts")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("New chart") }
        .task { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { CustomChartEditor(chart: $0) }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { CustomChartEditor(chart: nil) }
    }

    private func load() async { charts = (try? await GoldService().charts()) ?? [] }
}

struct CustomChartCard: View {
    @Environment(AppModel.self) private var app
    let chart: CustomChart
    @State private var points: [String: [(Date, Double)]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text(chart.title).font(Theme.Fonts.heading)
                Spacer()
                if chart.pinned { Image(systemName: "pin.fill").foregroundStyle(Theme.Colors.textMuted).accessibilityLabel("Pinned") }
            }
            let series = chart.series
            if points.values.allSatisfy(\.isEmpty) {
                Text("No data in the last \(chart.rangeDays) days.").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            } else {
                // Second series is normalised onto the first one's scale so both read on one plot.
                let first = points[series[0].id] ?? []
                let scale = scaleFactor(first.map(\.1), (series.count > 1 ? points[series[1].id] : nil)?.map(\.1) ?? [])
                Chart {
                    ForEach(series.indices, id: \.self) { i in
                        let s = series[i]
                        ForEach(Array((points[s.id] ?? []).enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("Day", p.0, unit: .day), y: .value(label(s), i == 0 ? p.1 : p.1 * scale), series: .value("Series", label(s)))
                                .foregroundStyle(by: .value("Series", label(s)))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartForegroundStyleScale(range: [Theme.Colors.accent, Theme.Colors.fat])
                .frame(height: 160)
                if series.count > 1 {
                    Text("\(label(series[1])) is scaled ×\(scale.formatted(.number.precision(.significantDigits(2)))) to share the axis.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
        .card()
        .task(id: chart) { await load() }
    }

    private func label(_ s: ChartSeries) -> String {
        s.type == .nutrient ? (app.nutrient(s.key)?.name ?? s.key) : (app.biometricTypes.first { $0.key == s.key }?.name ?? s.key)
    }

    private func scaleFactor(_ a: [Double], _ b: [Double]) -> Double {
        guard let ma = a.max(), let mb = b.max(), mb > 0 else { return 1 }
        return ma / mb
    }

    private func load() async {
        let from = Day.today.adding(days: -(chart.rangeDays - 1))
        var out: [String: [(Date, Double)]] = [:]
        if chart.series.contains(where: { $0.type == .nutrient }) {
            let totals = (try? await DiaryService().totals(from: from, to: .today)) ?? [:]
            for s in chart.series where s.type == .nutrient {
                out[s.id] = totals.keys.sorted().map { ($0.date, totals[$0]?.withDerived[s.key] ?? 0) }
            }
        }
        for s in chart.series where s.type == .biometric {
            guard let t = app.biometricTypes.first(where: { $0.key == s.key }) else { continue }
            let rows = (try? await DiaryService().entries(from: from, to: .today, kind: .biometric, biometricTypeId: t.id)) ?? []
            out[s.id] = rows.map { ($0.loggedAt ?? $0.day.date, $0.value ?? 0) }
        }
        points = out
    }
}

struct CustomChartEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let chart: CustomChart?
    @State private var title = ""
    @State private var first = "nutrient:energy"
    @State private var second = ""
    @State private var range = 30
    @State private var pinned = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Series", selection: $first) { options }
                Picker("Compare with", selection: $second) {
                    Text("Nothing").tag("")
                    options
                }
                Picker("Range", selection: $range) {
                    ForEach([7, 30, 90, 180, 365], id: \.self) { Text("\($0) days").tag($0) }
                }
                Toggle("Pin to dashboard", isOn: $pinned)
            }
            .navigationTitle(chart == nil ? "New chart" : "Edit chart")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(title.isEmpty) }
            }
            .onAppear {
                guard let chart else { return }
                title = chart.title
                first = chart.series.first?.id ?? first
                second = chart.series.count > 1 ? chart.series[1].id : ""
                range = chart.rangeDays
                pinned = chart.pinned
            }
        }
    }

    @ViewBuilder private var options: some View {
        Section("Nutrients") { ForEach(app.nutrients) { Text($0.name).tag("nutrient:\($0.key)") } }
        Section("Biometrics") { ForEach(app.biometricTypes) { Text($0.name).tag("biometric:\($0.key)") } }
    }

    private func parse(_ id: String) -> ChartSeries? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = ChartSeries.Kind(rawValue: parts[0]) else { return nil }
        return ChartSeries(type: kind, key: parts[1])
    }

    private func save() async {
        guard let uid = app.userId, let s1 = parse(first) else { return }
        var c = chart ?? CustomChart(userId: uid, title: title, series: [])
        c.title = title
        c.series = [s1] + [parse(second)].compactMap { $0 }
        c.rangeDays = range
        c.pinned = pinned
        do { try await GoldService().save(c); dismiss() } catch { app.report(error) }
    }
}

/// Any biometric over time, including Health time series like glucose (CGM) and HRV.
struct BiometricChartsView: View {
    @Environment(AppModel.self) private var app
    @State private var type: BiometricType?
    @State private var rows: [DiaryEntry] = []
    @State private var days = 30

    var body: some View {
        List {
            Picker("Metric", selection: $type) {
                Text("Choose").tag(BiometricType?.none)
                ForEach(app.biometricTypes) { Text($0.name).tag(BiometricType?.some($0)) }
            }
            Picker("Range", selection: $days) { ForEach([7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) } }.pickerStyle(.segmented)
            if let type {
                if rows.isEmpty {
                    Text("No \(type.name.lowercased()) logged in this range.").foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Chart(rows) { e in
                        LineMark(x: .value("Time", e.loggedAt ?? e.day.date), y: .value(type.name, display(e, type)))
                        if let v2 = e.value2 {
                            LineMark(x: .value("Time", e.loggedAt ?? e.day.date), y: .value("Second", v2)).foregroundStyle(Theme.Colors.fat)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    let values = rows.map { display($0, type) }
                    LabeledContent("Average", value: (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(0...1))))
                    LabeledContent("Range", value: "\(values.min()!.formatted(.number.precision(.fractionLength(0...1)))) – \(values.max()!.formatted(.number.precision(.fractionLength(0...1))))")
                }
            }
        }
        .navigationTitle("Biometrics")
        .task(id: "\(type?.id.uuidString ?? "")-\(days)") {
            guard let type else { return }
            rows = (try? await DiaryService().entries(from: Day.today.adding(days: -(days - 1)), to: .today, kind: .biometric, biometricTypeId: type.id)) ?? []
        }
        .onAppear { if type == nil { type = app.biometricType("weight") } }
    }

    private func display(_ e: DiaryEntry, _ t: BiometricType) -> Double {
        t.key == "weight" ? Units.weightValue(e.value ?? 0, app.unitSystem) : (e.value ?? 0)
    }
}
