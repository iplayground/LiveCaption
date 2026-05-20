import SwiftUI
import Foundation

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

struct SpeechSettings: Equatable {
    static let requiredOutputLanguageIDs: Set<String> = ["zh-Hant", "en"]
    static let defaultOutputLanguageIDs: Set<String> = ["zh-Hant", "en", "ja"]
    static let maximumPhraseHintsPerRecognition = 250
    static let defaultPhraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]] = [
        .shared: [
            SpeechPhraseHint(text: "iPlayground")
        ],
        .mandarin: [],
        .english: []
    ]
    static let minimumSentenceSilenceTimeoutMilliseconds = 100
    static let maximumSentenceSilenceTimeoutMilliseconds = 5_000
    static let defaultSentenceSilenceTimeoutMilliseconds = 800
    private static let userDefaults = UserDefaults.standard

    var region = ""
    var speechKey = ""
    var isAccurateCaptionEnabled = false
    var azureOpenAIEndpointURLString = ""
    var azureOpenAITranscriptionDeploymentName = "accurate-transcribe"
    var azureOpenAITranslationDeploymentName = "accurate-translate"
    var azureOpenAIAPIKey = ""
    var phraseHintsByScope = defaultPhraseHintsByScope
    var sentenceSilenceTimeoutMilliseconds = defaultSentenceSilenceTimeoutMilliseconds {
        didSet {
            sentenceSilenceTimeoutMilliseconds = Self.clampedSentenceSilenceTimeoutMilliseconds(
                sentenceSilenceTimeoutMilliseconds
            )
        }
    }
    var selectedOutputLanguageIDs = defaultOutputLanguageIDs {
        didSet {
            selectedOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
            portalVisibleOutputLanguageIDs.formIntersection(selectedOutputLanguageIDs)
            portalVisibleOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
        }
    }
    var portalVisibleOutputLanguageIDs = defaultOutputLanguageIDs {
        didSet {
            portalVisibleOutputLanguageIDs.formIntersection(selectedOutputLanguageIDs)
            portalVisibleOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
        }
    }

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
    ) -> AzureOpenAIRealtimeTranslationConfiguration {
        AzureOpenAIRealtimeTranslationConfiguration(
            endpointURLString: azureOpenAIEndpointURLString,
            translationDeploymentName: azureOpenAITranslationDeploymentName,
            apiKey: azureOpenAIAPIKey,
            targetLanguages: outputLanguages
        )
    }

    func azureOpenAIRealtimeTranscriptionConfiguration(
        inputLanguage: InputLanguage
    ) -> AzureOpenAIRealtimeTranscriptionConfiguration {
        AzureOpenAIRealtimeTranscriptionConfiguration(
            endpointURLString: azureOpenAIEndpointURLString,
            transcriptionDeploymentName: azureOpenAITranscriptionDeploymentName,
            apiKey: azureOpenAIAPIKey,
            inputLanguage: inputLanguage,
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

    var regionSummary: String {
        region.isEmpty ? L10n.text("common.notConfigured") : region
    }

    var outputLanguageSummary: String {
        L10n.text("speech.outputLanguageCount", selectedOutputLanguageIDs.count)
    }

    var selectedOutputLanguages: [SpeechOutputLanguage] {
        availableSpeechOutputLanguages.filter {
            selectedOutputLanguageIDs.contains($0.id)
        }
    }

    var portalVisibleOutputLanguages: [SpeechOutputLanguage] {
        availableSpeechOutputLanguages.filter {
            portalVisibleOutputLanguageIDs.contains($0.id)
        }
    }

    func phraseHints(for inputLanguage: InputLanguage) -> [String] {
        Self.normalizedPhraseHintTexts(
            from: phraseHintsByScope[.shared, default: []] + phraseHintsByScope[inputLanguage.phraseHintScope, default: []]
        )
    }

    func testConnection() async throws -> SpeechConnectionTestResult {
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpeechKey = speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedRegion.isEmpty else {
            throw SpeechSettingsValidationError.missingRegion
        }

        guard !normalizedSpeechKey.isEmpty else {
            throw SpeechSettingsValidationError.missingSpeechKey
        }

        let endpointURLString = "https://\(normalizedRegion).api.cognitive.microsoft.com/sts/v1.0/issueToken"

        guard let endpointURL = URL(string: endpointURLString) else {
            throw SpeechSettingsValidationError.connectionFailed(L10n.text("speechSettings.error.invalidRegionFormat"))
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(normalizedSpeechKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpeechSettingsValidationError.connectionFailed(L10n.text("speechSettings.error.missingHTTPResponse"))
            }

            guard (200..<300).contains(httpResponse.statusCode), !data.isEmpty else {
                throw SpeechSettingsValidationError.serviceRejected(httpResponse.statusCode)
            }
        } catch {
            if let validationError = error as? SpeechSettingsValidationError {
                throw validationError
            }

            throw SpeechSettingsValidationError.connectionFailed(error.localizedDescription)
        }

        return SpeechConnectionTestResult(region: normalizedRegion)
    }

    static func load() -> SpeechSettings {
        var settings = SpeechSettings()
        let credentials = SpeechCredentialStore.load()

        settings.region = userDefaults.string(forKey: UserDefaultsKey.region.rawValue) ?? ""
        settings.speechKey = credentials.speechKey
        settings.isAccurateCaptionEnabled = userDefaults.bool(forKey: UserDefaultsKey.accurateCaptionEnabled.rawValue)
        settings.azureOpenAIEndpointURLString = userDefaults.string(forKey: UserDefaultsKey.azureOpenAIEndpoint.rawValue) ?? ""
        let storedTranscriptionDeploymentName = userDefaults.string(
            forKey: UserDefaultsKey.azureOpenAITranscriptionDeployment.rawValue
        ) ?? "accurate-transcribe"
        settings.azureOpenAITranscriptionDeploymentName = storedTranscriptionDeploymentName == "realtime-whisper"
            ? "accurate-transcribe"
            : storedTranscriptionDeploymentName
        let storedTranslationDeploymentName = userDefaults.string(
            forKey: UserDefaultsKey.azureOpenAITranslationDeployment.rawValue
        ) ?? userDefaults.string(forKey: UserDefaultsKey.azureOpenAIDeployment.rawValue) ?? "accurate-translate"
        settings.azureOpenAITranslationDeploymentName = storedTranslationDeploymentName == "realtime-translate"
            ? "accurate-translate"
            : storedTranslationDeploymentName
        settings.azureOpenAIAPIKey = credentials.azureOpenAIAPIKey
        settings.phraseHintsByScope = loadPhraseHintsByScope()

        if let outputLanguageIDs = userDefaults.object(forKey: UserDefaultsKey.outputLanguageIDs.rawValue) as? [String] {
            settings.selectedOutputLanguageIDs = Set(outputLanguageIDs).union(requiredOutputLanguageIDs)
        }
        if let visibleLanguageIDs = userDefaults.object(forKey: UserDefaultsKey.portalVisibleOutputLanguageIDs.rawValue) as? [String] {
            settings.portalVisibleOutputLanguageIDs = Set(visibleLanguageIDs).union(requiredOutputLanguageIDs)
        } else {
            settings.portalVisibleOutputLanguageIDs = settings.selectedOutputLanguageIDs
        }

        if userDefaults.object(forKey: UserDefaultsKey.sentenceSilenceTimeoutMilliseconds.rawValue) != nil {
            settings.sentenceSilenceTimeoutMilliseconds = clampedSentenceSilenceTimeoutMilliseconds(
                userDefaults.integer(forKey: UserDefaultsKey.sentenceSilenceTimeoutMilliseconds.rawValue)
            )
        }

        return settings
    }

    mutating func save() {
        sentenceSilenceTimeoutMilliseconds = Self.clampedSentenceSilenceTimeoutMilliseconds(
            sentenceSilenceTimeoutMilliseconds
        )
        phraseHintsByScope = Self.normalizedPhraseHintsByScope(phraseHintsByScope)
        Self.userDefaults.set(region, forKey: UserDefaultsKey.region.rawValue)
        Self.userDefaults.set(isAccurateCaptionEnabled, forKey: UserDefaultsKey.accurateCaptionEnabled.rawValue)
        Self.userDefaults.set(azureOpenAIEndpointURLString, forKey: UserDefaultsKey.azureOpenAIEndpoint.rawValue)
        Self.userDefaults.set(
            azureOpenAITranscriptionDeploymentName,
            forKey: UserDefaultsKey.azureOpenAITranscriptionDeployment.rawValue
        )
        Self.userDefaults.set(
            azureOpenAITranslationDeploymentName,
            forKey: UserDefaultsKey.azureOpenAITranslationDeployment.rawValue
        )
        Self.userDefaults.set(
            Array(selectedOutputLanguageIDs.union(Self.requiredOutputLanguageIDs)).sorted(),
            forKey: UserDefaultsKey.outputLanguageIDs.rawValue
        )
        Self.userDefaults.set(
            Array(portalVisibleOutputLanguageIDs.union(Self.requiredOutputLanguageIDs)).sorted(),
            forKey: UserDefaultsKey.portalVisibleOutputLanguageIDs.rawValue
        )
        Self.userDefaults.set(
            sentenceSilenceTimeoutMilliseconds,
            forKey: UserDefaultsKey.sentenceSilenceTimeoutMilliseconds.rawValue
        )
        Self.savePhraseHintsByScope(phraseHintsByScope)
        SpeechCredentialStore.save(
            SpeechCredentials(
                speechKey: speechKey,
                azureOpenAIAPIKey: azureOpenAIAPIKey
            )
        )
    }

    static func normalizedPhraseHintsByScope(
        _ phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]
    ) -> [SpeechPhraseHintScope: [SpeechPhraseHint]] {
        var normalizedPhraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]] = [:]

        SpeechPhraseHintScope.allCases.forEach { scope in
            let hints = phraseHintsByScope[scope, default: []]
            normalizedPhraseHintsByScope[scope] = normalizedPhraseHints(from: hints)
        }

        return normalizedPhraseHintsByScope
    }

    static func phraseHintRecognitionCount(
        for scope: SpeechPhraseHintScope,
        in phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]
    ) -> Int {
        let normalizedPhraseHintsByScope = normalizedPhraseHintsByScope(phraseHintsByScope)
        let sharedCount = normalizedPhraseHintsByScope[.shared, default: []].count

        switch scope {
        case .shared:
            return sharedCount
        case .mandarin, .english:
            return sharedCount + normalizedPhraseHintsByScope[scope, default: []].count
        }
    }

    static func remainingPhraseHintCapacity(
        for scope: SpeechPhraseHintScope,
        in phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]
    ) -> Int {
        let normalizedPhraseHintsByScope = normalizedPhraseHintsByScope(phraseHintsByScope)
        let sharedCount = normalizedPhraseHintsByScope[.shared, default: []].count
        let mandarinCount = normalizedPhraseHintsByScope[.mandarin, default: []].count
        let englishCount = normalizedPhraseHintsByScope[.english, default: []].count

        switch scope {
        case .shared:
            return max(
                0,
                min(
                    maximumPhraseHintsPerRecognition - sharedCount - mandarinCount,
                    maximumPhraseHintsPerRecognition - sharedCount - englishCount
                )
            )
        case .mandarin:
            return max(0, maximumPhraseHintsPerRecognition - sharedCount - mandarinCount)
        case .english:
            return max(0, maximumPhraseHintsPerRecognition - sharedCount - englishCount)
        }
    }

    private static func normalizedPhraseHints(from hints: [SpeechPhraseHint]) -> [SpeechPhraseHint] {
        var seenPhrases: Set<String> = []

        return hints.compactMap { hint in
            let normalizedText = hint.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else {
                return nil
            }

            let key = normalizedText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenPhrases.insert(key).inserted else {
                return nil
            }

            return SpeechPhraseHint(id: hint.id, text: normalizedText)
        }
    }

    private static func normalizedPhraseHintTexts(from hints: [SpeechPhraseHint]) -> [String] {
        normalizedPhraseHints(from: hints).map(\.text)
    }

    private static func loadPhraseHintsByScope() -> [SpeechPhraseHintScope: [SpeechPhraseHint]] {
        guard let fileURL = phraseHintsFileURL,
              let data = try? Data(contentsOf: fileURL),
              let storageValue = try? JSONDecoder().decode([String: [SpeechPhraseHint]].self, from: data)
        else {
            return defaultPhraseHintsByScope
        }

        var phraseHintsByScope = defaultPhraseHintsByScope
        storageValue.forEach { rawScope, hints in
            guard let scope = SpeechPhraseHintScope(rawValue: rawScope) else {
                return
            }

            phraseHintsByScope[scope] = hints
        }

        return normalizedPhraseHintsByScope(phraseHintsByScope)
    }

    private static func savePhraseHintsByScope(_ phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]) {
        guard let fileURL = phraseHintsFileURL,
              let data = try? JSONEncoder().encode(storageValue(from: phraseHintsByScope))
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }

    private static func storageValue(
        from phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]
    ) -> [String: [SpeechPhraseHint]] {
        Dictionary(uniqueKeysWithValues: SpeechPhraseHintScope.allCases.map { scope in
            (scope.rawValue, phraseHintsByScope[scope, default: []])
        })
    }

    private static var phraseHintsFileURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent("LiveCaptionPortal", isDirectory: true)
            .appendingPathComponent("speech-phrase-hints.json", isDirectory: false)
    }

    private static func clampedSentenceSilenceTimeoutMilliseconds(_ value: Int) -> Int {
        min(
            max(value, minimumSentenceSilenceTimeoutMilliseconds),
            maximumSentenceSilenceTimeoutMilliseconds
        )
    }

    private enum UserDefaultsKey: String {
        case region = "speech.region"
        case accurateCaptionEnabled = "speech.accurateCaptionEnabled"
        case azureOpenAIEndpoint = "speech.azureOpenAI.endpoint"
        case azureOpenAIDeployment = "speech.azureOpenAI.deployment"
        case azureOpenAITranscriptionDeployment = "speech.azureOpenAI.transcriptionDeployment"
        case azureOpenAITranslationDeployment = "speech.azureOpenAI.translationDeployment"
        case outputLanguageIDs = "speech.outputLanguageIDs"
        case portalVisibleOutputLanguageIDs = "speech.portalVisibleOutputLanguageIDs"
        case sentenceSilenceTimeoutMilliseconds = "speech.sentenceSilenceTimeoutMilliseconds"
    }
}

