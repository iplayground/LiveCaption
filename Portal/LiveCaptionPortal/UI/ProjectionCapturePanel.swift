import SwiftUI

enum ProjectionPreviewDisplayMode: String, CaseIterable, Identifiable {
    case inline
    case window

    var id: String { rawValue }

    static func mode(for rawValue: String) -> ProjectionPreviewDisplayMode {
        ProjectionPreviewDisplayMode(rawValue: rawValue) ?? .inline
    }
}

enum ProjectionCapturePreviewArrangement: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .vertical:
            L10n.text("caption.projectionArrangement.vertical")
        case .horizontal:
            L10n.text("caption.projectionArrangement.horizontal")
        }
    }

    static func arrangement(for rawValue: String) -> ProjectionCapturePreviewArrangement {
        ProjectionCapturePreviewArrangement(rawValue: rawValue) ?? .vertical
    }
}

enum ProjectionCaptionSource: String, CaseIterable, Identifiable {
    case speech
    case openAI

    var id: String { rawValue }

    var captionMode: CaptionQualityMode {
        switch self {
        case .speech:
            .fast
        case .openAI:
            .accurate
        }
    }

    var localizedName: String {
        switch self {
        case .speech:
            L10n.text("caption.projectionSource.speech")
        case .openAI:
            L10n.text("caption.projectionSource.openAI")
        }
    }

    static func source(for rawValue: String) -> ProjectionCaptionSource {
        ProjectionCaptionSource(rawValue: rawValue) ?? .speech
    }
}

enum ProjectionCaptureLanguageSelection {
    static func selectedIDs(
        from rawValue: String,
        outputLanguages: [SpeechOutputLanguage],
        fallbackID: String
    ) -> [String] {
        let availableIDs = Set(outputLanguages.map(\.id))
        var selectedIDs: [String] = []

        rawValue
            .split(separator: ",")
            .map(String.init)
            .filter { availableIDs.contains($0) }
            .forEach { languageID in
                if !selectedIDs.contains(languageID), selectedIDs.count < 2 {
                    selectedIDs.append(languageID)
                }
            }

        if !selectedIDs.isEmpty {
            return selectedIDs
        }

        if availableIDs.contains(fallbackID) {
            return [fallbackID]
        }

        return outputLanguages.first.map { [$0.id] } ?? []
    }

    static func rawValue(from selectedIDs: [String]) -> String {
        selectedIDs.prefix(2).joined(separator: ",")
    }
}

struct ProjectionCaptureSection: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0

    private var selectedProjectionLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        return outputLanguages.first?.id ?? inputLanguage.matchingOutputLanguageID
    }

    var body: some View {
        GeometryReader { geometry in
            let maximumWidth = WindowLayout.projectionCaptureMaximumWidth(for: geometry.size.width)
            let visibleWidth = clampedWidth(projectionCaptureWidth, maximumWidth: maximumWidth)
            let visibleHeight = clampedHeight(projectionCaptureHeight)

            VStack(alignment: .leading, spacing: 0) {
                ProjectionCaptureView(
                    inputLanguage: inputLanguage,
                    languageID: selectedProjectionLanguageID,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState
                )
                .frame(width: visibleWidth, height: visibleHeight)
            }
            .padding(.horizontal, WindowLayout.projectionCaptureHorizontalPadding)
            .padding(.vertical, WindowLayout.projectionCaptureVerticalPadding)
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: clampedHeight(projectionCaptureHeight) + (WindowLayout.projectionCaptureVerticalPadding * 2))
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func clampedWidth(_ value: Double, maximumWidth: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumWidth), maximumWidth)
    }

    private func clampedHeight(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumHeight), WindowLayout.projectionCaptureMaximumHeight)
    }
}
