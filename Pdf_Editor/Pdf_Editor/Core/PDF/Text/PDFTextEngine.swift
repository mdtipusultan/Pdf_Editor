import CoreGraphics
import PDFKit
import UIKit

final class PDFTextEngine {
    private var masters: [Int: PDFPage] = [:]
    private var rotationDeltas: [Int: Int] = [:]
    private var replacements: [PDFTextReplacement] = []
    private var ocrElements: [Int: [PDFTextElement]] = [:]
    private let cache = PDFTextCache()

    func elements(on pageIndex: Int, document: PDFDocument) -> [PDFTextElement] {
        ensureExtracted(pageIndex: pageIndex, document: document)
        return displayElements(on: pageIndex)
    }

    func element(at point: CGPoint, on pageIndex: Int, document: PDFDocument) -> PDFTextElement? {
        let hits = elements(on: pageIndex, document: document).filter {
            $0.bounds.insetBy(dx: -4, dy: -4).contains(point)
        }
        return hits.min { lhs, rhs in
            (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
        }
    }

    func wordElement(at point: CGPoint, on pageIndex: Int, document: PDFDocument) -> PDFTextElement? {
        let sourcePage = masters[pageIndex] ?? document.page(at: pageIndex)
        guard let sourcePage,
              let selection = sourcePage.selectionForWord(at: point),
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let bounds = selection.bounds(for: sourcePage)
        guard bounds.width > 0.5, bounds.height > 0.5 else { return nil }
        let host = element(at: point, on: pageIndex, document: document)
        var style = host?.style ?? PDFTextStyle.fallback.with(fontSize: max(PDFTextLayout.minimumFontSize, bounds.height * 0.85))
        if let sample = PDFBackgroundSampler.sample(page: sourcePage, rect: bounds) {
            style.color = sample.foreground
            return PDFTextElement(
                id: UUID(),
                pageIndex: pageIndex,
                text: text,
                bounds: bounds,
                style: style,
                backgroundColor: sample.background,
                backgroundIsUniform: sample.isUniform,
                source: .content,
                lineCount: 1
            )
        }
        return PDFTextElement(
            id: UUID(),
            pageIndex: pageIndex,
            text: text,
            bounds: bounds,
            style: style,
            backgroundColor: host?.backgroundColor ?? .white,
            backgroundIsUniform: host?.backgroundIsUniform ?? false,
            source: .content,
            lineCount: 1
        )
    }

    func paragraphElement(containing element: PDFTextElement, document: PDFDocument) -> PDFTextElement {
        let lines = elements(on: element.pageIndex, document: document)
        return PDFTextExtractor.paragraph(containing: element, among: lines)
    }

    func contentKind(of page: PDFPage) -> PDFPageContentKind {
        PDFDocumentInspector.contentKind(of: page)
    }

    @discardableResult
    func apply(
        element: PDFTextElement,
        newText: String,
        style: PDFTextStyle,
        document: PDFDocument
    ) throws -> PDFTextElement {
        guard element.canEditDirectly else { throw PDFTextEditError.unsupportedBackground }
        guard document.page(at: element.pageIndex) != nil else { throw PDFTextEditError.missingPage }

        ensureExtracted(pageIndex: element.pageIndex, document: document)
        let pageBounds = masters[element.pageIndex]?.bounds(for: .mediaBox)
            ?? document.page(at: element.pageIndex)?.bounds(for: .mediaBox)
            ?? .zero
        let obstacles = displayElements(on: element.pageIndex)
            .filter { $0.id != element.id }
            .map(\.bounds)
        let fitted = PDFTextFitter.fit(
            text: newText,
            style: style,
            originalBounds: element.bounds,
            pageBounds: pageBounds,
            obstacles: obstacles,
            lineCount: max(element.lineCount, newText.contains("\n") ? 2 : 1)
        )
        let replacement = PDFTextReplacement(
            id: UUID(),
            elementID: element.id,
            pageIndex: element.pageIndex,
            originalBounds: element.bounds,
            visibleBounds: fitted.visibleBounds,
            coverBounds: fitted.coverBounds,
            text: newText,
            style: fitted.style,
            backgroundColor: element.backgroundColor,
            lineCount: max(1, newText.components(separatedBy: "\n").count)
        )

        let previous = replacements
        replacements.removeAll { $0.elementID == element.id }
        replacements.removeAll { existing in
            existing.pageIndex == element.pageIndex && overlapRatio(existing.coverBounds, fitted.coverBounds) > 0.55
        }
        replacements.append(replacement)
        do {
            try rebuild(pageIndex: element.pageIndex, document: document)
        } catch {
            replacements = previous
            throw error
        }
        return replacement.displayElement
    }

    func importOCR(_ tokens: [PDFOCRToken], on pageIndex: Int, document: PDFDocument) {
        guard let page = document.page(at: pageIndex) else { return }
        let elements = tokens.map { token -> PDFTextElement in
            let sample = PDFBackgroundSampler.sample(page: page, rect: token.bounds)
            let fontSize = max(PDFTextLayout.minimumFontSize, token.bounds.height * 0.72)
            var style = PDFTextStyle.fallback.with(fontSize: fontSize)
            style.color = sample?.foreground ?? .black
            return PDFTextElement(
                id: UUID(),
                pageIndex: pageIndex,
                text: token.text,
                bounds: token.bounds,
                style: style,
                backgroundColor: sample?.background ?? PDFColor(red: 0.96, green: 0.96, blue: 0.94),
                backgroundIsUniform: sample?.isUniform ?? true,
                source: .ocr,
                lineCount: token.text.contains("\n") ? 2 : 1
            )
        }
        ocrElements[pageIndex] = elements
    }

    func notePageDeleted(at index: Int, previousPageCount: Int) {
        reindex(deleteAt: index, previousCount: previousPageCount)
    }

    func notePageMoved(from source: Int, to destination: Int, pageCount: Int) {
        guard source != destination else { return }
        var indices = Array(0..<pageCount)
        let item = indices.remove(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        guard indices.indices.contains(insertIndex) || insertIndex == indices.count else { return }
        indices.insert(item, at: min(insertIndex, indices.count))
        var map: [Int: Int] = [:]
        for (newIndex, oldIndex) in indices.enumerated() {
            map[oldIndex] = newIndex
        }
        apply(map: map)
    }

    func notePageDuplicated(at index: Int, pageCountBeforeInsert: Int) {
        let newIndex = index + 1
        var map: [Int: Int] = [:]
        for old in 0..<pageCountBeforeInsert {
            map[old] = old >= newIndex ? old + 1 : old
        }
        apply(map: map)
        if let extracted = cache.elements(for: index) {
            var idMap: [UUID: UUID] = [:]
            let clones = extracted.map { element -> PDFTextElement in
                let newID = UUID()
                idMap[element.id] = newID
                return element.duplicated(id: newID, pageIndex: newIndex)
            }
            cache.insert(clones, for: newIndex)
            let clonedReplacements = replacements.filter { $0.pageIndex == index }.map { replacement -> PDFTextReplacement in
                var copy = replacement
                copy.id = UUID()
                copy.pageIndex = newIndex
                copy.elementID = idMap[replacement.elementID] ?? UUID()
                return copy
            }
            replacements.append(contentsOf: clonedReplacements)
        }
        if let master = masters[index] {
            masters[newIndex] = master
        }
        rotationDeltas[newIndex] = rotationDeltas[index]
        if let ocr = ocrElements[index] {
            ocrElements[newIndex] = ocr.map { $0.duplicated(id: UUID(), pageIndex: newIndex) }
        }
    }

    func notePageRotated(at index: Int, degrees: Int = 90) {
        // Rotation that already exists before the first text edit is baked into the
        // master drawing. Only rotations applied after that need to be replayed.
        guard masters[index] != nil else { return }
        let current = rotationDeltas[index] ?? 0
        rotationDeltas[index] = (current + degrees) % 360
    }

    func snapshot() -> PDFTextEngineState {
        PDFTextEngineState(
            masters: masters,
            rotationDeltas: rotationDeltas,
            replacements: replacements,
            extracted: cache.snapshot(),
            ocrElements: ocrElements
        )
    }

    func restore(_ state: PDFTextEngineState) {
        masters = state.masters
        rotationDeltas = state.rotationDeltas
        replacements = state.replacements
        ocrElements = state.ocrElements
        cache.restore(state.extracted)
    }

    private func ensureExtracted(pageIndex: Int, document: PDFDocument) {
        guard cache.elements(for: pageIndex) == nil else { return }
        let extracted = PDFTextExtractor.extract(pageIndex: pageIndex, from: document)
        cache.insert(extracted, for: pageIndex)
    }

    private func displayElements(on pageIndex: Int) -> [PDFTextElement] {
        let base = cache.elements(for: pageIndex) ?? []
        let pageReplacements = replacements.filter { $0.pageIndex == pageIndex && !$0.text.isEmpty }
        let covers = replacements.filter { $0.pageIndex == pageIndex }
        let hidden = base.filter { element in
            covers.contains { cover in
                cover.elementID == element.id || overlapRatio(element.bounds, cover.coverBounds) > 0.6
            }
        }
        let hiddenIDs = Set(hidden.map(\.id))
        var visible = base.filter { !hiddenIDs.contains($0.id) }
        visible.append(contentsOf: pageReplacements.map(\.displayElement))
        if let ocr = ocrElements[pageIndex] {
            let remaining = ocr.filter { element in
                !covers.contains { $0.elementID == element.id || overlapRatio(element.bounds, $0.coverBounds) > 0.6 }
            }
            visible.append(contentsOf: remaining)
        }
        return visible
    }

    private func rebuild(pageIndex: Int, document: PDFDocument) throws {
        guard let live = document.page(at: pageIndex) else { throw PDFTextEditError.missingPage }
        let isFirstMaster = masters[pageIndex] == nil
        let master = try ensureMaster(pageIndex: pageIndex, document: document)
        let annotations = live.annotations
        if isFirstMaster {
            rotationDeltas[pageIndex] = 0
        }
        let rotation = rotationDeltas[pageIndex] ?? 0
        let pageReplacements = replacements.filter { $0.pageIndex == pageIndex }
        guard let newPage = PDFPageCompositor.composite(master: master, replacements: pageReplacements, rotation: rotation) else {
            throw PDFTextEditError.failedToRebuild
        }
        for annotation in annotations {
            newPage.addAnnotation(annotation)
        }
        document.removePage(at: pageIndex)
        document.insert(newPage, at: pageIndex)
    }

    private func ensureMaster(pageIndex: Int, document: PDFDocument) throws -> PDFPage {
        if let existing = masters[pageIndex] {
            return existing
        }
        guard let page = document.page(at: pageIndex) else { throw PDFTextEditError.missingPage }
        masters[pageIndex] = page
        return page
    }

    private func reindex(deleteAt index: Int, previousCount: Int) {
        var map: [Int: Int] = [:]
        for old in 0..<previousCount where old != index {
            map[old] = old > index ? old - 1 : old
        }
        apply(map: map)
    }

    private func apply(map: [Int: Int]) {
        cache.reindex(map)
        masters = rekeyed(masters, map: map)
        rotationDeltas = rekeyed(rotationDeltas, map: map)
        ocrElements = rekeyed(ocrElements, map: map)
        replacements = replacements.compactMap { replacement in
            guard let pageIndex = map[replacement.pageIndex] else { return nil }
            var copy = replacement
            copy.pageIndex = pageIndex
            return copy
        }
    }

    private func rekeyed<T>(_ values: [Int: T], map: [Int: Int]) -> [Int: T] {
        var updated: [Int: T] = [:]
        for (index, value) in values {
            if let newIndex = map[index] {
                updated[newIndex] = value
            }
        }
        return updated
    }

    private func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, a.width > 0, a.height > 0 else { return 0 }
        return (intersection.width * intersection.height) / (a.width * a.height)
    }
}
