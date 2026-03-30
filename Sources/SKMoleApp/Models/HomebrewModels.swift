import Foundation

enum HomebrewPackageKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case formula
    case cask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }

    var symbol: String {
        switch self {
        case .formula: "shippingbox"
        case .cask: "app.dashed"
        }
    }

    func installCommand(for token: String) -> String {
        switch self {
        case .formula:
            "brew install \(token)"
        case .cask:
            "brew install --cask \(token)"
        }
    }

    func upgradeCommand(for token: String) -> String {
        switch self {
        case .formula:
            "brew upgrade \(token)"
        case .cask:
            "brew upgrade --cask \(token)"
        }
    }

    func reinstallCommand(for token: String) -> String {
        switch self {
        case .formula:
            "brew reinstall \(token)"
        case .cask:
            "brew reinstall --cask \(token)"
        }
    }

    func uninstallCommand(for token: String) -> String {
        switch self {
        case .formula:
            "brew uninstall \(token)"
        case .cask:
            "brew uninstall --cask \(token)"
        }
    }
}

struct HomebrewStatus: Hashable {
    static let installGuideURL = URL(string: "https://docs.brew.sh/Installation")!
    static let installCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    let executablePath: String?
    let version: String?
    let prefix: String?

    var isInstalled: Bool {
        executablePath != nil
    }

    var summary: String {
        guard isInstalled else {
            return "Homebrew not installed"
        }

        if let version {
            return "Homebrew \(version)"
        }

        return "Homebrew installed"
    }

    var detail: String {
        guard isInstalled else {
            return "Install Homebrew once and SK Mole can manage formulae, casks, services, and maintenance with a native UI."
        }

        if let prefix {
            return "Packages are managed under \(prefix)."
        }

        return "SK Mole can manage installed formulae, casks, and brew services on this Mac."
    }
}

struct HomebrewPackageReference: Hashable, Identifiable {
    let token: String
    let kind: HomebrewPackageKind

    var id: String {
        "\(kind.rawValue):\(token)"
    }
}

struct HomebrewInstalledPackage: Hashable, Identifiable {
    let reference: HomebrewPackageReference
    let displayName: String
    let description: String
    let homepage: URL?
    let installedVersion: String?
    let latestVersion: String?
    let tap: String?
    let isOutdated: Bool
    let isPinned: Bool
    let autoUpdates: Bool
    let hasService: Bool
    let installedOnRequest: Bool

    var id: String { reference.id }
    var token: String { reference.token }
    var kind: HomebrewPackageKind { reference.kind }

    var installCommand: String { kind.installCommand(for: token) }
    var upgradeCommand: String { kind.upgradeCommand(for: token) }
    var reinstallCommand: String { kind.reinstallCommand(for: token) }
    var uninstallCommand: String { kind.uninstallCommand(for: token) }
    var cleanupCommand: String { "brew cleanup \(token)" }
}

struct HomebrewPackageSearchResult: Hashable, Identifiable {
    let reference: HomebrewPackageReference
    let displayName: String
    let description: String
    let source: String
    let bundleIdentifier: String?

    var id: String { reference.id }
    var token: String { reference.token }
    var kind: HomebrewPackageKind { reference.kind }

    var installCommand: String { kind.installCommand(for: token) }

