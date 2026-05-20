import Foundation

enum PortalEnvironmentSettingsConfigurationFileError: LocalizedError {
    case unsupportedVersion(Int)
    case noExportSelection
    case noImportSelection
    case unreadableFile(String)
    case invalidFile(String)
    case unwritableFile(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            L10n.text("portalEnvironment.transfer.error.unsupportedVersion", version)
        case .noExportSelection:
            L10n.text("portalEnvironment.transfer.error.noExportSelection")
        case .noImportSelection:
            L10n.text("portalEnvironment.transfer.error.noImportSelection")
        case .unreadableFile(let message):
            L10n.text("portalEnvironment.transfer.error.unreadableFile", message)
        case .invalidFile(let message):
            L10n.text("portalEnvironment.transfer.error.invalidFile", message)
        case .unwritableFile(let message):
            L10n.text("portalEnvironment.transfer.error.unwritableFile", message)
        }
    }
}

struct PortalEnvironmentExportSelection: Equatable {
    var includesAzureSpeechAuthorization = true
    var includesAzureOpenAISettings = true
    var includesCaptionOutputAndSegmentation = true
    var includesPhraseHints = true
    var includesRelayURL = true

    static let all = PortalEnvironmentExportSelection()

    var includesAnySection: Bool {
        includesAzureSpeechAuthorization
            || includesAzureOpenAISettings
            || includesCaptionOutputAndSegmentation
            || includesPhraseHints
            || includesRelayURL
    }

    var includesAnySpeechSection: Bool {
        includesAzureSpeechAuthorization
            || includesAzureOpenAISettings
            || includesCaptionOutputAndSegmentation
            || includesPhraseHints
    }
}

struct PortalEnvironmentSettings {
    static let configurationFileName = "LiveCaption-Portal-Environment.json"

    var speechSettings: SpeechSettings
    var relaySettings: RelaySettings
    var includedSections = PortalEnvironmentExportSelection.all

    func writeConfiguration(to fileURL: URL, selection: PortalEnvironmentExportSelection) throws {
        guard selection.includesAnySection else {
            throw PortalEnvironmentSettingsConfigurationFileError.noExportSelection
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                PortalEnvironmentSettingsConfigurationFile(settings: self, selection: selection)
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch let error as PortalEnvironmentSettingsConfigurationFileError {
            throw error
        } catch {
            throw PortalEnvironmentSettingsConfigurationFileError.unwritableFile(error.localizedDescription)
        }
    }

    static func importedConfiguration(
        from fileURL: URL,
        preservingLocalSettings currentSettings: PortalEnvironmentSettings,
        selection: PortalEnvironmentExportSelection
    ) throws -> PortalEnvironmentSettings {
        guard selection.includesAnySection else {
            throw PortalEnvironmentSettingsConfigurationFileError.noImportSelection
        }

        let configuration = try decodedConfiguration(from: fileURL)
        return try configuration.environmentSettings(
            preservingLocalSettings: currentSettings,
            selection: selection
        )
    }

    static func availableImportSections(from fileURL: URL) throws -> PortalEnvironmentExportSelection {
        try decodedConfiguration(from: fileURL).includedSections()
    }

    private static func decodedConfiguration(from fileURL: URL) throws -> PortalEnvironmentSettingsConfigurationFile {
        let data: Data

        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PortalEnvironmentSettingsConfigurationFileError.unreadableFile(error.localizedDescription)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PortalEnvironmentSettingsConfigurationFile.self, from: data)
        } catch let error as PortalEnvironmentSettingsConfigurationFileError {
            throw error
        } catch {
            throw PortalEnvironmentSettingsConfigurationFileError.invalidFile(error.localizedDescription)
        }
    }
}

private struct PortalEnvironmentSettingsConfigurationFile: Codable {
    private static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var azureSpeechAuthorization: AzureSpeechAuthorizationConfiguration?
    var azureOpenAI: AzureOpenAISettingsConfiguration?
    var captionOutputAndSegmentation: CaptionOutputAndSegmentationConfiguration?
    var phraseHints: PhraseHintsConfiguration?
    var speech: LegacySpeechSettingsConfiguration?
    var relay: RelaySettingsConfiguration?

