import CryptoKit
import Foundation

actor CleanupScanner {
    private struct CleanupRule {
        let id: CleanupCategoryID
        let title: String
        let subtitle: String
        let icon: String
        let safetyLevel: SafetyLevel
        let minimumSize: UInt64
        let roots: [URL]
    }

    private let guardService: SystemGuard
    private let sizer: DirectorySizer
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let installerExtensions: Set<String> = ["dmg", "pkg", "xip", "iso"]
    private let duplicateMinimumSize: UInt64 = 16 * 1_024 * 1_024

    init(guardService: SystemGuard, sizer: DirectorySizer) {
        self.guardService = guardService
        self.sizer = sizer
    }

    func scan(progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }) async -> [CleanupCategorySummary] {
        await sizer.pruneMissingEntries()

        let rules = [
            CleanupRule(
                id: .userCaches,
                title: "User caches",
                subtitle: "App caches in your home Library that macOS and apps can rebuild safely.",
                icon: "externaldrive.badge.timemachine",
                safetyLevel: .safe,
                minimumSize: 32 * 1_024 * 1_024,
                roots: [home.appendingPathComponent("Library/Caches")]
            ),
            CleanupRule(
                id: .browserLeftovers,
                title: "Browser leftovers",
                subtitle: "Browser cache stores and web process leftovers, not bookmarks or saved logins.",
                icon: "globe",
                safetyLevel: .review,
                minimumSize: 48 * 1_024 * 1_024,
                roots: [
                    home.appendingPathComponent("Library/Caches/Google/Chrome"),
                    home.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser"),
                    home.appendingPathComponent("Library/Caches/Microsoft Edge"),
                    home.appendingPathComponent("Library/Caches/Firefox"),
                    home.appendingPathComponent("Library/Caches/com.apple.Safari")
                ]
            ),
            CleanupRule(
                id: .logs,
                title: "Logs and diagnostics",
                subtitle: "Rotating logs and crash diagnostics that are safe to reclaim when no longer needed.",
                icon: "doc.text.magnifyingglass",
                safetyLevel: .safe,
                minimumSize: 8 * 1_024 * 1_024,
                roots: [
                    home.appendingPathComponent("Library/Logs"),
                    home.appendingPathComponent("Library/Logs/DiagnosticReports")
                ]
            ),
            CleanupRule(
                id: .developer,
                title: "Developer artifacts",
                subtitle: "Build outputs and simulator caches that can consume tens of gigabytes.",
                icon: "hammer",
                safetyLevel: .safe,
                minimumSize: 64 * 1_024 * 1_024,
                roots: [
                    home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                    home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")
                ]
            ),
            CleanupRule(
                id: .packageManagers,
                title: "Package manager caches",
                subtitle: "npm, pnpm, Yarn, and Gradle caches. Safe, but expect slower first rebuilds afterward.",
                icon: "shippingbox",
                safetyLevel: .review,
                minimumSize: 64 * 1_024 * 1_024,
                roots: [
                    home.appendingPathComponent(".npm/_cacache"),
                    home.appendingPathComponent(".pnpm-store"),
                    home.appendingPathComponent(".cache/yarn"),
                    home.appendingPathComponent(".gradle/caches")
                ]
            ),
            CleanupRule(
                id: .trash,
                title: "Trash",
                subtitle: "Files already removed from apps and Finder but still occupying space.",
                icon: "trash",
                safetyLevel: .safe,
                minimumSize: 1,
                roots: [home.appendingPathComponent(".Trash")]
            )
        ]

        var results: [CleanupCategorySummary] = []
        let totalSteps = rules.count + 3

        for (index, rule) in rules.enumerated() {
            if Task.isCancelled {
                return results
            }

            await progress(
                ScanProgress(
                    title: "Cleanup scan",
                    detail: "Sizing \(rule.title.lowercased())",
                    completedUnits: index + 1,
                    totalUnits: totalSteps
                )
            )

            var candidates: [CleanupCandidate] = []

            for root in rule.roots where FileManager.default.fileExists(atPath: root.path) {
                if Task.isCancelled {
                    return results
                }

                let children = await sizer.children(of: root, includeHidden: rule.id == .trash)

                for child in children {
                    if Task.isCancelled {
                        return results
                    }

                    guard await guardService.canOperate(on: child, purpose: .cleanup) else {
                        continue
                    }

                    let size = await sizer.size(of: child)
                    guard size >= rule.minimumSize else {
                        continue
                    }

                    let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey])
                    let candidate = CleanupCandidate(
                        url: child,
                        displayName: values?.localizedName ?? child.lastPathComponent,
                        sizeBytes: size,
                        lastModified: values?.contentModificationDate,
                        rationale: rule.subtitle,
                        safetyLevel: rule.safetyLevel
                    )
                    candidates.append(candidate)
                }
            }

            candidates.sort { $0.sizeBytes > $1.sizeBytes }

            results.append(
                CleanupCategorySummary(
                    category: rule.id,
                    title: rule.title,
                    subtitle: rule.subtitle,
                    icon: rule.icon,
                    safetyLevel: rule.safetyLevel,
                    totalBytes: candidates.reduce(into: 0) { $0 += $1.sizeBytes },
                    candidates: candidates
                )
            )
        }

        await progress(
            ScanProgress(
                title: "Cleanup scan",
                detail: "Looking for installer leftovers",
                completedUnits: rules.count + 1,
                totalUnits: totalSteps
            )
        )
        results.append(await installersCategory())

        await progress(
            ScanProgress(
                title: "Cleanup scan",
                detail: "Reviewing old downloads",
                completedUnits: rules.count + 2,
                totalUnits: totalSteps
            )
        )
        results.append(await oldDownloadsCategory())

        await progress(
            ScanProgress(
                title: "Cleanup scan",
                detail: "Hashing likely duplicate files",
                completedUnits: rules.count + 3,
                totalUnits: totalSteps
            )
        )
        results.append(await duplicatesCategory())

        return results
    }

    private func installersCategory() async -> CleanupCategorySummary {
        let roots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents")
        ]
        var candidates: [CleanupCandidate] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            for file in enumerateFiles(in: root, includePackages: true) {
                if Task.isCancelled {
                    break
                }

                guard await guardService.canOperate(on: file, purpose: .cleanup) else {
                    continue
                }

                let lowerExtension = file.pathExtension.lowercased()
                guard installerExtensions.contains(lowerExtension) else {
                    continue
                }

                let size = await sizer.size(of: file)
                guard size >= 8 * 1_024 * 1_024 else {
                    continue
                }

                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey])
                candidates.append(
                    CleanupCandidate(
                        url: file,
                        displayName: values?.localizedName ?? file.lastPathComponent,
                        sizeBytes: size,
                        lastModified: values?.contentModificationDate,
                        rationale: "Installer image or package. These files are usually only needed until the app is installed or updated.",
                        safetyLevel: .review
                    )
                )
            }
        }

        candidates.sort { $0.sizeBytes > $1.sizeBytes }

        return CleanupCategorySummary(
            category: .installers,
            title: "Installers and disk images",
            subtitle: "DMGs, PKGs, XIPs, and installer images left in common user folders.",
            icon: "shippingbox.circle",
            safetyLevel: .review,
            totalBytes: candidates.reduce(into: 0) { $0 += $1.sizeBytes },
            candidates: candidates
        )
    }

    private func oldDownloadsCategory() async -> CleanupCategorySummary {
        let root = home.appendingPathComponent("Downloads")
        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: .now) ?? .distantPast
        var candidates: [CleanupCandidate] = []

        guard fileManager.fileExists(atPath: root.path) else {
            return CleanupCategorySummary(
                category: .oldDownloads,
                title: "Old downloads",
                subtitle: "Large, stale downloads that have not been touched in over 45 days.",
                icon: "clock.arrow.circlepath",
                safetyLevel: .review,
                totalBytes: 0,
                candidates: []
            )
        }

        let children = await sizer.children(of: root)
        for child in children {
            if Task.isCancelled {
                break
            }

            guard await guardService.canOperate(on: child, purpose: .cleanup) else {
                continue
            }

            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else {
                continue
            }

            let size = await sizer.size(of: child)
            guard size >= 48 * 1_024 * 1_024 else {
                continue
            }

            candidates.append(
                CleanupCandidate(
                    url: child,
                    displayName: values?.localizedName ?? child.lastPathComponent,
                    sizeBytes: size,
                    lastModified: modified,
                    rationale: "Older download that looks inactive. Review before removing in case it is still part of your working set.",
                    safetyLevel: .review
                )
            )
        }

        candidates.sort { left, right in
            if left.sizeBytes != right.sizeBytes {
                return left.sizeBytes > right.sizeBytes
            }
            return (left.lastModified ?? .distantPast) < (right.lastModified ?? .distantPast)
        }

        return CleanupCategorySummary(
            category: .oldDownloads,
            title: "Old downloads",
            subtitle: "Large, stale downloads that have not been touched in over 45 days.",
            icon: "arrow.down.circle.dotted",
            safetyLevel: .review,
            totalBytes: candidates.reduce(into: 0) { $0 += $1.sizeBytes },
            candidates: candidates
        )
    }

    private func duplicatesCategory() async -> CleanupCategorySummary {
        let roots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Pictures")
        ]

        struct DuplicateSource {
            let url: URL
            let sizeBytes: UInt64
            let modifiedAt: Date?
            let displayName: String
        }

        var sizeBuckets: [UInt64: [DuplicateSource]] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            for file in enumerateFiles(in: root, includePackages: false) {
                if Task.isCancelled {
                    break
                }

                guard await guardService.canOperate(on: file, purpose: .cleanup) else {
                    continue
                }

                let values = try? file.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isPackageKey,
                    .fileAllocatedSizeKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .localizedNameKey
                ])
                guard values?.isDirectory != true else {
                    continue
                }

                let size = UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
                guard size >= duplicateMinimumSize else {
                    continue
                }

                sizeBuckets[size, default: []].append(
                    DuplicateSource(
                        url: file,
                        sizeBytes: size,
                        modifiedAt: values?.contentModificationDate,
                        displayName: values?.localizedName ?? file.lastPathComponent
                    )
                )
            }
        }

        var candidates: [CleanupCandidate] = []

        for bucket in sizeBuckets.values where bucket.count > 1 {
            if Task.isCancelled {
                break
            }

            var digestBuckets: [String: [DuplicateSource]] = [:]
            for source in bucket {
                if Task.isCancelled {
                    break
                }

                if let digest = digest(for: source.url) {
                    digestBuckets[digest, default: []].append(source)
                }
            }

            for group in digestBuckets.values where group.count > 1 {
                let sorted = group.sorted {
                    ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
                }
                guard let retained = sorted.first else { continue }

                for duplicate in sorted.dropFirst() {
                    candidates.append(
                        CleanupCandidate(
                            url: duplicate.url,
                            displayName: duplicate.displayName,
                            sizeBytes: duplicate.sizeBytes,
                            lastModified: duplicate.modifiedAt,
                            rationale: "Duplicate of \(retained.displayName). SK Mole keeps the newest copy selected by default and surfaces the extras for review.",
                            safetyLevel: .review
                        )
                    )
                }
            }
        }

        candidates.sort { $0.sizeBytes > $1.sizeBytes }

        return CleanupCategorySummary(
            category: .duplicates,
            title: "Duplicate files",
            subtitle: "Likely duplicate files from common user folders. SK Mole keeps one copy and surfaces the extras for review.",
            icon: "square.on.square",
            safetyLevel: .review,
            totalBytes: candidates.reduce(into: 0) { $0 += $1.sizeBytes },
            candidates: candidates
        )
    }

    private func enumerateFiles(in root: URL, includePackages: Bool) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDirectory = values?.isDirectory == true
            let isPackage = values?.isPackage == true

            if isDirectory, isPackage != true {
                continue
            }

            if isDirectory, !includePackages {
                continue
            }

            if isPackage == true {
                enumerator.skipDescendants()
            }

            results.append(url)
        }

        return results
    }

    private func digest(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }

        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1_048_576)
            guard let data, !data.isEmpty else {
                return false
            }

            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
