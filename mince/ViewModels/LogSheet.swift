import Foundation

/// Every logging flow, opened from the plus menu, the diary, Siri or a deep link.
enum LogSheet: Identifiable, Hashable {
    case food(groupId: UUID?)
    case barcode(groupId: UUID?)
    case photo(groupId: UUID?)
    case voice(groupId: UUID?, text: String?)
    case quickAdd(groupId: UUID?)
    case exercise
    case biometric(typeKey: String?)
    case note(groupId: UUID?)
    case water
    case fasting
    case editEntry(DiaryEntry)
    case sharedFood(UUID)

    var id: String { "\(self)" }
}

/// One action in the plus menu. Order and visibility are saved in profiles.plus_menu.
enum PlusAction: String, CaseIterable, Identifiable {
    case food, barcode, photo, voice, quickAdd = "quick_add", exercise, biometric, weight, water, note, fast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "Food"
        case .barcode: "Scan barcode"
        case .photo: "Photo"
        case .voice: "Voice"
        case .quickAdd: "Quick add"
        case .exercise: "Exercise"
        case .biometric: "Biometric"
        case .weight: "Weight"
        case .water: "Water"
        case .note: "Note"
        case .fast: "Fast"
        }
    }
    var symbol: String {
        switch self {
        case .food: "magnifyingglass"
        case .barcode: "barcode.viewfinder"
        case .photo: "camera"
        case .voice: "mic"
        case .quickAdd: "bolt"
        case .exercise: "figure.run"
        case .biometric: "heart.text.square"
        case .weight: "scalemass"
        case .water: "drop"
        case .note: "note.text"
        case .fast: "timer"
        }
    }
    var needsPlus: Bool { [.photo, .voice, .fast].contains(self) }

    var sheet: LogSheet {
        switch self {
        case .food: .food(groupId: nil)
        case .barcode: .barcode(groupId: nil)
        case .photo: .photo(groupId: nil)
        case .voice: .voice(groupId: nil, text: nil)
        case .quickAdd: .quickAdd(groupId: nil)
        case .exercise: .exercise
        case .biometric: .biometric(typeKey: nil)
        case .weight: .biometric(typeKey: "weight")
        case .water: .water
        case .note: .note(groupId: nil)
        case .fast: .fasting
        }
    }

    static func ordered(_ saved: [String]) -> [PlusAction] {
        let picked = saved.compactMap(PlusAction.init(rawValue:))
        return picked.isEmpty ? allCases : picked
    }
}
