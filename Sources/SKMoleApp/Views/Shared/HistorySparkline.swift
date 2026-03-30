import SwiftUI

struct HistorySparkline: View {
    let points: [MetricHistoryPoint]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .local)
            let normalizedPoints = plotPoints(in: frame.size)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.secondaryCard.opacity(0.35))

                if normalizedPoints.count > 1 {
                    areaPath(for: normalizedPoints, in: frame.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.24), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(for: normalizedPoints)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                    if let last = normalizedPoints.last {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .position(last)
                    }
                } else {
                    Text("History builds up as SK Mole samples your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(height: 120)
        .allowsHitTesting(false)
    }

    private func plotPoints(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else {
            return []
        }

        let maxValue = max(points.map(\.value).max() ?? 1, 1)
        let stepX = size.width / CGFloat(max(points.count - 1, 1))

        return points.enumerated().map { index, point in
            let x = CGFloat(index) * stepX
            let yProgress = max(0, min(1, point.value / maxValue))
            let y = size.height - (size.height * CGFloat(yProgress))
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(for points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(for points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }

            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)

            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
