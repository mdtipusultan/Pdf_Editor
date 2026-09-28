import Foundation

/// Centralized freemium limits — adjust values here.
enum AppFeatureLimits {
    static let freeExportsPerDay = 3
    static let freeSignaturesCount = 1
    static let freeAnnotationsPerDocument = 10
}

enum AppFeature: CaseIterable {
    case unlimitedEditing
    case existingTextEditing
    case unlimitedExports
    case advancedAnnotations
    case pageManagement
    case premiumTools
    case unlimitedSignatures

    var requiresPro: Bool { true }

    var displayName: String {
        switch self {
        case .unlimitedEditing: "Unlimited PDF editing"
        case .existingTextEditing: "Edit existing PDF text"
        case .unlimitedExports: "Unlimited exports"
        case .advancedAnnotations: "Advanced annotations"
        case .pageManagement: "Page management"
        case .premiumTools: "Premium tools"
        case .unlimitedSignatures: "Unlimited signatures"
        }
    }
}

@Observable
final class AppFeatureAccess {
    static let shared = AppFeatureAccess()

    private let exportCountKey = "dailyExportCount"
    private let exportDateKey = "dailyExportDate"
    private let signatureCountKey = "savedSignatureCount"

    private init() {}

    var isPro: Bool {
        EntitlementManager.shared.isPro
    }

    func canUseTool(_ tool: EditorTool) -> Bool {
        if !tool.requiresPro { return true }
        return isPro
    }

    func canUsePageManagement() -> Bool {
        isPro
    }

    func canEditExistingText() -> Bool {
        isPro
    }

    func canExport() -> Bool {
        if isPro { return true }
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: exportCountKey)
        return count < AppFeatureLimits.freeExportsPerDay
    }

    func recordExport() {
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: exportCountKey)
        UserDefaults.standard.set(count + 1, forKey: exportCountKey)
    }

    func remainingFreeExports() -> Int {
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: exportCountKey)
        return max(0, AppFeatureLimits.freeExportsPerDay - count)
    }

    func canAddAnnotation(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < AppFeatureLimits.freeAnnotationsPerDocument
    }

    func canSaveSignature() -> Bool {
        if isPro { return true }
        let count = UserDefaults.standard.integer(forKey: signatureCountKey)
        return count < AppFeatureLimits.freeSignaturesCount
    }

    func recordSignatureSaved() {
        let count = UserDefaults.standard.integer(forKey: signatureCountKey)
        UserDefaults.standard.set(count + 1, forKey: signatureCountKey)
    }

    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        let storedDate = UserDefaults.standard.object(forKey: exportDateKey) as? Date ?? .distantPast
        if !Calendar.current.isDate(storedDate, inSameDayAs: today) {
            UserDefaults.standard.set(0, forKey: exportCountKey)
            UserDefaults.standard.set(today, forKey: exportDateKey)
        }
    }

    #if DEBUG
    func resetDailyExportCount() {
        UserDefaults.standard.set(0, forKey: exportCountKey)
        UserDefaults.standard.set(Date(), forKey: exportDateKey)
    }
    #endif
}
