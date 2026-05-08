import Foundation
import SKMoleShared

enum ProcessSortMode: String, CaseIterable, Hashable, Identifiable {
    case cpu
    case memory
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        }
    }
}

struct ProcessTerminationResult: Hashable {
    let pid: Int32
    let processName: String
    let detail: String
    let succeeded: Bool
}

extension NativeProcessActivity {
    var shortCommand: String {
        URL(fileURLWithPath: command).lastPathComponent.isEmpty ? command : URL(fileURLWithPath: command).lastPathComponent
    }
}
