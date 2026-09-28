import CoreGraphics
import PDFKit
import UIKit

enum PDFPageCompositor {
    /// Replays `master` into a new PDF page and paints each replacement on top.
    /// The destination is a PDF context, so vectors, images, and the new text
    /// stay as PDF content instead of a flattened screenshot.
    static func composite(
        master: PDFPage,
        replacements: [PDFTextReplacement],
        rotation: Int
    ) -> PDFPage? {
        let pageBounds = master.bounds(for: .mediaBox)
        guard pageBounds.width > 1, pageBounds.height > 1 else { return nil }
        let rendererBounds = CGRect(origin: .zero, size: pageBounds.size)
        let renderer = UIGraphicsPDFRenderer(bounds: rendererBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.saveGState()
            // UIGraphicsPDFRenderer uses a top-left origin. PDFPage draws in PDF space.
            cgContext.translateBy(x: 0, y: pageBounds.height)
            cgContext.scaleBy(x: 1, y: -1)
            if pageBounds.origin != .zero {
                cgContext.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            }
            master.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
            for replacement in replacements {
                draw(replacement, pageBounds: pageBounds)
            }
        }
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        let normalized = ((rotation % 360) + 360) % 360
        if normalized != 0 {
            page.rotation = normalized
        }
        return page
    }

    private static func draw(_ replacement: PDFTextReplacement, pageBounds: CGRect) {
        let cover = PDFCoordinateConverter.uiKitRect(fromPDF: replacement.coverBounds, pageBounds: pageBounds)
        let visible = PDFCoordinateConverter.uiKitRect(fromPDF: replacement.visibleBounds, pageBounds: pageBounds)
        guard cover.width > 0.5, cover.height > 0.5 else { return }

        replacement.backgroundColor.uiColor.setFill()
        UIBezierPath(rect: cover).fill()
        guard !replacement.text.isEmpty else { return }

        let font = PDFFontMatcher.font(for: replacement.style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = replacement.style.alignment.nsTextAlignment
        paragraph.lineBreakMode = replacement.text.contains("\n") ? .byWordWrapping : .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: replacement.style.color.uiColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: replacement.text, attributes: attributes)
        let measured = PDFTextFitter.measure(replacement.text, font: font, wrapping: max(visible.width, 1))
        var textRect = visible
        if !replacement.text.contains("\n") {
            let extra = visible.height - measured.height
            if extra > 0 {
                textRect.origin.y += extra / 2
                textRect.size.height = measured.height
            }
        }
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
    }
}
