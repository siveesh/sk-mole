import SwiftUI

struct ExportPluginGridView: View {
    let plugins: [MaintenanceExportPluginDescriptor]
    let onExport: (MaintenanceExportPluginID) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(plugins) { plugin in
                Button {
                    onExport(plugin.id)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(plugin.title, systemImage: plugin.icon)
                            .font(.headline)

                        Text(plugin.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(".\(plugin.fileExtension)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
