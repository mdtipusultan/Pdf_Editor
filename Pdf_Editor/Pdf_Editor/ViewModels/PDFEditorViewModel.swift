import PDFKit
import SwiftUI
import PhotosUI

@Observable
@MainActor
final class PDFEditorViewModel {
    let document: PDFDocument
    var fileURL: URL
    var fileName: String

    var selectedTool: EditorTool?
    var drawSubTool: DrawSubTool = .pen
    var markupStyle: MarkupStyle = .highlight
    var shapeType: ShapeType = .rectangle
    var currentPageIndex = 0
    var selectedColor: Color = .yellow
    var penSize: Double = 3
    var fontSize: Double = 16
    var isDrawingEnabled = false
    var showTextEditor = false
    var textInput = ""
    var showSignaturePad = false
    var showShapePicker = false
    var showImagePicker = false
    var selectedPhotoItem: PhotosPickerItem?
    var savedSignature: UIImage?
    var isSaving = false
    var errorMessage: String?
    var hasUnsavedChanges = false
    var documentRevision = 0
    var selectedTextElement: PDFTextElement?
    var showExistingTextEditor = false
    var showTextMoreOptions = false
    var textDraft = ""
    var styleDraft = PDFTextStyle.fallback
    var editBlockMessage: String?
    var editBlockOffersAddText = false
    var showSignatureWarning = false
    var shouldPresentExport = false
    var isRecognizingText = false
    var pageContentKind: PDFPageContentKind = .text
    var hasDigitalSignature = false

    private let undoManager = PDFUndoManager()
    private let featureAccess = AppFeatureAccess.shared
    private let textEngine = PDFTextEngine()
    private let ocrService = VisionPDFOCRService()
    private var editingRestriction: PDFEditingRestriction?
    private var didAcknowledgeSignatureWarning = false
    private var pendingSignatureAction: PendingSignatureAction?
    private var lastTextTapPoint: CGPoint?
    private var lastTextTapPage = 0

    private enum PendingSignatureAction {
        case beginEdit
        case deleteSelection
        case export
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }
    var pageCount: Int { document.pageCount }
    var annotationCount: Int { PDFAnnotationHelper.annotationCount(in: document) }
    var isTextSelectionEnabled: Bool {
        switch selectedTool {
        case .none, .editText: true
        default: false
        }
    }
    var selectedTextBounds: CGRect? { selectedTextElement?.bounds }
    var selectedTextPageIndex: Int? {
        guard let selectedTextElement else { return nil }
        return selectedTextElement.pageIndex
    }

    init(document: PDFDocument, fileURL: URL, fileName: String) {
        self.document = document
        self.fileURL = fileURL
        self.fileName = fileName
        self.selectedColor = Color(hex: UserPreferences.shared.defaultAnnotationColorHex) ?? .yellow
        self.penSize = UserPreferences.shared.defaultPenSize
        self.hasDigitalSignature = PDFDocumentInspector.hasDigitalSignature(document)
        self.editingRestriction = PDFDocumentInspector.editingRestriction(of: document)
        loadSavedSignature()
    }

    func selectTool(_ tool: EditorTool) {
        if tool.requiresPro && !featureAccess.canUseTool(tool) {
            errorMessage = "Upgrade to PDF Pro to use \(tool.title)."
            return
        }

        if selectedTool == tool {
            selectedTool = nil
            isDrawingEnabled = false
        } else {
            selectedTool = tool
            configureForTool(tool)
        }
        HapticsManager.selection()
    }

    private func configureForTool(_ tool: EditorTool) {
        isDrawingEnabled = false
        switch tool {
        case .editText:
            break
        case .text:
            showTextEditor = true
        case .draw:
            isDrawingEnabled = true
            drawSubTool = .pen
        case .highlight:
            isDrawingEnabled = false
        case .signature:
            showSignaturePad = true
        case .shape:
            showShapePicker = true
        case .image:
            showImagePicker = true
        case .pages:
            break
        }
    }

    func recordChange() {
        undoManager.recordSnapshot(document, textState: textEngine.snapshot())
        hasUnsavedChanges = true
    }

