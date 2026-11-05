import Foundation
import Supabase

/// Calls the Edge Functions that hold secrets: AI features, purchase verification, account deletion.
/// Server code: supabase/functions/*.
struct AIService {
    private var db: SupabaseClient { SupabaseService.shared }

    /// One food the model recognised, matched against the food database where possible.
    struct Item: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var grams: Double
        var foodId: UUID?
        var note: String?

        enum CodingKeys: String, CodingKey { case name, grams, foodId = "food_id", note }
        init(name: String, grams: Double, foodId: UUID? = nil, note: String? = nil) {
            (self.name, self.grams, self.foodId, self.note) = (name, grams, foodId, note)
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            grams = try c.decode(Double.self, forKey: .grams)
            foodId = try c.decodeIfPresent(UUID.self, forKey: .foodId)
            note = try c.decodeIfPresent(String.self, forKey: .note)
        }
    }

    struct ItemsResponse: Decodable { var items: [Item]; var suggestions: [Item]? }

    struct ImportedRecipe: Decodable {
        var name: String
        var servings: Double?
        var instructions: String?
        var ingredients: [Ingredient]
        struct Ingredient: Decodable, Hashable {
            var line: String
            var name: String
            var grams: Double?
            var foodId: UUID?
            enum CodingKeys: String, CodingKey { case line, name, grams, foodId = "food_id" }
        }
    }

    private func call<T: Decodable>(_ fn: String, body: some Encodable) async throws -> T {
        do {
            return try await db.functions.invoke(fn, options: FunctionInvokeOptions(body: body))
        } catch let FunctionsError.httpError(code, data) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            if code == 402 { throw AppError.goldRequired }
            throw AppError.message(message ?? "Something went wrong (\(code)). Try again.")
        }
    }

    /// Photo Log: uploads a resized JPEG, returns recognised items plus easy-to-miss extras (oil, butter, sauces).
    func recognise(photo jpeg: Data) async throws -> ItemsResponse {
        let path = "\(try SupabaseService.userId.uuidString.lowercased())/\(UUID().uuidString).jpg"
        try await db.storage.from("meal-photos").upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return try await call("photo-log", body: ["path": path])
    }

    /// Voice Log / Siri: free text ("two eggs and a slice of toast") to items.
    func parse(text: String) async throws -> ItemsResponse {
        try await call("voice-parse", body: ["text": text])
    }

    /// Recipe Importer: a URL or pasted recipe text.
    func importRecipe(url: String?, text: String?) async throws -> ImportedRecipe {
        struct Body: Encodable { let url: String?; let text: String? }
        return try await call("recipe-import", body: Body(url: url, text: text))
    }

    /// Coach: a few short suggestions from the user's own recent totals.
    func coach(days: Int) async throws -> [String] {
        struct R: Decodable { var tips: [String] }
        let r: R = try await call("coach", body: ["days": days])
        return r.tips
    }

    /// Sends a StoreKit 2 signed transaction for server verification. Returns the server's Gold status.
    func verifyPurchase(jws: String) async throws -> Bool {
        struct R: Decodable { var gold: Bool }
        let r: R = try await call("verify-purchase", body: ["jws": jws])
        return r.gold
    }

    /// Deletes the auth user; every table cascades and the storage folders are emptied.
    func deleteAccount() async throws {
        struct R: Decodable { var ok: Bool }
        let _: R = try await call("delete-account", body: ["confirm": "delete"])
    }
}
