import Darwin
import Foundation
import SKMoleShared

actor ProcessInspectorService {
    private let sampler = NativeProcessSampler()
    private let guardService: SystemGuard

    init(guardService: SystemGuard) {
        self.guardService = guardService
    }

    func snapshot() async -> [NativeProcessActivity] {
        sampler.sampleProcesses()
    }

    func terminate(_ process: NativeProcessActivity) async throws -> ProcessTerminationResult {
        guard await guardService.canTerminate(process: process) else {
            throw NSError(
                domain: "SKMole.Processes",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SK Mole only terminates your own non-system processes."]
            )
        }

        guard kill(process.pid, SIGTERM) == 0 else {
            let description = String(cString: strerror(errno))
            throw NSError(
                domain: "SKMole.Processes",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }

        SKMoleLog.processes.info("Sent SIGTERM to PID \(process.pid, privacy: .public) (\(process.name, privacy: .public))")

        return ProcessTerminationResult(
            pid: process.pid,
            processName: process.name,
            detail: "Sent SIGTERM to \(process.name) (PID \(process.pid)).",
            succeeded: true
        )
    }
}
