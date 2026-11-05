import Foundation

/// Converts stored metric values to the user's display units and back.
enum Units {
    static let lbPerKg = 2.2046226218
    static let cmPerInch = 2.54
    static let kjPerKcal = 4.184

    static func weight(_ kg: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric: return "\(kg.formatted(.number.precision(.fractionLength(0...1)))) kg"
        case .imperial: return "\((kg * lbPerKg).formatted(.number.precision(.fractionLength(0...1)))) lb"
        case .uk:
            let totalLb = (kg * lbPerKg * 10).rounded() / 10   // round first so 13.96 lb never shows as "14 lb"
            let st = Int(totalLb / 14)
            let lb = totalLb - Double(st) * 14
            return "\(st) st \(lb.formatted(.number.precision(.fractionLength(0...1)))) lb"
        }
    }

    /// The number shown in a weight field (kg or lb; UK users type pounds too).
    static func weightValue(_ kg: Double, _ system: UnitSystem) -> Double { system == .metric ? kg : kg * lbPerKg }
    static func weightKg(fromDisplay value: Double, _ system: UnitSystem) -> Double { system == .metric ? value : value / lbPerKg }
    static func weightUnit(_ system: UnitSystem) -> String { system == .metric ? "kg" : "lb" }

    static func height(_ cm: Double, _ system: UnitSystem) -> String {
        guard system != .metric else { return "\(Int(cm.rounded())) cm" }
        let inches = Int((cm / cmPerInch).rounded())
        return "\(inches / 12) ft \(inches % 12) in"
    }

    static func energy(_ kcal: Double, _ unit: EnergyUnit) -> String {
        let v = unit == .kj ? kcal * kjPerKcal : kcal
        return "\(Int(v.rounded()).formatted()) \(unit == .kj ? "kJ" : "kcal")"
    }

    static func energyValue(_ kcal: Double, _ unit: EnergyUnit) -> Double { unit == .kj ? kcal * kjPerKcal : kcal }

    /// "12.5 g", "850 mg", "2.4 mcg", sized to the magnitude.
    static func amount(_ value: Double, unit: String) -> String {
        let digits = value >= 100 ? 0 : value >= 10 ? 1 : value >= 1 ? 1 : 2
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit)"
    }
}
