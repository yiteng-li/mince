import SwiftUI

/// S34 (mince+): a PDF report for a health professional, and CSV exports of totals and the raw diary.
struct ExportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let from: Day
    let to: Day
    @State var daily: [Day: Nutrients]
    let targets: DayTargets
    @State private var files: [URL] = []
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("From", value: from.title)
                    LabeledContent("To", value: to.title)
                }
                Section {
                    Button("PDF report") { Task { await make { [try pdf()] } } }
                    Button("Daily totals (CSV)") { Task { await make { [try totalsCSV()] } } }
                    Button("Every diary entry (CSV)") { Task { await make { [try await entriesCSV()] } } }
                }
                if working { ProgressView() }
            }
            .navigationTitle("Export")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: Binding(get: { !files.isEmpty }, set: { if !$0 { files = [] } })) { ShareSheet(items: files) }
            .task { if daily.isEmpty { daily = (try? await DiaryService().totals(from: from, to: to)) ?? [:] } }
        }
    }

    private var average: Nutrients {
        let logged = daily.values.filter { ($0["energy"] ?? 0) > 0 }
        guard !logged.isEmpty else { return [:] }
        return logged.reduce(into: Nutrients()) { $0 += $1 }.scaled(by: 1 / Double(logged.count))
    }

    private func make(_ build: () async throws -> [URL]) async {
        working = true
        defer { working = false }
        do { files = try await build() } catch { app.report(error) }
    }

    private func file(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mince-\(name)-\(from)-to-\(to)")
    }

    private func pdf() throws -> URL {
        let url = file("report").appendingPathExtension("pdf")
        let renderer = ImageRenderer(content: ReportPage(from: from, to: to, average: average, targets: targets, app: app).frame(width: 612))
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 612, height: max(size.height, 792)))
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return url
    }

    /// Quotes a CSV field when it contains a comma, quote or newline (quotes inside are doubled).
    private func csvField(_ s: String) -> String {
        guard s.contains(where: { ",\"\n".contains($0) }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func totalsCSV() throws -> URL {
        let keys = app.nutrients.map(\.key)
        var lines = ["date," + app.nutrients.map { csvField("\($0.name) (\($0.unit))") }.joined(separator: ",")]
        for day in daily.keys.sorted() {
            let n = daily[day]!.withDerived
            lines.append(day.rawValue + "," + keys.map { n[$0].map { String(format: "%.3f", $0) } ?? "" }.joined(separator: ","))
        }
        let url = file("daily-totals").appendingPathExtension("csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func entriesCSV() async throws -> URL {
        let rows = try await DiaryService().entries(from: from, to: to)
        var lines = ["date,time,group,kind,name,amount_g,energy_kcal,protein_g,carbs_g,fat_g,value,note"]
        for e in rows {
            let n = e.consumed
            let name = e.food?.name ?? e.exercise?.name ?? e.title ?? app.biometricType(id: e.biometricTypeId)?.name ?? ""
            lines.append([e.day.rawValue, e.loggedAt?.ISO8601Format() ?? "", app.group(id: e.groupId)?.name ?? "", e.kind.rawValue, name,
                          e.amountG.map { String($0) } ?? "", e.kind == .exercise ? String(-(e.energyKcal ?? 0)) : String(n[.energy]),
                          String(n[.protein]), String(n[.carbs]), String(n[.fat]), e.value.map { String($0) } ?? "", e.note ?? ""]
                .map(csvField).joined(separator: ","))
        }
        let url = file("diary").appendingPathExtension("csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// The printable report: averages vs targets for every nutrient with a target.
private struct ReportPage: View {
    let from: Day
    let to: Day
    let average: Nutrients
    let targets: DayTargets
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition report").font(.title.bold())
            Text("\(app.profile?.displayName ?? "mince user") · \(from.rawValue) to \(to.rawValue) · daily averages").font(.subheadline)
            Divider()
            let avg = average.withDerived
            ForEach(NutrientCategory.allCases) { cat in
                let rows = app.nutrients.filter { $0.category == cat && targets.goals[$0.key] != nil }
                if !rows.isEmpty {
                    Text(cat.title).font(.headline).padding(.top, 6)
                    ForEach(rows) { n in
                        let g = targets.goals[n.key]!
                        let t = g.min ?? g.max ?? 0
                        HStack {
                            Text(n.name).frame(width: 200, alignment: .leading)
                            Text(Units.amount(avg[n.key] ?? 0, unit: n.unit)).frame(width: 110, alignment: .trailing)
                            Text("target \(Units.amount(t, unit: n.unit))").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            Text(t > 0 ? "\(Int((avg[n.key] ?? 0) / t * 100))%" : "").frame(width: 60, alignment: .trailing)
                        }
                        .font(.caption)
                    }
                }
            }
            Text("Generated by mince. Food data: USDA FoodData Central and Open Food Facts (ODbL).").font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(.white)
    }
}
