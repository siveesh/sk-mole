import AppKit
import SwiftUI

struct AboutView: View {
    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 8) {
                Text("SK Mole")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Native macOS maintenance, cleanup, uninstall, storage insight, and live system monitoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(versionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                aboutRow(title: "Developer", value: "Siveesh Kodapully")
                aboutRow(title: "Focus", value: "Safe previews, Trash-first actions, and efficient native performance")
                aboutRow(title: "Appearance", value: "Supports system-wide light and dark mode")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 440)
        .background(AppPalette.canvas)
    }

    private func aboutRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}
