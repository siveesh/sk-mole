import SwiftUI

struct StorageSpaceMap: View {
    let currentNode: StorageNode
    let onOpen: (StorageNode) -> Void
    let onReveal: (URL) -> Void
    let onUseUninstaller: (URL) -> Void

    private var totalBytes: UInt64 {
        max(
            currentNode.sizeBytes,
            currentNode.children.reduce(into: 0) { $0 += $1.sizeBytes }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if currentNode.children.isEmpty {
                ContentUnavailableView(
                    "No Deeper Breakdown Here",
                    systemImage: "square.grid.3x3.square",
                    description: Text("This level is already a leaf in the current storage scan.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                StorageSpaceCardGrid(
                    nodes: currentNode.children,
                    totalBytes: totalBytes,
                    onOpen: onOpen
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Largest contributors at this level")
                        .font(.headline)

                    ForEach(currentNode.children) { node in
                        StorageSpaceRow(
                            node: node,
                            totalBytes: totalBytes,
                            onOpen: onOpen,
                            onReveal: onReveal,
                            onUseUninstaller: onUseUninstaller
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.62))
        )
    }
}

private struct StorageSpaceCardGrid: View {
    let nodes: [StorageNode]
    let totalBytes: UInt64
    let onOpen: (StorageNode) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 320), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(nodes) { node in
                StorageSpaceCard(
                    node: node,
                    totalBytes: totalBytes,
                    onOpen: onOpen
                )
            }
        }
    }
}

private struct StorageSpaceCard: View {
    let node: StorageNode
    let totalBytes: UInt64
    let onOpen: (StorageNode) -> Void

    private var percentageText: String {
        guard totalBytes > 0 else {
            return "0%"
        }

        return (Double(node.sizeBytes) / Double(totalBytes))
            .formatted(.percent.precision(.fractionLength(0)))
    }

    private var progressFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(Double(node.sizeBytes) / Double(totalBytes), 1)
    }

    private var isInteractive: Bool {
        node.isDrillable || node.canReveal
    }

    var body: some View {
        Group {
            if isInteractive {
                Button {
                    onOpen(node)
                } label: {
                    cardBody
                }
                .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
        .help(node.isDrillable ? "Drill into \(node.name)" : node.name)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(node.name, systemImage: node.icon)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(percentageText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }

            Text(ByteFormatting.format(node.sizeBytes))
                .font(.title3.weight(.bold))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))

                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: max(proxy.size.width * progressFraction, 10))
                }
            }
            .frame(height: 10)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if node.isDrillable {
                    Text("Drill Down")
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                } else if node.canReveal {
                    Text("Open")
                    Image(systemName: "eye")
                } else {
                    Text("Summary")
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(StorageSpaceColor.color(for: node.id))
        )
    }
}

private struct StorageSpaceRow: View {
    let node: StorageNode
    let totalBytes: UInt64
    let onOpen: (StorageNode) -> Void
    let onReveal: (URL) -> Void
    let onUseUninstaller: (URL) -> Void

    private var percentageText: String {
        guard totalBytes > 0 else {
            return "0%"
        }

        return (Double(node.sizeBytes) / Double(totalBytes))
            .formatted(.percent.precision(.fractionLength(0)))
    }

    private var progressFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(Double(node.sizeBytes) / Double(totalBytes), 1)
    }

    private var isAppBundle: Bool {
        node.url?.pathExtension.lowercased() == "app"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: node.icon)
                .foregroundStyle(StorageSpaceColor.color(for: node.id))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(ByteFormatting.format(node.sizeBytes))
                    Text(percentageText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(StorageSpaceColor.color(for: node.id))
                        .frame(width: max(proxy.size.width * progressFraction, 10))
                }
            }
            .frame(height: 10)

            if node.isDrillable {
                Button("Explore") {
                    onOpen(node)
                }
                .buttonStyle(.bordered)

                if let url = node.url {
                    ActionIconButton(symbol: "eye", label: "Reveal \(node.name)") {
                        onReveal(url)
                    }
                }
            } else if let url = node.url {
                ActionIconButton(
                    symbol: isAppBundle ? "xmark.app" : "eye",
                    label: isAppBundle ? "Preview \(node.name) in Uninstaller" : "Reveal \(node.name)",
                    style: isAppBundle ? .prominent(AppPalette.accent) : .bordered
                ) {
                    if isAppBundle {
                        onUseUninstaller(url)
                    } else {
                        onReveal(url)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private enum StorageSpaceColor {
    private static let palette: [Color] = [
        AppPalette.accent,
        AppPalette.sky,
        AppPalette.mint,
        AppPalette.amber,
        AppPalette.rose
    ]

    static func color(for id: String) -> Color {
        let hash = UInt(bitPattern: id.hashValue)
        return palette[Int(hash % UInt(palette.count))]
    }
}
