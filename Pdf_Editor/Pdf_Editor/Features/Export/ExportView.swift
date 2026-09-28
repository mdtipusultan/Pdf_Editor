import SwiftUI

struct ExportView: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showFileExporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var renamedFile = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Your PDF is ready.")
                        .font(AppTypography.sectionTitle())
                    Text(viewModel.fileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    exportButton("Save to Files", icon: "folder") {
                        saveAndExport()
                    }
                    exportButton("Share", icon: "square.and.arrow.up") {
                        saveAndShare()
                    }
                    exportButton("Save as Copy", icon: "doc.on.doc") {
                        saveAsCopy()
                    }
                }
                .padding(.horizontal)

                Section {
                    TextField("Rename", text: $renamedFile)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Filename")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving your changes...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                renamedFile = viewModel.fileName
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: PDFExportDocument(url: exportURL ?? viewModel.fileURL),
                contentType: .pdf,
                defaultFilename: renamedFile
            ) { result in
                if case .failure = result {
                    errorMessage = "Couldn't export this PDF."
                } else {
                    AppFeatureAccess.shared.recordExport()
                    HapticsManager.success()
                }
            }
            .alert("Export Failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
    }

    private func exportButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .font(.body.weight(.medium))
            .padding()
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func saveAndExport() {
        performSave {
            exportURL = viewModel.fileURL
            showFileExporter = true
        }
    }

    private func saveAndShare() {
        performSave {
            exportURL = viewModel.fileURL
            showShareSheet = true
            AppFeatureAccess.shared.recordExport()
        }
    }

    private func saveAsCopy() {
        performSave {
            do {
                let name = renamedFile.isEmpty ? viewModel.fileName : renamedFile
                exportURL = try viewModel.exportCopy(newName: name)
                showShareSheet = true
                AppFeatureAccess.shared.recordExport()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performSave(_ completion: @escaping () -> Void) {
        isSaving = true
        Task {
            do {
                try viewModel.saveDocument()
                isSaving = false
                completion()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import UniformTypeIdentifiers

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        url = URL(fileURLWithPath: "/tmp/empty.pdf")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}
