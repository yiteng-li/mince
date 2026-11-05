import Foundation

/// Open Food Facts (ODbL): free, keyless barcode and branded-product data.
/// Results become the user's own foods when picked, so nothing is written to the shared database.
struct OpenFoodFactsService {
    private static let userAgent = "mince-ios/1.0"

    struct Product: Decodable {
        var code: String?
        var productName: String?
        var brands: String?
        var servingSize: String?
        var servingQuantity: Double?
        var nutriments: [String: JSONNumber]?

        enum CodingKeys: String, CodingKey {
            case code, productName = "product_name", brands, servingSize = "serving_size"
            case servingQuantity = "serving_quantity", nutriments
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decodeIfPresent(String.self, forKey: .code)
            productName = try c.decodeIfPresent(String.self, forKey: .productName)
            brands = try c.decodeIfPresent(String.self, forKey: .brands)
            servingSize = try c.decodeIfPresent(String.self, forKey: .servingSize)
            servingQuantity = try? c.decodeIfPresent(JSONNumber.self, forKey: .servingQuantity)?.value
            nutriments = try? c.decodeIfPresent([String: JSONNumber].self, forKey: .nutriments)
        }
    }

    /// OFF mixes numbers and numeric strings; anything else decodes as nil.
    struct JSONNumber: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d } else if let s = try? c.decode(String.self) { value = Double(s) } else { value = nil }
        }
    }

    /// OFF `<name>_100g` field -> (mince key, factor from OFF's unit to ours). OFF stores minerals/vitamins in grams.
    static let fieldMap: [String: (String, Double)] = [
        "energy-kcal": ("energy", 1), "proteins": ("protein", 1), "carbohydrates": ("carbs", 1), "fat": ("fat", 1),
        "fiber": ("fiber", 1), "sugars": ("sugars", 1), "added-sugars": ("added_sugars", 1), "starch": ("starch", 1),
        "saturated-fat": ("saturated_fat", 1), "monounsaturated-fat": ("monounsaturated_fat", 1),
        "polyunsaturated-fat": ("polyunsaturated_fat", 1), "trans-fat": ("trans_fat", 1), "cholesterol": ("cholesterol", 1000),
        "omega-3-fat": ("omega_3", 1), "omega-6-fat": ("omega_6", 1), "alcohol": ("alcohol", 1), "caffeine": ("caffeine", 1000),
        "sodium": ("sodium", 1000), "potassium": ("potassium", 1000), "calcium": ("calcium", 1000), "iron": ("iron", 1000),
        "magnesium": ("magnesium", 1000), "zinc": ("zinc", 1000), "phosphorus": ("phosphorus", 1000), "copper": ("copper", 1000),
        "manganese": ("manganese", 1000), "selenium": ("selenium", 1_000_000), "iodine": ("iodine", 1_000_000),
        "vitamin-a": ("vitamin_a", 1_000_000), "vitamin-c": ("vitamin_c", 1000), "vitamin-d": ("vitamin_d", 1_000_000),
        "vitamin-e": ("vitamin_e", 1000), "vitamin-k": ("vitamin_k", 1_000_000), "vitamin-b1": ("thiamin", 1000),
        "vitamin-b2": ("riboflavin", 1000), "vitamin-pp": ("niacin", 1000), "vitamin-b6": ("vitamin_b6", 1000),
        "vitamin-b9": ("folate", 1_000_000), "vitamin-b12": ("vitamin_b12", 1_000_000), "pantothenic-acid": ("pantothenic_acid", 1000),
        "biotin": ("biotin", 1_000_000), "choline": ("choline", 1000),
    ]

    /// Converts an OFF product to an unsaved Food owned by `userId`, or nil without a name or energy.
    static func food(from p: Product, userId: UUID) -> (Food, [FoodServing])? {
        guard let name = p.productName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        var n: Nutrients = [:]
        for (field, (key, factor)) in fieldMap {
            if let v = p.nutriments?["\(field)_100g"]?.value { n[key] = v * factor }
        }
        if n["energy"] == nil, let kj = p.nutriments?["energy_100g"]?.value { n["energy"] = kj / 4.184 }
        guard n["energy"] != nil else { return nil }
        var food = Food(userId: userId, source: .off, sourceId: p.code, name: name,
                        brand: p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) },
                        barcode: p.code, nutrients: n)
        food.servings = []
        var servings: [FoodServing] = []
        if let g = p.servingQuantity, g > 0 {
            servings.append(FoodServing(foodId: food.id, name: p.servingSize ?? "1 serving", grams: g, isDefault: true))
        }
        return (food, servings)
    }

    func lookup(barcode: String) async throws -> Product? {
        struct Response: Decodable { var status: Int; var product: Product? }
        let digits = barcode.filter(\.isNumber)
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json")!
        let r = try JSONDecoder().decode(Response.self, from: try await get(url))
        return r.status == 1 ? r.product : nil
    }

    /// Branded product search (OFF limits this endpoint; call it only on an explicit tap).
    func search(_ query: String) async throws -> [Product] {
        struct Response: Decodable { var products: [Product] }
        var c = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [.init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
                        .init(name: "json", value: "1"), .init(name: "page_size", value: "25"),
                        .init(name: "fields", value: "code,product_name,brands,serving_size,serving_quantity,nutriments")]
        return try JSONDecoder().decode(Response.self, from: try await get(c.url!)).products
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.message("Open Food Facts is busy. Try again in a minute.")
        }
        return data
    }
}
