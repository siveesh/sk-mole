import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var monitor: SystemMonitorStore

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._monitor = ObservedObject(wrappedValue: model.monitorStore)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "aqi.medium")
                .foregroundStyle(AppPalette.accent)
            Text("\(Int((monitor.metrics.cpuUsage * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .accessibilityLabel("SK Mole CPU \(Int((monitor.metrics.cpuUsage * 100).rounded())) percent")
    }
}
