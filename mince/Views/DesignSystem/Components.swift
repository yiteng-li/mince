import SwiftUI

// Screen-level building blocks shared by several screens. Specs: replica/design/components.md.

struct DateNavigator: View {
    @Binding var day: Day
    var completed = false
    @State private var showCalendar = false

    var body: some View {
        HStack {
            // Borderless: inside a List row, default-style buttons all fire on any tap in the row.
            Button { day = day.adding(days: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous day")
            Spacer()
            Button { showCalendar = true } label: {
                HStack(spacing: Theme.Space.xxs) {
                    Text(day.title).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.text)
                    if completed { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success).accessibilityLabel("Day complete") }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens a calendar")
            Spacer()
            Button { day = day.adding(days: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next day")
        }
        .sheet(isPresented: $showCalendar) {
            NavigationStack {
                DatePicker("Day", selection: Binding(get: { day.date }, set: { day = Day($0); showCalendar = false }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Today") { day = .today; showCalendar = false } }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}

/// Protein / carbs (or net carbs) / fat bars.
struct MacroBars: View {
    let totals: Nutrients
    let targets: DayTargets

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            NutrientBar(name: "Protein", amount: totals[.protein], unit: "g", target: targets.goal(.protein)?.min, tint: Theme.Colors.protein)
            if let net = targets.goal(.netCarbs) {
                NutrientBar(name: "Net carbs", amount: totals.withDerived[.netCarbs], unit: "g", target: net.max, max: net.max, tint: Theme.Colors.carbs)
            } else {
                NutrientBar(name: "Carbs", amount: totals[.carbs], unit: "g", target: targets.goal(.carbs)?.min, tint: Theme.Colors.carbs)
            }
            NutrientBar(name: "Fat", amount: totals[.fat], unit: "g", target: targets.goal(.fat)?.min, tint: Theme.Colors.fat)
        }
    }
}

struct EnergySummaryCard: View {
    @Environment(AppModel.self) private var app
    let balance: EnergyBalance
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            // Ring beside the numbers when it fits; above them at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Theme.Space.md) { ring; totals }
                VStack(alignment: .leading, spacing: Theme.Space.sm) { ring.frame(maxWidth: .infinity); totals }
            }
            Button { withAnimation(Theme.Motion.fast) { expanded.toggle() } } label: {
                HStack {
                    Text("How burned adds up")
                    Spacer()
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(minHeight: Theme.Layout.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .font(Theme.Fonts.footnote)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(spacing: Theme.Space.xxs) {
                    row("Resting (BMR)", balance.bmr)
                    row("Daily activity", balance.baseline)
                    row("Exercise", balance.exercise)
                }
            }
        }
        .card()
    }

    private var ring: some View {
        EnergyRing(consumed: Units.energyValue(balance.consumed, app.energyUnit), target: Units.energyValue(balance.target, app.energyUnit))
            .frame(width: 120, height: 120)
            .scaleEffect(0.75)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)   // fixed-size graphic; the same numbers are in the rows beside it
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            row("Eaten", balance.consumed)
            row("Burned", balance.burned)
            row("Target", balance.target)
        }
    }

    private func row(_ title: String, _ kcal: Double) -> some View {
        let label = Text(title).foregroundStyle(Theme.Colors.textMuted)
        let value = Text(Units.energy(kcal, app.energyUnit)).monospacedDigit()
        return ViewThatFits(in: .horizontal) {
            HStack { label; Spacer(); value }
            VStack(alignment: .leading, spacing: 0) { label; value }
        }
        .font(Theme.Fonts.label)
    }
}

/// Every nutrient with a target, grouped like a nutrition label. Tapping a row calls `onSelect`.
struct NutrientTargetsView: View {
    @Environment(AppModel.self) private var app
    let totals: Nutrients
    let goals: [String: NutrientGoal]
    var showAll = false
    var onSelect: ((Nutrient) -> Void)?

    var body: some View {
        let t = totals.withDerived
        ForEach(NutrientCategory.allCases) { category in
            let rows = app.nutrients.filter { $0.category == category && (showAll || goals[$0.key] != nil || (t[$0.key] ?? 0) > 0) }
            if !rows.isEmpty {
                Section(category.title) {
                    ForEach(rows) { n in
                        let goal = goals[n.key]
                        Button { onSelect?(n) } label: {
                            NutrientBar(name: n.name, amount: t[n.key] ?? 0, unit: n.unit, target: goal?.min ?? goal?.max, max: goal?.max,
                                        tint: tint(n.key))
                        }
                        .buttonStyle(.plain)
                        .disabled(onSelect == nil)
                    }
                }
            }
        }
    }

    private func tint(_ key: String) -> Color {
        switch key {
        case "protein": Theme.Colors.protein
        case "carbs", "net_carbs": Theme.Colors.carbs
        case "fat": Theme.Colors.fat
        case "energy": Theme.Colors.energy
        default: Theme.Colors.accent
        }
    }
}

/// A decimal text field bound to an optional Double.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var unit: String?

    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Space.xxs) {
                TextField("0", text: $text, selection: $selection)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    // Select the number on focus so typing replaces it (no "01" when you meant "0").
                    .onChange(of: focused) { _, on in if on { selection = TextSelection(range: text.startIndex..<text.endIndex) } }
                    .onChange(of: text) { _, new in value = Double(new.replacingOccurrences(of: ",", with: ".")) }
                if let unit { Text(unit).foregroundStyle(Theme.Colors.textMuted) }
            }
        } label: {
            Text(title)
        }
        .onAppear { text = value.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "" }
        .onChange(of: value) { _, new in
            guard !focused else { return }
            text = new.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
        }
    }
}

/// Loading / error / content wrapper for screens that fetch.
struct LoadingView<Content: View>: View {
    let isLoading: Bool
    let error: String?
    var retry: (() async -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let error {
            EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load", hint: error, actionTitle: retry == nil ? nil : "Try again") {
                Task { await retry?() }
            }
        } else if isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else {
            content()
        }
    }
}

struct Toast: Equatable {
    var message: String
    var undo: (() -> Void)?
    static func == (a: Toast, b: Toast) -> Bool { a.message == b.message }
}

extension View {
    /// Bottom toast with optional Undo, auto-dismissed after 4 seconds and announced to VoiceOver.
    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .bottom) {
            if let t = toast.wrappedValue {
                HStack {
                    Text(t.message).font(Theme.Fonts.label)
                    Spacer()
                    if let undo = t.undo {
                        Button("Undo") { undo(); toast.wrappedValue = nil }.font(Theme.Fonts.heading)
                    }
                }
                .padding(Theme.Space.md)
                .foregroundStyle(Theme.Colors.surface)
                .background(Theme.Colors.text, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .padding(Theme.Space.md)
                .padding(.bottom, 56)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t.message) {
                    UIAccessibility.post(notification: .announcement, argument: t.message)
                    try? await Task.sleep(for: .seconds(4))
                    toast.wrappedValue = nil
                }
            }
        }
        .animation(Theme.Motion.base, value: toast.wrappedValue)
    }

    /// Standard screen background.
    func screenBackground() -> some View { scrollContentBackground(.hidden).background(Theme.Colors.bg) }
}

/// A row with a Gold badge that opens the paywall for Basic users.
struct GoldRow<Label: View>: View {
    @Environment(AppModel.self) private var app
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            app.requireGold(action)
        } label: {
            HStack {
                label()
                Spacer()
                if !app.isGold { GoldBadge() }
            }
        }
    }
}
