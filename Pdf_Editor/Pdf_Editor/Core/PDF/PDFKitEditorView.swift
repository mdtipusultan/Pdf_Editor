import PDFKit
import SwiftUI

struct PDFKitEditorView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var isDrawingEnabled: Bool
    var drawColor: UIColor
    var drawLineWidth: CGFloat
    var onAnnotationAdded: () -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)
        pdfView.backgroundColor = .systemGroupedBackground

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        context.coordinator.setupDrawingOverlay()
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        context.coordinator.isDrawingEnabled = isDrawingEnabled
        context.coordinator.drawColor = drawColor
        context.coordinator.drawLineWidth = drawLineWidth
        context.coordinator.onAnnotationAdded = onAnnotationAdded
        context.coordinator.updateDrawingOverlay()

        if let page = document.page(at: currentPageIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPageIndex: $currentPageIndex)
    }

    final class Coordinator: NSObject {
        @Binding var currentPageIndex: Int
        weak var pdfView: PDFView?
        var isDrawingEnabled = false
        var drawColor: UIColor = .black
        var drawLineWidth: CGFloat = 3
        var onAnnotationAdded: () -> Void = {}

        private var drawingView: DrawingOverlayView?
        private var currentPath: UIBezierPath?

        init(currentPageIndex: Binding<Int>) {
            _currentPageIndex = currentPageIndex
        }

        func setupDrawingOverlay() {
            guard let pdfView, drawingView == nil else { return }
            let overlay = DrawingOverlayView(frame: pdfView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = .clear
            overlay.onStrokeEnded = { [weak self] path in
                self?.addInkAnnotation(path: path)
            }
            pdfView.addSubview(overlay)
            drawingView = overlay
        }

        func updateDrawingOverlay() {
            drawingView?.isUserInteractionEnabled = isDrawingEnabled
            drawingView?.strokeColor = drawColor
            drawingView?.lineWidth = drawLineWidth
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            currentPageIndex = document.index(for: page)
        }

        private func addInkAnnotation(path: UIBezierPath) {
            guard let pdfView, let page = pdfView.currentPage, let drawingView else { return }

            let pagePath = convertPathToPageCoordinates(
                path,
                from: drawingView,
                pdfView: pdfView,
                page: page
            )
            pagePath.lineWidth = drawLineWidth
            pagePath.lineCapStyle = .round
            pagePath.lineJoinStyle = .round

            PDFAnnotationHelper.addInk(to: page, paths: [pagePath], color: drawColor, width: drawLineWidth)
            onAnnotationAdded()
        }

        private func convertPathToPageCoordinates(
            _ path: UIBezierPath,
            from overlay: UIView,
            pdfView: PDFView,
            page: PDFPage
        ) -> UIBezierPath {
            let pagePath = UIBezierPath()
            path.cgPath.applyWithBlock { element in
                let elementPoints = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint:
                    let pagePoint = pdfView.convert(
                        overlay.convert(elementPoints[0], to: pdfView),
                        to: page
                    )
                    pagePath.move(to: pagePoint)
                case .addLineToPoint:
                    let pagePoint = pdfView.convert(
                        overlay.convert(elementPoints[0], to: pdfView),
                        to: page
                    )
                    pagePath.addLine(to: pagePoint)
                default:
                    break
                }
            }
            return pagePath
        }
    }
}

final class DrawingOverlayView: UIView {
    var strokeColor: UIColor = .black
    var lineWidth: CGFloat = 3
    var onStrokeEnded: ((UIBezierPath) -> Void)?

    private var currentPath: UIBezierPath?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentPath = UIBezierPath()
        currentPath?.lineWidth = lineWidth
        currentPath?.lineCapStyle = .round
        currentPath?.move(to: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentPath?.addLine(to: point)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let path = currentPath else { return }
        onStrokeEnded?(path)
        currentPath = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        strokeColor.setStroke()
        currentPath?.stroke()
    }
}
