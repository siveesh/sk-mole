import SwiftUI

struct StorageDonutChart: View {
    let sections: [StorageSection]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2
            let total = max(Double(sections.reduce(into: UInt64(0)) { $0 += $1.sizeBytes }), 1)
            let palette: [Color] = [AppPalette.accent, AppPalette.amber, AppPalette.sky, AppPalette.rose, AppPalette.mint, .purple]

            ZStack {
                ForEach(Array(sections.prefix(6).enumerated()), id: \.offset) { offset, section in
                    let start = sections.prefix(offset).reduce(0.0) { partial, item in
                        partial + Double(item.sizeBytes) / total
                    }
                    let end = start + Double(section.sizeBytes) / total

                    DonutSliceShape(startFraction: start, endFraction: end)
                        .stroke(
                            palette[offset % palette.count],
                            style: StrokeStyle(lineWidth: radius * 0.28, lineCap: .round)
                        )
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: radius * 0.9, height: radius * 0.9)

                VStack(spacing: 6) {
                    Text("Tracked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ByteFormatting.format(sections.reduce(into: 0) { $0 += $1.sizeBytes }))
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .position(center)
            }
        }
    }
}

private struct DonutSliceShape: Shape {
    let startFraction: Double
    let endFraction: Double

    func path(in rect: CGRect) -> Path {
        let start = Angle(degrees: 360 * startFraction - 90)
        let end = Angle(degrees: 360 * endFraction - 90)
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        return path
    }
}
