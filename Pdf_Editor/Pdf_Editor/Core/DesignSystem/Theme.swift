import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let toolbarHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28

    static let accent = Color("AccentPrimary")
    static let accentSecondary = Color("AccentSecondary")
    static let cardBackground = Color("CardBackground")
    static let heroGradientStart = Color("HeroGradientStart")
    static let heroGradientEnd = Color("HeroGradientEnd")
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color(.secondarySystemBackground)]
                : [Color(.systemBackground), Color(red: 0.97, green: 0.97, blue: 0.99)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
