import SwiftUI

struct TextEditingView: View {
    @Bindable var viewModel: PDFEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Existing text", text: $viewModel.textDraft, axis: .vertical)
                        .lineLimit(2...8)
                }
                Section("Style") {
                    Stepper(
                        "Font size: \(Int(viewModel.styleDraft.fontSize.rounded()))",
                        value: $viewModel.styleDraft.fontSize,
                        in: 8...72,
                        step: 1
                    )
                    Picker("Alignment", selection: $viewModel.styleDraft.alignment) {
                        Text("Left").tag(PDFTextAlignment.left)
                        Text("Center").tag(PDFTextAlignment.center)
                        Text("Right").tag(PDFTextAlignment.right)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Bold", isOn: $viewModel.styleDraft.isBold)
                    Toggle("Italic", isOn: $viewModel.styleDraft.isItalic)
                    ColorPicker(
                        "Color",
                        selection: Binding(
                            get: { Color(uiColor: viewModel.styleDraft.color.uiColor) },
                            set: { viewModel.styleDraft.color = PDFColor(uiColor: UIColor($0)) }
                        )
                    )
                }
            }
            .navigationTitle("Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.commitTextEdit()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
