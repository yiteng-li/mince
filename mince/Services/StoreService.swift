import Foundation
import Observation
import StoreKit

/// StoreKit 2 subscriptions for mince+. The device decides what to show;
/// the server (verify-purchase + App Store notifications) decides what mince+ unlocks.
@MainActor
@Observable
final class StoreService {
    static let productIds = ["mince.plus.monthly", "mince.plus.annual"]

    private(set) var products: [Product] = []
    private(set) var hasActiveEntitlement = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    private var updates: Task<Void, Never>?
    /// Called with the server's mince+ status after a transaction is verified.
    var onServerStatus: ((Bool) -> Void)?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func load() async {
        do {
            products = try await Product.products(for: Self.productIds).sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Couldn't load plans. Check your connection."
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIds.contains(t.productID), t.revocationDate == nil {
                active = true
            }
        }
        hasActiveEntitlement = active
    }

    func purchase(_ product: Product, userId: UUID) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(userId)]) {
            case .success(let result):
                await handle(result)
                return true
            case .pending:
                errorMessage = "Purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func restore() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements { await handle(result) }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        do {
            let plus = try await AIService().verifyPurchase(jws: result.jwsRepresentation)
            onServerStatus?(plus)
        } catch {
            errorMessage = "Purchase went through, but we couldn't confirm it yet. It will retry next launch."
        }
        await transaction.finish()
        await refreshEntitlements()
    }
}
