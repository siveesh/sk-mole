import SwiftUI

struct InlineScanProgressView: View {
    let progress: ScanProgress
    var tint: Color = AppPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: progress.fractionComplete)
                .tint(tint)
                .controlSize(.small)
        }
    }
}
