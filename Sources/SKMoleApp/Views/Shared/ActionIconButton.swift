import SwiftUI

struct ActionIconButton: View {
    enum Style {
        case bordered
        case prominent(Color)
    }

    let symbol: String
    let label: String
    let style: Style
    let action: () -> Void

    init(symbol: String, label: String, style: Style = .bordered, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.style = style
        self.action = action
    }

    var body: some View {
        Group {
            switch style {
            case .bordered:
                Button(action: action) {
                    icon
                }
                .buttonStyle(.bordered)
            case .prominent(let tint):
                Button(action: action) {
                    icon
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(label)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: 16, height: 16)
    }
}
