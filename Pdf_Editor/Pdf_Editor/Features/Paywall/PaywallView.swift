import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseManager = PurchaseManager.shared
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefitsList
                    planPicker
                    purchaseButton
                    restoreButton
                    legalLinks
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("PDF Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Welcome to PDF Pro!", isPresented: $showSuccess) {
                Button("Continue") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow.gradient)
            Text("Unlock PDF Pro")
                .font(AppTypography.heroTitle())
            Text("Edit, sign, and export without limits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AppFeature.allCases, id: \.displayName) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feature.displayName)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(SubscriptionPlan.allCases) { plan in
                PlanRow(
                    plan: plan,
                    product: purchaseManager.product(for: plan),
                    isSelected: selectedPlan == plan
                ) {
                    selectedPlan = plan
                    HapticsManager.selection()
                }
            }
        }
    }

    private var purchaseButton: some View {
        PrimaryButton(isPurchasing ? "Processing..." : "Continue") {
            Task { await purchase() }
        }
        .disabled(isPurchasing || purchaseManager.purchaseInProgress)
        .opacity(isPurchasing ? 0.7 : 1)
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await restore() }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var legalLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
            }
            .font(.caption)
            Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchaseManager.purchase(selectedPlan)
            showSuccess = true
        } catch let error as PurchaseError {
            if error != .purchaseCancelled {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchaseManager.restorePurchases()
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlanRow: View {
    let plan: SubscriptionPlan
    let product: Product?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.headline)
                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product?.displayPrice ?? "—")
                    .font(.headline)
            }
            .padding()
            .background(isSelected ? AppTheme.accent.opacity(0.1) : AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.title), \(product?.displayPrice ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension PurchaseError: Equatable {
    static func == (lhs: PurchaseError, rhs: PurchaseError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
