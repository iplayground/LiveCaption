import Foundation

struct AccurateCaptionTranscriptDraft: Equatable, Sendable {
    static let azureOpenAIProviderID = "azure-openai"
    static let azureSpeechProviderID = "azure-speech"

    let providerID: String
    let text: String

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
