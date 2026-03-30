import Foundation

actor HomebrewService {
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    static func sanitizeJSONObjectEnvelope(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}") else {
            return trimmed
        }

        return String(trimmed[firstBrace...lastBrace])
    }

    static func parseDoctorIssues(from output: String) -> [HomebrewDoctorIssue] {
        let lines = output.components(separatedBy: .newlines)
        var issues: [HomebrewDoctorIssue] = []
        var currentTitle: String?
        var currentSummaryLines: [String] = []
        var currentPaths: [HomebrewDoctorIssuePath] = []
        var collectingUnexpectedDylibs = false

        func finalizeCurrentIssue() {
            guard let title = currentTitle else {
                return
            }

            let uniquePaths = Array(NSOrderedSet(array: currentPaths)).compactMap { $0 as? HomebrewDoctorIssuePath }
            let summary = currentSummaryLines.first(where: { !$0.isEmpty }) ?? title

            issues.append(
                HomebrewDoctorIssue(
                    title: title,
                    summary: summary,
                    paths: uniquePaths,
                    supportingLines: currentSummaryLines
                )
            )

            currentTitle = nil
            currentSummaryLines = []
            currentPaths = []
            collectingUnexpectedDylibs = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("Warning:") {
                finalizeCurrentIssue()
                currentTitle = trimmed.replacingOccurrences(of: "Warning:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }

            guard currentTitle != nil else {
                continue
            }

            if trimmed.localizedCaseInsensitiveContains("unexpected dylibs") {
                collectingUnexpectedDylibs = true
                currentSummaryLines.append(trimmed)
                continue
            }

            if collectingUnexpectedDylibs {
                if trimmed.isEmpty {
                    collectingUnexpectedDylibs = false
                    continue
                }

                if trimmed.hasPrefix("/") {
                    currentPaths.append(HomebrewDoctorIssuePath(path: trimmed, note: "brew doctor recommends removing unexpected dynamic libraries from this folder."))
                    continue
                }

                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    currentSummaryLines.append(trimmed)
                    continue
                }

                collectingUnexpectedDylibs = false
            }

            if !trimmed.isEmpty {
                currentSummaryLines.append(trimmed)
            }
        }

        finalizeCurrentIssue()
        return issues.filter { !$0.supportingLines.isEmpty || !$0.paths.isEmpty }
    }

    func loadInventory() async throws -> HomebrewInventory {
        let status = try await detectStatus()
        guard let brewPath = status.executablePath else {
            return HomebrewInventory(status: status, installedPackages: [], services: [], lastUpdated: .now)
        }

        async let installedInfoResult = runProcess(executable: brewPath, arguments: ["info", "--json=v2", "--installed"])
        async let outdatedInfoResult = runProcess(executable: brewPath, arguments: ["outdated", "--json=v2"])
        async let servicesResult = runProcess(executable: brewPath, arguments: ["services", "list", "--json"])

        let installedInfo = try await installedInfoResult
        let outdatedInfo = try await outdatedInfoResult
        let servicesOutput = try await servicesResult

        let installedPayload = decodeInventoryPayload(from: installedInfo)
        let outdatedPayload = decodeInventoryPayload(from: outdatedInfo)
        let outdatedKeys = Set(outdatedPayload.formulae.map { "formula:\($0.name)" } + outdatedPayload.casks.map { "cask:\($0.token)" })
        let services = parseServices(from: servicesOutput.output)

        let installedPackages =
            installedPayload.formulae.map { formula in
                makeInstalledPackage(from: formula, outdatedKeys: outdatedKeys)
            } +
            installedPayload.casks.map { cask in
                makeInstalledPackage(from: cask, outdatedKeys: outdatedKeys)
            }

        return HomebrewInventory(
            status: status,
            installedPackages: installedPackages.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            },
            services: services.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            lastUpdated: .now
        )
    }

    func searchPackages(query: String) async throws -> [HomebrewPackageSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return HomebrewPackageSearchResult.featured
        }

        guard let brewPath = try await detectStatus().executablePath else {
            return HomebrewPackageSearchResult.featured.filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed)
                    || $0.token.localizedCaseInsensitiveContains(trimmed)
                    || $0.description.localizedCaseInsensitiveContains(trimmed)
            }
        }

        async let formulaNameSearch = runProcess(executable: brewPath, arguments: ["search", "--formula", trimmed])
        async let formulaDescriptionSearch = runProcess(executable: brewPath, arguments: ["search", "--formula", "--desc", trimmed])
        async let caskNameSearch = runProcess(executable: brewPath, arguments: ["search", "--cask", trimmed])
        async let caskDescriptionSearch = runProcess(executable: brewPath, arguments: ["search", "--cask", "--desc", trimmed])

        let formulaNames = try parseNameMatches(from: await formulaNameSearch.output, kind: .formula)
        let formulaDescriptions = try parseDescriptionMatches(from: await formulaDescriptionSearch.output, kind: .formula)
        let caskNames = try parseNameMatches(from: await caskNameSearch.output, kind: .cask)
        let caskDescriptions = try parseDescriptionMatches(from: await caskDescriptionSearch.output, kind: .cask)

        var merged: [String: HomebrewPackageSearchResult] = [:]
        for result in formulaNames + formulaDescriptions + caskNames + caskDescriptions {
            let key = result.id
            if let existing = merged[key] {
                let description = existing.description == "Match by package name" ? result.description : existing.description
                merged[key] = HomebrewPackageSearchResult(
                    reference: result.reference,
                    displayName: result.displayName,
                    description: description,
                    source: result.source,
                    bundleIdentifier: result.bundleIdentifier
                )
            } else {
                merged[key] = result
            }
        }

        return merged.values
            .sorted { left, right in
                if left.kind != right.kind {
                    return left.kind.rawValue < right.kind.rawValue
                }

                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
            .prefix(24)
            .map { $0 }
    }

    func loadDetail(for reference: HomebrewPackageReference) async throws -> HomebrewPackageDetail {
        guard let brewPath = try await detectStatus().executablePath else {
            if let featured = HomebrewPackageSearchResult.featured.first(where: { $0.reference == reference }) {
                return .fallback(from: featured)
            }

            throw HomebrewError.notInstalled
        }

        var arguments = ["info", "--json=v2"]
        if reference.kind == .cask {
            arguments.append("--cask")
        }
        arguments.append(reference.token)

        let result = try await runProcess(executable: brewPath, arguments: arguments)
        guard result.terminationStatus == 0 else {
            throw HomebrewError.commandFailed(result.output)
        }

        let payload = try decodeInfoPayload(from: result.output)
        switch reference.kind {
        case .formula:
            guard let formula = payload.formulae.first else {
                throw HomebrewError.invalidResponse
            }
            return makeDetail(from: formula)
        case .cask:
            guard let cask = payload.casks.first else {
                throw HomebrewError.invalidResponse
            }
            return makeDetail(from: cask)
        }
    }

    func run(arguments: [String], actionTitle: String) async -> OptimizationLog {
        do {
            guard let brewPath = try await detectStatus().executablePath else {
                return OptimizationLog(
                    actionTitle: actionTitle,
                    output: HomebrewError.notInstalled.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                )
            }

            let result = try await runProcess(executable: brewPath, arguments: arguments)
            let output = result.output.isEmpty ? "Completed without terminal output." : result.output
            return OptimizationLog(
                actionTitle: actionTitle,
                output: output,
                succeeded: result.terminationStatus == 0,
                timestamp: .now
            )
        } catch {
            return OptimizationLog(
                actionTitle: actionTitle,
                output: error.localizedDescription,
                succeeded: false,
                timestamp: .now
            )
        }
    }

    func detectStatus() async throws -> HomebrewStatus {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        let executablePath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        guard let executablePath else {
            return HomebrewStatus(executablePath: nil, version: nil, prefix: nil)
        }

        let versionResult = try await runProcess(executable: executablePath, arguments: ["--version"])
        let prefixResult = try await runProcess(executable: executablePath, arguments: ["--prefix"])

        let version = versionResult.output
            .split(whereSeparator: \.isNewline)
            .first?
            .replacingOccurrences(of: "Homebrew ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = prefixResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        return HomebrewStatus(
            executablePath: executablePath,
            version: version,
            prefix: prefix.isEmpty ? nil : prefix
        )
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = Self.processEnvironment(for: executable)
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

    private static func processEnvironment(for executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let defaultPathEntries = [
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
        environment["PATH"] = Array(NSOrderedSet(array: defaultPathEntries)).compactMap { $0 as? String }.joined(separator: ":")
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        return environment
    }

    private func parseNameMatches(from output: String, kind: HomebrewPackageKind) throws -> [HomebrewPackageSearchResult] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
            .map { line in
                HomebrewPackageSearchResult(
                    reference: HomebrewPackageReference(token: line, kind: kind),
                    displayName: line,
                    description: "Match by package name",
                    source: kind == .formula ? "Formula search" : "Cask search",
                    bundleIdentifier: nil
                )
            }
    }

    private func parseDescriptionMatches(from output: String, kind: HomebrewPackageKind) throws -> [HomebrewPackageSearchResult] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
            .compactMap { line in
                guard let separator = line.firstIndex(of: ":") else {
                    return nil
                }

                let token = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let remainder = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

                if kind == .cask,
                   remainder.hasPrefix("("),
                   let closing = remainder.firstIndex(of: ")") {
                    let displayName = String(remainder[remainder.index(after: remainder.startIndex)..<closing])
                    let description = String(remainder[remainder.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
                    return HomebrewPackageSearchResult(
                        reference: HomebrewPackageReference(token: token, kind: kind),
                        displayName: displayName.isEmpty ? token : displayName,
                        description: description.isEmpty ? "Match by package description" : description,
                        source: "Description search",
                        bundleIdentifier: nil
                    )
                }

                return HomebrewPackageSearchResult(
                    reference: HomebrewPackageReference(token: token, kind: kind),
                    displayName: token,
                    description: remainder.isEmpty ? "Match by package description" : remainder,
                    source: "Description search",
                    bundleIdentifier: nil
                )
            }
    }

    private func parseServices(from output: String) -> [HomebrewServiceEntry] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if let data = trimmed.data(using: .utf8),
           let services = try? decoder.decode([BrewServiceListEntry].self, from: data) {
            return services.map {
                HomebrewServiceEntry(
                    name: $0.name,
                    status: $0.status,
                    user: $0.user,
                    file: $0.file,
                    pid: $0.pid,
                    exitCode: $0.exitCode
                )
            }
        }

        return []
    }

    private func decodeInfoPayload(from output: String) throws -> BrewInfoPayload {
        let sanitized = Self.sanitizeJSONObjectEnvelope(from: output)
        guard let data = sanitized.data(using: .utf8) else {
            throw HomebrewError.invalidResponse
        }

        return try decoder.decode(BrewInfoPayload.self, from: data)
    }

    private func decodeInventoryPayload(from result: ProcessResult) -> BrewInfoPayload {
        guard result.terminationStatus == 0 else {
            return .empty
        }

        return (try? decodeInfoPayload(from: result.output)) ?? .empty
    }

    private func makeInstalledPackage(from formula: BrewFormulaInfo, outdatedKeys: Set<String>) -> HomebrewInstalledPackage {
        let installedVersion = formula.installed.last?.version ?? formula.linkedKeg
        let key = "formula:\(formula.name)"

        return HomebrewInstalledPackage(
            reference: HomebrewPackageReference(token: formula.name, kind: .formula),
            displayName: formula.name,
            description: formula.desc ?? "No description available.",
            homepage: URL(string: formula.homepage ?? ""),
            installedVersion: installedVersion,
            latestVersion: formula.versions?.stable,
            tap: formula.tap,
            isOutdated: outdatedKeys.contains(key) || formula.outdated == true,
            isPinned: formula.pinned == true,
            autoUpdates: false,
            hasService: formula.service != nil,
            installedOnRequest: formula.installed.last?.installedOnRequest ?? true
        )
    }

    private func makeInstalledPackage(from cask: BrewCaskInfo, outdatedKeys: Set<String>) -> HomebrewInstalledPackage {
        let key = "cask:\(cask.token)"

        return HomebrewInstalledPackage(
            reference: HomebrewPackageReference(token: cask.token, kind: .cask),
            displayName: cask.name.first ?? cask.token,
            description: cask.desc ?? "No description available.",
            homepage: URL(string: cask.homepage ?? ""),
            installedVersion: cask.installed,
            latestVersion: cask.version,
            tap: cask.tap,
            isOutdated: outdatedKeys.contains(key) || cask.outdated == true,
            isPinned: false,
            autoUpdates: cask.autoUpdates == true,
            hasService: false,
            installedOnRequest: true
        )
    }

    private func makeDetail(from formula: BrewFormulaInfo) -> HomebrewPackageDetail {
        HomebrewPackageDetail(
            reference: HomebrewPackageReference(token: formula.name, kind: .formula),
            displayName: formula.name,
            description: formula.desc ?? "No description available.",
            homepage: URL(string: formula.homepage ?? ""),
            latestVersion: formula.versions?.stable,
            installedVersion: formula.installed.last?.version ?? formula.linkedKeg,
            tap: formula.tap,
            dependencies: formula.dependencies ?? [],
            conflicts: formula.conflictsWith ?? [],
            caveats: formula.caveats,
            hasService: formula.service != nil,
            serviceCommandHint: formula.service?.run,
            isInstalled: !formula.installed.isEmpty,
            isOutdated: formula.outdated == true,
            isPinned: formula.pinned == true,
            autoUpdates: false
        )
    }

    private func makeDetail(from cask: BrewCaskInfo) -> HomebrewPackageDetail {
        HomebrewPackageDetail(
            reference: HomebrewPackageReference(token: cask.token, kind: .cask),
            displayName: cask.name.first ?? cask.token,
            description: cask.desc ?? "No description available.",
            homepage: URL(string: cask.homepage ?? ""),
            latestVersion: cask.version,
            installedVersion: cask.installed,
            tap: cask.tap,
            dependencies: cask.dependsOn?.formula ?? [],
            conflicts: cask.conflictsWith?.cask ?? [],
            caveats: cask.caveats,
            hasService: false,
            serviceCommandHint: nil,
            isInstalled: cask.installed != nil,
            isOutdated: cask.outdated == true,
            isPinned: false,
            autoUpdates: cask.autoUpdates == true
        )
    }
}

