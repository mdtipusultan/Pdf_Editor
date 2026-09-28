import SwiftUI

struct OnboardingPageData: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let features: [String]?
}

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var appState = AppState.shared

    private let pages: [OnboardingPageData] = [
        OnboardingPageData(
            title: "Edit PDFs, effortlessly.",
            subtitle: "Open any PDF, make useful edits, and save in seconds.",
            icon: "doc.richtext",
            features: nil
        ),
        OnboardingPageData(
            title: "Everything you need.",
            subtitle: "Practical tools for everyday PDF editing.",
            icon: "pencil.and.outline",
            features: ["Text", "Signature", "Markup", "Pages"]
        ),
        OnboardingPageData(
            title: "Designed for iPhone.",
            subtitle: "Fast, simple, and processed privately on your device.",
            icon: "iphone",
            features: ["Fast", "Simple", "Private"]
        ),
        OnboardingPageData(
            title: "Ready to edit?",
            subtitle: "Your documents stay on your device. No account required.",
            icon: "checkmark.circle.fill",
            features: nil
        )
    ]

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            HapticsManager.lightImpact()
                            appState.completeOnboarding()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip onboarding")
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 8)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        onboardingPage(page, isLast: index == pages.count - 1)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                progressIndicator
                    .padding(.bottom, 32)
            }
        }
    }

    private func onboardingPage(_ page: OnboardingPageData, isLast: Bool) -> some View {
        VStack(spacing: 32) {
            Spacer()

            OnboardingIllustration(icon: page.icon, pageIndex: currentPage)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(AppTypography.heroTitle())
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(AppTypography.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let features = page.features {
                featureGrid(features)
            }

            Spacer()

            if isLast {
                PrimaryButton("Get Started", icon: "arrow.right") {
                    appState.completeOnboarding()
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            } else {
                PrimaryButton("Continue", icon: "arrow.right") {
                    withAnimation {
                        currentPage += 1
                        HapticsManager.selection()
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
        .padding(.bottom, 16)
    }

    private func featureGrid(_ features: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: iconForFeature(feature))
                        .foregroundStyle(AppTheme.accent)
                    Text(feature)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private func iconForFeature(_ feature: String) -> String {
        switch feature {
        case "Text": "textformat"
        case "Signature": "signature"
        case "Markup": "highlighter"
        case "Pages": "square.grid.2x2"
        case "Fast": "bolt.fill"
        case "Simple": "hand.tap.fill"
        case "Private": "lock.fill"
        default: "checkmark"
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppTheme.accent : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }
}

struct OnboardingIllustration: View {
    let icon: String
    let pageIndex: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 180, height: 180)

            Circle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 220, height: 220)

            Image(systemName: icon)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(AppTheme.accent.gradient)
                .symbolEffect(.bounce, value: pageIndex)
        }
        .padding(.vertical, 20)
        .accessibilityHidden(true)
    }
}
