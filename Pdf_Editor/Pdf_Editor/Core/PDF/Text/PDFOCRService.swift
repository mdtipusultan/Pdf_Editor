import CoreGraphics
import PDFKit
import UIKit
import Vision

struct PDFOCRToken: Equatable {
    var text: String
    var bounds: CGRect
}

enum PDFOCRError: LocalizedError {
    case unreadablePage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unreadablePage:
            "Couldn't read this page for OCR."
        case .recognitionFailed:
            "No text was found on this page."
        }
    }
}

/// Vision OCR is intentionally separate from PDF text extraction.
/// It turns a rendered page into text boxes the editor can select.
final class VisionPDFOCRService {
    func recognize(page: PDFPage) async throws -> [PDFOCRToken] {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let rendered = PDFPageImage.thumbnail(of: page, maxDimension: 1800),
              let png = rendered.image.pngData() else {
            throw PDFOCRError.unreadablePage
        }
        let tokens = try await Task.detached(priority: .userInitiated) {
            try VisionPDFOCRService.recognize(png: png, pageBounds: pageBounds)
        }.value
        let cleaned = tokens.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if cleaned.isEmpty {
            throw PDFOCRError.recognitionFailed
        }
        return cleaned
    }

    nonisolated private static func recognize(png: Data, pageBounds: CGRect) throws -> [PDFOCRToken] {
        guard let image = UIImage(data: png)?.cgImage else {
            throw PDFOCRError.unreadablePage
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            let rect = CGRect(
                x: pageBounds.minX + (box.minX * pageBounds.width),
                y: pageBounds.minY + (box.minY * pageBounds.height),
                width: box.width * pageBounds.width,
                height: box.height * pageBounds.height
            )
            guard rect.width > 1, rect.height > 1 else { return nil }
            return PDFOCRToken(text: text, bounds: rect)
        }
    }
}
