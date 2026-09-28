import PDFKit
import UIKit

enum PDFAnnotationHelper {
    static func addFreeText(
        to page: PDFPage,
        text: String,
        at rect: CGRect,
        fontSize: CGFloat,
        color: UIColor
    ) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont.systemFont(ofSize: fontSize)
        annotation.fontColor = color
        annotation.color = .clear
        page.addAnnotation(annotation)
        return annotation
    }

    static func addInk(to page: PDFPage, paths: [UIBezierPath], color: UIColor, width: CGFloat) {
        guard !paths.isEmpty else { return }

        let bounds = paths.reduce(CGRect.null) { $0.union($1.bounds) }
        let paddedBounds = bounds.insetBy(dx: -width, dy: -width)

        let annotation = PDFAnnotation(bounds: paddedBounds, forType: .ink, withProperties: nil)
        annotation.color = color
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = width

        // PDFKit expects InkList to be an array of UIBezierPath objects (each responds to cgPath).
        annotation.setValue(paths, forAnnotationKey: PDFAnnotationKey(rawValue: "InkList"))
        page.addAnnotation(annotation)
    }

    static func addHighlight(to page: PDFPage, bounds: CGRect, style: MarkupStyle, color: UIColor) {
        let subtype: PDFAnnotationSubtype = switch style {
        case .highlight: .highlight
        case .underline: .underline
        case .strikethrough: .strikeOut
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        annotation.color = color.withAlphaComponent(style == .highlight ? 0.4 : 1.0)
        page.addAnnotation(annotation)
    }

    static func addShape(to page: PDFPage, type: ShapeType, bounds: CGRect, color: UIColor, lineWidth: CGFloat) {
        let annotationType: PDFAnnotationSubtype = switch type {
        case .rectangle: .square
        case .circle: .circle
        case .checkmark: .stamp
        }

        let annotation = PDFAnnotation(bounds: bounds, forType: annotationType, withProperties: nil)
        annotation.color = .clear
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = lineWidth
        annotation.color = color

        if type == .checkmark {
            annotation.setValue("Checkmark", forAnnotationKey: .name)
            if let image = drawCheckmark(in: bounds.size, color: color) {
                annotation.setValue(image, forAnnotationKey: PDFAnnotationKey(rawValue: "AP"))
            }
        }

        page.addAnnotation(annotation)
    }

    static func addImageStamp(to page: PDFPage, image: UIImage, at rect: CGRect) {
        let annotation = PDFAnnotation(bounds: rect, forType: .stamp, withProperties: nil)
        annotation.setValue(image, forAnnotationKey: PDFAnnotationKey(rawValue: "AP"))
        page.addAnnotation(annotation)
    }

    static func addSignature(to page: PDFPage, image: UIImage, at rect: CGRect) {
        addImageStamp(to: page, image: image, at: rect)
    }

    static func annotationCount(in document: PDFDocument) -> Int {
        var count = 0
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                count += page.annotations.count
            }
        }
        return count
    }

    static func deleteSelectedAnnotations(from page: PDFPage) {
        for annotation in page.annotations where annotation.shouldDisplay {
            if annotation.isHighlighted {
                page.removeAnnotation(annotation)
            }
        }
    }

    private static func drawCheckmark(in size: CGSize, color: UIColor) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setStroke()
            let path = UIBezierPath()
            path.lineWidth = max(2, size.width * 0.08)
            path.lineCapStyle = .round
            path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.5))
            path.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.72))
            path.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.28))
            path.stroke()
        }
    }
}
