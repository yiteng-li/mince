import Foundation

/// Extension point for a future AI photo-based calorie estimation feature
/// (explicitly out of scope for now).
struct FoodPhotoEstimate {
    var foodName: String
    var estimatedCalories: Double
    var confidence: Double // 0...1
}

protocol FoodPhotoEstimationService {
    func estimate(imageData: Data) async throws -> FoodPhotoEstimate
}

/// Fake implementation so the rest of the app can be wired against the
/// protocol before real photo estimation exists.
struct MockFoodPhotoEstimationService: FoodPhotoEstimationService {
    func estimate(imageData: Data) async throws -> FoodPhotoEstimate {
        FoodPhotoEstimate(foodName: "Mock food", estimatedCalories: 250, confidence: 0.5)
    }
}
