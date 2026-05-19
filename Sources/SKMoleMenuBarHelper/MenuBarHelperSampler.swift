import Darwin
import Foundation
import IOKit
import IOKit.ps
import SKMoleShared

struct MenuBarTopProcessSummary: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

struct MenuBarSystemConfiguration: Hashable {
    let modelName: String
    let chipName: String
    let memoryBytes: UInt64
    let osVersion: String
    let uptime: String
}

struct MenuBarSnapshot {
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let diskFreeBytes: UInt64
    let diskTotalBytes: UInt64
    let diskFreeRatio: Double
    let memoryPressureLevel: Int
    let thermalStateLevel: Int
    let downloadRate: UInt64
    let uploadRate: UInt64
    let batteryLevel: Double?
    let topProcessName: String?
    let topProcessCPU: Double?
    let topProcessMemoryBytes: UInt64?
    let topProcesses: [MenuBarTopProcessSummary]
    let powerSummary: String?
    let systemConfiguration: MenuBarSystemConfiguration
}

final class MenuBarHelperSampler: @unchecked Sendable {
    private struct NetworkSample {
        let incoming: UInt64
        let outgoing: UInt64
        let date: Date
    }

    private let queue = DispatchQueue(label: "com.siveesh.skmole.menubar.metrics", qos: .utility)
    private let visibleProcessRefreshInterval: TimeInterval = 5
    private let hiddenProcessRefreshInterval: TimeInterval = 15
    private let powerRefreshInterval: TimeInterval = 20
    private let processSampler = NativeProcessSampler()
    private let systemConfiguration = MenuBarHelperSampler.readSystemConfiguration()

    private var timer: DispatchSourceTimer?
    private var previousPerCoreTicks: [[UInt32]] = []
    private var previousNetworkSample: NetworkSample?
    private var cachedTopProcesses: [MenuBarTopProcessSummary] = []
    private var lastTopProcessSampleDate = Date.distantPast
    private var cachedPowerDetails: (summary: String?, batteryLevel: Double?) = (nil, nil)
    private var lastPowerSampleDate = Date.distantPast
    private var isPopoverVisible = false

    func start(handler: @escaping (MenuBarSnapshot) -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            handler(self.captureSnapshot())
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func setPopoverVisible(_ isVisible: Bool) {
        queue.async { [weak self] in
            guard let self, let timer = self.timer else { return }
            self.isPopoverVisible = isVisible
            timer.schedule(deadline: .now(), repeating: isVisible ? .seconds(1) : .seconds(3))
        }
    }

    private func captureSnapshot() -> MenuBarSnapshot {
        let cpu = currentCPUUsage()
        let memory = currentMemoryUsage()
        let disk = currentDiskUsage()
        let network = currentNetworkRates()
        let topProcesses = currentTopProcesses()
        let topProcess = topProcesses.first
        let power = currentPowerDetails()

        return MenuBarSnapshot(
            cpuUsage: cpu,
            memoryUsage: memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            diskFreeRatio: disk.total > 0 ? Double(disk.free) / Double(disk.total) : 0,
            memoryPressureLevel: Self.classifyMemoryPressure(
                available: memory.available,
                total: memory.total,
                swapUsed: memory.swapUsed,
                compressed: memory.compressed
            ),
            thermalStateLevel: Self.readThermalStateLevel(),
            downloadRate: network.down,
            uploadRate: network.up,
            batteryLevel: power.batteryLevel,
            topProcessName: topProcess?.name,
            topProcessCPU: topProcess?.cpuPercent,
            topProcessMemoryBytes: topProcess?.memoryBytes,
            topProcesses: topProcesses,
            powerSummary: power.summary,
            systemConfiguration: systemConfiguration
        )
    }

    private func currentCPUUsage() -> Double {
        var cpuCount = natural_t()
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount = mach_msg_type_number_t()

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return 0
        }

        defer {
            let size = vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let loadInfo = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        let currentTicks: [[UInt32]] = (0..<Int(cpuCount)).map { index in
            let base = index * Int(CPU_STATE_MAX)
            return [
                UInt32(loadInfo[base + Int(CPU_STATE_USER)]),
                UInt32(loadInfo[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(loadInfo[base + Int(CPU_STATE_IDLE)]),
                UInt32(loadInfo[base + Int(CPU_STATE_NICE)])
            ]
        }

        defer {
            previousPerCoreTicks = currentTicks
        }

        guard previousPerCoreTicks.count == currentTicks.count else {
            return 0
        }

        let total = zip(currentTicks, previousPerCoreTicks).reduce(0.0) { partial, pair in
            let deltas = zip(pair.0, pair.1).map { Int64($0) - Int64($1) }
            let ticks = deltas.reduce(0, +)
            guard ticks > 0 else { return partial }
            let idle = max(0, deltas[Int(CPU_STATE_IDLE)])
            return partial + max(0, min(1, Double(ticks - idle) / Double(ticks)))
        }

        return total / Double(max(currentTicks.count, 1))
    }

    private func currentMemoryUsage() -> (used: UInt64, total: UInt64, available: UInt64, compressed: UInt64, swapUsed: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return (0, total, 0, 0, 0)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)
        let active = UInt64(stats.active_count) * pageBytes
        let wired = UInt64(stats.wire_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let cached = UInt64(stats.inactive_count + stats.speculative_count) * pageBytes
        let free = UInt64(stats.free_count) * pageBytes
        let swap = Self.readSwapUsage()
        return (active + wired + compressed, total, cached + free, compressed, swap)
    }

    private func currentDiskUsage() -> (free: UInt64, total: UInt64) {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let preferredAvailable = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let free = preferredAvailable > 0 ? UInt64(preferredAvailable) : 0
        return (free, total)
    }

    private func currentNetworkRates() -> (down: UInt64, up: UInt64) {
        let current = Self.readNetworkTotals()
        let sample = NetworkSample(incoming: current.incoming, outgoing: current.outgoing, date: .now)
        defer { previousNetworkSample = sample }

        guard let previousNetworkSample else {
            return (0, 0)
        }

        let interval = max(sample.date.timeIntervalSince(previousNetworkSample.date), 1)
        let down = sample.incoming > previousNetworkSample.incoming ? sample.incoming - previousNetworkSample.incoming : 0
        let up = sample.outgoing > previousNetworkSample.outgoing ? sample.outgoing - previousNetworkSample.outgoing : 0

        return (
            UInt64(Double(down) / interval),
            UInt64(Double(up) / interval)
        )
    }

    private func currentTopProcesses() -> [MenuBarTopProcessSummary] {
        let now = Date()
        let interval = isPopoverVisible ? visibleProcessRefreshInterval : hiddenProcessRefreshInterval
        guard now.timeIntervalSince(lastTopProcessSampleDate) >= interval else {
            return cachedTopProcesses
        }

        lastTopProcessSampleDate = now

        cachedTopProcesses = processSampler.sampleTopProcesses(limit: 5).map {
            MenuBarTopProcessSummary(
                pid: $0.pid,
                name: $0.name,
                cpuPercent: $0.cpuPercent,
                memoryBytes: $0.memoryBytes
            )
        }

        return cachedTopProcesses
    }

    private func currentPowerDetails() -> (summary: String?, batteryLevel: Double?) {
        let now = Date()
        guard now.timeIntervalSince(lastPowerSampleDate) >= powerRefreshInterval else {
            return cachedPowerDetails
        }

        cachedPowerDetails = Self.readPowerDetails()
        lastPowerSampleDate = now
        return cachedPowerDetails
    }

    private static func readNetworkTotals() -> (incoming: UInt64, outgoing: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        var incoming: UInt64 = 0
        var outgoing: UInt64 = 0

        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return (0, 0)
        }

        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)

            if
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                (flags & IFF_UP) != 0,
                (flags & IFF_LOOPBACK) == 0,
                let data = interface.ifa_data
            {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                incoming += UInt64(networkData.ifi_ibytes)
                outgoing += UInt64(networkData.ifi_obytes)
            }

            cursor = interface.ifa_next
        }

        return (incoming, outgoing)
    }

