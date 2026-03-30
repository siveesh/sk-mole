import Foundation

enum QuarantineSignatureStatus: Hashable {
    case valid
    case unsigned
    case invalid(String?)
    case unknown(String?)

    var title: String {
        switch self {
        case .valid:
            "Signed"
        case .unsigned:
            "Unsigned"
        case .invalid:
            "Signature Issue"
        case .unknown:
            "Unknown"
        }
    }

    var subtitle: String {
        switch self {
        case .valid:
            "The bundle has a valid signature, but macOS quarantine is still present."
        case .unsigned:
            "No valid code signature was found for this app bundle."
        case .invalid(let message):
            message ?? "The code signature exists, but macOS reported a validation problem."
        case .unknown(let message):
            message ?? "SK Mole could not determine the signature state for this app."
        }
    }

    var symbol: String {
        switch self {
        case .valid:
            "checkmark.shield"
        case .unsigned:
            "shield.slash"
        case .invalid:
            "exclamationmark.shield"
        case .unknown:
            "questionmark.shield"
        }
    }

    var sortOrder: Int {
        switch self {
        case .unsigned:
            0
        case .invalid:
            1
        case .unknown:
            2
        case .valid:
            3
        }
    }
}

struct QuarantinedApplication: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
    let sizeBytes: UInt64
    let quarantineValue: String
    let signatureStatus: QuarantineSignatureStatus
    let lastModified: Date?

    var id: String { url.path }

    var xattrCommand: String {
        #"/usr/bin/xattr -d com.apple.quarantine "\#(url.path.replacingOccurrences(of: "\"", with: "\\\""))""#
    }

    var locationSummary: String {
        url.deletingLastPathComponent().path
    }
}
