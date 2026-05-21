import Foundation

final class SpeechInterimUpdateGate: @unchecked Sendable {
    private let updateInterval: TimeInterval
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast
    private var lastText = ""

    init(updateInterval: TimeInterval) {
        self.updateInterval = updateInterval
    }

    func shouldPublish(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        guard text != lastText,
              now.timeIntervalSince(lastUpdate) >= updateInterval else {
            return false
        }

        lastText = text
        lastUpdate = now
        return true
    }
}

enum SpeechRecognitionError: LocalizedError {
    case audioConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .audioConfigurationFailed:
            L10n.text("speechRecognition.error.audioConfigurationFailed")
        }
    }
}
