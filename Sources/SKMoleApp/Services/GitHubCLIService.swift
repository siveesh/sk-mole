import Foundation

actor GitHubCLIService {
    private let fileManager = FileManager.default
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func loadInventory() async throws -> GitHubCLIInventory {
        let status = try await detectStatus()
        guard let executablePath = status.executablePath, let login = status.userLogin else {
            return GitHubCLIInventory(status: status, repositories: [], lastUpdated: .now)
        }

        let result = try await runProcess(
            executable: executablePath,
            arguments: [
                "repo", "list", login,
                "--limit", "100",
                "--json", "name,nameWithOwner,description,visibility,isPrivate,isFork,isArchived,url,updatedAt"
            ]
        )

        guard result.terminationStatus == 0 else {
            throw GitHubCLIError.commandFailed(result.output)
        }

        let repositories = try decodeRepositories(from: result.output)
            .sorted { left, right in
                switch (left.updatedAt, right.updatedAt) {
                case let (lhs?, rhs?):
                    return lhs > rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return left.nameWithOwner.localizedCaseInsensitiveCompare(right.nameWithOwner) == .orderedAscending
                }
            }

        return GitHubCLIInventory(status: status, repositories: repositories, lastUpdated: .now)
    }

    func detectStatus() async throws -> GitHubCLIStatus {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh"
        ]

        let executablePath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        guard let executablePath else {
            return GitHubCLIStatus(
                executablePath: nil,
                version: nil,
                authStatusOutput: nil,
                userLogin: nil,
                userName: nil,
                profileURL: nil,
                host: nil
            )
        }

        let versionResult = try await runProcess(executable: executablePath, arguments: ["--version"])
        let authStatusResult = try await runProcess(executable: executablePath, arguments: ["auth", "status"])
        let version = versionResult.output
            .split(whereSeparator: \.isNewline)
            .first?
            .replacingOccurrences(of: "gh version ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard authStatusResult.terminationStatus == 0 else {
            return GitHubCLIStatus(
                executablePath: executablePath,
                version: version,
                authStatusOutput: authStatusResult.output,
                userLogin: nil,
                userName: nil,
                profileURL: nil,
                host: "github.com"
            )
        }

        let userResult = try await runProcess(executable: executablePath, arguments: ["api", "user"])
        guard userResult.terminationStatus == 0 else {
            return GitHubCLIStatus(
                executablePath: executablePath,
                version: version,
                authStatusOutput: authStatusResult.output,
                userLogin: nil,
                userName: nil,
                profileURL: nil,
                host: "github.com"
            )
        }

        let user = try decodeUser(from: userResult.output)
        return GitHubCLIStatus(
            executablePath: executablePath,
            version: version,
            authStatusOutput: authStatusResult.output,
            userLogin: user.login,
            userName: user.name,
            profileURL: user.htmlURL,
            host: "github.com"
        )
    }

    func run(arguments: [String], actionTitle: String) async -> OptimizationLog {
        do {
            guard let executablePath = try await detectStatus().executablePath else {
                return OptimizationLog(
                    actionTitle: actionTitle,
                    output: GitHubCLIError.notInstalled.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                )
            }

            let result = try await runProcess(executable: executablePath, arguments: arguments)
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

    private func runProcess(executable: String, arguments: [String]) async throws -> GitHubCLIProcessResult {
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
                    continuation.resume(returning: GitHubCLIProcessResult(output: output, terminationStatus: process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
        environment["GH_PAGER"] = "cat"
        environment["NO_COLOR"] = "1"
        return environment
    }

    private func decodeUser(from output: String) throws -> GitHubCLIUserPayload {
        guard let data = output.data(using: .utf8) else {
            throw GitHubCLIError.invalidResponse
        }

        return try decoder.decode(GitHubCLIUserPayload.self, from: data)
    }

    private func decodeRepositories(from output: String) throws -> [GitHubRepositorySummary] {
        guard let data = output.data(using: .utf8) else {
            throw GitHubCLIError.invalidResponse
        }

        return try decoder.decode([GitHubRepositorySummary].self, from: data)
    }
}

private struct GitHubCLIProcessResult {
    let output: String
    let terminationStatus: Int32
}

private struct GitHubCLIUserPayload: Decodable {
    let login: String
    let name: String?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case htmlURL = "html_url"
    }
}

private enum GitHubCLIError: LocalizedError {
    case notInstalled
    case invalidResponse
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "GitHub CLI is not installed on this Mac yet."
        case .invalidResponse:
            "GitHub CLI returned an unreadable response."
        case let .commandFailed(output):
            output.isEmpty ? "The GitHub CLI command failed." : output
        }
    }
}
