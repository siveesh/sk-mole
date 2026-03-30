import SwiftUI

struct PerCoreUsageGrid: View {
    let usage: [Double]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
            ForEach(Array(usage.enumerated()), id: \.offset) { index, value in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Core \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(Int((value * 100).rounded()))%")
                            .font(.caption.weight(.bold))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))

                            Capsule()
                                .fill(AppPalette.accent)
                                .frame(width: max(10, proxy.size.width * value))
                        }
                    }
                    .frame(height: 10)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppPalette.secondaryCard.opacity(0.55))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
