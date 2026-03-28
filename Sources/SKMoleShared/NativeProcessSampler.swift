import Darwin
import Foundation

public struct NativeProcessActivity: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let name: String
    public let command: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, command: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.command = command
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public final class NativeProcessSampler {
    private struct ProcessSample {
        let pid: Int32
        let name: String
        let command: String
        let cpuTimeNanos: UInt64
        let memoryBytes: UInt64
    }

    private var previousCPUTime: [Int32: UInt64] = [:]
    private var lastSampleDate = Date.distantPast

    public init() {}

    public func sampleTopProcesses(limit: Int) -> [NativeProcessActivity] {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleDate)
        let previousTimes = previousCPUTime
        var currentTimes: [Int32: UInt64] = [:]
        var activities: [NativeProcessActivity] = []

        for sample in enumerateProcesses() {
            currentTimes[sample.pid] = sample.cpuTimeNanos

            let cpuPercent: Double
            if elapsed > 0, let previous = previousTimes[sample.pid], sample.cpuTimeNanos >= previous {
                let cpuDeltaSeconds = Double(sample.cpuTimeNanos - previous) / 1_000_000_000
                cpuPercent = max(0, (cpuDeltaSeconds / elapsed) * 100)
            } else {
                cpuPercent = 0
            }

            activities.append(
                NativeProcessActivity(
                    pid: sample.pid,
                    name: sample.name,
                    command: sample.command,
                    cpuPercent: cpuPercent,
                    memoryBytes: sample.memoryBytes
                )
            )
        }

        previousCPUTime = currentTimes
        lastSampleDate = now

        return activities
            .sorted { left, right in
                if abs(left.cpuPercent - right.cpuPercent) > 0.05 {
                    return left.cpuPercent > right.cpuPercent
                }

                if left.memoryBytes != right.memoryBytes {
                    return left.memoryBytes > right.memoryBytes
                }

                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private func enumerateProcesses() -> [ProcessSample] {
        let count = max(proc_listallpids(nil, 0), 0)
        guard count > 0 else {
            return []
        }

        var pids = [pid_t](repeating: 0, count: Int(count))
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }

        guard filled > 0 else {
            return []
        }

        return pids
            .prefix(Int(filled))
            .compactMap { pid -> ProcessSample? in
                guard pid > 0, pid != getpid() else {
                    return nil
                }

                return sampleProcess(pid: Int32(pid))
            }
    }

    private func sampleProcess(pid: Int32) -> ProcessSample? {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = MemoryLayout<proc_taskinfo>.stride
        let taskResult = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: taskInfoSize) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(taskInfoSize))
            }
        }

        guard taskResult == taskInfoSize else {
            return nil
        }

        var shortInfo = proc_bsdshortinfo()
        let shortInfoSize = MemoryLayout<proc_bsdshortinfo>.stride
        let shortInfoResult = withUnsafeMutablePointer(to: &shortInfo) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: shortInfoSize) {
                proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, $0, Int32(shortInfoSize))
            }
        }

        guard shortInfoResult == shortInfoSize else {
            return nil
        }

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        let nameResult = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = nameResult > 0
            ? String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : ""

        let command = processPath(for: pid) ?? name
        let cpuTimeNanos = taskInfo.pti_total_user + taskInfo.pti_total_system

        return ProcessSample(
            pid: pid,
            name: name.isEmpty ? URL(fileURLWithPath: command).lastPathComponent : name,
            command: command,
            cpuTimeNanos: cpuTimeNanos,
            memoryBytes: UInt64(taskInfo.pti_resident_size)
        )
    }

    private func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))

        guard result > 0 else {
            return nil
        }

        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
