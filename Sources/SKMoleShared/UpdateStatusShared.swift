import Foundation

public struct AppUpdateStatusSnapshot: Codable, Hashable, Sendable {
    public let scannedAt: Date
    public let availableCount: Int
    public let automaticCount: Int
    public let manualCount: Int
    public let ignoredCount: Int
    public let deferredCount: Int

    public init(
        scannedAt: Date,
        availableCount: Int,
        automaticCount: Int,
        manualCount: Int,
        ignoredCount: Int,
        deferredCount: Int
    ) {
        self.scannedAt = scannedAt
        self.availableCount = availableCount
        self.automaticCount = automaticCount
        self.manualCount = manualCount
        self.ignoredCount = ignoredCount
        self.deferredCount = deferredCount
    }

    public var actionableCount: Int {
        max(0, availableCount - ignoredCount - deferredCount)
    }
}

public final class AppUpdateStatusStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let maximumStatusFileBytes = 512 * 1_024

    public init(fileURL: URL = SharedSupportDirectories.fileURL(named: "update-status.json")) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppUpdateStatusSnapshot? {
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumStatusFileBytes {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode(AppUpdateStatusSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppUpdateStatusSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
