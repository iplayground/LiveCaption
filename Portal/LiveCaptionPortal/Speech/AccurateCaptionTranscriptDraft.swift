import Foundation

struct AccurateCaptionTranscriptDraft: Equatable, Sendable {
    let providerID: String
    let text: String

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
