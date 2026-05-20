import Foundation

enum CaptionQualityMode: String, CaseIterable, Hashable, Sendable {
    case fast
    case accurate

    var providerID: String {
        switch self {
        case .fast:
            "azure-speech"
        case .accurate:
            "azure-openai"
        }
    }
}

struct CaptionModeResult: Equatable, Sendable {
    let providerID: String
    let text: String
    let translations: [String: String]

    init(providerID: String, text: String, translations: [String: String]) {
        self.providerID = providerID
        self.text = text
        self.translations = translations
    }
}

struct RecognizedCaptionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let translations: [String: String]
    let offsetTicks: UInt64
    let durationTicks: UInt64
    let sessionOffsetTicks: UInt64
    let inputLanguage: InputLanguage
    let processingGeneration: Int
    let captionModes: [CaptionQualityMode: CaptionModeResult]

    init(
        id: UUID = UUID(),
        text: String,
        translations: [String: String],
        offsetTicks: UInt64,
        durationTicks: UInt64,
        sessionOffsetTicks: UInt64? = nil,
        inputLanguage: InputLanguage,
        processingGeneration: Int,
        captionModes: [CaptionQualityMode: CaptionModeResult] = [:]
    ) {
        self.id = id
        self.text = text
        self.translations = translations
        self.offsetTicks = offsetTicks
        self.durationTicks = durationTicks
        self.sessionOffsetTicks = sessionOffsetTicks ?? offsetTicks
        self.inputLanguage = inputLanguage
        self.processingGeneration = processingGeneration

        var normalizedModes = captionModes
        if normalizedModes[.fast] == nil {
            normalizedModes[.fast] = CaptionModeResult(
                providerID: CaptionQualityMode.fast.providerID,
                text: text,
                translations: translations
            )
        }
        self.captionModes = normalizedModes
    }

    func addingCaptionMode(_ mode: CaptionQualityMode, result: CaptionModeResult) -> RecognizedCaptionEvent {
        var updatedModes = captionModes
        updatedModes[mode] = result
        return RecognizedCaptionEvent(
            id: id,
            text: text,
            translations: translations,
            offsetTicks: offsetTicks,
            durationTicks: durationTicks,
            sessionOffsetTicks: sessionOffsetTicks,
            inputLanguage: inputLanguage,
            processingGeneration: processingGeneration,
            captionModes: updatedModes
        )
    }
}
