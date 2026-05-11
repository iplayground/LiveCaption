import SwiftUI

struct ProjectionCaptureSettingsInspector: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumWidth: Double
    var preferredWidth: CGFloat? = 330
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.visibleLanguageIDs") private var projectionCaptureVisibleLanguageIDs = ""
    @AppStorage("projectionCapture.previewArrangement") private var projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement.vertical.rawValue
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0
    @AppStorage("projectionCapture.fontID") private var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") private var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") private var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") private var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") private var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") private var projectionCapturePaddingHorizontal = 28.0
    @AppStorage("projectionCapture.verticalPlacement") private var projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.bottom.rawValue

    private var usesWideLayout: Bool {
        preferredWidth == nil
    }

    private var selectedLanguageID: Binding<String> {
        Binding(
            get: { validatedLanguageID },
            set: { projectionCaptureLanguageID = $0 }
        )
    }

    private var selectedWindowLanguageIDs: [String] {
        ProjectionCaptureLanguageSelection.selectedIDs(
            from: projectionCaptureVisibleLanguageIDs,
            outputLanguages: outputLanguages,
            fallbackID: validatedLanguageID
        )
    }

    private var selectedPreviewArrangement: Binding<String> {
        Binding(
            get: { validatedPreviewArrangement.rawValue },
            set: { projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement.arrangement(for: $0).rawValue }
        )
    }

    private var selectedVerticalPlacement: Binding<String> {
        Binding(
            get: { validatedVerticalPlacement.rawValue },
            set: { projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.placement(for: $0).rawValue }
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

        if outputLanguages.contains(where: { $0.id == inputLanguage.matchingOutputLanguageID }) {
            return inputLanguage.matchingOutputLanguageID
        }

        return outputLanguages.first?.id ?? projectionCaptureLanguageID
    }

    private var validatedFontID: String {
        if ProjectionCaptionFontChoice.availableChoices.contains(where: { $0.id == projectionCaptureFontID }) {
            return projectionCaptureFontID
        }

        return ProjectionCaptionFontChoice.systemID
    }

    private var validatedPreviewArrangement: ProjectionCapturePreviewArrangement {
        ProjectionCapturePreviewArrangement.arrangement(for: projectionCapturePreviewArrangement)
    }

    private var validatedVerticalPlacement: ProjectionCaptionVerticalPlacement {
        ProjectionCaptionVerticalPlacement.placement(for: projectionCaptureVerticalPlacement)
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
        .onAppear(perform: normalizeStoredValues)
    }

    private var narrowLayout: some View {
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

    private var wideLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
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

    private var languagePicker: some View {
        Picker(L10n.text("caption.projectionLanguage"), selection: selectedLanguageID) {
            ForEach(outputLanguages) { language in
                Text(language.nativeName).tag(language.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var windowLanguageSelection: some View {
        HStack(spacing: 10) {
            ForEach(outputLanguages) { language in
                Toggle(language.nativeName, isOn: windowLanguageSelection(for: language))
                    .toggleStyle(.checkbox)
                    .disabled(isWindowLanguageSelectionDisabled(for: language))
                    .fixedSize()
            }
        }
        .frame(minHeight: 26, alignment: .leading)
    }

    private var windowLanguageControls: some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectionInspectorRow(title: L10n.text("caption.projectionVisibleLanguages")) {
                windowLanguageSelection
            }
            .fixedSize(horizontal: true, vertical: false)

            if selectedWindowLanguageIDs.count == 2 {
                previewArrangementPicker
                    .frame(width: 132, alignment: .leading)
            }

            verticalPlacementPicker
                .frame(width: 102, alignment: .leading)
        }
    }

    private var previewArrangementPicker: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionArrangement")) {
            Picker(L10n.text("caption.projectionArrangement"), selection: selectedPreviewArrangement) {
                ForEach(ProjectionCapturePreviewArrangement.allCases) { arrangement in
                    Text(arrangement.localizedName).tag(arrangement.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    private var appendModeToggle: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionAppendMode")) {
            Toggle(L10n.text("caption.projectionAppendMode"), isOn: $projectionCaptureAppendsText)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .frame(width: 54, height: 26, alignment: .leading)
        }
    }

    private var fontSizeField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionFontSize")) {
            ProjectionDimensionField(
                value: fontSize,
                range: WindowLayout.projectionCaptureMinimumFontSize...WindowLayout.projectionCaptureMaximumFontSize,
                step: 2
            )
        }
    }

    private var widthField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionWidth")) {
            ProjectionDimensionField(
                value: width,
                range: WindowLayout.projectionCaptureMinimumWidth...maximumWidth,
                step: 20
            )
        }
    }

    private var heightField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionHeight")) {
            ProjectionDimensionField(
                value: height,
                range: WindowLayout.projectionCaptureMinimumHeight...WindowLayout.projectionCaptureMaximumHeight,
                step: 10
            )
        }
    }

    private var lineSpacingField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionLineSpacing")) {
            ProjectionDimensionField(
                value: lineSpacing,
                range: WindowLayout.projectionCaptureMinimumLineSpacing...WindowLayout.projectionCaptureMaximumLineSpacing,
                step: 1
            )
        }
    }

    private var paddingField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionPaddingHorizontal")) {
            ProjectionDimensionField(
                value: paddingHorizontal,
                range: WindowLayout.projectionCaptureMinimumPadding...WindowLayout.projectionCaptureMaximumPadding,
                step: 2
            )
        }
    }

    private var appendLineLimitField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionAppendLineLimit")) {
            ProjectionDimensionField(
                value: appendLineLimit,
                range: WindowLayout.projectionCaptureMinimumAppendLineLimit...WindowLayout.projectionCaptureMaximumAppendLineLimit,
                step: 1,
                unit: L10n.text("caption.projectionAppendLineLimitUnit")
            )
        }
    }

    private var verticalPlacementPicker: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionVerticalPlacement")) {
            Picker(L10n.text("caption.projectionVerticalPlacement"), selection: selectedVerticalPlacement) {
                ForEach(ProjectionCaptionVerticalPlacement.allCases) { placement in
                    Text(placement.localizedName).tag(placement.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 90)
        }
    }

    private func fontPicker(width: CGFloat) -> some View {
        Picker(L10n.text("caption.projectionFont"), selection: selectedFontID) {
            ForEach(ProjectionCaptionFontChoice.availableChoices) { fontChoice in
                Text(fontChoice.localizedName).tag(fontChoice.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width, alignment: .leading)
    }

    private func actionButtons(compact: Bool) -> some View {
        ProjectionInspectorRow(title: compact ? " " : "") {
            HStack(spacing: 8) {
                Button {
                    captionPreviewState.clearProjectionCaption()
                } label: {
                    if compact {
                        Image(systemName: "trash")
                    } else {
                        Text(L10n.text("caption.projectionClear"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .help(L10n.text("caption.projectionClear"))

                Button {
                    captionPreviewState.fillProjectionCaption()
                } label: {
                    if compact {
                        Image(systemName: "text.append")
                    } else {
                        Text(L10n.text("caption.projectionFill"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .help(L10n.text("caption.projectionFill"))
            }
            .frame(maxWidth: compact ? nil : .infinity)
        }
    }

    private func windowLanguageSelection(for language: SpeechOutputLanguage) -> Binding<Bool> {
        Binding(
            get: { selectedWindowLanguageIDs.contains(language.id) },
            set: { isSelected in
                var selectedIDs = selectedWindowLanguageIDs

                if isSelected {
                    guard !selectedIDs.contains(language.id), selectedIDs.count < 2 else {
                        return
                    }
                    selectedIDs.append(language.id)
                } else {
                    guard selectedIDs.count > 1 else {
                        return
                    }
                    selectedIDs.removeAll { $0 == language.id }
                }

                projectionCaptureVisibleLanguageIDs = ProjectionCaptureLanguageSelection.rawValue(from: selectedIDs)
            }
        )
    }

    private func isWindowLanguageSelectionDisabled(for language: SpeechOutputLanguage) -> Bool {
        let selectedIDs = selectedWindowLanguageIDs
        let isSelected = selectedIDs.contains(language.id)

        if isSelected {
            return selectedIDs.count <= 1
        }

        return selectedIDs.count >= 2
    }

    private func normalizeStoredValues() {
        projectionCaptureLanguageID = validatedLanguageID
        projectionCaptureVisibleLanguageIDs = ProjectionCaptureLanguageSelection.rawValue(from: selectedWindowLanguageIDs)
        projectionCapturePreviewArrangement = validatedPreviewArrangement.rawValue
        projectionCaptureVerticalPlacement = validatedVerticalPlacement.rawValue
        projectionCaptureWidth = clampedWidth(projectionCaptureWidth)
        projectionCaptureHeight = clampedHeight(projectionCaptureHeight)
        projectionCaptureFontID = validatedFontID
        projectionCaptureFontSize = clampedFontSize(projectionCaptureFontSize)
        projectionCaptureLineSpacing = clampedLineSpacing(projectionCaptureLineSpacing)
        projectionCapturePaddingHorizontal = clampedPadding(projectionCapturePaddingHorizontal)
        projectionCaptureAppendLineLimit = clampedAppendLineLimit(projectionCaptureAppendLineLimit)
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
