import SwiftUI

enum AppTypography {
    static func heroTitle() -> Font {
        .system(.largeTitle, design: .rounded, weight: .bold)
    }

    static func sectionTitle() -> Font {
        .system(.title3, design: .rounded, weight: .semibold)
    }

    static func body() -> Font {
        .system(.body, design: .default)
    }

    static func caption() -> Font {
        .system(.caption, design: .default)
    }

    static func button() -> Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }
}
