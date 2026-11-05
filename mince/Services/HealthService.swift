import Foundation
import HealthKit

/// Apple Health: imports workouts, active energy, weight, sleep, resting heart rate, HRV and glucose
/// as diary rows (idempotent via the sample UUID), and exports logged nutrition.
struct HealthService {
    static let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let quantityReads: [HKQuantityTypeIdentifier] = [
        .activeEnergyBurned, .bodyMass, .bodyFatPercentage, .restingHeartRate, .heartRateVariabilitySDNN, .bloodGlucose,
        .oxygenSaturation, .respiratoryRate, .vo2Max,
    ]
    /// Nutrition written back to Health: HealthKit identifier -> (mince key, HK unit, factor from our unit).
    private static let exports: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
        (.dietaryEnergyConsumed, "energy", .kilocalorie()), (.dietaryProtein, "protein", .gram()),
        (.dietaryCarbohydrates, "carbs", .gram()), (.dietaryFatTotal, "fat", .gram()), (.dietaryFiber, "fiber", .gram()),
        (.dietarySugar, "sugars", .gram()), (.dietaryFatSaturated, "saturated_fat", .gram()),
        (.dietaryCholesterol, "cholesterol", .gramUnit(with: .milli)), (.dietarySodium, "sodium", .gramUnit(with: .milli)),
        (.dietaryPotassium, "potassium", .gramUnit(with: .milli)), (.dietaryCalcium, "calcium", .gramUnit(with: .milli)),
        (.dietaryIron, "iron", .gramUnit(with: .milli)), (.dietaryVitaminC, "vitamin_c", .gramUnit(with: .milli)),
        (.dietaryWater, "water", .literUnit(with: .milli)), (.dietaryCaffeine, "caffeine", .gramUnit(with: .milli)),
    ]

    func requestAccess() async throws {
        var read: Set<HKObjectType> = Set(Self.quantityReads.map { HKQuantityType($0) })
        read.insert(HKObjectType.workoutType())
        read.insert(HKCategoryType(.sleepAnalysis))
        let write: Set<HKSampleType> = Set(Self.exports.map { HKQuantityType($0.0) })
        try await Self.store.requestAuthorization(toShare: write, read: read)
    }

    /// Builds diary rows for one day from Health. The caller inserts them; duplicates are rejected
    /// by the database's unique (user, source, external_id) index, so re-running is safe.
    func importRows(day: Day, userId: UUID, types: [String: BiometricType], weightKg: Double) async throws -> [DiaryEntry] {
        let start = Calendar.current.startOfDay(for: day.date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        var rows: [DiaryEntry] = []

        // Workouts -> exercise rows.
        for w in try await samples(HKObjectType.workoutType(), predicate) as? [HKWorkout] ?? [] {
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                ?? w.duration / 3600 * 5 * weightKg
            rows.append(DiaryEntry(userId: userId, day: day, kind: .exercise, loggedAt: w.startDate,
                                   title: w.workoutActivityType.name, minutes: max(w.duration / 60, 1), energyKcal: kcal,
                                   source: .health, externalId: w.uuid.uuidString))
        }

        // Active energy as one daily row (replaces the activity multiplier when that setting is on).
        if let total = try await sum(.activeEnergyBurned, .kilocalorie(), predicate), total > 0 {
            rows.append(DiaryEntry(userId: userId, day: day, kind: .exercise, loggedAt: start, title: "Active energy (Apple Health)",
                                   minutes: 1, energyKcal: total, source: .health, externalId: "active-energy-\(day.rawValue)"))
        }

        // Biometrics.
        let map: [(HKQuantityTypeIdentifier, String, HKUnit, Double)] = [
            (.bodyMass, "weight", .gramUnit(with: .kilo), 1), (.bodyFatPercentage, "body_fat", .percent(), 100),
            (.restingHeartRate, "resting_heart_rate", HKUnit.count().unitDivided(by: .minute()), 1),
            (.heartRateVariabilitySDNN, "hrv", .secondUnit(with: .milli), 1),
            (.bloodGlucose, "blood_glucose", HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), 1),
            (.oxygenSaturation, "blood_oxygen", .percent(), 100), (.respiratoryRate, "respiratory_rate", HKUnit.count().unitDivided(by: .minute()), 1),
            (.vo2Max, "vo2_max", HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), 1),
        ]
        for (id, key, unit, factor) in map {
            guard let type = types[key] else { continue }
            for s in try await samples(HKQuantityType(id), predicate) as? [HKQuantitySample] ?? [] {
                rows.append(DiaryEntry(userId: userId, day: day, kind: .biometric, loggedAt: s.startDate, biometricTypeId: type.id,
                                       value: s.quantity.doubleValue(for: unit) * factor, source: .health, externalId: s.uuid.uuidString))
            }
        }

        // Sleep: total asleep minutes for the night ending this morning.
        if let sleepType = types["sleep"] {
            let nightStart = Calendar.current.date(byAdding: .hour, value: -12, to: start)!
            let p = HKQuery.predicateForSamples(withStart: nightStart, end: Calendar.current.date(byAdding: .hour, value: 12, to: start)!)
            let asleep = (try await samples(HKCategoryType(.sleepAnalysis), p) as? [HKCategorySample] ?? [])
                .filter { HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains($0.value) }
                .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if asleep > 0 {
                rows.append(DiaryEntry(userId: userId, day: day, kind: .biometric, loggedAt: start, biometricTypeId: sleepType.id,
                                       value: (asleep / 60).rounded(), source: .health, externalId: "sleep-\(day.rawValue)"))
            }
        }
        return rows
    }

    /// Writes the day's nutrition totals to Health, replacing what mince wrote for that day before.
    func export(day: Day, totals: Nutrients) async throws {
        let start = Calendar.current.startOfDay(for: day.date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let meta = [HKMetadataKeyExternalUUID: "mince-\(day.rawValue)"]
        for (id, _, _) in Self.exports {
            let old = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: ["mince-\(day.rawValue)"])
            _ = try? await Self.store.deleteObjects(of: HKQuantityType(id), predicate: old)
        }
        let samples: [HKQuantitySample] = Self.exports.compactMap { id, key, unit in
            guard let v = totals[key], v > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: v), start: start, end: end, metadata: meta)
        }
        if !samples.isEmpty { try await Self.store.save(samples) }
    }

    private func samples(_ type: HKSampleType, _ predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, e in
                if let e { cont.resume(throwing: e) } else { cont.resume(returning: s ?? []) }
            }
            Self.store.execute(q)
        }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ predicate: NSPredicate) async throws -> Double? {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, s, _ in
                cont.resume(returning: s?.sumQuantity()?.doubleValue(for: unit))
            }
            Self.store.execute(q)
        }
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .swimming: "Swim"
        case .hiking: "Hike"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "HIIT"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .dance: "Dance"
        case .pilates: "Pilates"
        default: "Workout"
        }
    }
}
