import Foundation

/// Replace these product IDs with your App Store Connect identifiers before release.
enum ProductIdentifiers {
    static let monthly = "com.yourcompany.pdfeditor.pro.monthly"
    static let yearly = "com.yourcompany.pdfeditor.pro.yearly"
    static let lifetime = "com.yourcompany.pdfeditor.pro.lifetime"

    static let all: [String] = [monthly, yearly, lifetime]
}

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .monthly: ProductIdentifiers.monthly
        case .yearly: ProductIdentifiers.yearly
        case .lifetime: ProductIdentifiers.lifetime
        }
    }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .lifetime: "Lifetime"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: "Flexible monthly access"
        case .yearly: "Best value for regular use"
        case .lifetime: "One-time purchase"
        }
    }
}
