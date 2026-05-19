import Darwin
import Foundation

public struct ProcessRunnerResult: Sendable {
    public let output: String
    public let terminationStatus: Int32
    public let didTruncateOutput: Bool

    public init(output: String, terminationStatus: Int32, didTruncateOutput: Bool = false) {
        self.output = output
        self.terminationStatus = terminationStatus
        self.didTruncateOutput = didTruncateOutput
    }
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case timedOut(executable: String, seconds: TimeInterval)
    case cancelled(executable: String)
    case launchFailed(executable: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(executable, seconds):
            "\(executable) did not finish within \(Int(seconds.rounded())) seconds."
        case let .cancelled(executable):
            "\(executable) was cancelled."
        case let .launchFailed(executable, message):
            "Could not launch \(executable): \(message)"
        }
    }
}

public enum ProcessRunner {
    public static let defaultTimeout: TimeInterval = 30
    public static let defaultOutputLimit = 4 * 1_024 * 1_024

    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = defaultTimeout,
        maxOutputBytes: Int = defaultOutputLimit
    ) async throws -> ProcessRunnerResult {
        let state = ProcessRunnerState(
            executable: executable,
            timeout: max(timeout, 1),
            maxOutputBytes: max(maxOutputBytes, 1)
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)

                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    let pipe = Pipe()

                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    if let environment {
                        process.environment = environment
                    }
                    process.standardOutput = pipe
                    process.standardError = pipe

                    state.setProcess(process)

                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        state.append(chunk)
                    }

                    process.terminationHandler = { process in
                        pipe.fileHandleForReading.readabilityHandler = nil
                        state.append(pipe.fileHandleForReading.readDataToEndOfFile())
                        state.succeed(status: process.terminationStatus)
                    }

                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + state.timeout) {
                        state.timeoutProcess()
                    }

                    do {
                        try process.run()
                    } catch {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        state.fail(.launchFailed(executable: executable, message: error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class ProcessRunnerState: @unchecked Sendable {
    let executable: String
    let timeout: TimeInterval

    private let maxOutputBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessRunnerResult, Error>?
    private var process: Process?
    private var output = Data()
    private var completed = false
    private var didTruncateOutput = false

    init(executable: String, timeout: TimeInterval, maxOutputBytes: Int) {
        self.executable = executable
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    func setContinuation(_ continuation: CheckedContinuation<ProcessRunnerResult, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }

        let remaining = maxOutputBytes - output.count
        if remaining > 0 {
            output.append(data.prefix(remaining))
        }
        if data.count > remaining {
            didTruncateOutput = true
        }
    }

    func succeed(status: Int32) {
        guard let completion = complete() else { return }
        let text = String(decoding: completion.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        completion.continuation?.resume(
            returning: ProcessRunnerResult(
                output: completion.didTruncateOutput
                    ? text + "\n\n[Output truncated by SK Mole to protect memory usage.]"
                    : text,
                terminationStatus: status,
                didTruncateOutput: completion.didTruncateOutput
            )
        )
    }

    func timeoutProcess() {
        guard let completion = complete() else { return }
        Self.stopProcess(completion.process)
        completion.continuation?.resume(
            throwing: ProcessRunnerError.timedOut(
                executable: executable,
                seconds: timeout
            )
        )
    }

    func cancel() {
        guard let completion = complete() else { return }
        Self.stopProcess(completion.process)
        completion.continuation?.resume(throwing: ProcessRunnerError.cancelled(executable: executable))
    }

    func fail(_ error: ProcessRunnerError) {
        complete()?.continuation?.resume(throwing: error)
    }

    private func complete() -> Completion? {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return nil
        }
        completed = true
        let completion = Completion(
            continuation: continuation,
            process: process,
            output: output,
            didTruncateOutput: didTruncateOutput
        )
        continuation = nil
        process = nil
        lock.unlock()
        return completion
    }

    private static func stopProcess(_ process: Process?) {
        guard let process, process.isRunning else { return }

        let pid = process.processIdentifier
        process.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(1)) {
            guard process.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    private struct Completion {
        let continuation: CheckedContinuation<ProcessRunnerResult, Error>?
        let process: Process?
        let output: Data
        let didTruncateOutput: Bool
    }
}