    func undo() {
        let state = textEngine.snapshot()
        guard undoManager.undo(on: document, currentTextState: state) else { return }
        textEngine.restore(undoManager.lastRestoredTextState)
        selectedTextElement = nil
        documentRevision += 1
        hasUnsavedChanges = true
        HapticsManager.lightImpact()
    }

    func redo() {
        let state = textEngine.snapshot()
        guard undoManager.redo(on: document, currentTextState: state) else { return }
        textEngine.restore(undoManager.lastRestoredTextState)
        selectedTextElement = nil
        documentRevision += 1
        hasUnsavedChanges = true
        HapticsManager.lightImpact()
    }

    func addTextAnnotation() {
        guard !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard featureAccess.canAddAnnotation(currentCount: annotationCount) else {
            errorMessage = "Free plan allows \(AppFeatureLimits.freeAnnotationsPerDocument) annotations per document."
            return
        }

        guard let page = document.page(at: currentPageIndex) else { return }
        recordChange()

        let pageBounds = page.bounds(for: .mediaBox)
        let rect = CGRect(x: 50, y: pageBounds.height - 100, width: 200, height: 40)
        PDFAnnotationHelper.addFreeText(
            to: page,
            text: textInput,
            at: rect,
            fontSize: CGFloat(fontSize),
            color: UIColor(selectedColor)
        )
        textInput = ""
        showTextEditor = false
        hasUnsavedChanges = true
        HapticsManager.success()
    }

    func addHighlight(at rect: CGRect) {
        guard featureAccess.canAddAnnotation(currentCount: annotationCount) else {
            errorMessage = "Free plan allows \(AppFeatureLimits.freeAnnotationsPerDocument) annotations per document."
            return
        }
        guard let page = document.page(at: currentPageIndex) else { return }
        recordChange()
        PDFAnnotationHelper.addHighlight(
            to: page,
            bounds: rect,
            style: markupStyle,
            color: UIColor(selectedColor)
        )
        hasUnsavedChanges = true
        HapticsManager.lightImpact()
    }

    func addQuickHighlight() {
        guard let page = document.page(at: currentPageIndex) else { return }
        let bounds = page.bounds(for: .mediaBox)
        let rect = CGRect(x: bounds.width * 0.1, y: bounds.height * 0.5, width: bounds.width * 0.8, height: 24)
        addHighlight(at: rect)
    }

    func addShape() {
        guard featureAccess.canAddAnnotation(currentCount: annotationCount) else {
            errorMessage = "Upgrade to add more annotations."
            return
        }
        guard let page = document.page(at: currentPageIndex) else { return }
        recordChange()
        let bounds = page.bounds(for: .mediaBox)
        let rect = CGRect(x: bounds.width * 0.3, y: bounds.height * 0.3, width: 120, height: 80)
        PDFAnnotationHelper.addShape(
            to: page,
            type: shapeType,
            bounds: rect,
            color: UIColor(selectedColor),
            lineWidth: CGFloat(penSize)
        )
        showShapePicker = false
        hasUnsavedChanges = true
        HapticsManager.success()
    }

    func applySignature(_ image: UIImage) {
        guard featureAccess.canAddAnnotation(currentCount: annotationCount) else {
            errorMessage = "Upgrade to add more annotations."
            return
        }
        guard let page = document.page(at: currentPageIndex) else { return }
        recordChange()
        let bounds = page.bounds(for: .mediaBox)
        let rect = CGRect(x: bounds.width - 220, y: 60, width: 180, height: 60)
        PDFAnnotationHelper.addSignature(to: page, image: image, at: rect)

        if featureAccess.canSaveSignature() {
            saveSignature(image)
            featureAccess.recordSignatureSaved()
        }
        showSignaturePad = false
        hasUnsavedChanges = true
        HapticsManager.success()
    }

    func addImage(_ image: UIImage) {
        guard featureAccess.canAddAnnotation(currentCount: annotationCount) else {
            errorMessage = "Upgrade to add more annotations."
            return
        }
        guard let page = document.page(at: currentPageIndex) else { return }
        recordChange()
        let bounds = page.bounds(for: .mediaBox)
        let aspect = image.size.width / image.size.height
        let width: CGFloat = min(200, bounds.width * 0.4)
        let height = width / aspect
        let rect = CGRect(x: 40, y: bounds.height - height - 40, width: width, height: height)
        PDFAnnotationHelper.addImageStamp(to: page, image: image, at: rect)
        showImagePicker = false
        hasUnsavedChanges = true
        HapticsManager.success()
    }

