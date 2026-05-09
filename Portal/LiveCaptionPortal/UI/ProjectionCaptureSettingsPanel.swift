import SwiftUI

struct ProjectionCaptureSettingsInspector: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumWidth: Double
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0
    @AppStorage("projectionCapture.fontID") private var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") private var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") private var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") private var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") private var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") private var projectionCapturePaddingHorizontal = 28.0

    private var selectedLanguageID: Binding<String> {
        Binding(
            get: { validatedLanguageID },
            set: { projectionCaptureLanguageID = $0 }
        )
    }

    private var width: Binding<Double> {
        Binding(
            get: { projectionCaptureWidth },
            set: { projectionCaptureWidth = clampedWidth($0) }
        )
    }

    private var height: Binding<Double> {
        Binding(
            get: { projectionCaptureHeight },
            set: { projectionCaptureHeight = clampedHeight($0) }
        )
    }

    private var selectedFontID: Binding<String> {
        Binding(
            get: { validatedFontID },
            set: { projectionCaptureFontID = $0 }
        )
    }

    private var fontSize: Binding<Double> {
        Binding(
            get: { projectionCaptureFontSize },
            set: { projectionCaptureFontSize = clampedFontSize($0) }
        )
    }

    private var lineSpacing: Binding<Double> {
        Binding(
            get: { projectionCaptureLineSpacing },
            set: { projectionCaptureLineSpacing = clampedLineSpacing($0) }
        )
    }

    private var paddingHorizontal: Binding<Double> {
        Binding(
            get: { projectionCapturePaddingHorizontal },
            set: { projectionCapturePaddingHorizontal = clampedPadding($0) }
        )
    }

    private var appendLineLimit: Binding<Double> {
        Binding(
            get: { projectionCaptureAppendLineLimit },
            set: { projectionCaptureAppendLineLimit = clampedAppendLineLimit($0) }
        )
    }

    private var validatedLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        return outputLanguages.first?.id ?? projectionCaptureLanguageID
    }

    private var validatedFontID: String {
        if ProjectionCaptionFontChoice.availableChoices.contains(where: { $0.id == projectionCaptureFontID }) {
            return projectionCaptureFontID
        }

        return ProjectionCaptionFontChoice.systemID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionLanguage")) {
                        Picker(L10n.text("caption.projectionLanguage"), selection: selectedLanguageID) {
                            ForEach(outputLanguages) { language in
                                Text(language.nativeName).tag(language.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionAppendMode")) {
                        Toggle(L10n.text("caption.projectionAppendMode"), isOn: $projectionCaptureAppendsText)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .frame(height: 26, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionFont")) {
                        Picker(L10n.text("caption.projectionFont"), selection: selectedFontID) {
                            ForEach(ProjectionCaptionFontChoice.availableChoices) { fontChoice in
                                Text(fontChoice.localizedName).tag(fontChoice.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 170, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionFontSize")) {
                        ProjectionDimensionField(
                            value: fontSize,
                            range: WindowLayout.projectionCaptureMinimumFontSize...WindowLayout.projectionCaptureMaximumFontSize,
                            step: 2
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionWidth")) {
                        ProjectionDimensionField(
                            value: width,
                            range: WindowLayout.projectionCaptureMinimumWidth...maximumWidth,
                            step: 20
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionHeight")) {
                        ProjectionDimensionField(
                            value: height,
                            range: WindowLayout.projectionCaptureMinimumHeight...WindowLayout.projectionCaptureMaximumHeight,
                            step: 10
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionLineSpacing")) {
                        ProjectionDimensionField(
                            value: lineSpacing,
                            range: WindowLayout.projectionCaptureMinimumLineSpacing...WindowLayout.projectionCaptureMaximumLineSpacing,
                            step: 1
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionPaddingHorizontal")) {
                        ProjectionDimensionField(
                            value: paddingHorizontal,
                            range: WindowLayout.projectionCaptureMinimumPadding...WindowLayout.projectionCaptureMaximumPadding,
                            step: 2
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ProjectionInspectorRow(title: L10n.text("caption.projectionAppendLineLimit")) {
                    ProjectionDimensionField(
                        value: appendLineLimit,
                        range: WindowLayout.projectionCaptureMinimumAppendLineLimit...WindowLayout.projectionCaptureMaximumAppendLineLimit,
                        step: 1,
                        unit: L10n.text("caption.projectionAppendLineLimitUnit")
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        captionPreviewState.clearProjectionCaption()
                    } label: {
                        Text(L10n.text("caption.projectionClear"))
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        captionPreviewState.fillProjectionCaption()
                    } label: {
                        Text(L10n.text("caption.projectionFill"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 330)
        .background(.regularMaterial)
        .onAppear {
            projectionCaptureWidth = clampedWidth(projectionCaptureWidth)
            projectionCaptureHeight = clampedHeight(projectionCaptureHeight)
            projectionCaptureFontID = validatedFontID
            projectionCaptureFontSize = clampedFontSize(projectionCaptureFontSize)
            projectionCaptureLineSpacing = clampedLineSpacing(projectionCaptureLineSpacing)
            projectionCapturePaddingHorizontal = clampedPadding(projectionCapturePaddingHorizontal)
            projectionCaptureAppendLineLimit = clampedAppendLineLimit(projectionCaptureAppendLineLimit)
        }
    }

    private var selectedOutputLanguage: SpeechOutputLanguage? {
        outputLanguages.first { $0.id == validatedLanguageID }
    }

    private func clampedWidth(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumWidth), maximumWidth)
    }

    private func clampedHeight(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumHeight), WindowLayout.projectionCaptureMaximumHeight)
    }

    private func clampedFontSize(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumFontSize), WindowLayout.projectionCaptureMaximumFontSize)
    }

    private func clampedLineSpacing(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumLineSpacing), WindowLayout.projectionCaptureMaximumLineSpacing)
    }

    private func clampedPadding(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumPadding), WindowLayout.projectionCaptureMaximumPadding)
    }

    private func clampedAppendLineLimit(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumAppendLineLimit),
            WindowLayout.projectionCaptureMaximumAppendLineLimit
        )
    }
}
