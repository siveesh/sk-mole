import Foundation

enum URLPathSafety {
    static func standardized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let childPath = standardized(url).path
        let rootPath = standardized(root).path

        if childPath == rootPath {
            return true
        }

        return childPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }
}
