import Foundation

@Observable
final class EntitlementManager {
    static let shared = EntitlementManager()

    private(set) var isPro: Bool = false
    private(set) var activeProductID: String?

    #if DEBUG
    var debugProOverride: Bool? {
        didSet {
            if let override = debugProOverride {
                isPro = override
            } else {
                isPro = hasValidPurchase
            }
        }
    }
    #endif

    private var hasValidPurchase = false

    private init() {}

    func updateEntitlement(isPro: Bool, productID: String? = nil) {
        hasValidPurchase = isPro
        #if DEBUG
        if debugProOverride == nil {
            self.isPro = isPro
        }
        #else
        self.isPro = isPro
        #endif
        activeProductID = productID
    }

    #if DEBUG
    func enableDebugPro() {
        debugProOverride = true
        HapticsManager.success()
    }

    func disableDebugPro() {
        debugProOverride = false
        HapticsManager.selection()
    }

    func resetDebugPro() {
        debugProOverride = nil
        isPro = hasValidPurchase
        HapticsManager.selection()
    }
    #endif
}
