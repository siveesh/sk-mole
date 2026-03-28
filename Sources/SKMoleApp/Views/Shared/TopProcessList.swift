import SwiftUI

struct TopProcessList: View {
    let processes: [ProcessActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if processes.isEmpty {
                Text("Process insight fills in after the first few monitoring samples.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(process.name)
                                .font(.headline)
                            Text(process.command)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("PID \(process.pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1f%% CPU", process.cpuPercent))
                                .font(.subheadline.weight(.semibold))
                            Text(ByteFormatting.format(process.memoryBytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.55))
                    )
                }
            }
        }
    }
}
