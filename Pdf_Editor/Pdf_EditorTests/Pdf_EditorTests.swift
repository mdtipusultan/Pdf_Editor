import PDFKit
import XCTest
@testable import Pdf_Editor

final class AppFeatureAccessTests: XCTestCase {
    func testFreeAnnotationLimit() {
        let access = AppFeatureAccess.shared
        #if DEBUG
        EntitlementManager.shared.disableDebugPro()
        #endif
        XCTAssertTrue(access.canAddAnnotation(currentCount: 5))
        XCTAssertFalse(access.canAddAnnotation(currentCount: AppFeatureLimits.freeAnnotationsPerDocument))
    }

    func testProBypassesLimits() {
        #if DEBUG
        EntitlementManager.shared.enableDebugPro()
        defer { EntitlementManager.shared.resetDebugPro() }
        let access = AppFeatureAccess.shared
        XCTAssertTrue(access.canAddAnnotation(currentCount: 100))
        XCTAssertTrue(access.canUsePageManagement())
        #endif
    }

    func testToolAccess() {
        #if DEBUG
        EntitlementManager.shared.disableDebugPro()
        defer { EntitlementManager.shared.resetDebugPro() }
        let access = AppFeatureAccess.shared
        XCTAssertTrue(access.canUseTool(.text))
        XCTAssertFalse(access.canUseTool(.pages))
        #endif
    }
}

final class PageOperationsTests: XCTestCase {
    func testRotatePage() {
        let document = makeTestDocument(pages: 1)
        PageOperations.rotatePage(at: 0, in: document)
        XCTAssertEqual(document.page(at: 0)?.rotation, 90)
    }

    func testDeletePage() {
        let document = makeTestDocument(pages: 3)
        PageOperations.deletePage(at: 1, in: document)
        XCTAssertEqual(document.pageCount, 2)
    }

    func testDuplicatePage() {
        let document = makeTestDocument(pages: 2)
        PageOperations.duplicatePage(at: 0, in: document)
        XCTAssertEqual(document.pageCount, 3)
    }

    func testMovePage() {
        let document = makeTestDocument(pages: 3)
        PageOperations.movePage(from: 0, to: 2, in: document)
        XCTAssertEqual(document.pageCount, 3)
    }

    private func makeTestDocument(pages: Int) -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<pages {
            let page = PDFPage()
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}

final class PDFUndoManagerTests: XCTestCase {
    func testUndoRedo() {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let undoManager = PDFUndoManager()
        undoManager.recordSnapshot(document)
        document.insert(PDFPage(), at: 1)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(undoManager.undo(on: document))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(undoManager.redo(on: document))
        XCTAssertEqual(document.pageCount, 2)
    }
}

final class DocumentStorageTests: XCTestCase {
    func testUniqueFileName() {
        let name1 = DocumentStorage.uniqueFileName(basedOn: "test.pdf")
        XCTAssertTrue(name1.hasSuffix(".pdf"))
    }

    func testImportInvalidData() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.pdf")
        try? Data("not a pdf".utf8).write(to: tempURL)
        do {
            _ = try await DocumentStorage.importPDF(from: tempURL)
            XCTFail("Expected import to fail")
        } catch {
            XCTAssertNotNil(error.localizedDescription)
        }
    }
}

final class EntitlementManagerTests: XCTestCase {
    func testDebugProOverride() {
        #if DEBUG
        let manager = EntitlementManager.shared
        manager.updateEntitlement(isPro: false)
        manager.enableDebugPro()
        XCTAssertTrue(manager.isPro)
        manager.resetDebugPro()
        #endif
    }
}

final class ProductIdentifiersTests: XCTestCase {
    func testAllProductsDefined() {
        XCTAssertEqual(ProductIdentifiers.all.count, 3)
        XCTAssertTrue(ProductIdentifiers.all.allSatisfy { $0.contains("pdfeditor") })
    }
}
