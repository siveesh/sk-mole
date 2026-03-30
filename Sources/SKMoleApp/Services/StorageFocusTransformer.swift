import Foundation

struct StorageFocusTransformer {
    private struct FileTypeDescriptor: Hashable {
        let id: String
        let title: String
        let icon: String
    }

    private struct CollapseRule {
        let id: String
        let title: String
        let icon: String
        let matchingNames: Set<String>
    }

    private let collapseRules: [CollapseRule] = [
        CollapseRule(
            id: "build-churn",
            title: "Build Artifacts",
            icon: "hammer.fill",
            matchingNames: ["build", "dist", ".next", "out", "deriveddata", "archive", ".cache"]
        ),
        CollapseRule(
            id: "dependencies",
            title: "Dependency Stores",
            icon: "shippingbox.fill",
            matchingNames: ["node_modules", "pods", "carthage", "package.resolved", ".pnpm-store", ".swiftpm", "vendor"]
        ),
        CollapseRule(
            id: "local-envs",
            title: "Local Environments",
            icon: "cube.transparent.fill",
            matchingNames: ["venv", ".venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"]
        )
    ]

    func transform(node: StorageNode, configuration: StorageFocusConfiguration) -> StorageFocusResult {
        let candidateNodes = nodes(for: node.children, mode: configuration.mode)
        let collapsedNodes = configuration.collapseCommonClutter
            ? applyCollapseRules(to: candidateNodes)
            : candidateNodes
        let filteredNodes = applyMinimumSize(configuration.minimumSize, to: collapsedNodes)
        let sortedNodes = filteredNodes.sorted { left, right in
            if left.sizeBytes != right.sizeBytes {
                return left.sizeBytes > right.sizeBytes
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        return StorageFocusResult(
            node: StorageNode(
                id: node.id,
                name: node.name,
                icon: node.icon,
                url: node.url,
                sizeBytes: node.sizeBytes,
                kind: node.kind,
                children: sortedNodes
            ),
            sourceChildCount: candidateNodes.count,
            visibleChildCount: sortedNodes.count,
            hiddenChildCount: max(candidateNodes.count - sortedNodes.count, 0),
            mode: configuration.mode,
            minimumSize: configuration.minimumSize,
            collapseCommonClutter: configuration.collapseCommonClutter
        )
    }

    private func nodes(for children: [StorageNode], mode: StorageFocusMode) -> [StorageNode] {
        switch mode {
        case .balanced:
            return children
        case .directories:
            return children.filter { $0.kind != .file }
        case .files:
            return flattenedFiles(in: children)
        case .fileTypes:
            return groupedFileTypes(in: children)
        }
    }

    private func flattenedFiles(in nodes: [StorageNode]) -> [StorageNode] {
        nodes.flatMap { node in
            switch node.kind {
            case .file, .package:
                return [node]
            case .remainder:
                return []
            case .root, .volume, .section, .directory:
                return flattenedFiles(in: node.children)
            }
        }
    }

    private func groupedFileTypes(in nodes: [StorageNode]) -> [StorageNode] {
        let files = flattenedFiles(in: nodes)
        let grouped = Dictionary(grouping: files, by: fileTypeDescriptor(for:))

        return grouped.map { descriptor, entries in
            StorageNode(
                id: "file-type:\(descriptor.id)",
                name: descriptor.title,
                icon: descriptor.icon,
                url: nil,
                sizeBytes: entries.reduce(into: 0) { $0 += $1.sizeBytes },
                kind: .remainder,
                children: []
            )
        }
    }

    private func applyCollapseRules(to nodes: [StorageNode]) -> [StorageNode] {
        guard !nodes.isEmpty else {
            return []
        }

        var remaining = nodes
        var collapsed: [StorageNode] = []

        for rule in collapseRules {
            let matches = remaining.filter { node in
                rule.matchingNames.contains(node.name.lowercased())
            }

            guard !matches.isEmpty else {
                continue
            }

            remaining.removeAll { node in
                matches.contains(where: { $0.id == node.id })
            }

            collapsed.append(
                StorageNode(
                    id: "collapsed:\(rule.id)",
                    name: rule.title,
                    icon: rule.icon,
                    url: nil,
                    sizeBytes: matches.reduce(into: 0) { $0 += $1.sizeBytes },
                    kind: .remainder,
                    children: []
                )
            )
        }

        return remaining + collapsed
    }

    private func applyMinimumSize(_ filter: StorageMinimumSizeFilter, to nodes: [StorageNode]) -> [StorageNode] {
        guard filter.minimumBytes > 0, !nodes.isEmpty else {
            return nodes
        }

        let filtered = nodes.filter { $0.sizeBytes >= filter.minimumBytes }
        guard !filtered.isEmpty else {
            return Array(nodes.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(8))
        }

        return filtered
    }

    private func fileTypeDescriptor(for node: StorageNode) -> FileTypeDescriptor {
        if node.kind == .package, node.url?.pathExtension.lowercased() == "app" {
            return FileTypeDescriptor(id: "applications", title: "Applications", icon: "xmark.app")
        }

        let ext = node.url?.pathExtension.lowercased() ?? ""

        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg":
            return FileTypeDescriptor(id: "images", title: "Images", icon: "photo")
        case "mov", "mp4", "m4v", "mkv", "avi":
            return FileTypeDescriptor(id: "video", title: "Video", icon: "film")
        case "mp3", "aac", "wav", "m4a", "flac":
            return FileTypeDescriptor(id: "audio", title: "Audio", icon: "music.note")
        case "zip", "tar", "gz", "xz", "7z", "rar":
            return FileTypeDescriptor(id: "archives", title: "Archives", icon: "archivebox")
        case "dmg", "pkg", "xip":
            return FileTypeDescriptor(id: "installers", title: "Installers", icon: "square.and.arrow.down.on.square")
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "cpp", "c", "h", "hpp", "json", "yaml", "yml":
            return FileTypeDescriptor(id: "code", title: "Code", icon: "chevron.left.forwardslash.chevron.right")
        case "pages", "doc", "docx", "pdf", "txt", "md", "rtf":
            return FileTypeDescriptor(id: "documents", title: "Documents", icon: "doc.text")
        case "":
            return FileTypeDescriptor(id: "no-extension", title: "No Extension", icon: "questionmark.folder")
        default:
            let uppercased = ext.uppercased()
            return FileTypeDescriptor(id: "ext-\(ext)", title: "\(uppercased) Files", icon: "doc")
        }
    }
}
