import CoreGraphics
import PDFKit

enum PDFDocumentInspector {
    static func editingRestriction(of document: PDFDocument) -> PDFEditingRestriction? {
        if document.isLocked {
            return .locked
        }
        if document.isEncrypted {
            let canChange = document.allowsDocumentChanges || document.allowsCommenting
            if !canChange {
                return .permissionDenied
            }
        }
        return nil
    }

    static func hasDigitalSignature(_ document: PDFDocument) -> Bool {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if annotation.type == "Sig" || annotation.widgetFieldType == .signature {
                    return true
                }
            }
        }
        return false
    }

    static func contentKind(of page: PDFPage) -> PDFPageContentKind {
        let characters = page.numberOfCharacters
        let hasImage = pageContainsImage(page)
        if characters < 12 {
            return .scanned
        }
        if hasImage {
            return .mixed
        }
        return .text
    }

    static func documentKind(for pageKinds: [PDFPageContentKind]) -> PDFDocumentContentKind {
        guard !pageKinds.isEmpty else { return .empty }
        let hasText = pageKinds.contains(.text) || pageKinds.contains(.mixed)
        let hasScan = pageKinds.contains(.scanned)
        if hasText && hasScan { return .mixed }
        if pageKinds.allSatisfy({ $0 == .scanned }) { return .scanned }
        if pageKinds.contains(.mixed) { return .mixed }
        return .textBased
    }

    static func pageContainsImage(_ page: PDFPage) -> Bool {
        guard let dictionary = page.pageRef?.dictionary else { return false }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else {
            return false
        }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else {
            return false
        }
        var found = false
        CGPDFDictionaryApplyFunction(xObjects, imageXObjectApplier, &found)
        return found
    }
}

nonisolated private func imageXObjectApplier(
    _ key: UnsafePointer<Int8>,
    _ object: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
    guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
    var subtype: UnsafePointer<Int8>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
    if String(cString: subtype) == "Image" {
        info.assumingMemoryBound(to: Bool.self).pointee = true
    }
}
