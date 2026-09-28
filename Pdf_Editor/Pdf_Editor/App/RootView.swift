import SwiftUI

struct RootView: View {
    @State private var appState = AppState.shared
    @State private var preferences = UserPreferences.shared

    var body: some View {
        ZStack {
            if appState.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                NavigationStack(path: $appState.navigationPath) {
                    HomeView()
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .editor(let url):
                                PDFEditorContainerView(fileURL: url)
                            case .settings:
                                SettingsView()
                            case .paywall:
                                PaywallView()
                            }
                        }
                }
                .transition(.opacity)
            }

            if appState.showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .sheet(isPresented: $appState.showPaywall) {
            PaywallView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                appState.dismissSplash()
            }
            DocumentStorage.cleanupTemporaryFiles()
        }
    }
}
