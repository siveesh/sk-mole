import Foundation
import SKMoleShared

actor DirectorySizer {
    private struct SizeCacheEntry: Codable {
        let sizeBytes: UInt64
        let modificationDate: Date?
        let isDirectory: Bool
        let cachedAt: Date?
        let resourceIdentity: String?
    }

    private let fileManager = FileManager.default
    private let cacheURL = SharedSupportDirectories.fileURL(named: "size-cache.json")
    private let maxCacheEntries = 5_000
    private let maxCacheFileBytes: UInt64 = 8 * 1_024 * 1_024
    private let maxCacheAge: TimeInterval = 6 * 60 * 60
    private let maxDirectChildren = 2_000

    private var cache: [String: SizeCacheEntry] = [:]
    private var hasLoadedCache = false
    private var saveTask: Task<Void, Never>?

    func invalidate() {
        cache.removeAll()
        hasLoadedCache = true
        saveNow()
    }

    func pruneMissingEntries() {
        loadCacheIfNeeded()
        cache = cache.filter { fileManager.fileExists(atPath: $0.key) }
        scheduleSave()
    }

    func size(of url: URL) async -> UInt64 {
        loadCacheIfNeeded()
        let normalized = URLPathSafety.standardized(url)
        let key = normalized.path

        if let cached = cache[key], isCacheValid(cached, for: normalized) {
            return cached.sizeBytes
        }

        let calculated = calculateSize(of: normalized)
        cache[key] = SizeCacheEntry(
            sizeBytes: calculated,
            modificationDate: modificationDate(for: normalized),
            isDirectory: isDirectory(at: normalized),
            cachedAt: .now,
            resourceIdentity: resourceIdentity(for: normalized)
        )
        trimCacheIfNeeded()
        scheduleSave()
        return calculated
    }

    func children(of root: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isPackageKey,
                .localizedNameKey
            ],
            options: options.union(.skipsSubdirectoryDescendants),
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var children: [URL] = []
        for case let child as URL in enumerator {
            children.append(child)
            if children.count >= maxDirectChildren || Task.isCancelled {
                break
            }
        }

        return children
    }

    func sizedChildren(of root: URL, includeHidden: Bool = false) async -> [(url: URL, sizeBytes: UInt64)] {
        loadCacheIfNeeded()

        let normalizedRoot = URLPathSafety.standardized(root)
        let directChildren = children(of: normalizedRoot, includeHidden: includeHidden)
        guard !directChildren.isEmpty else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        var childSizes = Dictionary(uniqueKeysWithValues: directChildren.map { (URLPathSafety.standardized($0).path, UInt64(0)) })
        let childLookup = Set(childSizes.keys)

        for child in directChildren {
            if Task.isCancelled {
                break
            }

            let values = try? child.resourceValues(forKeys: resourceKeys)
            let isDirectory = values?.isDirectory == true
            let isPackage = values?.isPackage == true

            if !isDirectory {
                childSizes[URLPathSafety.standardized(child).path] = UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
            } else if isPackage {
                childSizes[URLPathSafety.standardized(child).path] = await size(of: child)
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: includeHidden ? [] : [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return directChildren.map { ($0, childSizes[URLPathSafety.standardized($0).path] ?? 0) }
        }

        let rootPath = normalizedRoot.path
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                break
            }

            guard let childPath = directChildPath(for: fileURL, rootPath: rootPath),
                  childLookup.contains(childPath),
                  let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if URLPathSafety.standardized(fileURL).path == childPath {
                if values.isDirectory == true, values.isPackage == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values.isDirectory == true {
                if values.isPackage == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            childSizes[childPath, default: 0] += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        for child in directChildren {
            let normalized = URLPathSafety.standardized(child)
            let key = normalized.path
            let size = childSizes[key] ?? 0
            cache[key] = SizeCacheEntry(
                sizeBytes: size,
                modificationDate: modificationDate(for: normalized),
                isDirectory: isDirectory(at: normalized),
                cachedAt: .now,
                resourceIdentity: resourceIdentity(for: normalized)
            )
        }

        trimCacheIfNeeded()
        scheduleSave()
        return directChildren.map { ($0, childSizes[URLPathSafety.standardized($0).path] ?? 0) }
    }

    private func calculateSize(of url: URL) -> UInt64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(of: url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: UInt64 = 0

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                return total
            }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if values.isDirectory == true {
                continue
            }

            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        return total
    }

    private func fileSize(of url: URL) -> UInt64 {
        if Task.isCancelled {
            return 0
        }

        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }

        return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func directChildPath(for url: URL, rootPath: String) -> String? {
        let path = URLPathSafety.standardized(url).path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path.hasPrefix(prefix), path != rootPath else {
            return nil
        }

        let relative = path.dropFirst(prefix.count)
        guard let firstComponent = relative.split(separator: "/", maxSplits: 1).first else {
            return nil
        }

        if rootPath == "/" {
            return "/" + String(firstComponent)
        }

        return URL(fileURLWithPath: rootPath).appendingPathComponent(String(firstComponent)).path
    }

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else {
            return
        }

        hasLoadedCache = true

        if let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           UInt64(size) > maxCacheFileBytes {
            try? fileManager.removeItem(at: cacheURL)
            return
        }

        guard let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        cache = (try? JSONDecoder().decode([String: SizeCacheEntry].self, from: data)) ?? [:]
        trimCacheIfNeeded()
    }

    private func isCacheValid(_ entry: SizeCacheEntry, for url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        if let cachedAt = entry.cachedAt, Date().timeIntervalSince(cachedAt) > maxCacheAge {
            return false
        }

        guard entry.modificationDate == modificationDate(for: url) else {
            return false
        }

        guard let resourceIdentity = entry.resourceIdentity else {
            return false
        }

        return resourceIdentity == self.resourceIdentity(for: url)
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func resourceIdentity(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]) else {
            return nil
        }

        return [
            values.volumeIdentifier.map { String(describing: $0) } ?? "volume:unknown",
            values.fileResourceIdentifier.map { String(describing: $0) } ?? "file:unknown"
        ].joined(separator: "|")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        trimCacheIfNeeded()
        let snapshot = cache
        let destination = cacheURL

        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let encoder = JSONEncoder()
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        trimCacheIfNeeded()
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func trimCacheIfNeeded() {
        guard cache.count > maxCacheEntries else {
            return
        }

        cache = Dictionary(
            uniqueKeysWithValues: cache
                .sorted { left, right in
                    (left.value.modificationDate ?? .distantPast) > (right.value.modificationDate ?? .distantPast)
                }
                .prefix(maxCacheEntries)
                .map { ($0.key, $0.value) }
        )
    }
}
