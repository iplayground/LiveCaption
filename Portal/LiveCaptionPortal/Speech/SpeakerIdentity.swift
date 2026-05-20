import Foundation

enum SpeakerIdentity: String, CaseIterable, Identifiable, Sendable {
    case chinese
    case japanese
    case korean
    case indian
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese:
            L10n.text("speakerIdentity.chinese")
        case .japanese:
            L10n.text("speakerIdentity.japanese")
        case .korean:
            L10n.text("speakerIdentity.korean")
        case .indian:
            L10n.text("speakerIdentity.indian")
        case .other:
            L10n.text("speakerIdentity.other")
        }
    }

    nonisolated var transcriptionPromptDescription: String? {
        switch self {
        case .chinese:
            "a Chinese-background English speaker"
        case .japanese:
            "a Japanese-background English speaker"
        case .korean:
            "a Korean-background English speaker"
        case .indian:
            "an Indian-background English speaker"
        case .other:
            nil
        }
    }
}
