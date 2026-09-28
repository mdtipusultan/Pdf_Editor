import PDFKit

final class PDFUndoManager {
    private struct Snapshot {
        let data: Data
        let textState: PDFTextEngineState
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maxStackSize = 30
    private(set) var lastRestoredTextState = PDFTextEngineState.empty

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func recordSnapshot(_ document: PDFDocument, textState: PDFTextEngineState = .empty) {
        guard let data = document.dataRepresentation() else { return }
        undoStack.append(Snapshot(data: data, textState: textState))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func discardLastSnapshot() {
        _ = undoStack.popLast()
    }

    @discardableResult
    func undo(on document: PDFDocument, currentTextState: PDFTextEngineState = .empty) -> Bool {
        guard let current = document.dataRepresentation(),
              let previous = undoStack.popLast() else { return false }
        redoStack.append(Snapshot(data: current, textState: currentTextState))
        guard let restored = PDFDocument(data: previous.data) else { return false }
        copyPages(from: restored, to: document)
        lastRestoredTextState = previous.textState
        return true
    }

    @discardableResult
    func redo(on document: PDFDocument, currentTextState: PDFTextEngineState = .empty) -> Bool {
        guard let current = document.dataRepresentation(),
              let next = redoStack.popLast() else { return false }
        undoStack.append(Snapshot(data: current, textState: currentTextState))
        guard let restored = PDFDocument(data: next.data) else { return false }
        copyPages(from: restored, to: document)
        lastRestoredTextState = next.textState
        return true
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastRestoredTextState = .empty
    }

    private func copyPages(from source: PDFDocument, to destination: PDFDocument) {
        while destination.pageCount > 0 {
            destination.removePage(at: 0)
        }
        for index in 0..<source.pageCount {
            if let page = source.page(at: index) {
                destination.insert(page, at: index)
            }
        }
    }
}
