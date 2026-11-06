import Foundation

/// Sample data for screenshots and UI tests: launch a DEBUG build with `-demo` (add `-gold` for Gold,
/// `-tab diary|dashboard|trends|foods|more`, `-sheet food|quick|exercise|biometric|paywall`, `-screen design`).
/// Reads return fixtures; writes are kept in memory. Always off in release builds.
enum Demo {
    static var active: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }
    static var gold: Bool { active && ProcessInfo.processInfo.arguments.contains("-gold") }

    static let userId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static let nutrients: [Nutrient] = {
        let rows: [(String, String, String, NutrientCategory)] = [
            ("energy", "Energy", "kcal", .general), ("water", "Water", "g", .general), ("caffeine", "Caffeine", "mg", .general),
            ("carbs", "Carbohydrates", "g", .carbohydrates), ("net_carbs", "Net carbs", "g", .carbohydrates), ("fiber", "Fiber", "g", .carbohydrates),
            ("sugars", "Sugars", "g", .carbohydrates), ("fat", "Fat", "g", .lipids), ("saturated_fat", "Saturated fat", "g", .lipids),
            ("omega_3", "Omega-3", "g", .lipids), ("ala", "ALA (18:3)", "g", .lipids), ("cholesterol", "Cholesterol", "mg", .lipids),
            ("protein", "Protein", "g", .protein), ("leucine", "Leucine", "g", .protein),
            ("vitamin_a", "Vitamin A", "mcg", .vitamins), ("vitamin_c", "Vitamin C", "mg", .vitamins), ("vitamin_d", "Vitamin D", "mcg", .vitamins),
            ("vitamin_e", "Vitamin E", "mg", .vitamins), ("vitamin_k", "Vitamin K", "mcg", .vitamins), ("folate", "Folate (DFE)", "mcg", .vitamins),
            ("vitamin_b12", "B12", "mcg", .vitamins), ("calcium", "Calcium", "mg", .minerals), ("iron", "Iron", "mg", .minerals),
            ("magnesium", "Magnesium", "mg", .minerals), ("potassium", "Potassium", "mg", .minerals), ("sodium", "Sodium", "mg", .minerals),
            ("zinc", "Zinc", "mg", .minerals), ("selenium", "Selenium", "mcg", .minerals),
        ]
        return rows.enumerated().map { Nutrient(key: $1.0, name: $1.1, unit: $1.2, category: $1.3, position: $0) }
    }()

    static let dri: [NutrientDRI] = [
        ("vitamin_a", 700.0, 3000.0), ("vitamin_c", 75, 2000), ("vitamin_d", 15, 100), ("vitamin_e", 15, nil), ("vitamin_k", 90, nil),
        ("folate", 400, nil), ("vitamin_b12", 2.4, nil), ("calcium", 1000, 2500), ("iron", 18, 45), ("magnesium", 320, nil),
        ("potassium", 2600, nil), ("sodium", 1500, 2300), ("zinc", 8, 40), ("selenium", 55, 400), ("fiber", 25, nil), ("water", 2700, nil), ("ala", 1.1, nil),
    ].map { NutrientDRI(nutrientKey: $0.0, sex: .female, ageMin: 19, ageMax: 120, target: $0.1, upperLimit: $0.2) }

    static let profile: Profile = {
        var p = Profile(id: userId)
        p.displayName = "Sam"
        p.sex = .female
        p.dateOfBirth = Day(rawValue: "1992-04-18")
        p.heightCm = 168
        p.activityLevel = .light
        p.goalKgPerWeek = -0.25
        return p
    }()

    static var groups = ["Breakfast", "Lunch", "Dinner", "Snacks"].enumerated().map { i, n in
        DiaryGroup(id: UUID(uuidString: "22222222-2222-2222-2222-00000000000\(i)")!, userId: userId, name: n, position: i)
    }

    static var biometricTypes: [BiometricType] = [
        BiometricType(key: "weight", name: "Weight", unit: "kg", category: "body"),
        BiometricType(key: "waist", name: "Waist", unit: "cm", category: "body"),
        BiometricType(key: "blood_pressure", name: "Blood pressure", unit: "mmHg", category: "vitals", valueKind: .pair),
        BiometricType(key: "sleep", name: "Sleep", unit: "min", category: "sleep", valueKind: .minutes),
        BiometricType(key: "mood", name: "Mood", unit: "1-10", category: "mood", valueKind: .scale110),
    ]

    static var foods: [Food] = {
        func f(_ name: String, _ brand: String?, _ n: Nutrients, serving: (String, Double)?, mine: Bool = false, kind: Food.Kind = .food) -> Food {
            var food = Food(userId: mine ? userId : nil, kind: kind, source: mine ? .custom : .usda, name: name, brand: brand, nutrients: n)
            food.servings = serving.map { [FoodServing(foodId: food.id, name: $0.0, grams: $0.1, isDefault: true)] } ?? []
            return food
        }
        return [
            f("Oats, rolled, dry", nil, ["energy": 379, "protein": 13.2, "carbs": 67.7, "fiber": 10.1, "fat": 6.5, "iron": 4.3, "magnesium": 138, "potassium": 362, "zinc": 3.6], serving: ("1/2 cup", 40)),
            f("Blueberries, raw", nil, ["energy": 57, "carbs": 14.5, "fiber": 2.4, "sugars": 10, "vitamin_c": 9.7, "vitamin_k": 19.3, "water": 84], serving: ("1 cup", 148)),
            f("Greek yogurt, plain, nonfat", nil, ["energy": 59, "protein": 10.3, "carbs": 3.6, "calcium": 110, "vitamin_b12": 0.75, "water": 85], serving: ("1 container", 170)),
            f("Chicken breast, roasted", nil, ["energy": 165, "protein": 31, "fat": 3.6, "sodium": 74, "selenium": 27.6, "zinc": 1, "water": 65], serving: ("1 breast", 172)),
            f("Brown rice, cooked", nil, ["energy": 123, "protein": 2.7, "carbs": 25.6, "fiber": 1.6, "magnesium": 39, "water": 70], serving: ("1 cup", 195)),
            f("Broccoli, steamed", nil, ["energy": 35, "protein": 2.4, "carbs": 7.2, "fiber": 3.3, "vitamin_c": 64.9, "vitamin_k": 141, "folate": 108, "potassium": 293, "water": 89], serving: ("1 cup", 156)),
            f("Salmon, Atlantic, baked", nil, ["energy": 206, "protein": 22, "fat": 12.4, "ala": 0.11, "vitamin_d": 13, "vitamin_b12": 3, "selenium": 41, "potassium": 384, "water": 64], serving: ("1 fillet", 154)),
            f("Almonds", nil, ["energy": 579, "protein": 21, "fat": 50, "carbs": 22, "fiber": 12.5, "vitamin_e": 25.6, "magnesium": 270, "calcium": 269], serving: ("1 oz (23 nuts)", 28)),
            f("Protein bar, peanut butter", "Trailmix Co.", ["energy": 380, "protein": 33, "carbs": 38, "fiber": 15, "fat": 13, "sodium": 380], serving: ("1 bar", 60), mine: true),
            f("Overnight oats", nil, ["energy": 145, "protein": 7.5, "carbs": 22, "fiber": 3.4, "fat": 3.1, "calcium": 90], serving: ("1 jar", 320), mine: true, kind: .recipe),
        ]
    }()

    /// In-memory diary so demo writes show up.
    static var diary: [DiaryEntry] = {
        let today = Day.today
        func food(_ i: Int, _ group: Int, _ qty: Double, at hour: Int, day: Day = today) -> DiaryEntry {
            let f = foods[i]
            let s = f.defaultServing
            return DiaryEntry(userId: userId, day: day, kind: .food, groupId: groups[group].id,
                              loggedAt: Calendar.current.date(bySettingHour: hour, minute: 5, second: 0, of: day.date),
                              foodId: f.id, servingId: s.storedId, servingQty: qty, amountG: s.grams * qty, food: f,
                              serving: .init(name: s.name))
        }
        var rows = [food(0, 0, 1, at: 7), food(1, 0, 0.5, at: 7), food(2, 0, 1, at: 7), food(3, 1, 1, at: 12), food(4, 1, 1, at: 12),
                    food(5, 2, 1, at: 19), food(6, 2, 1, at: 19), food(7, 3, 1, at: 16)]
        rows.append(DiaryEntry(userId: userId, day: today, kind: .exercise, minutes: 40, energyKcal: 310, exercise: .init(name: "Cycling, moderate (12-14 mph)")))
        rows.append(DiaryEntry(userId: userId, day: today, kind: .biometric, biometricTypeId: biometricTypes[0].id, value: 64.2))
        rows.append(DiaryEntry(userId: userId, day: today, kind: .quickAdd, nutrients: ["water": 1250], title: "Water"))
        for d in 1...13 {
            let day = today.adding(days: -d)
            rows += [food(0, 0, 1, at: 7, day: day), food(3, 1, d % 3 == 0 ? 1.5 : 1, at: 12, day: day), food(6, 2, 1, at: 19, day: day)]
            rows.append(DiaryEntry(userId: userId, day: day, kind: .biometric, biometricTypeId: biometricTypes[0].id, value: 64.2 + Double(d) * 0.08))
        }
        return rows
    }()

    static func entries(on day: Day) -> [DiaryEntry] { diary.filter { $0.day == day } }

    static func totals(from: Day, to: Day) -> [Day: Nutrients] {
        diary.filter { $0.day >= from && $0.day <= to }.reduce(into: [:]) { $0[$1.day, default: [:]] += $1.consumed }
    }

    static var completed: Set<Day> = Set((1...5).map { Day.today.adding(days: -$0) })

    // In-memory stores so demo writes show up (reset on relaunch).
    static var meals: [Meal] = [Meal(userId: userId, name: "Usual breakfast", items: [0, 1, 2].map { i in
        FoodLine(parentId: userId, foodId: foods[i].id, servingId: nil, servingQty: 1, amountG: foods[i].defaultServing.grams, food: foods[i])
    })]
    static var recipeLines: [UUID: [FoodLine]] = [:]
    static var repeatRules: [RepeatRule] = [RepeatRule(userId: userId, foodId: foods[0].id, amountG: 40, groupId: groups[0].id,
                                                       weekdays: [1, 2, 3, 4, 5], startsOn: .today, food: .init(name: foods[0].name))]
    static var fasts: [Fast] = [Fast(userId: userId, startedAt: Date().addingTimeInterval(-11 * 3600), targetMinutes: 960),
                                Fast(userId: userId, startedAt: Date().addingTimeInterval(-36 * 3600), endedAt: Date().addingTimeInterval(-19 * 3600), targetMinutes: 960)]
    static var fastSchedules: [FastSchedule] = [FastSchedule(userId: userId, weekdays: [1, 2, 3, 4, 5], startTime: "20:00:00", targetMinutes: 960)]
    static var charts: [CustomChart] = [CustomChart(userId: userId, title: "Magnesium vs weight",
                                                    series: [.init(type: .nutrient, key: "magnesium"), .init(type: .biometric, key: "weight")], rangeDays: 14, pinned: true)]
    static var overrides: [NutrientTargetOverride] = []
    static var templates: [MacroTemplate] = [MacroTemplate(userId: userId, name: "Training day", energyKcal: 2300, proteinG: 140, carbsG: 260, fatG: 70)]
    static var schedule: [MacroScheduleDay] = []

    /// Replaces an element with the same id, or appends it.
    static func upsert<T: Identifiable>(_ item: T, into list: inout [T]) {
        if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item } else { list.append(item) }
    }
}
