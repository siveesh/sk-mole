import AppKit
import Darwin
import Foundation
import Security

actor QuarantineAuditService {
    private let fileManager = FileManager.default
    private let guardService: SystemGuard
    private let sizer: DirectorySizer
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init(guardService: SystemGuard, sizer: DirectorySizer) {
        self.guardService = guardService
        self.sizer = sizer
    }

    func discoverQuarantinedApplications(
        progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
    ) async -> [QuarantinedApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents")
        ]

        var appURLs: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled {
                return []
            }

            appURLs.append(contentsOf: findApplications(in: root))
        }

        let uniqueURLs = Array(Set(appURLs))
        var apps: [QuarantinedApplication] = []

        for (index, url) in uniqueURLs.enumerated() {
            if Task.isCancelled {
                return sorted(apps)
            }

            await progress(
                ScanProgress(
                    title: "Quarantine review",
                    detail: "Inspecting \(url.deletingPathExtension().lastPathComponent)",
                    completedUnits: index + 1,
                    totalUnits: max(uniqueURLs.count, 1)
                )
            )

            guard await guardService.canOperate(on: url, purpose: .quarantine),
                  let app = await inspectApplication(at: url) else {
                continue
            }

            apps.append(app)
        }

        return sorted(apps)
    }

    func removeQuarantine(from apps: [QuarantinedApplication]) async -> [OptimizationLog] {
        var logs: [OptimizationLog] = []

        for app in apps {
            do {
                guard await guardService.canOperate(on: app.url, purpose: .quarantine) else {
                    throw NSError(
                        domain: "SKMole.Quarantine",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Blocked xattr removal for unsupported location: \(app.url.path)"]
                    )
                }

                let result = try await runProcess(
                    executable: "/usr/bin/xattr",
                    arguments: ["-d", "com.apple.quarantine", app.url.path]
                )
                let output = result.output.isEmpty ? "Removed quarantine attribute from \(app.url.path)" : result.output

                logs.append(
                    OptimizationLog(
                        actionTitle: "xattr: \(app.name)",
                        output: output,
                        succeeded: result.terminationStatus == 0,
                        timestamp: .now
                    )
                )
            } catch {
                logs.append(
                    OptimizationLog(
                        actionTitle: "xattr: \(app.name)",
                        output: error.localizedDescription,
                        succeeded: false,
                        timestamp: .now
                    )
                )
            }
        }

        return logs
    }

    private func inspectApplication(at url: URL) async -> QuarantinedApplication? {
        let normalized = URLPathSafety.standardized(url)
        guard normalized.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: normalized.path),
              let quarantineValue = readExtendedAttribute(named: "com.apple.quarantine", at: normalized) else {
            return nil
        }

        let bundle = Bundle(url: normalized)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? normalized.deletingPathExtension().lastPathComponent
        let size = await sizer.size(of: normalized)
        let lastModified = try? normalized.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        return QuarantinedApplication(
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            url: normalized,
            sizeBytes: size,
            quarantineValue: quarantineValue,
            signatureStatus: signatureStatus(for: normalized),
            lastModified: lastModified
        )
    }

    private func findApplications(in root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [URL] = []

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                results.append(url)
                enumerator.skipDescendants()
            }
        }

        return results
    }

    private func readExtendedAttribute(named attribute: String, at url: URL) -> String? {
        let path = url.path

        return path.withCString { pathPointer in
            attribute.withCString { attributePointer in
                let length = getxattr(pathPointer, attributePointer, nil, 0, 0, 0)
                guard length > 0 else {
                    return nil
                }

                var buffer = [UInt8](repeating: 0, count: length)
                let readLength = getxattr(pathPointer, attributePointer, &buffer, length, 0, 0)
                guard readLength >= 0 else {
                    return nil
                }

                return String(decoding: buffer.prefix(readLength), as: UTF8.self)
            }
        }
    }

    private func signatureStatus(for url: URL) -> QuarantineSignatureStatus {
        var staticCode: SecStaticCode?
        let creationStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard creationStatus == errSecSuccess, let staticCode else {
            return .unknown(SecCopyErrorMessageString(creationStatus, nil) as String?)
        }

        let status = SecStaticCodeCheckValidityWithErrors(staticCode, [], nil, nil)
        if status == errSecSuccess {
            return .valid
        }

        if status == errSecCSUnsigned {
            return .unsigned
        }

        return .invalid(SecCopyErrorMessageString(status, nil) as String?)
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: ProcessResult(output: output, terminationStatus: process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sorted(_ apps: [QuarantinedApplication]) -> [QuarantinedApplication] {
        apps.sorted { left, right in
            if left.signatureStatus.sortOrder != right.signatureStatus.sortOrder {
                return left.signatureStatus.sortOrder < right.signatureStatus.sortOrder
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }
}

private struct ProcessResult {
    let output: String
    let terminationStatus: Int32
}