enum SpeechAuthorizationStatus: String {
    case unauthorized
    case unverified
    case verifying
    case authorized
    case failed

    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "speech.authorizationStatus"

    static func load(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        guard settings.hasAuthorizationMaterial else {
            return .unauthorized
        }

        guard let rawValue = userDefaults.string(forKey: userDefaultsKey),
              let status = SpeechAuthorizationStatus(rawValue: rawValue),
              status != .unauthorized,
              status != .verifying else {
            return .unverified
        }

        return status
    }

    static func initial(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        settings.hasAuthorizationMaterial ? .unverified : .unauthorized
    }

    func save() {
        Self.userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    var title: String {
        switch self {
        case .unauthorized:
            L10n.text("speechAuthorization.unauthorized")
        case .unverified:
            L10n.text("speechAuthorization.unverified")
        case .verifying:
            L10n.text("speechAuthorization.verifying")
        case .authorized:
            L10n.text("speechAuthorization.authorized")
        case .failed:
            L10n.text("speechAuthorization.failed")
        }
    }

    var tint: Color {
        switch self {
        case .unauthorized:
            .secondary
        case .unverified:
            .orange
        case .verifying:
            .blue
        case .authorized:
            .green
        case .failed:
            .red
        }
    }
}

enum AzureOpenAIConnectionStatus: String {
    case disabled
    case unconfigured
    case unverified
    case testing
    case connected
    case failed

    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "speech.azureOpenAI.connectionStatus"

