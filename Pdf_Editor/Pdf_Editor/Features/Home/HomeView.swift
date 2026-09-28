import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @State private var appState = AppState.shared
    @State private var recentStore = RecentDocumentsStore.shared
    @State private var entitlement = EntitlementManager.shared
    @State private var showImporter = false
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    header
                    heroSection
                    primaryActions
                    if !entitlement.isPro {
                        proCard
                    }
                    recentSection
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 32)
            }

            if isImporting {
                loadingOverlay
            }
        }
        .navigationBarHidden(true)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Couldn't Open PDF", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text("PDF Editor")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            Button {
                appState.navigationPath.append(AppRoute.settings)
                HapticsManager.lightImpact()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your PDFs,\nsimply edited.")
                .font(AppTypography.heroTitle())
            Text("Open. Edit. Save. Done.")
                .font(AppTypography.body())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            PrimaryButton("Edit PDF", icon: "plus") {
                showImporter = true
                HapticsManager.mediumImpact()
            }
            .accessibilityIdentifier("editPDFButton")

            SecondaryButton("Import PDF", icon: "folder") {
                showImporter = true
                HapticsManager.lightImpact()
            }
        }
    }

    private var proCard: some View {
        Button {
            appState.presentPaywall()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upgrade to Pro")
                        .font(.headline)
                    Text("Unlimited editing & exports")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upgrade to Pro")
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent PDFs")
                .font(AppTypography.sectionTitle())

            if recentStore.documents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(recentStore.documents) { doc in
                        RecentDocumentRow(document: doc) {
                            appState.openEditor(url: doc.localURL)
                        } onDelete: {
                            recentStore.remove(doc)
                            HapticsManager.lightImpact()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent.opacity(0.6))
            Text("Your documents will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap Edit PDF to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Opening PDF...")
                    .font(.subheadline.weight(.medium))
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening PDF")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importPDF(from: url) }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importPDF(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let (destination, document) = try await DocumentStorage.importPDF(from: url)
            let fileName = destination.lastPathComponent
            RecentDocumentsStore.shared.addOrUpdate(from: document, url: destination, fileName: fileName)
            HapticsManager.success()
            appState.openEditor(url: destination)
        } catch {
            importError = error.localizedDescription
            HapticsManager.error()
        }
    }
}

struct RecentDocumentRow: View {
    let document: RecentDocument
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(document.lastOpened, style: .relative)
                        Text("•")
                        Text("\(document.pageCount) pages")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Remove from Recents", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.fileName), \(document.pageCount) pages")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = document.thumbnailPath, let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.accent.opacity(0.15))
                .frame(width: 44, height: 58)
                .overlay {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(AppTheme.accent)
                }
        }
    }
}