    init(settings: PortalEnvironmentSettings, selection: PortalEnvironmentExportSelection) {
        version = Self.currentVersion
        exportedAt = Date()
        azureSpeechAuthorization = selection.includesAzureSpeechAuthorization
            ? AzureSpeechAuthorizationConfiguration(settings: settings.speechSettings)
            : nil
        azureOpenAI = selection.includesAzureOpenAISettings
            ? AzureOpenAISettingsConfiguration(settings: settings.speechSettings)
            : nil
        captionOutputAndSegmentation = selection.includesCaptionOutputAndSegmentation
            ? CaptionOutputAndSegmentationConfiguration(settings: settings.speechSettings)
            : nil
        phraseHints = selection.includesPhraseHints
            ? PhraseHintsConfiguration(settings: settings.speechSettings)
            : nil
        relay = selection.includesRelayURL ? RelaySettingsConfiguration(settings: settings.relaySettings) : nil
    }

    func environmentSettings(
        preservingLocalSettings currentSettings: PortalEnvironmentSettings,
        selection: PortalEnvironmentExportSelection
    ) throws -> PortalEnvironmentSettings {
        guard version == Self.currentVersion else {
            throw PortalEnvironmentSettingsConfigurationFileError.unsupportedVersion(version)
        }

        var speechSettings = currentSettings.speechSettings
        var relaySettings = currentSettings.relaySettings
        let availableSections = try includedSections()
        let appliedSections = PortalEnvironmentExportSelection(
            includesAzureSpeechAuthorization: availableSections.includesAzureSpeechAuthorization
                && selection.includesAzureSpeechAuthorization,
            includesAzureOpenAISettings: availableSections.includesAzureOpenAISettings
                && selection.includesAzureOpenAISettings,
            includesCaptionOutputAndSegmentation: availableSections.includesCaptionOutputAndSegmentation
                && selection.includesCaptionOutputAndSegmentation,
            includesPhraseHints: availableSections.includesPhraseHints
                && selection.includesPhraseHints,
            includesRelayURL: availableSections.includesRelayURL && selection.includesRelayURL
        )

        if appliedSections.includesAzureSpeechAuthorization {
            if let azureSpeechAuthorization {
                azureSpeechAuthorization.apply(to: &speechSettings)
            } else {
                speech?.applyAzureSpeechAuthorization(to: &speechSettings)
            }
        }
        if appliedSections.includesAzureOpenAISettings {
            if let azureOpenAI {
                azureOpenAI.apply(to: &speechSettings)
            } else {
                speech?.applyAzureOpenAISettings(to: &speechSettings)
            }
        }
        if appliedSections.includesCaptionOutputAndSegmentation {
            if let captionOutputAndSegmentation {
                captionOutputAndSegmentation.apply(to: &speechSettings)
            } else {
                speech?.applyCaptionOutputAndSegmentation(to: &speechSettings)
            }
        }
        if appliedSections.includesPhraseHints {
            if let phraseHints {
                phraseHints.apply(to: &speechSettings)
            } else {
                speech?.applyPhraseHints(to: &speechSettings)
            }
        }
        if appliedSections.includesRelayURL {
            relay?.apply(to: &relaySettings)
        }

        return PortalEnvironmentSettings(
            speechSettings: speechSettings,
            relaySettings: relaySettings,
            includedSections: appliedSections
        )
    }

    func includedSections() throws -> PortalEnvironmentExportSelection {
        guard version == Self.currentVersion else {
            throw PortalEnvironmentSettingsConfigurationFileError.unsupportedVersion(version)
        }

        return PortalEnvironmentExportSelection(
            includesAzureSpeechAuthorization: azureSpeechAuthorization != nil || speech != nil,
            includesAzureOpenAISettings: azureOpenAI != nil || speech != nil,
            includesCaptionOutputAndSegmentation: captionOutputAndSegmentation != nil || speech != nil,
            includesPhraseHints: phraseHints != nil || speech != nil,
            includesRelayURL: relay != nil
        )
    }
}

private struct RelaySettingsConfiguration: Codable {
    var relayURLString: String

    init(settings: RelaySettings) {
        relayURLString = settings.normalizedRelayURLString
    }

