import PDFKit
import UIKit
import Vision
import XCTest
@testable import Pdf_Editor

@MainActor
final class PDFTextEditingTests: XCTestCase {
    func testCoordinateConversionRoundTrips() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = CGRect(x: 72, y: 700, width: 120, height: 20)
        let uiKit = PDFCoordinateConverter.uiKitRect(fromPDF: pdf, pageBounds: bounds)
        let restored = PDFCoordinateConverter.pdfRect(fromUIKit: uiKit, pageBounds: bounds)
        XCTAssertEqual(uiKit.origin.y, 72, accuracy: 0.01)
        XCTAssertEqual(restored.origin.x, pdf.origin.x, accuracy: 0.01)
        XCTAssertEqual(restored.origin.y, pdf.origin.y, accuracy: 0.01)
        XCTAssertEqual(restored.width, pdf.width, accuracy: 0.01)
        XCTAssertEqual(restored.height, pdf.height, accuracy: 0.01)
    }

    func testSamplerReadsTheTopOfThePage() throws {
        let size = CGSize(width: 220, height: 220)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 220, height: 48))
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let pdfRect = PDFCoordinateConverter.pdfRect(
            fromUIKit: CGRect(x: 12, y: 8, width: 40, height: 20),
            pageBounds: page.bounds(for: .mediaBox)
        )
        let sample = try XCTUnwrap(PDFBackgroundSampler.sample(page: page, rect: pdfRect))
        XCTAssertGreaterThan(sample.background.blue, 0.45, "Background \(sample.background)")
        XCTAssertLessThan(sample.background.red, 0.35, "Background \(sample.background)")
    }

    func testCompositingKeepsUntouchedPageText() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Name: John Smith", at: CGPoint(x: 72, y: 90)),
            PDFFixture.line("Age: 28", at: CGPoint(x: 72, y: 130))
        ])
        let master = try XCTUnwrap(document.page(at: 0))
        let composited = try XCTUnwrap(PDFPageCompositor.composite(master: master, replacements: [], rotation: 0))
        let visible = try PDFCheck.visibleText(on: composited)
        XCTAssertTrue(visible.contains("John"), "Visible: \(visible) string: \(composited.string ?? "")")
        XCTAssertTrue(visible.contains("28") || visible.contains("Age"), "Visible: \(visible) string: \(composited.string ?? "")")
    }

    func testWhitePageReplacementSurvivesExport() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Name: John Smith", at: CGPoint(x: 72, y: 90)),
            PDFFixture.line("Age: 28", at: CGPoint(x: 72, y: 130))
        ])
        let engine = PDFTextEngine()
        let age = try element(containing: "Age", on: 0, document: document, engine: engine)
        try replace("John Smith", with: "David Smith", on: 0, document: document, engine: engine)
        let reopened = try PDFCheck.reopen(document)
        let page = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertTrue(page.string?.contains("David Smith") == true, "Page string: \(page.string ?? "")")
        let visible = try PDFCheck.visibleText(on: page)
        XCTAssertTrue(visible.contains("David"), "Visible: \(visible)")
        XCTAssertFalse(visible.contains("John"), "Visible: \(visible)")
        let ageInk = PDFCheck.darkRatio(of: page, pdfRect: age.bounds)
        XCTAssertGreaterThan(ageInk, 0.02, "Age line was covered. ink=\(ageInk) visible=\(visible)")
    }

    func testDeletingTextRemovesVisibleInk() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Erase Me", at: CGPoint(x: 72, y: 100), font: .boldSystemFont(ofSize: 28))
        ])
        let engine = PDFTextEngine()
        let element = try element(containing: "Erase", on: 0, document: document, engine: engine)
        let before = PDFCheck.darkRatio(of: try XCTUnwrap(document.page(at: 0)), pdfRect: element.bounds)
        _ = try engine.apply(element: element, newText: "", style: element.style, document: document)
        let reopened = try PDFCheck.reopen(document)
        let after = PDFCheck.darkRatio(of: try XCTUnwrap(reopened.page(at: 0)), pdfRect: element.bounds)
        XCTAssertGreaterThan(before, 0.02, "Expected ink before deletion, ratio \(before)")
        XCTAssertLessThan(after, before * 0.4, "Cover missed the text. before \(before) after \(after)")
    }

    func testMultipleEditsRemainAfterExport() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Name: John", at: CGPoint(x: 72, y: 80)),
            PDFFixture.line("Age: 28", at: CGPoint(x: 72, y: 120)),
            PDFFixture.line("City: Dhaka", at: CGPoint(x: 72, y: 160))
        ])
        let engine = PDFTextEngine()
        try replace("John", with: "David", on: 0, document: document, engine: engine)
        try replace("28", with: "30", on: 0, document: document, engine: engine)
        try replace("Dhaka", with: "Chittagong", on: 0, document: document, engine: engine)
        let visible = try PDFCheck.visibleText(on: try XCTUnwrap(PDFCheck.reopen(document).page(at: 0)))
        XCTAssertTrue(visible.contains("David"), visible)
        XCTAssertTrue(visible.contains("30"), visible)
        XCTAssertTrue(visible.contains("Chittagong"), visible)
        XCTAssertFalse(visible.contains("John"), visible)
        XCTAssertFalse(visible.contains("Dhaka"), visible)
    }

    func testColoredBackgroundIsSampled() throws {
        let document = PDFFixture.page(
            lines: [PDFFixture.line("White Words", at: CGPoint(x: 72, y: 120), color: .white)],
            background: UIColor(red: 0.12, green: 0.28, blue: 0.72, alpha: 1)
        )
        let engine = PDFTextEngine()
        let element = try element(containing: "White", on: 0, document: document, engine: engine)
        XCTAssertGreaterThan(element.backgroundColor.blue, element.backgroundColor.red)
        XCTAssertTrue(element.canEditDirectly)
        _ = try engine.apply(
            element: element,
            newText: "Blue Words",
            style: element.style,
            document: document
        )
        let visible = try PDFCheck.visibleText(on: try XCTUnwrap(PDFCheck.reopen(document).page(at: 0)))
        XCTAssertTrue(visible.contains("Blue"), visible)
        XCTAssertFalse(visible.contains("White"), visible)
    }

    func testColoredTextIsDetected() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Red Label", at: CGPoint(x: 72, y: 100), color: UIColor(red: 0.86, green: 0.08, blue: 0.08, alpha: 1))
        ])
        let element = try element(containing: "Red", on: 0, document: document, engine: PDFTextEngine())
        XCTAssertGreaterThan(element.style.color.red, element.style.color.blue)
        XCTAssertGreaterThan(element.style.color.red, 0.4)
    }

    func testDifferentFontSizesStayOrdered() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Small Text", at: CGPoint(x: 72, y: 80), font: .systemFont(ofSize: 12)),
            PDFFixture.line("Large Text", at: CGPoint(x: 72, y: 140), font: .systemFont(ofSize: 28))
        ])
        let engine = PDFTextEngine()
        let small = try element(containing: "Small", on: 0, document: document, engine: engine)
        let large = try element(containing: "Large", on: 0, document: document, engine: engine)
        XCTAssertGreaterThan(large.style.fontSize, small.style.fontSize)
    }

    func testEditingOneLineKeepsTheOtherLine() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Address:", at: CGPoint(x: 72, y: 100), font: .systemFont(ofSize: 16)),
            PDFFixture.line("Dhaka, Bangladesh", at: CGPoint(x: 72, y: 126), font: .systemFont(ofSize: 16))
        ])
        let engine = PDFTextEngine()
        let lines = engine.elements(on: 0, document: document)
        XCTAssertGreaterThanOrEqual(lines.count, 2, "Lines: \(lines.map(\.text))")
        let paragraph = engine.paragraphElement(
            containing: try element(containing: "Dhaka", on: 0, document: document, engine: engine),
            document: document
        )
        XCTAssertTrue(paragraph.text.contains("\n"), paragraph.text)
        let address = try element(containing: "Address", on: 0, document: document, engine: engine)
        try replace("Dhaka, Bangladesh", with: "Chittagong, Bangladesh", on: 0, document: document, engine: engine)
        let page = try XCTUnwrap(PDFCheck.reopen(document).page(at: 0))
        let visible = try PDFCheck.visibleText(on: page)
        let addressInk = PDFCheck.darkRatio(of: page, pdfRect: address.bounds)
        XCTAssertGreaterThan(addressInk, 0.02, "Address was covered. ink=\(addressInk) visible=\(visible)")
        XCTAssertTrue(visible.contains("Chittagong"), visible)
        XCTAssertFalse(visible.contains("Dhaka"), visible)
    }

    func testLongerReplacementHidesTheOriginal() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("John", at: CGPoint(x: 72, y: 110), font: .systemFont(ofSize: 22))
        ])
        let engine = PDFTextEngine()
        let element = try element(containing: "John", on: 0, document: document, engine: engine)
        _ = try engine.apply(element: element, newText: "Christopher", style: element.style, document: document)
        let page = try XCTUnwrap(PDFCheck.reopen(document).page(at: 0))
        let visible = try PDFCheck.visibleText(on: page)
        XCTAssertTrue(visible.contains("Christopher"), visible)
        XCTAssertFalse(visible.contains("John"), visible)
        XCTAssertLessThan(element.style.fontSize, 80)
    }

    func testEditsOnSeparatePagesBothExport() throws {
        let document = PDFFixture.pages([
            [PDFFixture.line("Name: Alice", at: CGPoint(x: 72, y: 90))],
            [PDFFixture.line("Middle page", at: CGPoint(x: 72, y: 90))],
            [PDFFixture.line("Company: North", at: CGPoint(x: 72, y: 90))]
        ])
        let engine = PDFTextEngine()
        try replace("Alice", with: "Maria", on: 0, document: document, engine: engine)
        try replace("North", with: "South", on: 2, document: document, engine: engine)
        let reopened = try PDFCheck.reopen(document)
        XCTAssertEqual(reopened.pageCount, 3)
        let first = try PDFCheck.visibleText(on: try XCTUnwrap(reopened.page(at: 0)))
        let third = try PDFCheck.visibleText(on: try XCTUnwrap(reopened.page(at: 2)))
        XCTAssertTrue(first.contains("Maria"), first)
        XCTAssertFalse(first.contains("Alice"), first)
        XCTAssertTrue(third.contains("South"), third)
        XCTAssertFalse(third.contains("North"), third)
    }

    func testScannedPageIsNotPretendingToBeEditableText() throws {
        let document = PDFFixture.scannedPage()
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFDocumentInspector.contentKind(of: page), .scanned)
        XCTAssertTrue(PDFTextEngine().elements(on: 0, document: document).isEmpty)
    }

    func testLargeDocumentEditDoesNotDropPages() throws {
        let document = PDFFixture.largeDocument(pageCount: 60, textPage: 59)
        XCTAssertEqual(document.pageCount, 60)
        let engine = PDFTextEngine()
        let element = try element(containing: "UniqueToken", on: 59, document: document, engine: engine)
        _ = try engine.apply(element: element, newText: "EditedToken", style: element.style, document: document)
        let reopened = try PDFCheck.reopen(document)
        XCTAssertEqual(reopened.pageCount, 60)
        let visible = try PDFCheck.visibleText(on: try XCTUnwrap(reopened.page(at: 59)))
        XCTAssertTrue(visible.contains("Edited"), visible)
        XCTAssertFalse(visible.contains("Unique"), visible)
    }

    func testRotatedPageCanBeReplaced() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Rotate Me", at: CGPoint(x: 72, y: 140), font: .boldSystemFont(ofSize: 26))
        ])
        document.page(at: 0)?.rotation = 90
        let engine = PDFTextEngine()
        try replace("Rotate", with: "Turned", on: 0, document: document, engine: engine)
        let visible = try PDFCheck.visibleText(on: try XCTUnwrap(PDFCheck.reopen(document).page(at: 0)))
        XCTAssertTrue(visible.contains("Turned"), visible)
        XCTAssertFalse(visible.contains("Rotate"), visible)
    }

    func testUndoAndRedoChangeTheExportedPixels() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("John Smith", at: CGPoint(x: 72, y: 100), font: .boldSystemFont(ofSize: 26))
        ])
        let engine = PDFTextEngine()
        let undoManager = PDFUndoManager()
        undoManager.recordSnapshot(document, textState: engine.snapshot())
        try replace("John Smith", with: "David Smith", on: 0, document: document, engine: engine)

        var visible = try PDFCheck.visibleText(on: try XCTUnwrap(document.page(at: 0)))
        XCTAssertTrue(visible.contains("David"), visible)

        XCTAssertTrue(undoManager.undo(on: document, currentTextState: engine.snapshot()))
        engine.restore(undoManager.lastRestoredTextState)
        visible = try PDFCheck.visibleText(on: try XCTUnwrap(document.page(at: 0)))
        XCTAssertTrue(visible.contains("John"), visible)
        XCTAssertFalse(visible.contains("David"), visible)

        XCTAssertTrue(undoManager.redo(on: document, currentTextState: engine.snapshot()))
        engine.restore(undoManager.lastRestoredTextState)
        let reopened = try PDFCheck.reopen(document)
        visible = try PDFCheck.visibleText(on: try XCTUnwrap(reopened.page(at: 0)))
        XCTAssertTrue(visible.contains("David"), visible)
        XCTAssertFalse(visible.contains("John"), visible)
    }

    func testAnnotationSurvivesTextReplacement() throws {
        let document = PDFFixture.page(lines: [
            PDFFixture.line("Keep Nearby", at: CGPoint(x: 72, y: 80))
        ])
        let page = try XCTUnwrap(document.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 72, y: 40, width: 120, height: 24), forType: .freeText, withProperties: nil)
        note.contents = "Keep me"
        page.addAnnotation(note)
        let engine = PDFTextEngine()
        try replace("Keep Nearby", with: "Changed Nearby", on: 0, document: document, engine: engine)
        let reopened = try PDFCheck.reopen(document)
        let annotations = reopened.page(at: 0)?.annotations ?? []
        XCTAssertTrue(annotations.contains { $0.contents == "Keep me" }, "Annotations: \(annotations.map(\.contents))")
    }

    func testImageAndTextPageStillReplacesText() throws {
        let document = PDFFixture.pageWithImage(text: "Caption Here")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFDocumentInspector.contentKind(of: page), .mixed)
        let engine = PDFTextEngine()
        try replace("Caption", with: "Updated", on: 0, document: document, engine: engine)
        let visible = try PDFCheck.visibleText(on: try XCTUnwrap(PDFCheck.reopen(document).page(at: 0)))
        XCTAssertTrue(visible.contains("Updated"), visible)
        XCTAssertFalse(visible.contains("Caption"), visible)
    }

    func testLockedDocumentIsRejected() throws {
        let document = PDFFixture.page(lines: [PDFFixture.line("Secret", at: CGPoint(x: 72, y: 80))])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        XCTAssertTrue(document.write(to: url, withOptions: [
            .userPasswordOption: "secret",
            .ownerPasswordOption: "owner"
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        let locked = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(PDFDocumentInspector.editingRestriction(of: locked), .locked)
        XCTAssertNil(PDFDocumentInspector.editingRestriction(of: document))
    }

    func testSignatureAnnotationIsDetected() throws {
        let document = PDFFixture.page(lines: [PDFFixture.line("Signed", at: CGPoint(x: 72, y: 80))])
        XCTAssertFalse(PDFDocumentInspector.hasDigitalSignature(document))
        let page = try XCTUnwrap(document.page(at: 0))
        let widget = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 40, height: 20), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .signature
        page.addAnnotation(widget)
        XCTAssertTrue(PDFDocumentInspector.hasDigitalSignature(document))
    }

    func testFontMatcherFallsBackWithoutCrashing() {
        let missing = PDFTextStyle(
            fontName: "DefinitelyMissingFontXYZ",
            fontSize: 14,
            color: .black,
            alignment: .left,
            isBold: true,
            isItalic: false
        )
        let font = PDFFontMatcher.font(for: missing)
        XCTAssertEqual(font.pointSize, 14, accuracy: 0.1)

        XCTAssertEqual(PDFFontMatcher.normalized("ABCDEF+Times-Roman"), "Times-Roman")
        let times = PDFFontMatcher.font(for: PDFTextStyle(
            fontName: "ABCDEF+Helvetica-Bold",
            fontSize: 18,
            color: .black,
            alignment: .left,
            isBold: true,
            isItalic: false
        ))
        XCTAssertTrue(times.fontName.localizedCaseInsensitiveContains("Helvetica") || times.fontName.localizedCaseInsensitiveContains("Bold"))
    }

    func testExistingTextEditingIsProOnly() {
        #if DEBUG
        EntitlementManager.shared.disableDebugPro()
        defer { EntitlementManager.shared.resetDebugPro() }
        XCTAssertFalse(AppFeatureAccess.shared.canEditExistingText())
        XCTAssertTrue(EditorTool.editText.requiresPro)
        EntitlementManager.shared.enableDebugPro()
        XCTAssertTrue(AppFeatureAccess.shared.canEditExistingText())
        #endif
    }

    private func element(
        containing needle: String,
        on pageIndex: Int,
        document: PDFDocument,
        engine: PDFTextEngine
    ) throws -> PDFTextElement {
        let elements = engine.elements(on: pageIndex, document: document)
        return try XCTUnwrap(
            elements.first { $0.text.localizedCaseInsensitiveContains(needle) },
            "Looking for \(needle). Elements: \(elements.map(\.text)). Page: \(document.page(at: pageIndex)?.string ?? "")"
        )
    }

    private func replace(
        _ needle: String,
        with replacement: String,
        on pageIndex: Int,
        document: PDFDocument,
        engine: PDFTextEngine
    ) throws {
        let current = try element(containing: needle, on: pageIndex, document: document, engine: engine)
        let updated = current.text.replacingOccurrences(of: needle, with: replacement)
        _ = try engine.apply(element: current, newText: updated, style: current.style, document: document)
    }
}

private enum PDFFixture {
    static func line(
        _ text: String,
        at origin: CGPoint,
        font: UIFont = .systemFont(ofSize: 20),
        color: UIColor = .black
    ) -> PDFLineSpec {
        let width = max(160, font.pointSize * CGFloat(text.count) * 0.7)
        return PDFLineSpec(text: text, rect: CGRect(x: origin.x, y: origin.y, width: width, height: font.pointSize + 8), font: font, color: color)
    }

    static func page(
        lines: [PDFLineSpec],
        background: UIColor = .white,
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) -> PDFDocument {
        pages([lines], background: background, pageSize: pageSize)
    }

    static func pages(
        _ pages: [[PDFLineSpec]],
        background: UIColor = .white,
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            for pageLines in pages {
                context.beginPage()
                background.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
                for line in pageLines {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: line.font,
                        .foregroundColor: line.color
                    ]
                    (line.text as NSString).draw(in: line.rect, withAttributes: attributes)
                }
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    static func scannedPage() -> PDFDocument {
        let size = CGSize(width: 420, height: 540)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("SCANNED ONLY" as NSString).draw(
                at: CGPoint(x: 40, y: 220),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.black]
            )
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    static func pageWithImage(text: String) -> PDFDocument {
        let size = CGSize(width: 612, height: 792)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: 72, y: 80, width: 80, height: 80))
            (text as NSString).draw(
                in: CGRect(x: 72, y: 190, width: 240, height: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black]
            )
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    static func largeDocument(pageCount: Int, textPage: Int) -> PDFDocument {
        let size = CGSize(width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                if index == textPage {
                    ("UniqueToken" as NSString).draw(
                        at: CGPoint(x: 72, y: 90),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)]
                    )
                }
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }
}

