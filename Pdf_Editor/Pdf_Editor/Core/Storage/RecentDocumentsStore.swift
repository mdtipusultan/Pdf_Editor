import Foundation
import PDFKit

@Observable
final class RecentDocumentsStore {
    static let shared = RecentDocumentsStore()

    private(set) var documents: [RecentDocument] = []
    private let storageKey = "recentDocuments"
    private let maxDocuments = 50

    private init() {
        load()
    }

    func addOrUpdate(from pdfDocument: PDFDocument, url: URL, fileName: String) {
        let pageCount = pdfDocument.pageCount
        let thumbnailPath = generateThumbnail(for: pdfDocument, documentID: url.lastPathComponent)

        if let index = documents.firstIndex(where: { $0.localURL == url }) {
            documents[index].lastOpened = .now
            documents[index].pageCount = pageCount
            documents[index].fileName = fileName
            documents[index].thumbnailPath = thumbnailPath
        } else {
            let doc = RecentDocument(
                fileName: fileName,
                localURL: url,
                pageCount: pageCount,
                thumbnailPath: thumbnailPath
            )
            documents.insert(doc, at: 0)
        }

        documents.sort { $0.lastOpened > $1.lastOpened }
        if documents.count > maxDocuments {
            documents = Array(documents.prefix(maxDocuments))
        }
        save()
    }

    func remove(_ document: RecentDocument) {
        documents.removeAll { $0.id == document.id }
        if let path = document.thumbnailPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        save()
    }

    func rename(_ document: RecentDocument, to newName: String) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].fileName = newName
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) else { return }
        documents = decoded.filter { FileManager.default.fileExists(atPath: $0.localURL.path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func generateThumbnail(for document: PDFDocument, documentID: String) -> String? {
        guard let page = document.page(at: 0) else { return nil }
        let thumbnailSize = CGSize(width: 120, height: 160)
        let image = page.thumbnail(of: thumbnailSize, for: .mediaBox)

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("\(documentID).jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        try? data.write(to: path)
        return path.path
    }
}
