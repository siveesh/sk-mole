import Foundation

actor StartupItemsService {
    private struct RootSpec {
        let kind: StartupItemKind
        let root: URL
    }

    private let fileManager = FileManager.default
    private let userID = getuid()
    private let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")

    func loadItems() async throws -> [StartupItem] {
        let loadedLabels = try await userLoadedLabels()
        let disabledLabels = try await userDisabledLabels()
        let specs = [
            RootSpec(kind: .userLaunchAgent, root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")),
            RootSpec(kind: .systemLaunchAgent, root: URL(fileURLWithPath: "/Library/LaunchAgents")),
            RootSpec(kind: .systemLaunchDaemon, root: URL(fileURLWithPath: "/Library/LaunchDaemons"))
        ]

        var results: [StartupItem] = []

        for spec in specs where fileManager.fileExists(atPath: spec.root.path) {
            let urls = (try? fileManager.contentsOfDirectory(
                at: spec.root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls where url.pathExtension == "plist" {
                if let item = try await parseItem(
                    at: url,
                    kind: spec.kind,
                    loadedLabels: loadedLabels,
                    disabledLabels: disabledLabels
                ) {
                    results.append(item)
                }
            }
        }

        return results.sorted { left, right in
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }

            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    func disable(_ item: StartupItem) async throws -> String {
        guard item.canToggle else {
            throw NSError(
                domain: "SKMole.StartupItems",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Only user launch agents can be disabled from SK Mole."]
            )
        }

        let domain = "gui/\(userID)"
        let disableResult = try await runLaunchctl(arguments: ["disable", "\(domain)/\(item.label)"])

        if item.isLoaded {
            _ = try? await runLaunchctl(arguments: ["bootout", domain, item.url.path])
        }

        return disableResult.output.isEmpty ? "Disabled \(item.displayName)." : disableResult.output
    }

    func enable(_ item: StartupItem) async throws -> String {
        guard item.canToggle else {
            throw NSError(
                domain: "SKMole.StartupItems",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Only user launch agents can be enabled from SK Mole."]
            )
        }

        let domain = "gui/\(userID)"
        let enableResult = try await runLaunchctl(arguments: ["enable", "\(domain)/\(item.label)"])
        _ = try? await runLaunchctl(arguments: ["bootstrap", domain, item.url.path])

        return enableResult.output.isEmpty ? "Enabled \(item.displayName)." : enableResult.output
    }

    private func parseItem(
        at url: URL,
        kind: StartupItemKind,
        loadedLabels: Set<String>,
        disabledLabels: Set<String>
    ) async throws -> StartupItem? {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dictionary = plist as? [String: Any] else {
            return nil
        }

        let label = (dictionary["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? url.deletingPathExtension().lastPathComponent
        guard !label.isEmpty else {
            return nil
        }

        let program = dictionary["Program"] as? String
            ?? (dictionary["ProgramArguments"] as? [String])?.first
        let runAtLoad = dictionary["RunAtLoad"] as? Bool ?? false
        let keepAlive = (dictionary["KeepAlive"] as? Bool) ?? ((dictionary["KeepAlive"] as? [String: Any]) != nil)
        let plistDisabled = dictionary["Disabled"] as? Bool ?? false
        let disabled = kind.isManageable ? (disabledLabels.contains(label) || plistDisabled) : plistDisabled
        let loaded = kind.isManageable ? loadedLabels.contains(label) : false
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])

        return StartupItem(
            label: label,
            displayName: Self.displayName(for: label),
            url: url,
            program: program,
            kind: kind,
            isLoaded: loaded,
            isDisabled: disabled,
            runsAtLoad: runAtLoad,
            keepAlive: keepAlive,
            lastModified: values?.contentModificationDate
        )
    }

    private func userLoadedLabels() async throws -> Set<String> {
        let result = try await runLaunchctl(arguments: ["list"])
        guard result.terminationStatus == 0 else {
            return []
        }

        let labels = result.output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> String? in
                let columns = line.split(whereSeparator: \.isWhitespace)
                return columns.last.map(String.init)
            }

        return Set(labels)
    }

    private func userDisabledLabels() async throws -> Set<String> {
        let result = try await runLaunchctl(arguments: ["print-disabled", "gui/\(userID)"])
        guard result.terminationStatus == 0 else {
            return []
        }

        let pattern = #""([^"]+)"\s*=>\s*true"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(result.output.startIndex..<result.output.endIndex, in: result.output)

        return Set(regex.matches(in: result.output, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: result.output) else {
                return nil
            }

            return String(result.output[tokenRange])
        })
    }

    private func runLaunchctl(arguments: [String]) async throws -> StartupProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = self.launchctlURL
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let combined = [output, error]
                        .map { String(decoding: $0, as: UTF8.self) }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    continuation.resume(
                        returning: StartupProcessResult(output: combined, terminationStatus: process.terminationStatus)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func displayName(for label: String) -> String {
        let token = label
            .split(separator: ".")
            .last
            .map(String.init)
            ?? label

        return token
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct StartupProcessResult {
    let output: String
    let terminationStatus: Int32
}
