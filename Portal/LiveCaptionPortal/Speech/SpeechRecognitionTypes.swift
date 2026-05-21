import Foundation
import SwiftUI

struct SpeechConnectionTestResult {
    let region: String
}

enum SpeechRecognitionState: Equatable {
    case idle
    case listening
    case recognizing
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            L10n.text("speechRecognition.state.idle")
        case .listening:
            L10n.text("speechRecognition.state.listening")
        case .recognizing:
            L10n.text("speechRecognition.state.recognizing")
        case .failed:
            L10n.text("speechRecognition.state.failed")
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "pause.circle"
        case .listening:
            "ear"
        case .recognizing:
            "waveform.badge.magnifyingglass"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .listening:
            .blue
        case .recognizing:
            .green
        case .failed:
            .red
        }
    }
}
