import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint.opacity(0.12)))

                Spacer()

                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 198, alignment: .topLeading)
        .moleCardStyle()
    }
}
