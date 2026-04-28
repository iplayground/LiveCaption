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
            "尚未設定 Region"
        case .missingSpeechKey:
            "尚未設定 Speech Key"
        case .serviceRejected(let statusCode):
            "Azure Speech 拒絕連線，HTTP \(statusCode)"
        case .connectionFailed(let message):
            "Azure Speech 連線失敗：\(message)"
        }
    }
}

struct SpeechSettings: Equatable {
    static let requiredOutputLanguageIDs: Set<String> = ["zh-Hant", "en"]
    static let defaultOutputLanguageIDs: Set<String> = ["zh-Hant", "en", "ja"]
    private static let userDefaults = UserDefaults.standard

    var region = ""
    var speechKey = ""
    var selectedOutputLanguageIDs = defaultOutputLanguageIDs {
        didSet {
            selectedOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
        }
    }

    var hasAuthorizationMaterial: Bool {
        !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var regionSummary: String {
        region.isEmpty ? "尚未設定" : region
    }

    var outputLanguageSummary: String {
        "\(selectedOutputLanguageIDs.count) 種"
    }

    var selectedOutputLanguages: [SpeechOutputLanguage] {
        availableSpeechOutputLanguages.filter {
            selectedOutputLanguageIDs.contains($0.id)
        }
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
            throw SpeechSettingsValidationError.connectionFailed("Region 格式無效")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(normalizedSpeechKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpeechSettingsValidationError.connectionFailed("未收到 HTTP 回應")
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

        settings.region = userDefaults.string(forKey: UserDefaultsKey.region.rawValue) ?? ""
        settings.speechKey = userDefaults.string(forKey: UserDefaultsKey.speechKey.rawValue) ?? ""

        if let outputLanguageIDs = userDefaults.object(forKey: UserDefaultsKey.outputLanguageIDs.rawValue) as? [String] {
            settings.selectedOutputLanguageIDs = Set(outputLanguageIDs).union(requiredOutputLanguageIDs)
        }

        return settings
    }

    mutating func save() {
        Self.userDefaults.set(region, forKey: UserDefaultsKey.region.rawValue)
        Self.userDefaults.set(
            Array(selectedOutputLanguageIDs.union(Self.requiredOutputLanguageIDs)).sorted(),
            forKey: UserDefaultsKey.outputLanguageIDs.rawValue
        )
        if speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.userDefaults.removeObject(forKey: UserDefaultsKey.speechKey.rawValue)
        } else {
            Self.userDefaults.set(speechKey, forKey: UserDefaultsKey.speechKey.rawValue)
        }
    }

    private enum UserDefaultsKey: String {
        case region = "speech.region"
        case speechKey = "speech.key"
        case outputLanguageIDs = "speech.outputLanguageIDs"
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
            "未授權"
        case .unverified:
            "未驗證"
        case .verifying:
            "驗證中"
        case .authorized:
            "已授權"
        case .failed:
            "授權失敗"
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
