import SwiftUI

struct SignaturePadView: View {
    let savedSignature: UIImage?
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Draw your signature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Canvas { context, size in
                        for line in lines {
                            var path = Path()
                            if let first = line.first {
                                path.move(to: first)
                                for point in line.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                            context.stroke(path, with: .color(.primary), lineWidth: 2.5)
                        }
                        var currentPath = Path()
                        if let first = currentLine.first {
                            currentPath.move(to: first)
                            for point in currentLine.dropFirst() {
                                currentPath.addLine(to: point)
                            }
                        }
                        context.stroke(currentPath, with: .color(.primary), lineWidth: 2.5)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentLine.append(value.location)
                            }
                            .onEnded { _ in
                                lines.append(currentLine)
                                currentLine = []
                            }
                    )
                }
                .frame(height: 180)
                .padding(.horizontal)

                if let savedSignature {
                    Button("Use Saved Signature") {
                        onSave(savedSignature)
                        dismiss()
                    }
                    .font(.subheadline)
                }

                HStack(spacing: 16) {
                    Button("Clear") {
                        lines.removeAll()
                        currentLine.removeAll()
                        HapticsManager.lightImpact()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Apply") {
                        if let image = renderSignature() {
                            onSave(image)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lines.isEmpty && currentLine.isEmpty)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func renderSignature() -> UIImage? {
        let size = CGSize(width: 400, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.label.setStroke()
            for line in lines + [currentLine] {
                let path = UIBezierPath()
                guard let first = line.first else { continue }
                path.move(to: first)
                for point in line.dropFirst() {
                    path.addLine(to: point)
                }
                path.lineWidth = 2.5
                path.stroke()
            }
        }
    }
}
