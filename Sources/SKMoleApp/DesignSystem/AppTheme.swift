import SwiftUI

enum AppPalette {
    static let accent = Color(red: 0.12, green: 0.71, blue: 0.63)
    static let amber = Color(red: 0.92, green: 0.62, blue: 0.22)
    static let sky = Color(red: 0.32, green: 0.58, blue: 0.95)
    static let rose = Color(red: 0.79, green: 0.38, blue: 0.41)
    static let mint = Color(red: 0.29, green: 0.77, blue: 0.67)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let secondaryCard = Color(nsColor: .underPageBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)

    static let heroGradient = LinearGradient(
        colors: [
            accent.opacity(0.28),
            amber.opacity(0.24),
            sky.opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct MoleCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
    }
}

extension View {
    func moleCardStyle() -> some View {
        modifier(MoleCardModifier())
    }
}
