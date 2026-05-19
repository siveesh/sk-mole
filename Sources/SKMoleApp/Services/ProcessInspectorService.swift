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

        guard let liveProcess = sampler.sampleProcesses().first(where: { $0.pid == process.pid }) else {
            return ProcessTerminationResult(
                pid: process.pid,
                processName: process.name,
                detail: "\(process.name) already exited before SK Mole sent a signal.",
                succeeded: false
            )
        }

        guard matchesSelectedProcess(liveProcess, selected: process),
              await guardService.canTerminate(process: liveProcess) else {
            throw NSError(
                domain: "SKMole.Processes",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "SK Mole stopped because that PID now belongs to a different or protected process."]
            )
        }

        guard kill(liveProcess.pid, SIGTERM) == 0 else {
            let description = String(cString: strerror(errno))
            throw NSError(
                domain: "SKMole.Processes",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }

        SKMoleLog.processes.info("Sent SIGTERM to PID \(liveProcess.pid, privacy: .public) (\(liveProcess.name, privacy: .public))")

        return ProcessTerminationResult(
            pid: liveProcess.pid,
            processName: liveProcess.name,
            detail: "Sent SIGTERM to \(liveProcess.name) (PID \(liveProcess.pid)).",
            succeeded: true
        )
    }

    private func matchesSelectedProcess(_ live: NativeProcessActivity, selected: NativeProcessActivity) -> Bool {
        live.ownerUserID == selected.ownerUserID
            && live.name == selected.name
            && URLPathSafety.standardized(URL(fileURLWithPath: live.command)).path == URLPathSafety.standardized(URL(fileURLWithPath: selected.command)).path
    }
}