private struct PDFLineSpec {
    var text: String
    var rect: CGRect
    var font: UIFont
    var color: UIColor
}

private enum PDFCheck {
    static func reopen(_ document: PDFDocument) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        XCTAssertTrue(document.write(to: url))
        let reopened = try XCTUnwrap(PDFDocument(url: url))
        try? FileManager.default.removeItem(at: url)
        return reopened
    }

    static func visibleText(on page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    static func darkRatio(of page: PDFPage, pdfRect: CGRect) -> CGFloat {
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let uiRect = PDFCoordinateConverter.uiKitRect(fromPDF: pdfRect, pageBounds: bounds)
        let scaleX = CGFloat(width) / max(bounds.width, 1)
        let scaleY = CGFloat(height) / max(bounds.height, 1)
        let minX = max(0, Int(uiRect.minX * scaleX))
        let maxX = min(width - 1, Int(uiRect.maxX * scaleX))
        let minY = max(0, Int(uiRect.minY * scaleY))
        let maxY = min(height - 1, Int(uiRect.maxY * scaleY))
        guard minX < maxX, minY < maxY else { return 0 }
        var dark = 0
        var total = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = ((y * width) + x) * 4
                let luminance = (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])) / 255
                if luminance < 0.55 { dark += 1 }
                total += 1
            }
        }
        guard total > 0 else { return 0 }
        return CGFloat(dark) / CGFloat(total)
    }
}
