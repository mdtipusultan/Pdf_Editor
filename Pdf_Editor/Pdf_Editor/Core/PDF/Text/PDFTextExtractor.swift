import CoreGraphics
import PDFKit
import UIKit

enum PDFTextExtractor {
    static func extract(pageIndex: Int, from document: PDFDocument) -> [PDFTextElement] {
        guard let page = document.page(at: pageIndex) else { return [] }
        guard page.numberOfCharacters > 0, let raw = page.string, !raw.isEmpty else { return [] }

        let ns = raw as NSString
        guard let selection = page.selection(for: NSRange(location: 0, length: ns.length)) else { return [] }
        let lines = selection.selectionsByLine()
        guard !lines.isEmpty else { return [] }

        let pageBounds = page.bounds(for: .mediaBox)
        let fontSamples = PDFFontMatcher.samples(on: page)
        let rendered = PDFPageImage.thumbnail(of: page)

        return lines.compactMap { line in
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let bounds = line.bounds(for: page)
            guard bounds.width > 0.4, bounds.height > 0.4, bounds.width < 20_000 else { return nil }

            let sample = rendered.flatMap {
                PDFBackgroundSampler.sample(image: $0.image, pageBounds: $0.pageBounds, pdfRect: bounds)
            }
            var style = PDFFontMatcher.style(
                estimatedSize: max(PDFTextLayout.minimumFontSize, bounds.height * 0.8),
                samples: fontSamples,
                color: sample?.foreground ?? .black
            )
            style.alignment = alignment(for: bounds, pageBounds: pageBounds)

            return PDFTextElement(
                id: UUID(),
                pageIndex: pageIndex,
                text: text,
                bounds: bounds,
                style: style,
                backgroundColor: sample?.background ?? .white,
                backgroundIsUniform: sample?.isUniform ?? false,
                source: .content,
                lineCount: 1
            )
        }
    }

    static func paragraph(containing element: PDFTextElement, among elements: [PDFTextElement]) -> PDFTextElement {
        let lines = elements
            .filter { $0.pageIndex == element.pageIndex && $0.source == .content }
            .sorted { $0.bounds.maxY > $1.bounds.maxY }
        guard let start = lines.firstIndex(where: { $0.id == element.id }) else { return element }

        var indexes = [start]
        var cursor = start
        while cursor > 0, shouldJoin(lines[cursor - 1], lines[cursor]) {
            cursor -= 1
            indexes.insert(cursor, at: 0)
        }
        cursor = start
        while cursor + 1 < lines.count, shouldJoin(lines[cursor], lines[cursor + 1]) {
            cursor += 1
            indexes.append(cursor)
        }

        let grouped = indexes.map { lines[$0] }
        guard grouped.count > 1 else { return element }
        let text = grouped.map(\.text).joined(separator: "\n")
        let bounds = grouped.reduce(CGRect.null) { $0.union($1.bounds) }
        let uniform = grouped.allSatisfy(\.backgroundIsUniform)
        return PDFTextElement(
            id: UUID(),
            pageIndex: element.pageIndex,
            text: text,
            bounds: bounds,
            style: element.style,
            backgroundColor: element.backgroundColor,
            backgroundIsUniform: uniform,
            source: .content,
            lineCount: grouped.count
        )
    }

    static func shouldJoin(_ upper: PDFTextElement, _ lower: PDFTextElement) -> Bool {
        let gap = upper.bounds.minY - lower.bounds.maxY
        let lineHeight = max(upper.bounds.height, lower.bounds.height)
        let close = gap >= -2 && gap <= max(8, lineHeight * 0.5)
        let overlap = horizontalOverlap(upper.bounds, lower.bounds)
        let aligned = abs(upper.bounds.minX - lower.bounds.minX) < 14
        return close && (overlap > 0.35 || aligned)
    }

    private static func alignment(for bounds: CGRect, pageBounds: CGRect) -> PDFTextAlignment {
        let left = bounds.minX - pageBounds.minX
        let right = pageBounds.maxX - bounds.maxX
        if left > 36, right > 36, abs(left - right) < 28 {
            return .center
        }
        if left > right + 80, right < 48 {
            return .right
        }
        return .left
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        guard overlap > 0 else { return 0 }
        return overlap / max(1, min(a.width, b.width))
    }
}
