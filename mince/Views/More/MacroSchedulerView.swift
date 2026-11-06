import SwiftUI

/// S28 (mince+): different macro templates per weekday.
struct MacroSchedulerView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: MacroTemplate?
    @State private var creating = false

    var body: some View {
        List {
            Section("Templates") {
                ForEach(app.macroTemplates) { t in
                    Button { editing = t } label: {
                        VStack(alignment: .leading) {
                            Text(t.name).foregroundStyle(Theme.Colors.text)
                            Text(summary(t)).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
                .onDelete { idx in
                    let gone = idx.map { app.macroTemplates[$0] }
                    Task { for t in gone { try? await ProfileService().delete(template: t) }; await app.refreshMacroSchedule() }
                }
                Button { creating = true } label: { Label("New template", systemImage: "plus") }
            }
            Section {
                ForEach(0..<7) { d in
                    Picker(Calendar.current.weekdaySymbols[d], selection: Binding(get: { app.macroSchedule[d] }, set: { id in
                        Task {
                            do { try await ProfileService().setSchedule(weekday: d, templateId: id); await app.refreshMacroSchedule() } catch { app.report(error) }
                        }
                    })) {
                        Text("Default targets").tag(UUID?.none)
                        ForEach(app.macroTemplates) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            } header: { Text("Week") } footer: { Text("Days without a template use your normal targets.") }
        }
        .navigationTitle("Macro Scheduler")
        .task { await app.refreshMacroSchedule() }
        .sheet(item: $editing) { MacroTemplateEditor(template: $0) }
        .sheet(isPresented: $creating) { MacroTemplateEditor(template: nil) }
    }

    private func summary(_ t: MacroTemplate) -> String {
        [t.energyKcal.map { "\($0) kcal" }, t.proteinG.map { "P \(Int($0))g" }, t.carbsG.map { "C \(Int($0))g" }, t.fatG.map { "F \(Int($0))g" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct MacroTemplateEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let template: MacroTemplate?
    @State private var name = ""
    @State private var kcal: Double?
    @State private var p: Double?
    @State private var c: Double?
    @State private var f: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Training day)", text: $name)
                NumberField(title: "Energy", value: $kcal, unit: "kcal")
                NumberField(title: "Protein", value: $p, unit: "g")
                NumberField(title: "Carbs", value: $c, unit: "g")
                NumberField(title: "Fat", value: $f, unit: "g")
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            var t = template ?? MacroTemplate(userId: uid, name: name)
                            t.name = name; t.energyKcal = kcal.map { Int($0) }; t.proteinG = p; t.carbsG = c; t.fatG = f
                            do { try await ProfileService().save(template: t); await app.refreshMacroSchedule(); dismiss() } catch { app.report(error) }
                        }
                    }
                    .disabled(name.isEmpty || (kcal.map { $0 < 500 } ?? false))
                }
            }
            .onAppear {
                guard let t = template else { return }
                (name, kcal, p, c, f) = (t.name, t.energyKcal.map(Double.init), t.proteinG, t.carbsG, t.fatG)
            }
        }
    }
}
