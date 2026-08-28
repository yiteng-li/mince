import Foundation

/// Rollup of a day's diary entries. Not a DB table — computed client-side
/// from `DiaryEntryWithFood` so it always reflects each food's latest data.
struct MacroTotals: Equatable {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    // A couple of key micros worth surfacing on the diary screen; extend
    // this struct (and the sum below) with more as your UI needs them.
    var fiberG: Double = 0
    var sodiumMg: Double = 0

    // TODO: implement the real rollup. For each entry, scale the food's
    // per-100g values by (entry.quantityG / 100) and sum across entries.
    static func from(_ entries: [DiaryEntryWithFood]) -> MacroTotals {
        MacroTotals()
    }
}
