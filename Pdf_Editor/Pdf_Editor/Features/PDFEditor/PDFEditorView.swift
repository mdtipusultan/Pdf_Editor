import PhotosUI
import SwiftUI

struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Binding var showExport: Bool
    @Binding var showPageManager: Bool
    @Binding var showPaywall: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            pdfContent
            bottomToolbar
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $viewModel.showTextEditor) {
            TextAnnotationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showExistingTextEditor) {
            TextEditingView(viewModel: viewModel)
        }
        .confirmationDialog("Text", isPresented: $viewModel.showTextMoreOptions, titleVisibility: .visible) {
            Button("Select Word") { viewModel.selectWordAtLastTap() }
            Button("Select Paragraph") { viewModel.selectParagraph() }
            Button("Copy") { viewModel.copySelectedText() }
            Button("Add Text Instead") { viewModel.beginAddTextFallback() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Can't Edit Text", isPresented: Binding(
            get: { viewModel.editBlockMessage != nil },
            set: { if !$0 { viewModel.editBlockMessage = nil } }
        )) {
            if viewModel.editBlockOffersAddText {
                Button("Add Text Instead") { viewModel.beginAddTextFallback() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.editBlockMessage ?? "")
        }
        .alert("Digital Signature", isPresented: $viewModel.showSignatureWarning) {
            Button("Continue") { viewModel.acknowledgeSignatureAndContinue() }
            Button("Cancel", role: .cancel) { viewModel.cancelSignatureWarning() }
        } message: {
            Text("Editing this PDF may invalidate its existing digital signature.")
        }
        .onChange(of: viewModel.shouldPresentExport) { _, ready in
            guard ready else { return }
            viewModel.shouldPresentExport = false
            finishExport()
        }
        .task(id: viewModel.currentPageIndex) {
            await viewModel.prepareCurrentPage()
        }
        .sheet(isPresented: $viewModel.showSignaturePad) {
            SignaturePadView(savedSignature: viewModel.savedSignature) { image in
                viewModel.applySignature(image)
            }
        }
        .sheet(isPresented: $viewModel.showShapePicker) {
            ShapePickerSheet(viewModel: viewModel)
        }
        .photosPicker(isPresented: $viewModel.showImagePicker, selection: $viewModel.selectedPhotoItem, matching: .images)
        .onChange(of: viewModel.selectedPhotoItem) { _, _ in
            Task { await viewModel.handlePhotoSelection() }
        }
        .alert("Notice", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Upgrade") { showPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
                HapticsManager.lightImpact()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Back")

            Text(viewModel.fileName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            Button {
                viewModel.requestExport()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Done editing")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var pdfContent: some View {
        ZStack(alignment: .bottom) {
            PDFKitEditorView(
                document: viewModel.document,
                currentPageIndex: $viewModel.currentPageIndex,
                documentRevision: viewModel.documentRevision,
                isDrawingEnabled: viewModel.isDrawingEnabled,
                drawColor: viewModel.drawUIColor,
                drawLineWidth: CGFloat(viewModel.penSize),
                isTextSelectionEnabled: viewModel.isTextSelectionEnabled,
                selectedTextPageIndex: viewModel.selectedTextPageIndex,
                selectedTextBounds: viewModel.selectedTextBounds,
                onAnnotationAdded: {
                    viewModel.recordChange()
                    viewModel.hasUnsavedChanges = true
                },
                onTextTap: { pageIndex, point in
                    viewModel.handleTextTap(pageIndex: pageIndex, point: point)
                }
            )

            VStack(spacing: 8) {
                if viewModel.selectedTextElement != nil {
                    textSelectionBar
                } else if viewModel.isTextSelectionEnabled {
                    Text("Tap existing text to select it")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                pageIndicator
            }
        }
    }

    private var textSelectionBar: some View {
        VStack(spacing: 6) {
            if let text = viewModel.selectedTextElement?.text {
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                textAction("Edit", systemImage: "pencil") { viewModel.beginEditingSelection() }
                textAction("Style", systemImage: "textformat") { viewModel.beginEditingSelection() }
                textAction("Delete", systemImage: "trash") { viewModel.deleteSelectedText() }
                textAction("More", systemImage: "ellipsis") { viewModel.showTextMoreOptions = true }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func textAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var pageIndicator: some View {
        Text("Page \(viewModel.currentPageIndex + 1) of \(viewModel.pageCount)")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 8)
            .accessibilityLabel("Page \(viewModel.currentPageIndex + 1) of \(viewModel.pageCount)")
    }

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            pageKindBanner
            if viewModel.selectedTool == .draw || viewModel.selectedTool == .highlight {
                toolOptionsBar
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(EditorTool.allCases) { tool in
                        EditorToolButton(
                            tool: tool,
                            isSelected: viewModel.selectedTool == tool,
                            isPro: tool.requiresPro && !AppFeatureAccess.shared.isPro
                        ) {
                            if tool == .pages {
                                if AppFeatureAccess.shared.canUsePageManagement() {
                                    showPageManager = true
                                } else {
                                    viewModel.errorMessage = "Page management requires PDF Pro."
                                }
                            } else {
                                viewModel.selectTool(tool)
                                if tool == .highlight {
                                    viewModel.addQuickHighlight()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var pageKindBanner: some View {
        switch viewModel.pageContentKind {
        case .scanned:
            HStack {
                Text("Scanned PDF")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(viewModel.isRecognizingText ? "Reading..." : "Use OCR to edit text") {
                    Task { await viewModel.recognizeCurrentPage() }
                }
                .font(.caption.weight(.semibold))
                .disabled(viewModel.isRecognizingText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground)
        case .mixed:
            Text("Text on this page can be edited. Image areas can't.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(AppTheme.cardBackground)
        case .text:
            EmptyView()
        }
    }

    private var toolOptionsBar: some View {
        HStack(spacing: 16) {
            if viewModel.selectedTool == .draw {
                ForEach(DrawSubTool.allCases) { sub in
                    Button {
                        viewModel.drawSubTool = sub
                        HapticsManager.selection()
                    } label: {
                        Image(systemName: sub.icon)
                            .foregroundStyle(viewModel.drawSubTool == sub ? AppTheme.accent : .secondary)
                    }
                }
            }

            if viewModel.selectedTool == .highlight {
                ForEach(MarkupStyle.allCases) { style in
                    Button(style.title) {
                        viewModel.markupStyle = style
                        HapticsManager.selection()
                    }
                    .font(.caption.weight(viewModel.markupStyle == style ? .bold : .regular))
                    .foregroundStyle(viewModel.markupStyle == style ? AppTheme.accent : .secondary)
                }
            }

            ColorPicker("", selection: $viewModel.selectedColor)
                .labelsHidden()

            Slider(value: $viewModel.penSize, in: 1...12)
                .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground)
    }

    private func finishExport() {
        if UserPreferences.shared.autoSave || viewModel.hasUnsavedChanges {
            do {
                try viewModel.saveDocument()
            } catch {
                viewModel.errorMessage = error.localizedDescription
                return
            }
        }

        if AppFeatureAccess.shared.canExport() {
            showExport = true
        } else {
            viewModel.errorMessage = "You've reached today's free export limit. Upgrade for unlimited exports."
        }
    }
}

struct EditorToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let isPro: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 20))
                    if isPro {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(tool.title)
                    .font(.caption2)
            }
            .frame(width: 56, height: 52)
            .foregroundStyle(isSelected ? AppTheme.accent : .primary)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TextAnnotationSheet: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Enter text", text: $viewModel.textInput, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Style") {
                    Stepper("Font size: \(Int(viewModel.fontSize))", value: $viewModel.fontSize, in: 8...48)
                    ColorPicker("Color", selection: $viewModel.selectedColor)
                }
            }
            .navigationTitle("Add Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addTextAnnotation()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ShapePickerSheet: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Shape", selection: $viewModel.shapeType) {
                    ForEach(ShapeType.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                ColorPicker("Color", selection: $viewModel.selectedColor)
                Stepper("Line width: \(Int(viewModel.penSize))", value: $viewModel.penSize, in: 1...12)
            }
            .navigationTitle("Add Shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addShape()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
