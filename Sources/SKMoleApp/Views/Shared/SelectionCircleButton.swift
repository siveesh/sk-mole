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
                    .padding(5)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 22, height: 22)
            .animation(.snappy(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(isSelected ? "Deselect" : "Select")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
