import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "aqi.medium")
                .foregroundStyle(AppPalette.accent)
            Text("\(Int((model.metrics.cpuUsage * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .accessibilityLabel("SK Mole CPU \(Int((model.metrics.cpuUsage * 100).rounded())) percent")
    }
}
