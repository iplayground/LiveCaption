import SwiftUI
import Foundation

enum LogLevel: String, CaseIterable, Identifiable {
    case all = "全部"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .all:
            .secondary
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let level: LogLevel
    let title: String
    let detail: String
}

enum LogClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func currentTimeString() -> String {
        formatter.string(from: Date())
    }
}
