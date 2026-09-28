import Foundation
import PDFKit
import UniformTypeIdentifiers

enum PDFImportError: LocalizedError {
    case invalidDocument
    case passwordProtected
    case corrupted
    case tooLarge
    case unsupportedType
    case accessDenied
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "This file couldn't be opened as a PDF."
        case .passwordProtected:
            "This PDF is password protected."
        case .corrupted:
            "This PDF appears to be corrupted."
        case .tooLarge:
            "This PDF is too large to open."
        case .unsupportedType:
            "This file type isn't supported."
        case .accessDenied:
            "Couldn't access this file."
        case .unknown(let message):
            message
        }
    }
}

enum DocumentStorage {
    static let maxFileSizeBytes: Int64 = 200 * 1024 * 1024

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PDFs", isDirectory: true)
    }

    static func ensureDocumentsDirectory() throws {
        try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    }

    static func importPDF(from sourceURL: URL) async throws -> (URL, PDFDocument) {
        try ensureDocumentsDirectory()

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let size = values.fileSize, Int64(size) > maxFileSizeBytes {
            throw PDFImportError.tooLarge
        }

        if let contentType = values.contentType, contentType != .pdf {
            throw PDFImportError.unsupportedType
        }

        let fileName = uniqueFileName(basedOn: sourceURL.lastPathComponent)
        let destination = documentsDirectory.appendingPathComponent(fileName)

        if sourceURL.path != destination.path {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }

        guard let document = PDFDocument(url: destination) else {
            throw PDFImportError.invalidDocument
        }

        if document.isLocked {
            throw PDFImportError.passwordProtected
        }

        if document.pageCount == 0 {
            throw PDFImportError.corrupted
        }

        return (destination, document)
    }

    static func savePDF(_ document: PDFDocument, to url: URL) throws {
        guard document.write(to: url) else {
            throw PDFImportError.unknown("Couldn't save this PDF.")
        }
    }

    static func exportCopy(_ document: PDFDocument, fileName: String) throws -> URL {
        try ensureDocumentsDirectory()
        let url = documentsDirectory.appendingPathComponent(uniqueFileName(basedOn: fileName))
        try savePDF(document, to: url)
        return url
    }

    static func uniqueFileName(basedOn name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? "pdf" : (name as NSString).pathExtension
        var candidate = "\(base).\(ext)"
        var counter = 1
        while FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    static func cleanupTemporaryFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for url in contents where url.pathExtension.lowercased() == "pdf" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