    static let featured: [HomebrewPackageSearchResult] = [
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "wget", kind: .formula),
            displayName: "wget",
            description: "Internet file retriever",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "git", kind: .formula),
            displayName: "git",
            description: "Distributed revision control system",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "python", kind: .formula),
            displayName: "python",
            description: "Interpreted, interactive, object-oriented programming language",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "node", kind: .formula),
            displayName: "node",
            description: "Platform built on V8 for building network applications",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "ffmpeg", kind: .formula),
            displayName: "ffmpeg",
            description: "Play, record, convert, and stream audio and video",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "mas", kind: .formula),
            displayName: "mas",
            description: "Mac App Store command-line interface",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "gh", kind: .formula),
            displayName: "gh",
            description: "GitHub command-line tool",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "ripgrep", kind: .formula),
            displayName: "ripgrep",
            description: "Line-oriented search tool that recursively searches directories",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "fd", kind: .formula),
            displayName: "fd",
            description: "Simple, fast and user-friendly alternative to find",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "bat", kind: .formula),
            displayName: "bat",
            description: "Cat clone with syntax highlighting and Git integration",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "eza", kind: .formula),
            displayName: "eza",
            description: "Modern replacement for ls",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "fzf", kind: .formula),
            displayName: "fzf",
            description: "Command-line fuzzy finder",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "zoxide", kind: .formula),
            displayName: "zoxide",
            description: "Smarter cd command powered by your shell history",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "jq", kind: .formula),
            displayName: "jq",
            description: "Lightweight and flexible JSON processor",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "httpie", kind: .formula),
            displayName: "httpie",
            description: "User-friendly HTTP client",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "pnpm", kind: .formula),
            displayName: "pnpm",
            description: "Fast, disk space efficient package manager",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "uv", kind: .formula),
            displayName: "uv",
            description: "Extremely fast Python package and project manager",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "watchman", kind: .formula),
            displayName: "watchman",
            description: "Watch files and trigger actions on change",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "htop", kind: .formula),
            displayName: "htop",
            description: "Interactive process viewer",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "tree", kind: .formula),
            displayName: "tree",
            description: "Display directories as trees",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "ollama", kind: .formula),
            displayName: "ollama",
            description: "Run and manage local large language models",
            source: "Recommended formula",
            bundleIdentifier: nil
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "iterm2", kind: .cask),
            displayName: "iTerm2",
            description: "Terminal emulator as alternative to Apple's Terminal app",
            source: "Recommended cask",
            bundleIdentifier: "com.googlecode.iterm2"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "visual-studio-code", kind: .cask),
            displayName: "Visual Studio Code",
            description: "Open-source code editor",
            source: "Recommended cask",
            bundleIdentifier: "com.microsoft.VSCode"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "firefox", kind: .cask),
            displayName: "Firefox",
            description: "Web browser",
            source: "Recommended cask",
            bundleIdentifier: "org.mozilla.firefox"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "raycast", kind: .cask),
            displayName: "Raycast",
            description: "Control your tools with a launcher and command palette",
            source: "Recommended cask",
            bundleIdentifier: "com.raycast.macos"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "docker-desktop", kind: .cask),
            displayName: "Docker Desktop",
            description: "App to build and share containerized applications and microservices",
            source: "Recommended cask",
            bundleIdentifier: "com.docker.docker"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "vlc", kind: .cask),
            displayName: "VLC",
            description: "Multimedia player",
            source: "Recommended cask",
            bundleIdentifier: "org.videolan.vlc"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "rectangle", kind: .cask),
            displayName: "Rectangle",
            description: "Move and resize windows using keyboard shortcuts or snap areas",
            source: "Recommended cask",
            bundleIdentifier: "com.knollsoft.Rectangle"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "obsidian", kind: .cask),
            displayName: "Obsidian",
            description: "Markdown knowledge base and note-taking app",
            source: "Recommended cask",
            bundleIdentifier: "md.obsidian"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "postman", kind: .cask),
            displayName: "Postman",
            description: "API platform for design, testing, and collaboration",
            source: "Recommended cask",
            bundleIdentifier: "com.postmanlabs.mac"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "orbstack", kind: .cask),
            displayName: "OrbStack",
            description: "Fast container and Linux VM environment for macOS",
            source: "Recommended cask",
            bundleIdentifier: "dev.orbstack.OrbStack"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "arc", kind: .cask),
            displayName: "Arc",
            description: "Modern productivity-focused web browser",
            source: "Recommended cask",
            bundleIdentifier: "company.thebrowser.Browser"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "1password", kind: .cask),
            displayName: "1Password",
            description: "Password manager and secure vault",
            source: "Recommended cask",
            bundleIdentifier: "com.1password.1password"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "slack", kind: .cask),
            displayName: "Slack",
            description: "Team communication app",
            source: "Recommended cask",
            bundleIdentifier: "com.tinyspeck.slackmacgap"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "discord", kind: .cask),
            displayName: "Discord",
            description: "Voice, video, and text chat",
            source: "Recommended cask",
            bundleIdentifier: "com.hnc.Discord"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "utm", kind: .cask),
            displayName: "UTM",
            description: "Virtual machines for macOS on Apple silicon and Intel",
            source: "Recommended cask",
            bundleIdentifier: "com.utmapp.UTM"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "tailscale-app", kind: .cask),
            displayName: "Tailscale",
            description: "Zero-config mesh VPN with simple device login",
            source: "Recommended cask",
            bundleIdentifier: "io.tailscale.ipn.macos"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "stats", kind: .cask),
            displayName: "Stats",
            description: "System monitor in your menu bar",
            source: "Recommended cask",
            bundleIdentifier: "eu.exelban.Stats"
        ),
        HomebrewPackageSearchResult(
            reference: HomebrewPackageReference(token: "bruno", kind: .cask),
            displayName: "Bruno",
            description: "Open-source API client for local collections",
            source: "Recommended cask",
            bundleIdentifier: "com.usebruno.app"
        )
    ]
}

struct HomebrewPackageDetail: Hashable, Identifiable {
    let reference: HomebrewPackageReference
    let displayName: String
    let description: String
    let homepage: URL?
    let latestVersion: String?
    let installedVersion: String?
    let tap: String?
    let dependencies: [String]
    let conflicts: [String]
    let caveats: String?
    let hasService: Bool
    let serviceCommandHint: String?
    let isInstalled: Bool
    let isOutdated: Bool
    let isPinned: Bool
    let autoUpdates: Bool

    var id: String { reference.id }
    var token: String { reference.token }
    var kind: HomebrewPackageKind { reference.kind }

    var installCommand: String { kind.installCommand(for: token) }
    var upgradeCommand: String { kind.upgradeCommand(for: token) }
    var reinstallCommand: String { kind.reinstallCommand(for: token) }
    var uninstallCommand: String { kind.uninstallCommand(for: token) }
    var cleanupCommand: String { "brew cleanup \(token)" }
    var serviceStartCommand: String { "brew services start \(token)" }
    var serviceStopCommand: String { "brew services stop \(token)" }
    var serviceRestartCommand: String { "brew services restart \(token)" }