    func apply(to settings: inout RelaySettings) {
        settings.relayURLString = relayURLString
        settings.normalize()
    }
}

private struct AzureSpeechAuthorizationConfiguration: Codable {
    var region: String
    var speechKey: String

    init(settings: SpeechSettings) {
        region = settings.region
        speechKey = settings.speechKey
    }

    func apply(to settings: inout SpeechSettings) {
        settings.region = region
        settings.speechKey = speechKey
    }
}

private struct AzureOpenAISettingsConfiguration: Codable {
    var isAccurateCaptionEnabled: Bool
    var azureOpenAIEndpointURLString: String
    var azureOpenAITranscriptionDeploymentName: String
    var azureOpenAITranslationDeploymentName: String
    var azureOpenAIAPIKey: String

    init(settings: SpeechSettings) {
        isAccurateCaptionEnabled = settings.isAccurateCaptionEnabled
        azureOpenAIEndpointURLString = settings.azureOpenAIEndpointURLString
        azureOpenAITranscriptionDeploymentName = settings.azureOpenAITranscriptionDeploymentName
        azureOpenAITranslationDeploymentName = settings.azureOpenAITranslationDeploymentName
        azureOpenAIAPIKey = settings.azureOpenAIAPIKey
    }

    func apply(to settings: inout SpeechSettings) {
        settings.isAccurateCaptionEnabled = isAccurateCaptionEnabled
        settings.azureOpenAIEndpointURLString = azureOpenAIEndpointURLString
        settings.azureOpenAITranscriptionDeploymentName = azureOpenAITranscriptionDeploymentName
        settings.azureOpenAITranslationDeploymentName = azureOpenAITranslationDeploymentName
        settings.azureOpenAIAPIKey = azureOpenAIAPIKey
    }
}

private struct CaptionOutputAndSegmentationConfiguration: Codable {
    var sentenceSilenceTimeoutMilliseconds: Int
    var selectedOutputLanguageIDs: [String]
    var portalVisibleOutputLanguageIDs: [String]?

    init(settings: SpeechSettings) {
        sentenceSilenceTimeoutMilliseconds = settings.sentenceSilenceTimeoutMilliseconds
        selectedOutputLanguageIDs = Array(
            settings.selectedOutputLanguageIDs.union(SpeechSettings.requiredOutputLanguageIDs)
        ).sorted()
        portalVisibleOutputLanguageIDs = Array(
            settings.portalVisibleOutputLanguageIDs.union(SpeechSettings.requiredOutputLanguageIDs)
        ).sorted()
    }

    func apply(to settings: inout SpeechSettings) {
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
}

private struct PhraseHintsConfiguration: Codable {
    var phraseHintsByScope: [String: [String]]

    init(settings: SpeechSettings) {
        let normalizedPhraseHintsByScope = SpeechSettings.normalizedPhraseHintsByScope(settings.phraseHintsByScope)

        phraseHintsByScope = Dictionary(uniqueKeysWithValues: SpeechPhraseHintScope.allCases.map { scope in
            (scope.rawValue, normalizedPhraseHintsByScope[scope, default: []].map(\.text))
        })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            phraseHintsByScope = try container.decode([String: [String]].self, forKey: .phraseHintsByScope)
        } catch {
            let legacyHints = try container.decode([String: [SpeechPhraseHint]].self, forKey: .phraseHintsByScope)
            phraseHintsByScope = legacyHints.mapValues { hints in
                hints.map(\.text)
            }
        }
    }

    func apply(to settings: inout SpeechSettings) {
        settings.phraseHintsByScope = normalizedPhraseHintsByScope()
    }

    private func normalizedPhraseHintsByScope() -> [SpeechPhraseHintScope: [SpeechPhraseHint]] {
        var scopedHints = SpeechSettings.defaultPhraseHintsByScope

        phraseHintsByScope.forEach { rawScope, hints in
            guard let scope = SpeechPhraseHintScope(rawValue: rawScope) else {
                return
            }

            scopedHints[scope] = hints.map { SpeechPhraseHint(text: $0) }
        }

        return SpeechSettings.normalizedPhraseHintsByScope(scopedHints)
    }
}

private struct LegacySpeechSettingsConfiguration: Codable {
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
