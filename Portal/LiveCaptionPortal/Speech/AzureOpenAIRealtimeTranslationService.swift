import Foundation

struct AzureOpenAITranslationConfig: Equatable, Sendable {
    let endpointURLString: String
    let translationDeploymentName: String
    let apiKey: String
    let targetLanguages: [SpeechOutputLanguage]

    nonisolated var isConfigured: Bool {
        !normalizedEndpointURLString.isEmpty
            && !translationDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

struct AzureOpenAIRealtimeTranslationResult: Equatable, Sendable {
    let sourceText: String
    let translations: [String: String]
}

enum AzureOpenAIRealtimeTranslationError: LocalizedError {
    case incompleteConfiguration
    case invalidEndpoint
    case connectionFailed(summary: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            L10n.text("azureOpenAI.error.incompleteConfiguration")
        case .invalidEndpoint:
            L10n.text("azureOpenAI.error.invalidEndpoint")
        case .connectionFailed(let message, _):
            L10n.text("azureOpenAI.error.connectionFailed", message)
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .incompleteConfiguration:
            L10n.text("azureOpenAI.error.incompleteConfiguration")
        case .invalidEndpoint:
            L10n.text("azureOpenAI.error.invalidEndpoint")
        case .connectionFailed(_, let detail):
            detail
        }
    }
}

actor AzureOpenAIRealtimeTranslationService {
    static let apiVersion = "2025-04-01-preview"
    static let maximumRequestAttempts = 5
    static let maximumPreviousSourceTextCount = 5
    struct TranslationRequestContext {
        let transcriptDrafts: [AccurateCaptionTranscriptDraft]
        let previousSourceTexts: [String]
        let inputLanguage: InputLanguage
        let phraseHints: [String]
        let targetLanguages: [SpeechOutputLanguage]
        let configuration: AzureOpenAITranslationConfig
    }
    private var configuration: AzureOpenAITranslationConfig?
    private var queuedTranslationTask: Task<AzureOpenAIRealtimeTranslationResult?, Never>?
    var recentSourceTexts: [String] = []
    private var isStarted = false
    var onDiagnostic: (@Sendable (AzureOpenAIRealtimeTranslationDiagnostic) -> Void)?

}

extension AzureOpenAIRealtimeTranslationService {
    func setOnDiagnostic(_ handler: (@Sendable (AzureOpenAIRealtimeTranslationDiagnostic) -> Void)?) {
        onDiagnostic = handler
    }

    func start(configuration: AzureOpenAITranslationConfig) async throws {
        await stop()

        guard configuration.isConfigured else {
            throw AzureOpenAIRealtimeTranslationError.incompleteConfiguration
        }

        _ = try Self.requestURL(for: configuration)
        self.configuration = configuration
        recentSourceTexts.removeAll()
        isStarted = true
    }

    func stop() async {
        isStarted = false
        configuration = nil
        queuedTranslationTask?.cancel()
        queuedTranslationTask = nil
        recentSourceTexts.removeAll()
    }

    func normalizeAndTranslate(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguageIDs: Set<String>
    ) async -> AzureOpenAIRealtimeTranslationResult? {
        guard isStarted,
              let configuration
        else {
            return nil
        }

        let normalizedTranscriptDrafts = transcriptDrafts
            .map { AccurateCaptionTranscriptDraft(providerID: $0.providerID, text: $0.normalizedText) }
        guard normalizedTranscriptDrafts.contains(where: { !$0.normalizedText.isEmpty }) else {
            return nil
        }

        let targetLanguages = configuration.targetLanguages.filter { targetLanguageIDs.contains($0.id) }
        let previousTask = queuedTranslationTask
        let currentTask = Task<AzureOpenAIRealtimeTranslationResult?, Never> { [weak self] in
            _ = await previousTask?.value
            guard let self else {
                return nil
            }

            return await self.performNormalizeAndTranslate(
                requestContext: TranslationRequestContext(
                    transcriptDrafts: normalizedTranscriptDrafts,
                    previousSourceTexts: [],
                    inputLanguage: inputLanguage,
                    phraseHints: phraseHints,
                    targetLanguages: targetLanguages,
                    configuration: configuration
                )
            )
        }
        queuedTranslationTask = currentTask
        return await currentTask.value
    }

    private func performNormalizeAndTranslate(
        requestContext initialContext: TranslationRequestContext
    ) async -> AzureOpenAIRealtimeTranslationResult? {
        do {
            let requestContext = TranslationRequestContext(
                transcriptDrafts: initialContext.transcriptDrafts,
                previousSourceTexts: recentSourceTexts,
                inputLanguage: initialContext.inputLanguage,
                phraseHints: initialContext.phraseHints,
                targetLanguages: initialContext.targetLanguages,
                configuration: initialContext.configuration
            )
            let result = try await requestNormalizationAndTranslationsWithRetry(
                requestContext: requestContext
            )
            let sourceText = result.sourceText
            let translations = result.translations
            appendRecentSourceText(sourceText)

            let missingLanguageIDs = requestContext.targetLanguages
                .map(\.id)
                .filter { translations[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
            if !missingLanguageIDs.isEmpty {
                emitDiagnostic(
                    level: .warning,
                    detail: Self.translationMissingLanguagesDetail(
                        targetLanguages: requestContext.targetLanguages.map(\.id),
                        returnedLanguages: Array(translations.keys),
                        missingLanguages: missingLanguageIDs
                    )
                )
            }

            return AzureOpenAIRealtimeTranslationResult(sourceText: sourceText, translations: translations)
        } catch {
            emitDiagnostic(level: .error, detail: Self.errorDetail(error, phase: "translationRequest"))
            return nil
        }
    }
}