    private static func readPowerDetails() -> (summary: String?, batteryLevel: Double?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (nil, nil)
        }

        let sourceType = (IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?) ?? "AC Power"
        guard
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return (sourceType, nil)
        }

        let batteryLevel: Double?
        if let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double,
           let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double,
           maxCapacity > 0 {
            batteryLevel = max(0, min(1, currentCapacity / maxCapacity))
        } else {
            batteryLevel = nil
        }

        if let batteryLevel {
            let percentage = Int((batteryLevel * 100).rounded())
            return ("\(sourceType) • \(percentage)%", batteryLevel)
        }

        return (sourceType, nil)
    }

    private static func classifyMemoryPressure(
        available: UInt64,
        total: UInt64,
        swapUsed: UInt64,
        compressed: UInt64
    ) -> Int {
        SharedMemoryPressureLevel.classify(
            available: available,
            total: total,
            swapUsed: swapUsed,
            compressed: compressed
        ).rawValue
    }

    private static func readSwapUsage() -> UInt64 {
        var size = MemoryLayout<xsw_usage>.size
        var usage = xsw_usage()
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]

        let result = sysctl(&mib, 2, &usage, &size, nil, 0)
        guard result == 0 else {
            return 0
        }

        return usage.xsu_used
    }

    private static func readThermalStateLevel() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        @unknown default:
            return 0
        }
    }

    private static func readSystemConfiguration() -> MenuBarSystemConfiguration {
        let processInfo = ProcessInfo.processInfo
        let os = processInfo.operatingSystemVersion
        let osVersion = os.patchVersion > 0
            ? "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "macOS \(os.majorVersion).\(os.minorVersion)"
        let modelIdentifier = sysctlString("hw.model") ?? "Mac"
        let modelName = marketingModelName(for: modelIdentifier)
        let chipName = normalizedChipName(sysctlString("machdep.cpu.brand_string"))

        return MenuBarSystemConfiguration(
            modelName: modelName,
            chipName: chipName,
            memoryBytes: processInfo.physicalMemory,
            osVersion: osVersion,
            uptime: uptimeString(processInfo.systemUptime)
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedChipName(_ rawValue: String?) -> String {
        guard let rawValue, !rawValue.isEmpty else {
            return "Apple Silicon"
        }

        return rawValue
            .replacingOccurrences(of: "Apple ", with: "")
            .replacingOccurrences(of: " processor", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func marketingModelName(for identifier: String) -> String {
        switch identifier {
        case "Mac13,1", "Mac13,2":
            return "Mac Studio 2022"
        case "Mac14,13", "Mac14,14":
            return "Mac Studio 2023"
        case "Mac15,13", "Mac15,14":
            return "Mac Studio 2025"
        case "Mac14,3", "Mac14,8":
            return "Mac mini 2023"
        case "Mac16,10", "Mac16,11":
            return "Mac mini 2024"
        default:
            return identifier
        }
    }

    private static func uptimeString(_ uptime: TimeInterval) -> String {
        let totalHours = max(0, Int(uptime / 3_600))
        let days = totalHours / 24
        let hours = totalHours % 24

        if days > 0 {
            return "up \(days)d \(hours)h"
        }

        if hours > 0 {
            return "up \(hours)h"
        }

        return "up <1h"
    }
}
