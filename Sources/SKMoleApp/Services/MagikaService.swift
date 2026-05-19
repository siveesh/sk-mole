import Foundation
import SKMoleShared

actor MagikaService {
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let recursiveFileLimit = 500
    private let chunkSize = 80

    static func sanitizeJSONArrayEnvelope(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstBracket = trimmed.firstIndex(of: "["),
              let lastBracket = trimmed.lastIndex(of: "]") else {
            return trimmed
        }

        return String(trimmed[firstBracket...lastBracket])
    }

    func detectStatus() async throws -> MagikaStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/magika",
            "/usr/local/bin/magika",
            "\(home)/.local/bin/magika"
        ]

        let executablePath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        guard let executablePath else {
            return MagikaStatus(executablePath: nil, version: nil)
        }

        let versionResult = try await runProcess(executable: executablePath, arguments: ["--version"])
        let version = versionResult.output
            .split(whereSeparator: \.isNewline)
            .first?
            .replacingOccurrences(of: "magika ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MagikaStatus(executablePath: executablePath, version: version)
    }

    func scan(targets: [MagikaScanTarget], recursive: Bool, status: MagikaStatus? = nil) async throws -> MagikaScanReport {
        let resolvedStatus = try await resolvedStatus(from: status)
        guard let executablePath = resolvedStatus.executablePath else {
            throw MagikaError.notInstalled
        }

        let uniqueTargets = unique(targets: targets)
        guard !uniqueTargets.isEmpty else {
            throw MagikaError.noTargets
        }

        let displayArguments = commandArguments(for: uniqueTargets, recursive: recursive)
        let executionTargets = recursive ? expandedTargets(from: uniqueTargets) : uniqueTargets
        guard !executionTargets.isEmpty else {
            throw MagikaError.noTargets
        }

        var items: [MagikaScanItem] = []
        for chunk in executionTargets.chunked(into: chunkSize) {
            if Task.isCancelled {
                break
            }

            let arguments = commandArguments(for: chunk, recursive: false)
            let result = try await runProcess(executable: executablePath, arguments: arguments)
            guard result.terminationStatus == 0 else {
                throw MagikaError.commandFailed(result.output)
            }

            items.append(contentsOf: try decodeItems(from: result.output))
        }

        return MagikaScanReport(
            status: resolvedStatus,
            targets: uniqueTargets,
            recursive: recursive,
            command: shellCommand(executablePath: executablePath, arguments: displayArguments),
            items: items.sorted {
                $0.path.path.localizedCaseInsensitiveCompare($1.path.path) == .orderedAscending
            },
            scannedAt: .now
        )
    }

    private func resolvedStatus(from status: MagikaStatus?) async throws -> MagikaStatus {
        if let status {
            return status
        }

        return try await detectStatus()
    }

    private func unique(targets: [MagikaScanTarget]) -> [MagikaScanTarget] {
        var seen: [String: MagikaScanTarget] = [:]
        for target in targets {
            seen[target.id] = target
        }

        return seen.values.sorted {
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }

            return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }
    }

    private func commandArguments(for targets: [MagikaScanTarget], recursive: Bool) -> [String] {
        var arguments = ["--json"]
        if recursive {
            arguments.append("--recursive")
        }
        arguments.append(contentsOf: targets.map(\.url.path))
        return arguments
    }

    private func expandedTargets(from targets: [MagikaScanTarget]) -> [MagikaScanTarget] {
        var expanded: [MagikaScanTarget] = []
        var seen = Set<String>()

        for target in targets {
            if Task.isCancelled || expanded.count >= recursiveFileLimit {
                break
            }

            switch target.kind {
            case .file:
                appendTarget(target, to: &expanded, seen: &seen)
            case .directory:
                for file in files(in: target.url, limit: recursiveFileLimit - expanded.count) {
                    appendTarget(MagikaScanTarget(url: file, kind: .file), to: &expanded, seen: &seen)
                    if expanded.count >= recursiveFileLimit {
                        break
                    }
                }
            }
        }

        return expanded
    }

    private func appendTarget(
        _ target: MagikaScanTarget,
        to expanded: inout [MagikaScanTarget],
        seen: inout Set<String>
    ) {
        let normalized = URLPathSafety.standardized(target.url)
        guard seen.insert(normalized.path).inserted else {
            return
        }

        expanded.append(MagikaScanTarget(url: normalized, kind: target.kind))
    }

    private func files(in directory: URL, limit: Int) -> [URL] {
        guard limit > 0,
              let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
              ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled {
                break
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage == true {
                enumerator.skipDescendants()
                continue
            }

            guard values?.isRegularFile == true else {
                continue
            }

            files.append(url)
            if files.count >= limit {
                break
            }
        }

        return files
    }

    private func decodeItems(from output: String) throws -> [MagikaScanItem] {
        let sanitized = Self.sanitizeJSONArrayEnvelope(from: output)
        guard let data = sanitized.data(using: .utf8) else {
            throw MagikaError.invalidResponse
        }

        let payload = try decoder.decode([MagikaCLIRecord].self, from: data)
        return payload.map { record in
            let fileURL = fileURL(from: record.path)
            let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize

            return MagikaScanItem(
                path: fileURL,
                status: record.result.status,
                trustedType: record.result.value?.output,
                modelType: record.result.value?.dl,
                score: record.result.value?.score,
                overwriteReason: record.result.value?.overwriteReason,
                detail: record.result.detail,
                fileSizeBytes: size.map(UInt64.init)
            )
        }
    }

    private func fileURL(from path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            environment: Self.processEnvironment(for: executable),
            timeout: arguments.contains("--recursive") ? 240 : 90,
            maxOutputBytes: 16 * 1_024 * 1_024
        )
        return ProcessResult(output: result.output, terminationStatus: result.terminationStatus)
    }

    private static func processEnvironment(for executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let pathEntries = [
            executableDirectory,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = Array(NSOrderedSet(array: pathEntries)).compactMap { $0 as? String }.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    private func shellCommand(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments)
            .map(Self.shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ string: String) -> String {
        if string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "'\""))) == nil {
            return string
        }

        return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct ProcessResult {
    let output: String
    let terminationStatus: Int32
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index..<Swift.min(index + size, count)])
        }
    }
}

private struct MagikaCLIRecord: Decodable {
    let path: String
    let result: MagikaCLIResult
}

private struct MagikaCLIResult: Decodable {
    let status: String
    let value: MagikaCLIValue?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case status
        case value
        case detail = "description"
    }
}

private struct MagikaCLIValue: Decodable {
    let dl: MagikaContentTypeInfo
    let output: MagikaContentTypeInfo
    let score: Double
    let overwriteReason: String?

    enum CodingKeys: String, CodingKey {
        case dl
        case output
        case score
        case overwriteReason = "overwrite_reason"
    }
}

private enum MagikaError: LocalizedError {
    case notInstalled
    case invalidResponse
    case commandFailed(String)
    case noTargets

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Magika is not installed on this Mac yet."
        case .invalidResponse:
            return "Magika returned unreadable JSON."
        case let .commandFailed(output):
            return output.isEmpty ? "The Magika scan failed." : output
        case .noTargets:
            return "Add at least one file or folder before running Magika."
        }
    }
}
