import Foundation
import SwiftUI

enum SpeechSettingsValidationError: LocalizedError {
    case missingRegion
    case missingSpeechKey
    case serviceRejected(Int)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRegion:
            L10n.text("speechSettings.error.missingRegion")
        case .missingSpeechKey:
            L10n.text("speechSettings.error.missingSpeechKey")
        case .serviceRejected(let statusCode):
            L10n.text("speechSettings.error.serviceRejected", statusCode)
        case .connectionFailed(let message):
            L10n.text("speechSettings.error.connectionFailed", message)
        }
    }
}

enum SpeechPhraseHintScope: String, CaseIterable, Codable, Identifiable {
    case shared
    case mandarin = "zh-TW"
    case english = "en-US"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shared:
            L10n.text("speechSettings.phraseHints.scope.shared")
        case .mandarin:
            L10n.text("speechSettings.phraseHints.scope.mandarin")
        case .english:
            L10n.text("speechSettings.phraseHints.scope.english")
        }
    }
}

struct SpeechPhraseHint: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
