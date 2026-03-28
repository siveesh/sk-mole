import Foundation
import SKMoleShared

actor DirectorySizer {
    private struct SizeCacheEntry: Codable {
        let sizeBytes: UInt64
        let modificationDate: Date?
        let isDirectory: Bool
    }

    private let fileManager = FileManager.default
    private let cacheURL = SharedSupportDirectories.fileURL(named: "size-cache.json")

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
            isDirectory: isDirectory(at: normalized)
        )
        scheduleSave()
        return calculated
    }

    func children(of root: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]

        return (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isPackageKey,
                .localizedNameKey
            ],
            options: options
        )) ?? []
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

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else {
            return
        }

        hasLoadedCache = true

        guard let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        cache = (try? JSONDecoder().decode([String: SizeCacheEntry].self, from: data)) ?? [:]
    }

    private func isCacheValid(_ entry: SizeCacheEntry, for url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        return entry.modificationDate == modificationDate(for: url)
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func scheduleSave() {
        saveTask?.cancel()
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
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
