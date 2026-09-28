import PDFKit
import UIKit

final class TextSelectionOverlayView: UIView {
    weak var pdfView: PDFView?
    var pdfRect: CGRect?
    var pageIndex: Int?

    private let highlight = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        highlight.isUserInteractionEnabled = false
        highlight.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        highlight.layer.borderColor = UIColor.systemBlue.cgColor
        highlight.layer.borderWidth = 1.5
        highlight.layer.cornerRadius = 3
        highlight.isHidden = true
        addSubview(highlight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        guard let pdfView,
              let pdfRect,
              let pageIndex,
              let page = pdfView.document?.page(at: pageIndex) else {
            highlight.isHidden = true
            return
        }
        let rect = PDFCoordinateConverter.viewRect(pdfRect, page: page, pdfView: pdfView)
        guard rect.width > 1, rect.height > 1 else {
            highlight.isHidden = true
            return
        }
        highlight.frame = rect.insetBy(dx: -2, dy: -2)
        highlight.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }
}
