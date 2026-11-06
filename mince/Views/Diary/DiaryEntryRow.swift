import SwiftUI

struct DiaryEntryRow: View {
    @Environment(AppModel.self) private var app
    let entry: DiaryEntry
    var showTime = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xxs) {
                    if entry.repeatRuleId != nil { Image(systemName: "repeat").font(.caption).foregroundStyle(Theme.Colors.textMuted).accessibilityLabel("Repeats") }
                    if entry.source == .health { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.Colors.danger).accessibilityLabel("From Apple Health") }
                    Text(title).font(Theme.Fonts.body).lineLimit(2)
                }
                if let subtitle { Text(subtitle).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted).lineLimit(3) }
                if showTime, let t = entry.loggedAt {
                    Text(t, style: .time).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.Fonts.label.monospacedDigit())
                    .foregroundStyle(entry.kind == .exercise ? Theme.Colors.success : Theme.Colors.text)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isWater: Bool { entry.kind == .quickAdd && entry.nutrients?.keys.sorted() == ["water"] }

    private var title: String {
        switch entry.kind {
        case .food: entry.food?.displayName ?? "Food"
        case .quickAdd: isWater ? "Water" : entry.title ?? "Quick add"
        case .exercise: entry.exercise?.name ?? entry.title ?? "Exercise"
        case .biometric: app.biometricType(id: entry.biometricTypeId)?.name ?? "Biometric"
        case .note: entry.note ?? ""
        }
    }

    private var subtitle: String? {
        switch entry.kind {
        case .food:
            let g = Units.amount(entry.amountG ?? 0, unit: "g")
            if let q = entry.servingQty, let s = entry.serving?.name, s != "g" {
                return "\(q.formatted(.number.precision(.fractionLength(0...2)))) × \(s) · \(g)"
            }
            return g
        case .exercise: return entry.minutes.map { "\(Int($0)) min" }
        case .quickAdd where isWater: return nil
        case .quickAdd:
            let n = entry.nutrients ?? [:]
            return "P \(Int(n[.protein]))g · C \(Int(n[.carbs]))g · F \(Int(n[.fat]))g"
        default: return nil
        }
    }

    private var trailing: String? {
        switch entry.kind {
        case .quickAdd where isWater: "\(Int(entry.nutrients?["water"] ?? 0)) mL"
        case .food, .quickAdd: Units.energy(entry.consumed[.energy], app.energyUnit)
        case .exercise: "−" + Units.energy(entry.energyKcal ?? 0, app.energyUnit)
        case .biometric: BiometricFormat.value(entry, type: app.biometricType(id: entry.biometricTypeId), units: app.unitSystem)
        case .note: nil
        }
    }
}

enum BiometricFormat {
    static func value(_ e: DiaryEntry, type: BiometricType?, units: UnitSystem) -> String {
        guard let v = e.value, let type else { return "" }
        switch type.valueKind {
        case .pair: return "\(Int(v))/\(Int(e.value2 ?? 0)) \(type.unit)"
        case .minutes: return "\(Int(v) / 60) h \(Int(v) % 60) m"
        case .scale17, .scale110: return "\(Int(v)) / \(type.valueKind == .scale17 ? 7 : 10)"
        case .number:
            if type.key == "weight" { return Units.weight(v, units) }
            if ["waist", "hips", "chest", "neck", "bicep", "thigh", "calf"].contains(type.key), units != .metric {
                return "\((v / Units.cmPerInch).formatted(.number.precision(.fractionLength(0...1)))) in"
            }
            return "\(v.formatted(.number.precision(.fractionLength(0...1)))) \(type.unit)"
        }
    }
}
