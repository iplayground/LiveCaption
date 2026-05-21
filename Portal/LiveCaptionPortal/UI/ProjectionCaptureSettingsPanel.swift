import SwiftUI

struct ProjectionCaptureSettingsInspector: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumWidth: Double
    var preferredWidth: CGFloat? = 330
    var areConfigurationControlsLocked = false
    @AppStorage("projectionCapture.languageID") var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.visibleLanguageIDs") var projectionCaptureVisibleLanguageIDs = ""
    @AppStorage("projectionCapture.previewArrangement")
    var projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement.vertical.rawValue
    @AppStorage("projectionCapture.captionSource")
    var projectionCaptureCaptionSource = ProjectionCaptionSource.speech.rawValue
    @AppStorage("projectionCapture.width") var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") var projectionCaptureHeight = 180.0
    @AppStorage("projectionCapture.fontID") var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") var projectionCapturePaddingHorizontal = 28.0
    @AppStorage("projectionCapture.verticalPlacement")
    var projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.bottom.rawValue
}

extension ProjectionCaptureSettingsInspector {
    var usesWideLayout: Bool {
        preferredWidth == nil
    }

    var selectedLanguageID: Binding<String> {
        Binding(
            get: { validatedLanguageID },
            set: { projectionCaptureLanguageID = $0 }
        )
    }

    var selectedWindowLanguageIDs: [String] {
        ProjectionCaptureLanguageSelection.selectedIDs(
            from: projectionCaptureVisibleLanguageIDs,
            outputLanguages: outputLanguages,
            fallbackID: validatedLanguageID
        )
    }

    var selectedPreviewArrangement: Binding<String> {
        Binding(
            get: { validatedPreviewArrangement.rawValue },
            set: {
                projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement
                    .arrangement(for: $0)
                    .rawValue
            }
        )
    }

    var selectedCaptionSource: Binding<String> {
        Binding(
            get: { validatedCaptionSource.rawValue },
            set: { projectionCaptureCaptionSource = ProjectionCaptionSource.source(for: $0).rawValue }
        )
    }

    var selectedVerticalPlacement: Binding<String> {
        Binding(
            get: { validatedVerticalPlacement.rawValue },
            set: { projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.placement(for: $0).rawValue }
        )
    }

    var width: Binding<Double> {
        Binding(
            get: { clampedWidth(projectionCaptureWidth) },
            set: { projectionCaptureWidth = clampedWidth($0) }
        )
    }

    var height: Binding<Double> {
        Binding(
            get: { projectionCaptureHeight },
            set: { projectionCaptureHeight = clampedHeight($0) }
        )
    }

    var selectedFontID: Binding<String> {
        Binding(
            get: { validatedFontID },
            set: { projectionCaptureFontID = $0 }
        )
    }

    var fontSize: Binding<Double> {
        Binding(
            get: { projectionCaptureFontSize },
            set: { projectionCaptureFontSize = clampedFontSize($0) }
        )
    }

    var lineSpacing: Binding<Double> {
        Binding(
            get: { projectionCaptureLineSpacing },
            set: { projectionCaptureLineSpacing = clampedLineSpacing($0) }
        )
    }

    var paddingHorizontal: Binding<Double> {
        Binding(
            get: { projectionCapturePaddingHorizontal },
            set: { projectionCapturePaddingHorizontal = clampedPadding($0) }
        )
    }

    var appendLineLimit: Binding<Double> {
        Binding(
            get: { projectionCaptureAppendLineLimit },
            set: { projectionCaptureAppendLineLimit = clampedAppendLineLimit($0) }
        )
    }

    var validatedLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        if outputLanguages.contains(where: { $0.id == inputLanguage.matchingOutputLanguageID }) {
            return inputLanguage.matchingOutputLanguageID
        }

        return outputLanguages.first?.id ?? projectionCaptureLanguageID
    }

    var validatedFontID: String {
        if ProjectionCaptionFontChoice.availableChoices.contains(where: { $0.id == projectionCaptureFontID }) {
            return projectionCaptureFontID
        }

        return ProjectionCaptionFontChoice.systemID
    }

    var validatedPreviewArrangement: ProjectionCapturePreviewArrangement {
        ProjectionCapturePreviewArrangement.arrangement(for: projectionCapturePreviewArrangement)
    }

    var validatedCaptionSource: ProjectionCaptionSource {
        ProjectionCaptionSource.source(for: projectionCaptureCaptionSource)
    }

    var validatedVerticalPlacement: ProjectionCaptionVerticalPlacement {
        ProjectionCaptionVerticalPlacement.placement(for: projectionCaptureVerticalPlacement)
    }

    var maximumPreviewWidth: Double {
        guard usesWideLayout, selectedWindowLanguageIDs.count == 2, validatedPreviewArrangement == .horizontal else {
            return maximumWidth
        }

        let availableBlockWidth = (maximumWidth - WindowLayout.projectionCapturePreviewBlockSpacing) / 2
        return max(WindowLayout.projectionCaptureMinimumWidth, availableBlockWidth)
    }

    var body: some View {
        ScrollView {
            if usesWideLayout {
                wideLayout
            } else {
                narrowLayout
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: preferredWidth)
        .background(.regularMaterial)
        .disabled(areConfigurationControlsLocked)
        .onAppear(perform: normalizeStoredValues)
        .onChange(of: maximumPreviewWidth) {
            projectionCaptureWidth = clampedWidth(projectionCaptureWidth)
        }
    }

    var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ProjectionInspectorRow(title: L10n.text("caption.projectionLanguage")) {
                    languagePicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                appendModeToggle
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                ProjectionInspectorRow(title: L10n.text("caption.projectionFont")) {
                    fontPicker(width: 170)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                fontSizeField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                widthField
                    .frame(maxWidth: .infinity, alignment: .leading)

                heightField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                lineSpacingField
                    .frame(maxWidth: .infinity, alignment: .leading)

                paddingField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                verticalPlacementPicker
                    .frame(maxWidth: .infinity, alignment: .leading)

                appendLineLimitField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionButtons(compact: false)
        }
        .padding(16)
    }

    var wideLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                captionSourcePicker
                    .padding(.trailing, 28)

                windowLanguageControls

                appendModeToggle
                    .frame(width: 132, alignment: .leading)

                Spacer(minLength: 0)

                ProjectionInspectorRow(title: L10n.text("caption.projectionFont")) {
                    fontPicker(width: 150)
                }

                fontSizeField
            }

            HStack(alignment: .top, spacing: 12) {
                widthField

                heightField

                lineSpacingField

                paddingField

                appendLineLimitField

                actionButtons(compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
