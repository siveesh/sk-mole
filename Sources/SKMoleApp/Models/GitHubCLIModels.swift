import Foundation

struct GitHubCLIStatus: Hashable {
    static let homepageURL = URL(string: "https://cli.github.com")!
    static let authGuideURL = URL(string: "https://cli.github.com/manual/gh_auth_login")!
    static let statusGuideURL = URL(string: "https://cli.github.com/manual/gh_auth_status")!
    static let repositoriesGuideURL = URL(string: "https://cli.github.com/manual/gh_repo_list")!
    static let personalAccessTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!
    static let personalAccessTokenDocsURL = URL(string: "https://docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens")!
    static let installCommand = "brew install gh"
    static let authCommand = "gh auth login --web --git-protocol https"

    let executablePath: String?
    let version: String?
    let authStatusOutput: String?
    let userLogin: String?
    let userName: String?
    let profileURL: URL?
    let host: String?

    var isInstalled: Bool {
        executablePath != nil
    }

    var isAuthenticated: Bool {
        userLogin != nil
    }

    var summary: String {
        guard isInstalled else {
            return "GitHub CLI not installed"
        }

        guard let userLogin else {
            return "GitHub CLI installed"
        }

        return "Signed in as \(userLogin)"
    }

    var detail: String {
        guard isInstalled else {
            return "Install GitHub CLI to authenticate, inspect repositories, and handle release workflows from a guided Mac-native panel."
        }

        guard let userLogin else {
            return "Authenticate with GitHub CLI in your browser, then SK Mole can verify your session and list repositories owned by the signed-in account."
        }

        let displayName = userName?.isEmpty == false ? "\(userName!) (\(userLogin))" : userLogin
        return "Authenticated on \(host ?? "github.com") as \(displayName)."
    }
}

struct GitHubRepositorySummary: Hashable, Identifiable, Decodable {
    let name: String
    let nameWithOwner: String
    let description: String?
    let visibility: String
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let url: URL
    let updatedAt: Date?

    var id: String { nameWithOwner }

    var updatedSummary: String {
        guard let updatedAt else {
            return "Unknown update date"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: updatedAt, relativeTo: .now)
    }
}

struct GitHubCLIInventory: Hashable {
    let status: GitHubCLIStatus
    let repositories: [GitHubRepositorySummary]
    let lastUpdated: Date
}
