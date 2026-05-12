import Foundation

enum InputLanguage: String, CaseIterable, Identifiable, Sendable {
    case mandarin = "zh-TW"
    case english = "en-US"

    var id: String { rawValue }

    var speechLocale: String {
        rawValue
    }

    var phraseHintScope: SpeechPhraseHintScope {
        switch self {
        case .mandarin:
            .mandarin
        case .english:
            .english
        }
    }

    var matchingOutputLanguageID: String {
        switch self {
        case .mandarin:
            "zh-Hant"
        case .english:
            "en"
        }
    }

    var name: String {
        switch self {
        case .mandarin:
            "Chinese Traditional"
        case .english:
            "English"
        }
    }

    var nativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }

    var transcriptNativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }

    var previewText: String {
        availableSpeechOutputLanguages.first {
            $0.id == matchingOutputLanguageID
        }?.previewText ?? ""
    }
}

struct SpeechOutputLanguage: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let nativeName: String
    let previewText: String

    nonisolated var id: String { code }
}
