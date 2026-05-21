import Foundation

struct AzureOpenAITranscriptionConfig: Equatable, Sendable {
    let endpointURLString: String
    let transcriptionDeploymentName: String
    let apiKey: String
    let inputLanguage: InputLanguage
    let speakerIdentity: SpeakerIdentity?
    let phraseHints: [String]

    nonisolated var isConfigured: Bool {
        !normalizedEndpointURLString.isEmpty
            && !transcriptionDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated var normalizedEndpointURLString: String {
        var value = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

struct AzureOpenAIRealtimeTranscriptionResult: Equatable, Sendable {
    let captionEventID: RecognizedCaptionEvent.ID
    let openAIText: String
    let speechText: String
    let offsetTicks: UInt64
    let durationTicks: UInt64
    let sessionOffsetTicks: UInt64
    let inputLanguage: InputLanguage
    let processingGeneration: Int

    var transcriptDrafts: [AccurateCaptionTranscriptDraft] {
        [
            AccurateCaptionTranscriptDraft(
                providerID: AccurateCaptionTranscriptDraft.azureOpenAIProviderID,
                text: openAIText
            ),
            AccurateCaptionTranscriptDraft(
                providerID: AccurateCaptionTranscriptDraft.azureSpeechProviderID,
                text: speechText
            ),
        ]
    }
}

struct AzureOpenAITranscriptionDiagnostic: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case info
        case warning
        case error
    }

    let level: Level
    let detail: String
}

actor AzureOpenAIRealtimeTranscriptionService {
    var onTranscription: (@Sendable (AzureOpenAIRealtimeTranscriptionResult) -> Void)?
    var onDiagnostic: (@Sendable (AzureOpenAITranscriptionDiagnostic) -> Void)?

    static let ticksPerMillisecond: UInt64 = 10_000
    static let sampleRate = 24_000
    static let bytesPerSample = MemoryLayout<Int16>.size
    static let audioPaddingMilliseconds: UInt64 = 250
    static let apiVersion = "2025-04-01-preview"
    struct MultipartFileField {
        let name: String
        let filename: String
        let contentType: String
        let data: Data
    }
    struct AudioSegment {
        let startMilliseconds: UInt64
        let durationMilliseconds: UInt64
        let paddedStartMilliseconds: UInt64
        let paddedEndMilliseconds: UInt64
    }
    private var configuration: AzureOpenAITranscriptionConfig?
    var audioBuffer = Data()
    var bufferedAudioMilliseconds: UInt64 = 0
    private var isStarted = false

}

extension AzureOpenAIRealtimeTranscriptionService {
    func setOnTranscription(_ handler: (@Sendable (AzureOpenAIRealtimeTranscriptionResult) -> Void)?) {
        onTranscription = handler
    }

    func setOnDiagnostic(_ handler: (@Sendable (AzureOpenAITranscriptionDiagnostic) -> Void)?) {
        onDiagnostic = handler
    }

    func start(configuration: AzureOpenAITranscriptionConfig) async throws {
        await stop()

        guard configuration.isConfigured else {
            throw AzureOpenAIRealtimeTranslationError.incompleteConfiguration
        }

        _ = try Self.requestURL(for: configuration)
        self.configuration = configuration
        audioBuffer.removeAll(keepingCapacity: true)
        bufferedAudioMilliseconds = 0
        isStarted = true
    }

    func stop() async {
        isStarted = false
        configuration = nil
        audioBuffer.removeAll(keepingCapacity: false)
        bufferedAudioMilliseconds = 0
    }

    func appendPCM16Audio(_ audio: Data) async {
        guard isStarted, !audio.isEmpty else {
            return
        }

        audioBuffer.append(audio)
        bufferedAudioMilliseconds += Self.audioMilliseconds(forPCM16ByteCount: audio.count)
    }

    func transcribeAudio(for event: RecognizedCaptionEvent) async {
        guard isStarted, let configuration else {
            return
        }

        let speechText = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segment = audioSegment(for: event)

        guard segment.paddedEndMilliseconds > segment.paddedStartMilliseconds else {
            emitSkippedAudioDiagnostic(reason: "missingAudio", segment: segment)
            return
        }

        let audio = audioSlice(
            startMilliseconds: segment.paddedStartMilliseconds,
            endMilliseconds: segment.paddedEndMilliseconds
        )
        guard !audio.isEmpty else {
            emitSkippedAudioDiagnostic(reason: "emptyAudioSlice", segment: segment)
            return
        }

        do {
            let text = try await transcribe(
                wavAudio: Self.wavData(fromPCM16Mono24k: audio),
                configuration: configuration
            )
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeOpenAIText = safeTranscriptionText(
                normalizedText,
                configuration: configuration,
                segment: segment
            )
            guard !safeOpenAIText.isEmpty else {
                publishTranscriptionResult(openAIText: safeOpenAIText, speechText: speechText, event: event)
                return
            }

            publishTranscriptionResult(openAIText: safeOpenAIText, speechText: speechText, event: event)
        } catch {
            emitDiagnostic(level: .error, detail: Self.errorDetail(error, phase: "transcriptionRequest"))
            publishTranscriptionResult(openAIText: "", speechText: speechText, event: event)
        }
    }
}
