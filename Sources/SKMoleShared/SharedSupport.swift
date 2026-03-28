import Foundation

public enum SharedSupportDirectories {
    public static let directoryName = "SK Mole"

    public static func baseDirectory() -> URL {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(directoryName)", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    public static func fileURL(named name: String) -> URL {
        baseDirectory().appendingPathComponent(name)
    }
}
