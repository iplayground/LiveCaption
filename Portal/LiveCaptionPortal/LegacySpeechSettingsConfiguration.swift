import Foundation

struct LegacySpeechSettingsConfiguration: Codable {
    var region: String
    var speechKey: String
    var isAccurateCaptionEnabled: Bool
    var azureOpenAIEndpointURLString: String
    var azureOpenAITranscriptionDeploymentName: String
    var azureOpenAITranslationDeploymentName: String
    var azureOpenAIAPIKey: String
    var phraseHintsByScope: [String: [SpeechPhraseHint]]
    var sentenceSilenceTimeoutMilliseconds: Int
    var selectedOutputLanguageIDs: [String]
    var portalVisibleOutputLanguageIDs: [String]?

    func applyAzureSpeechAuthorization(to settings: inout SpeechSettings) {
        settings.region = region
        settings.speechKey = speechKey
    }

    func applyAzureOpenAISettings(to settings: inout SpeechSettings) {
        settings.isAccurateCaptionEnabled = isAccurateCaptionEnabled
        settings.azureOpenAIEndpointURLString = azureOpenAIEndpointURLString
        settings.azureOpenAITranscriptionDeploymentName = azureOpenAITranscriptionDeploymentName
        settings.azureOpenAITranslationDeploymentName = azureOpenAITranslationDeploymentName
        settings.azureOpenAIAPIKey = azureOpenAIAPIKey
    }

    func applyCaptionOutputAndSegmentation(to settings: inout SpeechSettings) {
        let availableLanguageIDs = Set(availableSpeechOutputLanguages.map(\.id))
        let selectedLanguageIDs = Set(selectedOutputLanguageIDs)
            .intersection(availableLanguageIDs)
            .union(SpeechSettings.requiredOutputLanguageIDs)

        settings.sentenceSilenceTimeoutMilliseconds = sentenceSilenceTimeoutMilliseconds
        settings.selectedOutputLanguageIDs = selectedLanguageIDs
        settings.portalVisibleOutputLanguageIDs = Set(portalVisibleOutputLanguageIDs ?? selectedOutputLanguageIDs)
            .intersection(availableLanguageIDs)
            .intersection(selectedLanguageIDs)
            .union(SpeechSettings.requiredOutputLanguageIDs)
    }

    func applyPhraseHints(to settings: inout SpeechSettings) {
        var scopedHints = SpeechSettings.defaultPhraseHintsByScope

        phraseHintsByScope.forEach { rawScope, hints in
            guard let scope = SpeechPhraseHintScope(rawValue: rawScope) else {
                return
            }

            scopedHints[scope] = hints
        }

        settings.phraseHintsByScope = SpeechSettings.normalizedPhraseHintsByScope(scopedHints)
    }
}
