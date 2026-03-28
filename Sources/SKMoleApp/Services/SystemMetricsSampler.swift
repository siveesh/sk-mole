import Darwin
import Foundation
import IOKit
import IOKit.ps
import Metal
import SKMoleShared

final class SystemMetricsSampler {
    private struct NetworkSample {
        let incoming: UInt64
        let outgoing: UInt64
        let date: Date
    }

    private struct CPUUsageResult {
        let total: Double
        let perCore: [Double]

        static let zero = CPUUsageResult(total: 0, perCore: [])
    }

    private struct MemoryStats {
        let used: UInt64
        let total: UInt64
        let cached: UInt64
        let wired: UInt64
        let compressed: UInt64
        let swapUsed: UInt64
        let swapTotal: UInt64
        let pressure: MemoryPressureState
    }

    private let queue = DispatchQueue(label: "com.siveesh.skmole.metrics", qos: .utility)
    private let topProcessRefreshInterval: TimeInterval = 5
    private let processSampler = NativeProcessSampler()

    private var timer: DispatchSourceTimer?
    private var previousPerCoreTicks: [[UInt32]] = []
    private var previousNetworkSample: NetworkSample?
    private var cachedTopProcesses: [ProcessActivity] = []
    private var lastTopProcessSampleDate = Date.distantPast

    private let gpuName: String
    private let gpuCoreCount: Int?
    private let metalSupport: String

    init() {
        let device = MTLCopyAllDevices().first
        self.gpuName = device?.name ?? "Metal GPU"
        self.gpuCoreCount = Self.readGPUCoreCount()
        self.metalSupport = device == nil ? "Unavailable" : "Metal ready"
    }

    func start(handler: @escaping @Sendable (SystemMetricSnapshot) -> Void) {
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

    private func captureSnapshot() -> SystemMetricSnapshot {
        let cpu = currentCPUUsage()
        let memory = currentMemoryUsage()
        let disk = currentDiskUsage()
        let network = currentNetworkRates()
        let gpuActivity = Self.readGPUActivity()

        return SystemMetricSnapshot(
            cpuUsage: cpu.total,
            perCoreUsage: cpu.perCore,
            gpuActivity: gpuActivity,
            gpuName: gpuName,
            gpuCores: gpuCoreCount,
            metalSupport: metalSupport,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            memoryCached: memory.cached,
            memoryWired: memory.wired,
            memoryCompressed: memory.compressed,
            swapUsed: memory.swapUsed,
            swapTotal: memory.swapTotal,
            memoryPressure: memory.pressure,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownloadRate: network.down,
            networkUploadRate: network.up,
            powerSource: Self.readPowerSource(),
            thermalState: Self.readThermalState(),
            topProcesses: currentTopProcesses(),
            timestamp: .now
        )
    }

    private func currentCPUUsage() -> CPUUsageResult {
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
            return .zero
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
            return CPUUsageResult(total: 0, perCore: Array(repeating: 0, count: currentTicks.count))
        }

        let perCore = zip(currentTicks, previousPerCoreTicks).map { current, previous -> Double in
            let deltas = zip(current, previous).map { Int64($0) - Int64($1) }
            let total = deltas.reduce(0, +)

            guard total > 0 else {
                return 0
            }

            let idle = max(0, deltas[Int(CPU_STATE_IDLE)])
            return max(0, min(1, Double(total - idle) / Double(total)))
        }

        let total = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        return CPUUsageResult(total: total, perCore: perCore)
    }