private struct ProcessResult {
    let output: String
    let terminationStatus: Int32
}

private struct BrewInfoPayload: Decodable {
    let formulae: [BrewFormulaInfo]
    let casks: [BrewCaskInfo]

    static let empty = BrewInfoPayload(formulae: [], casks: [])
}

private struct BrewFormulaInfo: Decodable {
    struct Versions: Decodable {
        let stable: String?
    }

    struct InstalledVersion: Decodable {
        let version: String?
        let installedOnRequest: Bool?

        enum CodingKeys: String, CodingKey {
            case version
            case installedOnRequest = "installed_on_request"
        }
    }

    struct Service: Decodable {
        let run: String?
    }

    let name: String
    let tap: String?
    let desc: String?
    let homepage: String?
    let versions: Versions?
    let dependencies: [String]?
    let conflictsWith: [String]?
    let caveats: String?
    let installed: [InstalledVersion]
    let linkedKeg: String?
    let pinned: Bool?
    let outdated: Bool?
    let service: Service?

    enum CodingKeys: String, CodingKey {
        case name
        case tap
        case desc
        case homepage
        case versions
        case dependencies
        case caveats
        case installed
        case pinned
        case outdated
        case service
        case linkedKeg = "linked_keg"
        case conflictsWith = "conflicts_with"
    }
}

