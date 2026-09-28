import CoreGraphics
import UIKit

final class PDFTextCache {
    private var pages: [Int: [PDFTextElement]] = [:]

    func elements(for pageIndex: Int) -> [PDFTextElement]? {
        pages[pageIndex]
    }

    func insert(_ elements: [PDFTextElement], for pageIndex: Int) {
        pages[pageIndex] = elements
    }

    func snapshot() -> [Int: [PDFTextElement]] {
        pages
    }

    func restore(_ pages: [Int: [PDFTextElement]]) {
        self.pages = pages
    }

    func reindex(_ map: [Int: Int]) {
        var updated: [Int: [PDFTextElement]] = [:]
        for (index, elements) in pages {
            guard let newIndex = map[index] else { continue }
            updated[newIndex] = elements.map { element in
                var copy = element
                copy.pageIndex = newIndex
                return copy
            }
        }
        pages = updated
    }
}