    private func currentMemoryUsage() -> MemoryStats {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryStats(
                used: 0,
                total: total,
                cached: 0,
                wired: 0,
                compressed: 0,
                swapUsed: 0,
                swapTotal: 0,
                pressure: .nominal
            )
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

        let active = UInt64(stats.active_count) * pageBytes
        let wired = UInt64(stats.wire_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let cached = UInt64(stats.inactive_count + stats.speculative_count) * pageBytes
        let free = UInt64(stats.free_count) * pageBytes
        let available = cached + free
        let swap = Self.readSwapUsage()

        return MemoryStats(
            used: active + wired + compressed,
            total: total,
            cached: cached,
            wired: wired,
            compressed: compressed,
            swapUsed: swap.used,
            swapTotal: swap.total,
            pressure: Self.classifyMemoryPressure(
                available: available,
                total: total,
                swapUsed: swap.used,
                compressed: compressed
            )
        )
    }

    private func currentDiskUsage() -> (used: UInt64, total: UInt64) {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let preferredAvailable = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let available = preferredAvailable > 0 ? UInt64(preferredAvailable) : 0
        return (total > available ? total - available : 0, total)
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

    private func currentTopProcesses() -> [ProcessActivity] {
        let now = Date()
        guard now.timeIntervalSince(lastTopProcessSampleDate) >= topProcessRefreshInterval else {
            return cachedTopProcesses
        }

        lastTopProcessSampleDate = now

        cachedTopProcesses = processSampler.sampleTopProcesses(limit: 8).map {
            ProcessActivity(
                pid: $0.pid,
                name: $0.name,
                command: $0.command,
                cpuPercent: $0.cpuPercent,
                memoryBytes: $0.memoryBytes
            )
        }

        return cachedTopProcesses
    }

    private static func classifyMemoryPressure(
        available: UInt64,
        total: UInt64,
        swapUsed: UInt64,
        compressed: UInt64
    ) -> MemoryPressureState {
        guard total > 0 else {
            return .nominal
        }

        let availableRatio = Double(available) / Double(total)
        let compressedRatio = Double(compressed) / Double(total)
        let gigabyte = Double(1_024 * 1_024 * 1_024)

        if Double(swapUsed) >= 2 * gigabyte || availableRatio < 0.08 {
            return .high
        }

        if swapUsed > 0 || availableRatio < 0.18 || compressedRatio > 0.10 {
            return .elevated
        }

        return .nominal
    }

    private static func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }

        guard result == 0 else {
            return (0, 0)
        }

        return (usage.xsu_used, usage.xsu_total)
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

    private static func readPowerSource() -> PowerSourceSnapshot? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }

        let sourceType = (IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?) ?? "AC Power"
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return PowerSourceSnapshot(
                source: sourceType,
                batteryLevel: nil,
                isCharging: false,
                timeRemainingMinutes: nil,
                lowPowerMode: lowPowerMode
            )
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double
        let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double
        let batteryLevel = (currentCapacity != nil && maxCapacity != nil && maxCapacity != 0)
            ? currentCapacity! / maxCapacity!
            : nil

        let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int

        return PowerSourceSnapshot(
            source: sourceType,
            batteryLevel: batteryLevel,
            isCharging: description[kIOPSIsChargingKey as String] as? Bool ?? false,
            timeRemainingMinutes: timeToFull ?? timeToEmpty,
            lowPowerMode: lowPowerMode
        )
    }

    private static func readThermalState() -> ThermalStateSummary {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .fair
        }
    }

    private static func readGPUCoreCount() -> Int? {
        guard let entry = firstGPURegistryEntry() else {
            return nil
        }
        defer { IOObjectRelease(entry) }

        guard
            let dict = IORegistryEntryCreateCFProperty(entry, "GPUConfigurationVariable" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
            let coreCount = dict["num_cores"] as? NSNumber
        else {
            return nil
        }

        return coreCount.intValue
    }

    private static func readGPUActivity() -> Double? {
        guard let entry = firstGPURegistryEntry() else {
            return nil
        }
        defer { IOObjectRelease(entry) }

        guard
            let dict = IORegistryEntryCreateCFProperty(entry, "AGCInfo" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }

        let busyCount = (dict["fBusyCount"] as? NSNumber)?.doubleValue ?? 0
        let submissions = (dict["fSubmissionsSinceLastCheck"] as? NSNumber)?.doubleValue ?? 0
        let normalized = min(1, max(busyCount / 12.0, submissions / 10.0))
        return normalized
    }

    private static func firstGPURegistryEntry() -> io_registry_entry_t? {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator = io_iterator_t()
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        return entry == 0 ? nil : entry
    }
}
