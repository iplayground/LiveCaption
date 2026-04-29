import Foundation

struct RecognizedCaptionEvent: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let translations: [String: String]
    let offsetTicks: UInt64
    let durationTicks: UInt64
}
