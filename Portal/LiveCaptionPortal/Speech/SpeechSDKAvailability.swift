import Foundation
import MicrosoftCognitiveServicesSpeech

enum SpeechSDKAvailability {
    static let speechConfigurationTypeName = String(describing: SPXSpeechConfiguration.self)
    static let translationConfigurationTypeName = String(describing: SPXSpeechTranslationConfiguration.self)

    static var version: String? {
        let bundle = Bundle(for: SPXSpeechConfiguration.self)
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var versionLabel: String {
        if let version {
            return "SDK \(version)"
        }

        return "SDK"
    }
}
