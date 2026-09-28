import PDFKit
import SwiftUI

struct PageManagerView: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [PageItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                    ForEach(pages) { page in
                        PageThumbnailCell(
                            page: page,
                            document: viewModel.document,
                            onRotate: { rotate(page) },
                            onDelete: { delete(page) },
                            onDuplicate: { duplicate(page) }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { reloadPages() }
        }
    }

    private func reloadPages() {
        pages = (0..<viewModel.pageCount).map { PageItem(index: $0) }
    }

    private func rotate(_ page: PageItem) {
        viewModel.rotatePage(at: page.index)
        reloadPages()
    }

    private func delete(_ page: PageItem) {
        viewModel.deletePage(at: page.index)
        reloadPages()
    }

    private func duplicate(_ page: PageItem) {
        viewModel.duplicatePage(at: page.index)
        reloadPages()
    }
}

struct PageItem: Identifiable {
    let id = UUID()
    let index: Int
}

struct PageThumbnailCell: View {
    let page: PageItem
    let document: PDFDocument
    let onRotate: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let pdfPage = document.page(at: page.index) {
                Image(uiImage: pdfPage.thumbnail(of: CGSize(width: 90, height: 120), for: .mediaBox))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(radius: 2)
            }

            Text("Page \(page.index + 1)")
                .font(.caption2)

            HStack(spacing: 8) {
                Button(action: onRotate) {
                    Image(systemName: "rotate.right")
                        .font(.caption)
                }
                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                        .font(.caption)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
        }
        .accessibilityLabel("Page \(page.index + 1)")
    }
}
