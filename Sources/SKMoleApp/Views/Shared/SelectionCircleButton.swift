import SwiftUI

struct SelectionCircleButton: View {
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? AppPalette.accent : Color.secondary.opacity(0.55), lineWidth: 2)

                Circle()
                    .fill(AppPalette.accent)
                    .padding(6)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.borderless)
        .padding(2)
        .help(isSelected ? "Deselect" : "Select")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