private struct BrewCaskInfo: Decodable {
    struct DependsOn: Decodable {
        let formula: [String]?
    }

    struct ConflictsWith: Decodable {
        let cask: [String]?
    }

    let token: String
    let tap: String?
    let name: [String]
    let desc: String?
    let homepage: String?
    let version: String?
    let installed: String?
    let outdated: Bool?
    let autoUpdates: Bool?
    let caveats: String?
    let dependsOn: DependsOn?
    let conflictsWith: ConflictsWith?

    enum CodingKeys: String, CodingKey {
        case token
        case tap
        case name
        case desc
        case homepage
        case version
        case installed
        case outdated
        case caveats
        case dependsOn = "depends_on"
        case conflictsWith = "conflicts_with"
        case autoUpdates = "auto_updates"
    }
}

private struct BrewServiceListEntry: Decodable {
    let name: String
    let status: String
    let user: String?
    let file: String?
    let pid: Int?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case user
        case file
        case pid
        case exitCode = "exit_code"
    }
}

private enum HomebrewError: LocalizedError {
    case notInstalled
    case invalidResponse
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Homebrew is not installed on this Mac yet."
        case .invalidResponse:
            "Homebrew returned an unreadable response."
        case let .commandFailed(output):
            output.isEmpty ? "The Homebrew command failed." : output
        }
    }
}
