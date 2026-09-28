import PDFKit

final class PDFUndoManager {
    private var undoStack: [PDFSnapshot] = []
    private var redoStack: [PDFSnapshot] = []
    private let maxStackSize = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func recordSnapshot(_ document: PDFDocument) {
        guard let data = document.dataRepresentation() else { return }
        undoStack.append(PDFSnapshot(data: data))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo(on document: PDFDocument) -> Bool {
        guard let current = document.dataRepresentation(),
              let previous = undoStack.popLast() else { return false }
        redoStack.append(PDFSnapshot(data: current))
        guard let restored = PDFDocument(data: previous.data) else { return false }
        copyPages(from: restored, to: document)
        return true
    }

    func redo(on document: PDFDocument) -> Bool {
        guard let current = document.dataRepresentation(),
              let next = redoStack.popLast() else { return false }
        undoStack.append(PDFSnapshot(data: current))
        guard let restored = PDFDocument(data: next.data) else { return false }
        copyPages(from: restored, to: document)
        return true
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
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

private struct PDFSnapshot {
    let data: Data
}