    static func load(for settings: SpeechSettings) -> AzureOpenAIConnectionStatus {
        guard settings.isAccurateCaptionEnabled else {
            return .disabled
        }

        guard settings.hasAzureOpenAIRealtimeConfiguration else {
            return .unconfigured
        }

        guard let rawValue = userDefaults.string(forKey: userDefaultsKey),
              let status = AzureOpenAIConnectionStatus(rawValue: rawValue),
              status != .disabled,
              status != .unconfigured,
              status != .testing else {
            return .unverified
        }

        return status
    }

    static func initial(for settings: SpeechSettings) -> AzureOpenAIConnectionStatus {
        guard settings.isAccurateCaptionEnabled else {
            return .disabled
        }

        return settings.hasAzureOpenAIRealtimeConfiguration ? .unverified : .unconfigured
    }

    func save() {
        Self.userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    var title: String {
        switch self {
        case .disabled:
            L10n.text("azureOpenAI.status.disabled")
        case .unconfigured:
            L10n.text("azureOpenAI.status.unconfigured")
        case .unverified:
            L10n.text("azureOpenAI.status.unverified")
        case .testing:
            L10n.text("azureOpenAI.status.testing")
        case .connected:
            L10n.text("azureOpenAI.status.connected")
        case .failed:
            L10n.text("azureOpenAI.status.failed")
        }
    }
}

let availableSpeechOutputLanguages = [
    SpeechOutputLanguage(
        code: "zh-Hant",
        name: "Chinese Traditional",
        nativeName: "繁體中文",
        previewText: "歡迎來到今天的活動，字幕系統準備就緒。"
    ),
    SpeechOutputLanguage(
        code: "en",
        name: "English",
        nativeName: "English",
        previewText: "Welcome to today's event. The caption system is ready."
    ),
    SpeechOutputLanguage(
        code: "ja",
        name: "Japanese",
        nativeName: "日本語",
        previewText: "本日のイベントへようこそ。字幕システムの準備ができました。"
    ),
    SpeechOutputLanguage(
        code: "ko",
        name: "Korean",
        nativeName: "한국어",
        previewText: "오늘 행사에 오신 것을 환영합니다. 자막 시스템이 준비되었습니다."
    )
]
