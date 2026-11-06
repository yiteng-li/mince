import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

/// App-wide state: session, profile, catalogues, Gold, the selected day, targets.
/// Screens own their own data; this holds what every screen needs.
@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, signedOut, onboarding, ready }

    private(set) var phase: Phase = .loading
    private(set) var session: Session?
    var profile: Profile?
    private(set) var nutrients: [Nutrient] = []
    private(set) var dri: [NutrientDRI] = []
    private(set) var overrides: [NutrientTargetOverride] = []
    private(set) var biometricTypes: [BiometricType] = []
    private(set) var groups: [DiaryGroup] = []
    private(set) var macroTemplates: [MacroTemplate] = []
    private(set) var macroSchedule: [Int: UUID] = [:]
    private(set) var currentWeightKg: Double?
    private(set) var serverGold = false

    var selectedDay: Day = .today
    /// Entries copied with "Copy", pasted with "Paste".
    var clipboard: [DiaryEntry] = []
    var showPaywall = false
    var showPlus = false
    var errorMessage: String?
    /// Set by deep links / Siri to open a logging flow.
    var activeSheet: LogSheet?
    /// Bumped after any diary write so open screens reload.
    private(set) var diaryVersion = 0

    let store = StoreService()
    private var db: SupabaseClient { SupabaseService.shared }
    private var appleNonce: String?

    var userId: UUID? { session?.user.id ?? demoUserId }
    /// Gold for UI purposes: server truth, or a fresh device entitlement the server hasn't confirmed yet.
    var isGold: Bool { serverGold || store.hasActiveEntitlement }
    var unitSystem: UnitSystem { profile?.unitSystem ?? .metric }
    var energyUnit: EnergyUnit { profile?.energyUnit ?? .kcal }
    var weightKg: Double { currentWeightKg ?? 70 }

    init() {
        store.onServerStatus = { [weak self] gold in self?.serverGold = gold }
        if Demo.active { loadDemo(); return }
        Task { await observeAuth() }
    }

    /// DEBUG `-demo`: fixture data, no network.
    private func loadDemo() {
        profile = Demo.profile
        nutrients = Demo.nutrients
        dri = Demo.dri
        biometricTypes = Demo.biometricTypes
        groups = Demo.groups
        serverGold = Demo.gold
        currentWeightKg = 64.2
        phase = ["signedOut": .signedOut, "onboarding": .onboarding][UserDefaults.standard.string(forKey: "phase") ?? ""] ?? .ready
    }

    var demoUserId: UUID? { Demo.active ? Demo.userId : nil }

    private func observeAuth() async {
        for await (event, session) in db.auth.authStateChanges {
            self.session = session
            if session == nil {
                phase = .signedOut
                profile = nil
            } else if event == .initialSession || event == .signedIn {
                await loadUserContext()
            }
        }
    }

    // MARK: loading

    func loadUserContext() async {
        do {
            async let p = ProfileService().profile()
            async let n = ProfileService().nutrients()
            async let d = ProfileService().dri()
            async let o = ProfileService().overrides()
            async let b = ProfileService().biometricTypes()
            async let g = DiaryService().groups()
            async let gold = GoldService().isGold()
            (profile, nutrients, dri, overrides, biometricTypes, groups) = try await (p, n, d, o, b, g)
            serverGold = (try? await gold) ?? false
            await refreshWeight()
            await refreshMacroSchedule()
            phase = profile?.isOnboarded == true ? .ready : .onboarding
            await store.load()
            if store.hasActiveEntitlement && !serverGold { await store.restore() }
        } catch {
            errorMessage = "Couldn't load your account: \(error.localizedDescription)"
            phase = session == nil ? .signedOut : .ready
        }
    }

    func refreshWeight() async {
        guard let weight = biometricType("weight") else { return }
        currentWeightKg = try? await DiaryService().latest(biometricTypeId: weight.id)?.value
    }

    func refreshMacroSchedule() async {
        guard isGold else { macroSchedule = [:]; return }
        macroTemplates = (try? await ProfileService().macroTemplates()) ?? []
        let rows = (try? await ProfileService().macroSchedule()) ?? []
        macroSchedule = Dictionary(rows.map { ($0.weekday, $0.templateId) }, uniquingKeysWith: { a, _ in a })
    }

    func refreshOverrides() async { overrides = (try? await ProfileService().overrides()) ?? overrides }
    func refreshBiometricTypes() async { biometricTypes = (try? await ProfileService().biometricTypes()) ?? biometricTypes }
    func refreshGroups() async { groups = (try? await DiaryService().groups()) ?? groups }
    func refreshGold() async { serverGold = (try? await GoldService().isGold()) ?? serverGold }

    func saveProfile(_ p: Profile) async {
        if Demo.active { profile = p; return }
        do {
            try await ProfileService().update(p)
            profile = p
            if phase == .onboarding, p.isOnboarded { phase = .ready }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: lookups

    func nutrient(_ key: String) -> Nutrient? { nutrients.first { $0.key == key } }
    func biometricType(_ key: String) -> BiometricType? { biometricTypes.first { $0.key == key && $0.userId == nil } }
    func biometricType(id: UUID?) -> BiometricType? { biometricTypes.first { $0.id == id } }
    func group(id: UUID?) -> DiaryGroup? { groups.first { $0.id == id } }

    /// The group that fits the time of day (Breakfast before 10:30, Lunch before 15:00, Dinner before 21:00, else the last).
    func defaultGroupId(at date: Date = Date()) -> UUID? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        let index = minutes < 630 ? 0 : minutes < 900 ? 1 : minutes < 1260 ? 2 : 3
        return groups.indices.contains(index) ? groups[index].id : groups.last?.id
    }

    /// Inserts entries for the selected day and tells open screens to reload.
    @discardableResult
    func log(_ entries: [DiaryEntry]) async -> Bool {
        do {
            try await DiaryService().insert(entries)
            diaryChanged()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// A food entry for the selected day.
    func foodEntry(_ food: Food, serving: FoodServing, qty: Double, groupId: UUID?, at time: Date?) -> DiaryEntry? {
        guard let uid = userId else { return nil }
        return DiaryEntry(userId: uid, day: selectedDay, kind: .food, groupId: groupId ?? defaultGroupId(), loggedAt: isGold ? time : nil,
                          foodId: food.id, servingId: serving.storedId, servingQty: qty, amountG: serving.grams * qty, food: food,
                          serving: serving.isBuiltIn ? nil : .init(name: serving.name))
    }

    func targets(for day: Day) -> DayTargets {
        let template = isGold ? macroSchedule[day.weekday].flatMap { id in macroTemplates.first { $0.id == id } } : nil
        return TargetCalculator.targets(profile: profile ?? Profile(id: UUID()), weightKg: weightKg, dri: dri, overrides: overrides,
                                        template: template, healthActiveEnergy: profile?.useHealthActiveEnergy ?? false)
    }

    /// Runs `action` if Gold, otherwise opens the paywall.
    func requireGold(_ action: () -> Void) {
        if isGold { action() } else { showPaywall = true }
    }

    func diaryChanged() { diaryVersion += 1 }

    /// Opens a logging flow, sending Gold-only ones to the paywall for Basic users.
    func open(_ sheet: LogSheet) {
        switch sheet {
        case .photo, .voice, .fasting: requireGold { activeSheet = sheet }
        default: activeSheet = sheet
        }
    }

    /// mince://shared/<token> (shared food) and mince://log?text=... (Siri / shortcuts).
    func handle(url: URL) {
        guard url.scheme == "mince" else { return }
        if url.host == "shared", let token = UUID(uuidString: url.lastPathComponent) {
            activeSheet = .sharedFood(token)
        } else if url.host == "log" {
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
            open(.voice(groupId: nil, text: text))
        }
    }

    func report(_ error: Error) {
        if case AppError.goldRequired = error { showPaywall = true } else { errorMessage = error.localizedDescription }
    }

    // MARK: auth

    func signUp(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard email.contains("@"), email.split(separator: "@").last?.contains(".") == true else {
            throw AppError.message("Enter a valid email address.")
        }
        guard password.count >= 8 else { throw AppError.message("Use at least 8 characters for your password.") }
        let response = try await db.auth.signUp(email: email, password: password)
        if response.session == nil {
            throw AppError.message("Check your inbox to confirm your email, then sign in.")
        }
    }

    func signIn(email: String, password: String) async throws {
        try await db.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
    }

    func resetPassword(email: String) async throws {
        try await db.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces))
    }

    func signOut() async {
        try? await db.auth.signOut()
        clipboard = []
        selectedDay = .today
    }

    /// Prepares a Sign in with Apple request with a hashed nonce.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = UUID().uuidString + UUID().uuidString
        appleNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async throws {
        let auth = try result.get()
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw AppError.message("Apple didn't return a sign-in token. Try again.")
        }
        try await db.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: appleNonce))
    }

    func deleteAccount() async throws {
        try await AIService().deleteAccount()
        await signOut()
    }
}

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
    var isGold: Bool { [.photo, .voice, .fast].contains(self) }

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
