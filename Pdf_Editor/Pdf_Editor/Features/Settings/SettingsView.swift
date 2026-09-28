import SwiftUI

struct SettingsView: View {
    @State private var preferences = UserPreferences.shared
    @State private var purchaseManager = PurchaseManager.shared
    @State private var entitlement = EntitlementManager.shared
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    var body: some View {
        List {
            generalSection
            pdfSection
            subscriptionSection
            aboutSection
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Restore Purchases", isPresented: .init(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var generalSection: some View {
        Section("General") {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            Toggle("Haptics", isOn: $preferences.hapticsEnabled)
        }
    }

    private var pdfSection: some View {
        Section("PDF") {
            ColorPicker("Default annotation color", selection: Binding(
                get: { Color(hex: preferences.defaultAnnotationColorHex) ?? .yellow },
                set: { preferences.defaultAnnotationColorHex = $0.hexString }
            ))
            Stepper("Default pen size: \(Int(preferences.defaultPenSize))", value: $preferences.defaultPenSize, in: 1...12)
            Toggle("Auto-save", isOn: $preferences.autoSave)
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Text("PDF Pro")
                Spacer()
                Text(entitlement.isPro ? "Active" : "Free")
                    .foregroundStyle(entitlement.isPro ? .green : .secondary)
            }

            if !entitlement.isPro {
                Button("Upgrade to Pro") {
                    showPaywall = true
                }
            }

            Button("Restore Purchases") {
                Task {
                    do {
                        try await purchaseManager.restorePurchases()
                        restoreMessage = "Purchases restored successfully."
                    } catch {
                        restoreMessage = error.localizedDescription
                    }
                }
            }

            Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
            Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
            Link("Contact Support", destination: URL(string: "mailto:support@example.com")!)
            Link("Rate the App", destination: URL(string: "https://apps.apple.com")!)

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Testing Mode") {
            HStack {
                Text("Pro Status")
                Spacer()
                Text(entitlement.isPro ? "Pro" : "Free")
                    .foregroundStyle(.secondary)
            }

            Button("Enable Pro (Debug)") {
                EntitlementManager.shared.enableDebugPro()
            }

            Button("Disable Pro (Debug)") {
                EntitlementManager.shared.disableDebugPro()
            }

            Button("Reset Test Pro") {
                EntitlementManager.shared.resetDebugPro()
            }

            Button("Reset Daily Export Count") {
                AppFeatureAccess.shared.resetDailyExportCount()
            }
        }
    }
    #endif
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
