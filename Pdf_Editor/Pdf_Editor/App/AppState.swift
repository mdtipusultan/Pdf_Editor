import SwiftUI

enum AppRoute: Hashable {
    case editor(URL)
    case settings
    case paywall
}

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var showSplash = true
    var showOnboarding = false
    var navigationPath = NavigationPath()
    var showDocumentPicker = false
    var isImporting = false
    var importError: String?
    var showPaywall = false

    private init() {
        showOnboarding = !UserPreferences.shared.onboardingCompleted
    }

    func completeOnboarding() {
        UserPreferences.shared.onboardingCompleted = true
        showOnboarding = false
        HapticsManager.success()
    }

    func dismissSplash() {
        withAnimation(.easeOut(duration: 0.4)) {
            showSplash = false
        }
    }

    func openEditor(url: URL) {
        navigationPath.append(AppRoute.editor(url))
    }

    func presentPaywall() {
        showPaywall = true
    }
}
