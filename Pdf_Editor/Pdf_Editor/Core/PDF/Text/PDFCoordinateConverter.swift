import CoreGraphics
import PDFKit

enum PDFCoordinateConverter {
    /// Converts a rectangle in PDF page space (origin at the bottom left of `pageBounds`)
    /// into UIKit space (origin at the top left) for a context the size of `pageBounds`.
    static func uiKitRect(fromPDF rect: CGRect, pageBounds: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - pageBounds.minX,
            y: pageBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func pdfRect(fromUIKit rect: CGRect, pageBounds: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + pageBounds.minX,
            y: pageBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func viewRect(_ pdfRect: CGRect, page: PDFPage, pdfView: PDFView) -> CGRect {
        pdfView.convert(pdfRect, from: page)
    }

    static func pdfPoint(from viewPoint: CGPoint, in pdfView: PDFView, page: PDFPage) -> CGPoint {
        pdfView.convert(viewPoint, to: page)
    }
}
