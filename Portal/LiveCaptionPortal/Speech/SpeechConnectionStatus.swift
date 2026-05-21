import Foundation
import SwiftUI

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
        previewText: "오늘 행사에 오신 것을 환영합니다. 자막 시스템이 준비되었습니다.",
    ),
]
