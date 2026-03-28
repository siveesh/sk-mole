import Darwin
import Foundation
import IOKit
import IOKit.ps
import SKMoleShared

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
    let powerSummary: String?
}

final class MenuBarHelperSampler {
    private struct NetworkSample {
        let incoming: UInt64
        let outgoing: UInt64
        let date: Date
    }

    private let queue = DispatchQueue(label: "com.siveesh.skmole.menubar.metrics", qos: .utility)
    private let processRefreshInterval: TimeInterval = 5
    private let processSampler = NativeProcessSampler()

    private var timer: DispatchSourceTimer?
    private var previousPerCoreTicks: [[UInt32]] = []
    private var previousNetworkSample: NetworkSample?
    private var cachedTopProcess: (name: String, cpu: Double, memoryBytes: UInt64)?
    private var lastTopProcessSampleDate = Date.distantPast

    func start(handler: @escaping (MenuBarSnapshot) -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
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

    private func captureSnapshot() -> MenuBarSnapshot {
        let cpu = currentCPUUsage()
        let memory = currentMemoryUsage()
        let disk = currentDiskUsage()
        let network = currentNetworkRates()
        let topProcess = currentTopProcess()
        let power = Self.readPowerDetails()

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
            topProcessCPU: topProcess?.cpu,
            topProcessMemoryBytes: topProcess?.memoryBytes,
            powerSummary: power.summary
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

    private func currentTopProcess() -> (name: String, cpu: Double, memoryBytes: UInt64)? {
        let now = Date()
        guard now.timeIntervalSince(lastTopProcessSampleDate) >= processRefreshInterval else {
            return cachedTopProcess
        }

        lastTopProcessSampleDate = now

        if let process = processSampler.sampleTopProcesses(limit: 1).first {
            cachedTopProcess = (process.name, process.cpuPercent, process.memoryBytes)
        }

        return cachedTopProcess
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

        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double
        let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double
        let batteryLevel = (currentCapacity != nil && maxCapacity != nil && maxCapacity != 0)
            ? max(0, min(1, currentCapacity! / maxCapacity!))
            : nil

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
        guard total > 0 else {
            return 0
        }

        let availableRatio = Double(available) / Double(total)
        let compressedRatio = Double(compressed) / Double(total)
        let gigabyte = Double(1_024 * 1_024 * 1_024)

        if Double(swapUsed) >= 2 * gigabyte || availableRatio < 0.08 {
            return 2
        }

        if swapUsed > 0 || availableRatio < 0.18 || compressedRatio > 0.10 {
            return 1
        }

        return 0
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
}
