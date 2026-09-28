import PDFKit

enum PageOperations {
    static func deletePage(at index: Int, in document: PDFDocument) {
        guard index >= 0, index < document.pageCount else { return }
        document.removePage(at: index)
    }

    static func rotatePage(at index: Int, in document: PDFDocument, degrees: Int = 90) {
        guard let page = document.page(at: index) else { return }
        let current = page.rotation
        page.rotation = (current + degrees) % 360
    }

    static func duplicatePage(at index: Int, in document: PDFDocument) {
        guard let page = document.page(at: index) else { return }
        document.insert(page, at: index + 1)
    }

    static func movePage(from source: Int, to destination: Int, in document: PDFDocument) {
        guard source != destination,
              source >= 0, source < document.pageCount,
              destination >= 0, destination < document.pageCount,
              let page = document.page(at: source) else { return }
        document.removePage(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        document.insert(page, at: insertIndex)
    }
}