    func handlePhotoSelection() async {
        guard let item = selectedPhotoItem,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        addImage(image)
        selectedPhotoItem = nil
    }

    func deletePage(at index: Int) {
        guard featureAccess.canUsePageManagement() else {
            errorMessage = "Page management requires PDF Pro."
            return
        }
        recordChange()
        let count = pageCount
        PageOperations.deletePage(at: index, in: document)
        textEngine.notePageDeleted(at: index, previousPageCount: count)
        if selectedTextElement?.pageIndex == index {
            selectedTextElement = nil
        }
        currentPageIndex = min(currentPageIndex, max(0, pageCount - 1))
        documentRevision += 1
        hasUnsavedChanges = true
        HapticsManager.mediumImpact()
    }

    func rotatePage(at index: Int) {
        guard featureAccess.canUsePageManagement() else {
            errorMessage = "Page management requires PDF Pro."
            return
        }
        recordChange()
        PageOperations.rotatePage(at: index, in: document)
        textEngine.notePageRotated(at: index)
        documentRevision += 1
        hasUnsavedChanges = true
        HapticsManager.lightImpact()
    }

    func duplicatePage(at index: Int) {
        guard featureAccess.canUsePageManagement() else {
            errorMessage = "Page management requires PDF Pro."
            return
        }
        recordChange()
        let count = pageCount
        PageOperations.duplicatePage(at: index, in: document)
        if pageCount == count + 1 {
            textEngine.notePageDuplicated(at: index, pageCountBeforeInsert: count)
        }
        documentRevision += 1
        hasUnsavedChanges = true
        HapticsManager.lightImpact()
    }

    func movePage(from source: Int, to destination: Int) {
        guard featureAccess.canUsePageManagement() else { return }
        recordChange()
        let count = pageCount
        PageOperations.movePage(from: source, to: destination, in: document)
        textEngine.notePageMoved(from: source, to: destination, pageCount: count)
        documentRevision += 1
        hasUnsavedChanges = true
    }

    func saveDocument() throws {
        isSaving = true
        defer { isSaving = false }
        try DocumentStorage.savePDF(document, to: fileURL)
        hasUnsavedChanges = false
        RecentDocumentsStore.shared.addOrUpdate(from: document, url: fileURL, fileName: fileName)
    }

    func exportCopy(newName: String?) throws -> URL {
        let name = newName ?? fileName
        return try DocumentStorage.exportCopy(document, fileName: name)
    }

    var drawUIColor: UIColor {
        switch drawSubTool {
        case .pen: UIColor(selectedColor)
        case .highlighter: UIColor(selectedColor).withAlphaComponent(0.5)
        case .eraser: .clear
        }
    }

    private func saveSignature(_ image: UIImage) {
        savedSignature = image
        if let data = image.pngData() {
            UserDefaults.standard.set(data, forKey: "savedSignature")
        }
    }

    func prepareCurrentPage() async {
        await Task.yield()
        guard let page = document.page(at: currentPageIndex) else { return }
        pageContentKind = textEngine.contentKind(of: page)
        _ = textEngine.elements(on: currentPageIndex, document: document)
    }

    func handleTextTap(pageIndex: Int, point: CGPoint) {
        lastTextTapPoint = point
        lastTextTapPage = pageIndex
        currentPageIndex = pageIndex
        if let element = textEngine.element(at: point, on: pageIndex, document: document) {
            selectedTextElement = element
            HapticsManager.selection()
        } else {
            selectedTextElement = nil
        }
    }

    func beginEditingSelection() {
        guard selectedTextElement != nil else { return }
        guard featureAccess.canEditExistingText() else {
            errorMessage = "Editing existing text requires PDF Pro."
            return
        }
        if let editingRestriction {
            editBlockOffersAddText = false
            editBlockMessage = editingRestriction.message
            return
        }
        guard let selectedTextElement, selectedTextElement.canEditDirectly else {
            editBlockOffersAddText = true
            editBlockMessage = PDFTextEditError.unsupportedBackground.localizedDescription
            return
        }
        if hasDigitalSignature && !didAcknowledgeSignatureWarning {
            pendingSignatureAction = .beginEdit
            showSignatureWarning = true
            return
        }
        presentTextEditor()
    }

