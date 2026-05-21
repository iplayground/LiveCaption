import Foundation
import SwiftUI

enum RelaySettingsValidationError: LocalizedError {
    case missingRelayURL
    case invalidRelayURL
    case invalidRoomName
    case invalidTrackNumber

    var errorDescription: String? {
        switch self {
        case .missingRelayURL:
            L10n.text("relaySettings.error.missingRelayURL")
        case .invalidRelayURL:
            L10n.text("relaySettings.error.invalidRelayURL")
        case .invalidRoomName:
            L10n.text("relaySettings.error.invalidRoomName")
        case .invalidTrackNumber:
            L10n.text("relaySettings.error.invalidTrackNumber")
        }
    }
}

enum RelayConnectionTestError: LocalizedError {
    case missingSpeechKey
    case serviceRejected(Int)
    case invalidResponse
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSpeechKey:
            L10n.text("relaySettings.error.missingSpeechKey")
        case .serviceRejected(let statusCode):
            L10n.text("relaySettings.error.serviceRejected", statusCode)
        case .invalidResponse:
            L10n.text("relaySettings.error.invalidResponse")
        case .connectionFailed(let message):
            L10n.text("relaySettings.error.connectionFailed", message)
        }
    }
}

struct RelayConnectionTestResult {
    let relayURL: URL
    let trackNumber: Int
    let viewerAccessCode: String
    let viewerAccessExpiresAt: Date

    var logDetail: String {
        L10n.text(
            "log.relay.connectionTestSucceededDetail",
            relayURL.absoluteString,
            trackNumber,
            viewerAccessCode
        )
    }
}

struct RelayPublishResult {
    let relayURL: URL
    let publishedAt: Date
}

struct RelayCaptionPublishInput: Sendable {
    let sessionID: String
    let speechText: String
    let text: String
    let translations: [String: String]
    let offsetTicks: UInt64
    let durationTicks: UInt64
    let inputLanguageSpeechLocale: String
    let inputLanguageOutputID: String
    let outputLanguageIDs: [String]
    let captionMode: CaptionQualityMode
    let captionProvider: String

    init?(
        event: RecognizedCaptionEvent,
        mode: CaptionQualityMode,
        sessionID: String,
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage]
    ) {
        guard let result = event.captionModes[mode] else {
            return nil
        }

        self.init(
            event: event,
            sessionID: sessionID,
            inputLanguage: inputLanguage,
            outputLanguages: outputLanguages,
            text: result.text,
            translations: result.translations,
            captionMode: mode,
            captionProvider: result.providerID
        )
    }

    private init(
        event: RecognizedCaptionEvent,
        sessionID: String,
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage],
        text: String,
        translations: [String: String],
        captionMode: CaptionQualityMode,
        captionProvider: String
    ) {
        self.sessionID = sessionID
        speechText = event.text
        self.text = text
        self.translations = translations
        offsetTicks = event.offsetTicks
        durationTicks = event.durationTicks
        inputLanguageSpeechLocale = inputLanguage.speechLocale
        inputLanguageOutputID = inputLanguage.matchingOutputLanguageID
        outputLanguageIDs = outputLanguages.map(\.id)
        self.captionMode = captionMode
        self.captionProvider = captionProvider
    }
}

enum RelayConnectionStatus: String {
    case notConfigured
    case unverified
    case testing
    case connected
    case failed

    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "relay.connectionStatus"

    static func load(for settings: RelaySettings) -> RelayConnectionStatus {
        guard settings.isConfigured else {
            return .notConfigured
        }

        guard let rawValue = userDefaults.string(forKey: userDefaultsKey),
              let status = RelayConnectionStatus(rawValue: rawValue),
              status != .notConfigured,
              status != .testing else {
            return .unverified
        }

        return status
    }

    static func initial(for settings: RelaySettings) -> RelayConnectionStatus {
        settings.isConfigured ? .unverified : .notConfigured
    }

    func save() {
        Self.userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    var title: String {
        switch self {
        case .notConfigured:
            L10n.text("common.notConfigured")
        case .unverified:
            L10n.text("relayConnection.readyToTest")
        case .testing:
            L10n.text("relayConnection.testing")
        case .connected:
            L10n.text("relayConnection.success")
        case .failed:
            L10n.text("relayConnection.failure")
        }
    }

    var tint: Color {
        switch self {
        case .notConfigured:
            .secondary
        case .unverified:
            .orange
        case .testing:
            .blue
        case .connected:
            .green
        case .failed:
            .red
        }
    }
}
