import Foundation

extension SpeechSettings {
var hasAuthorizationMaterial: Bool {
        !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAzureOpenAIRealtimeConfiguration: Bool {
        !azureOpenAIEndpointURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !azureOpenAITranscriptionDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !azureOpenAITranslationDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !azureOpenAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func azureOpenAIRealtimeConfiguration(
        outputLanguages: [SpeechOutputLanguage]
    ) -> AzureOpenAITranslationConfig {
        AzureOpenAITranslationConfig(
            endpointURLString: azureOpenAIEndpointURLString,
            translationDeploymentName: azureOpenAITranslationDeploymentName,
            apiKey: azureOpenAIAPIKey,
            targetLanguages: outputLanguages
        )
    }

    func azureOpenAIRealtimeTranscriptionConfiguration(
        inputLanguage: InputLanguage,
        speakerIdentity: SpeakerIdentity? = nil
    ) -> AzureOpenAITranscriptionConfig {
        AzureOpenAITranscriptionConfig(
            endpointURLString: azureOpenAIEndpointURLString,
            transcriptionDeploymentName: azureOpenAITranscriptionDeploymentName,
            apiKey: azureOpenAIAPIKey,
            inputLanguage: inputLanguage,
            speakerIdentity: speakerIdentity,
            phraseHints: phraseHints(for: inputLanguage)
        )
    }

    func testAzureOpenAIConnection() async throws {
        let outputLanguages = Array(selectedOutputLanguages.prefix(1))
        let configuration = azureOpenAIRealtimeConfiguration(outputLanguages: outputLanguages)
        let service = AzureOpenAIRealtimeTranslationService()

        try await service.start(configuration: configuration)
        await service.stop()
    }
}
