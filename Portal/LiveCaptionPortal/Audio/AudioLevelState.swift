import SwiftUI
import Combine

@MainActor
final class AudioLevelState: ObservableObject {
    @Published var level: Float = 0
    @Published var peakLevel: Float = 0
    @Published var decibels: Float = AudioInputController.minimumDecibels

    func reset() {
        level = 0
        peakLevel = 0
        decibels = AudioInputController.minimumDecibels
    }
}
