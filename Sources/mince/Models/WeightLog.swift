import Foundation

struct WeightLog: Identifiable, Codable, Hashable {
    let id: UUID = UUID()
    var userId: UUID
    /// yyyy-MM-dd — see the note on `UserProfile.dateOfBirth`.
    var loggedOn: String
    var weightKg: Double
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case loggedOn = "logged_on"
        case weightKg = "weight_kg"
        case createdAt = "created_at"
    }
}