    static func fallback(from result: HomebrewPackageSearchResult) -> HomebrewPackageDetail {
        HomebrewPackageDetail(
            reference: result.reference,
            displayName: result.displayName,
            description: result.description,
            homepage: nil,
            latestVersion: nil,
            installedVersion: nil,
            tap: nil,
            dependencies: [],
            conflicts: [],
            caveats: nil,
            hasService: false,
            serviceCommandHint: nil,
            isInstalled: false,
            isOutdated: false,
            isPinned: false,
            autoUpdates: false
        )
    }
}

struct HomebrewServiceEntry: Hashable, Identifiable {
    let name: String
    let status: String
    let user: String?
    let file: String?
    let pid: Int?
    let exitCode: Int?

    var id: String { name }

    var isRunning: Bool {
        status.localizedCaseInsensitiveContains("started")
            || status.localizedCaseInsensitiveContains("running")
            || status.localizedCaseInsensitiveContains("scheduled")
    }
}

struct HomebrewInventory: Hashable {
    let status: HomebrewStatus
    let installedPackages: [HomebrewInstalledPackage]
    let services: [HomebrewServiceEntry]
    let lastUpdated: Date

    var installedFormulaCount: Int {
        installedPackages.filter { $0.kind == .formula }.count
    }

    var installedCaskCount: Int {
        installedPackages.filter { $0.kind == .cask }.count
    }

    var outdatedCount: Int {
        installedPackages.filter(\.isOutdated).count
    }
}

struct HomebrewDoctorIssuePath: Hashable, Identifiable {
    let path: String
    let note: String?

    var id: String { path }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var canDelete: Bool {
        Self.supportsDeletion(path)
    }

    private static func supportsDeletion(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        guard lowercased.hasSuffix(".dylib") else {
            return false
        }

        let home = NSHomeDirectory().lowercased()
        return lowercased.hasPrefix("/usr/local/lib/")
            || lowercased.hasPrefix("/opt/homebrew/lib/")
            || lowercased.hasPrefix("\(home)/lib/")
    }
}

struct HomebrewDoctorIssue: Hashable, Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let paths: [HomebrewDoctorIssuePath]
    let supportingLines: [String]

    var hasActionablePaths: Bool {
        paths.contains(where: \.canDelete)
    }
}

enum HomebrewPackageListFilter: String, CaseIterable, Identifiable {
    case all
    case formulae
    case casks
    case outdated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .formulae: "Formulae"
        case .casks: "Casks"
        case .outdated: "Outdated"
        }
    }
}

enum HomebrewMaintenanceAction: String, CaseIterable, Identifiable {
    case updateMetadata
    case upgradeAll
    case cleanup
    case autoremove
    case doctor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updateMetadata: "Update Metadata"
        case .upgradeAll: "Upgrade All"
        case .cleanup: "Cleanup Cellar"
        case .autoremove: "Autoremove"
        case .doctor: "Run Doctor"
        }
    }

    var subtitle: String {
        switch self {
        case .updateMetadata:
            "Refresh taps and package metadata before browsing or upgrading."
        case .upgradeAll:
            "Upgrade every outdated formula and cask installed through Homebrew."
        case .cleanup:
            "Remove old downloads, stale package versions, and cache residue."
        case .autoremove:
            "Remove unused dependencies that are no longer required."
        case .doctor:
            "Run Homebrew diagnostics and surface any environment issues."
        }
    }

    var icon: String {
        switch self {
        case .updateMetadata: "arrow.triangle.2.circlepath"
        case .upgradeAll: "square.and.arrow.down.on.square"
        case .cleanup: "trash"
        case .autoremove: "scissors"
        case .doctor: "stethoscope"
        }
    }

    var caution: String {
        switch self {
        case .updateMetadata:
            "Refreshing metadata is low risk, but taps may briefly lock while Homebrew updates itself."
        case .upgradeAll:
            "Major upgrades can restart services, replace package versions, or change linked binaries."
        case .cleanup:
            "Cleanup removes older package versions and cached downloads you may have wanted to keep around."
        case .autoremove:
            "Autoremove deletes dependencies Homebrew believes are unused, so review package relationships first if you manage tools manually."
        case .doctor:
            "Doctor is read-only and is useful before bigger maintenance or troubleshooting."
        }
    }

    var command: String {
        switch self {
        case .updateMetadata:
            "brew update"
        case .upgradeAll:
            "brew upgrade"
        case .cleanup:
            "brew cleanup --prune=all"
        case .autoremove:
            "brew autoremove"
        case .doctor:
            "brew doctor"
        }
    }

    var arguments: [String] {
        switch self {
        case .updateMetadata:
            ["update"]
        case .upgradeAll:
            ["upgrade"]
        case .cleanup:
            ["cleanup", "--prune=all"]
        case .autoremove:
            ["autoremove"]
        case .doctor:
            ["doctor"]
        }
    }
}