    func commitTextEdit() {
        guard let selectedTextElement else { return }
        let draft = textDraft
        let style = styleDraft
        showExistingTextEditor = false
        recordChange()
        do {
            let updated = try textEngine.apply(
                element: selectedTextElement,
                newText: draft,
                style: style,
                document: document
            )
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.selectedTextElement = nil
            } else {
                self.selectedTextElement = updated
            }
            documentRevision += 1
            hasUnsavedChanges = true
            HapticsManager.success()
        } catch {
            undoManager.discardLastSnapshot()
            editBlockOffersAddText = true
            editBlockMessage = error.localizedDescription
            HapticsManager.error()
        }
    }

    func deleteSelectedText() {
        guard let selectedTextElement else { return }
        guard featureAccess.canEditExistingText() else {
            errorMessage = "Editing existing text requires PDF Pro."
            return
        }
        if let editingRestriction {
            editBlockOffersAddText = false
            editBlockMessage = editingRestriction.message
            return
        }
        guard selectedTextElement.canEditDirectly else {
            editBlockOffersAddText = true
            editBlockMessage = PDFTextEditError.unsupportedBackground.localizedDescription
            return
        }
        if hasDigitalSignature && !didAcknowledgeSignatureWarning {
            pendingSignatureAction = .deleteSelection
            showSignatureWarning = true
            return
        }
        recordChange()
        do {
            _ = try textEngine.apply(
                element: selectedTextElement,
                newText: "",
                style: selectedTextElement.style,
                document: document
            )
            self.selectedTextElement = nil
            documentRevision += 1
            hasUnsavedChanges = true
            HapticsManager.success()
        } catch {
            undoManager.discardLastSnapshot()
            editBlockOffersAddText = true
            editBlockMessage = error.localizedDescription
        }
    }

    func selectWordAtLastTap() {
        guard let lastTextTapPoint else { return }
        selectedTextElement = textEngine.wordElement(at: lastTextTapPoint, on: lastTextTapPage, document: document)
    }

    func selectParagraph() {
        guard let selectedTextElement else { return }
        self.selectedTextElement = textEngine.paragraphElement(containing: selectedTextElement, document: document)
    }

    func copySelectedText() {
        guard let text = selectedTextElement?.text else { return }
        UIPasteboard.general.string = text
        HapticsManager.success()
    }

    func beginAddTextFallback() {
        editBlockMessage = nil
        editBlockOffersAddText = false
        selectedTool = .text
        showTextEditor = true
    }

    func requestExport() {
        if hasDigitalSignature && hasUnsavedChanges && !didAcknowledgeSignatureWarning {
            pendingSignatureAction = .export
            showSignatureWarning = true
            return
        }
        shouldPresentExport = true
    }

    func acknowledgeSignatureAndContinue() {
        didAcknowledgeSignatureWarning = true
        let action = pendingSignatureAction
        pendingSignatureAction = nil
        switch action {
        case .beginEdit:
            presentTextEditor()
        case .deleteSelection:
            deleteSelectedText()
        case .export:
            shouldPresentExport = true
        case nil:
            break
        }
    }

    func cancelSignatureWarning() {
        pendingSignatureAction = nil
    }

    func recognizeCurrentPage() async {
        guard featureAccess.canEditExistingText() else {
            errorMessage = "Editing existing text requires PDF Pro."
            return
        }
        guard let page = document.page(at: currentPageIndex) else { return }
        isRecognizingText = true
        defer { isRecognizingText = false }
        do {
            let tokens = try await ocrService.recognize(page: page)
            textEngine.importOCR(tokens, on: currentPageIndex, document: document)
            HapticsManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func presentTextEditor() {
        guard let selectedTextElement else { return }
        textDraft = selectedTextElement.text
        styleDraft = selectedTextElement.style
        showExistingTextEditor = true
    }

    private func loadSavedSignature() {
        if let data = UserDefaults.standard.data(forKey: "savedSignature"),
           let image = UIImage(data: data) {
            savedSignature = image
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return "FFD700" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
