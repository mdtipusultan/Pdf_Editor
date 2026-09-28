import Foundation
import StoreKit

enum PurchaseError: LocalizedError {
    case productUnavailable
    case purchaseCancelled
    case purchasePending
    case purchaseFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "This plan isn't available right now."
        case .purchaseCancelled: "Purchase was cancelled."
        case .purchasePending: "Purchase is pending approval."
        case .purchaseFailed: "Purchase failed. Please try again."
        case .restoreFailed: "Couldn't restore purchases."
        }
    }
}

@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchaseInProgress = false
    private(set) var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: ProductIdentifiers.all)
                .sorted { $0.price < $1.price }
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    func purchase(_ plan: SubscriptionPlan) async throws {
        guard let product = product(for: plan) else {
            throw PurchaseError.productUnavailable
        }
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            HapticsManager.success()
        case .userCancelled:
            throw PurchaseError.purchaseCancelled
        case .pending:
            throw PurchaseError.purchasePending
        @unknown default:
            throw PurchaseError.purchaseFailed
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
        if EntitlementManager.shared.isPro {
            HapticsManager.success()
        } else {
            throw PurchaseError.restoreFailed
        }
    }

    func refreshEntitlements() async {
        var hasPro = false
        var activeID: String?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if ProductIdentifiers.all.contains(transaction.productID) {
                hasPro = true
                activeID = transaction.productID
            }
        }

        EntitlementManager.shared.updateEntitlement(isPro: hasPro, productID: activeID)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.purchaseFailed
        case .verified(let safe):
            return safe
        }
    }
}
