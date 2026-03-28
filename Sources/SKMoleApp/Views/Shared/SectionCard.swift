import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let content: Content

    init(title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(AppPalette.accent.opacity(0.12)))
                }

                Spacer(minLength: 0)
            }

            content
        }
        .moleCardStyle()
    }
}
