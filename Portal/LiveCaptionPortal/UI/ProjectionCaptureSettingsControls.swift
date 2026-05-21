import SwiftUI

extension ProjectionCaptureSettingsInspector {
    var languagePicker: some View {
        Picker(L10n.text("caption.projectionLanguage"), selection: selectedLanguageID) {
            ForEach(outputLanguages) { language in
                Text(language.nativeName).tag(language.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var windowLanguageSelection: some View {
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

    var windowLanguageControls: some View {
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

    var previewArrangementPicker: some View {
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

    var captionSourcePicker: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionSource")) {
            Picker(L10n.text("caption.projectionSource"), selection: selectedCaptionSource) {
                ForEach(ProjectionCaptionSource.allCases) { source in
                    Text(source.localizedName).tag(source.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    var appendModeToggle: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionAppendMode")) {
            Toggle(L10n.text("caption.projectionAppendMode"), isOn: $projectionCaptureAppendsText)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .frame(width: 54, height: 26, alignment: .leading)
        }
    }

    var fontSizeField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionFontSize")) {
            ProjectionDimensionField(
                value: fontSize,
                range: WindowLayout.projectionCaptureMinimumFontSize...WindowLayout.projectionCaptureMaximumFontSize,
                step: 2
            )
        }
    }

    var widthField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionWidth")) {
            ProjectionDimensionField(
                value: width,
                range: WindowLayout.projectionCaptureMinimumWidth...maximumPreviewWidth,
                step: 20
            )
        }
    }

    var heightField: some View {
        ProjectionInspectorRow(title: L10n.text("caption.projectionHeight")) {
            ProjectionDimensionField(
                value: height,
                range: WindowLayout.projectionCaptureMinimumHeight...WindowLayout.projectionCaptureMaximumHeight,
                step: 10
            )
        }
    }

    var lineSpacingField: some View {
        let range = ClosedRange(
            uncheckedBounds: (
                lower: WindowLayout.projectionCaptureMinimumLineSpacing,
                upper: WindowLayout.projectionCaptureMaximumLineSpacing
            )
        )

        return ProjectionInspectorRow(title: L10n.text("caption.projectionLineSpacing")) {
            ProjectionDimensionField(
                value: lineSpacing,
                range: range,
                step: 1
            )
        }
    }

    var paddingField: some View {
        let range = ClosedRange(
            uncheckedBounds: (
                lower: WindowLayout.projectionCaptureMinimumPadding,
                upper: WindowLayout.projectionCaptureMaximumPadding
            )
        )

        return ProjectionInspectorRow(title: L10n.text("caption.projectionPaddingHorizontal")) {
            ProjectionDimensionField(
                value: paddingHorizontal,
                range: range,
                step: 2
            )
        }
    }

    var appendLineLimitField: some View {
        let range = ClosedRange(
            uncheckedBounds: (
                lower: WindowLayout.projectionCaptureMinimumAppendLineLimit,
                upper: WindowLayout.projectionCaptureMaximumAppendLineLimit
            )
        )

        return ProjectionInspectorRow(title: L10n.text("caption.projectionAppendLineLimit")) {
            ProjectionDimensionField(
                value: appendLineLimit,
                range: range,
                step: 1,
                unit: L10n.text("caption.projectionAppendLineLimitUnit")
            )
        }
    }

    var verticalPlacementPicker: some View {
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

    func fontPicker(width: CGFloat) -> some View {
        Picker(L10n.text("caption.projectionFont"), selection: selectedFontID) {
            ForEach(ProjectionCaptionFontChoice.availableChoices) { fontChoice in
                Text(fontChoice.localizedName).tag(fontChoice.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width, alignment: .leading)
    }

    func actionButtons(compact: Bool) -> some View {
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

    func windowLanguageSelection(for language: SpeechOutputLanguage) -> Binding<Bool> {
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

    func isWindowLanguageSelectionDisabled(for language: SpeechOutputLanguage) -> Bool {
        let selectedIDs = selectedWindowLanguageIDs
        let isSelected = selectedIDs.contains(language.id)

        if isSelected {
            return selectedIDs.count <= 1
        }

        return selectedIDs.count >= 2
    }
}
