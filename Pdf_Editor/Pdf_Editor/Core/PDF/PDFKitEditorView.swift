import PDFKit
import SwiftUI

struct PDFKitEditorView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var documentRevision: Int
    var isDrawingEnabled: Bool
    var drawColor: UIColor
    var drawLineWidth: CGFloat
    var isTextSelectionEnabled: Bool
    var selectedTextPageIndex: Int?
    var selectedTextBounds: CGRect?
    var onAnnotationAdded: () -> Void
    var onTextTap: (Int, CGPoint) -> Void

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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTextTap(_:)))
        tap.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(tap)

        context.coordinator.pdfView = pdfView
        context.coordinator.setupDrawingOverlay()
        context.coordinator.setupSelectionOverlay()
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.document = document
        context.coordinator.isDrawingEnabled = isDrawingEnabled
        context.coordinator.drawColor = drawColor
        context.coordinator.drawLineWidth = drawLineWidth
        context.coordinator.onAnnotationAdded = onAnnotationAdded
        context.coordinator.onTextTap = onTextTap
        context.coordinator.isTextSelectionEnabled = isTextSelectionEnabled
        context.coordinator.refreshDocumentIfNeeded(pdfView, revision: documentRevision)
        if pdfView.document !== document {
            pdfView.document = document
        }
        context.coordinator.updateDrawingOverlay()
        context.coordinator.updateSelection(pageIndex: selectedTextPageIndex, bounds: selectedTextBounds)
        context.coordinator.attachScrollObserver(to: pdfView)

        if let page = document.page(at: currentPageIndex),
           pdfView.currentPage !== page,
           !context.coordinator.isRefreshingDocument {
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
        var onTextTap: (Int, CGPoint) -> Void = { _, _ in }
        var isTextSelectionEnabled = false
        var isRefreshingDocument = false
        var document: PDFDocument?

        private var drawingView: DrawingOverlayView?
        private var selectionOverlay: TextSelectionOverlayView?
        private weak var observedScrollView: UIScrollView?
        private var isObservingScroll = false
        private var appliedRevision = 0
        private static var scrollContext = 0

        init(currentPageIndex: Binding<Int>) {
            _currentPageIndex = currentPageIndex
        }

        deinit {
            if isObservingScroll {
                observedScrollView?.removeObserver(self, forKeyPath: "contentOffset", context: &Self.scrollContext)
            }
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

        func setupSelectionOverlay() {
            guard let pdfView, selectionOverlay == nil else { return }
            let overlay = TextSelectionOverlayView(frame: pdfView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.pdfView = pdfView
            pdfView.addSubview(overlay)
            selectionOverlay = overlay
        }

        func updateDrawingOverlay() {
            drawingView?.isUserInteractionEnabled = isDrawingEnabled
            drawingView?.strokeColor = drawColor
            drawingView?.lineWidth = drawLineWidth
        }

        func updateSelection(pageIndex: Int?, bounds: CGRect?) {
            selectionOverlay?.pageIndex = pageIndex
            selectionOverlay?.pdfRect = bounds
            selectionOverlay?.refresh()
            if let pdfView, let selectionOverlay {
                pdfView.bringSubviewToFront(selectionOverlay)
            }
        }

        func refreshDocumentIfNeeded(_ pdfView: PDFView, revision: Int) {
            guard revision != appliedRevision else { return }
            appliedRevision = revision
            let scale = pdfView.scaleFactor
            isRefreshingDocument = true
            pdfView.autoScales = false
            pdfView.document = nil
            pdfView.document = document
            if let page = document?.page(at: currentPageIndex) {
                pdfView.go(to: page)
            }
            if scale > 0 {
                pdfView.scaleFactor = scale
            }
            isRefreshingDocument = false
            selectionOverlay?.pdfView = pdfView
            selectionOverlay?.refresh()
            attachScrollObserver(to: pdfView)
        }

        func attachScrollObserver(to pdfView: PDFView) {
            let scrollView = findScrollView(in: pdfView)
            guard scrollView !== observedScrollView else { return }
            if isObservingScroll {
                observedScrollView?.removeObserver(self, forKeyPath: "contentOffset", context: &Self.scrollContext)
                isObservingScroll = false
            }
            observedScrollView = scrollView
            if let scrollView {
                scrollView.addObserver(self, forKeyPath: "contentOffset", options: [.new], context: &Self.scrollContext)
                isObservingScroll = true
            }
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if context == &Self.scrollContext {
                selectionOverlay?.refresh()
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isRefreshingDocument,
                  let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            currentPageIndex = document.index(for: page)
            selectionOverlay?.refresh()
        }

        @objc func scaleChanged(_ notification: Notification) {
            selectionOverlay?.refresh()
        }

        @objc func handleTextTap(_ gesture: UITapGestureRecognizer) {
            guard isTextSelectionEnabled, let pdfView, gesture.state == .ended else { return }
            let location = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: false) ?? pdfView.page(for: location, nearest: true) else { return }
            let point = PDFCoordinateConverter.pdfPoint(from: location, in: pdfView, page: page)
            let index = pdfView.document?.index(for: page) ?? currentPageIndex
            onTextTap(index, point)
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

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) {
                    return found
                }
            }
            return nil
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
