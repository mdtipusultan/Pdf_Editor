import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(AppTheme.accent.gradient)
                    .scaleEffect(scale)
                    .opacity(opacity)

                Text("PDF Editor")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PDF Editor")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                scale = 1
                opacity = 1
            }
        }
    }
}
