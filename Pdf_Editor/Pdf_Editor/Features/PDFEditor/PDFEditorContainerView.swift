import PDFKit
import SwiftUI

struct PDFEditorContainerView: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PDFEditorViewModel?
    @State private var loadError: String?
    @State private var showExport = false
    @State private var showPageManager = false
    @State private var showPaywall = false
    @State private var appState = AppState.shared

    var body: some View {
        Group {
            if let viewModel {
                PDFEditorView(
                    viewModel: viewModel,
                    showExport: $showExport,
                    showPageManager: $showPageManager,
                    showPaywall: $showPaywall
                )
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView("Opening PDF...")
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await loadDocument()
        }
        .sheet(isPresented: $showExport) {
            if let viewModel {
                ExportView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showPageManager) {
            if let viewModel {
                PageManagerView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func loadDocument() async {
        guard let document = PDFDocument(url: fileURL) else {
            loadError = PDFImportError.invalidDocument.errorDescription
            return
        }
        if document.isLocked {
            loadError = PDFImportError.passwordProtected.errorDescription
            return
        }
        viewModel = PDFEditorViewModel(
            document: document,
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent
        )
        RecentDocumentsStore.shared.addOrUpdate(
            from: document,
            url: fileURL,
            fileName: fileURL.lastPathComponent
        )
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Go Back") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
