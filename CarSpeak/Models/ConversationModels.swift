import Foundation

enum PersonaMode: String, CaseIterable, Codable, Identifiable {
    case executive = "executive"
    case surgical = "surgical"
    case architect = "architect"
    case memo = "memo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .executive: return "Executive Chief of Staff"
        case .surgical: return "Surgical & Clinical Consult"
        case .architect: return "Systems Architect"
        case .memo: return "Roadmap & Action Capture"
        }
    }

    var shortLabel: String {
        switch self {
        case .executive: return "Executive"
        case .surgical: return "Surgical"
        case .architect: return "Architect"
        case .memo: return "Roadmap"
        }
    }

    var iconName: String {
        switch self {
        case .executive: return "Waveform.circle.fill"
        case .surgical: return "cross.case.fill"
        case .architect: return "cpu.fill"
        case .memo: return "checklist.checked"
        }
    }
}

struct TranscriptTurn: Codable, Identifiable, Equatable {
    var id: String { "\(role)-\(timestamp)" }
    let role: String
    let text: String
    let timestamp: String
}

struct ConversationThread: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var projectId: String?
    var projectName: String?
    var persona: String?
    var createdAt: String
    var updatedAt: String
    var summary: String
    var turns: [TranscriptTurn]
}

struct RoadmapNote: Codable, Identifiable, Equatable {
    let id: String
    let note: String
    let timestamp: String
}

struct AGProjectDossier: Codable, Identifiable, Equatable {
    let id: String
    let folderName: String
    let displayName: String
    let category: String
    let bundleId: String
    let lastModified: String
    let summary: String
    let techStack: [String]
    let recentFocus: String
    var roadmapNotes: [RoadmapNote]?
}

struct HandoffTelemetry: Equatable {
    var networkInterface: String = "5G Cellular"
    var towerHandoffCount: Int = 0
    var bufferedFramesCount: Int = 0
    var sessionResumptionActive: Bool = true
    var lastHandoffLatencyMs: Int = 0
    var connectionState: String = "Standby"
}
