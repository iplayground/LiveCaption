import SwiftUI

struct SpeechSettingsSheet: View {
    @Binding var settings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTested: (SpeechConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onAuthorizationSettingsChanged: () -> Void
    let onSpeechKeyChanged: () -> Void
    @State private var connectionTestStatus = SpeechConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?
    @State private var selectedPhraseHintScope = SpeechPhraseHintScope.shared
    @State private var newPhraseHintText = ""

    private var canTestConnection: Bool {
        settings.hasAuthorizationMaterial && !settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var buildRequirementMessage: String {
        var missingItems: [String] = []

        if settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingItems.append("Region")
        }

        if !settings.hasAuthorizationMaterial {
            missingItems.append("Speech Key")
        }

        guard !missingItems.isEmpty else {
            return L10n.text("speechSettings.requirements.ready")
        }

        return L10n.text("speechSettings.requirements.missing", missingItems.joined(separator: L10n.text("list.separator")))
    }

    private var connectionHintMessage: String {
        connectionTestStatus.message.isEmpty ? buildRequirementMessage : connectionTestStatus.message
    }

    private var connectionHintTint: Color {
        connectionTestStatus.message.isEmpty
            ? (canTestConnection ? .green : .orange)
            : connectionTestStatus.tint
    }

    private func saveSettings() {
        settings.save()
    }

    private func testConnection() {
        settings.save()
        let testID = UUID()
        activeConnectionTestID = testID
        connectionTestStatus = .testing
        let settingsToTest = settings

        Task {
            do {
                let result = try await settingsToTest.testConnection()

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .success
                    onConnectionTested(result)
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .failure(message)
                    onFailure(message)
                }
            }
        }
    }

    private func markConnectionTestChanged() {
        activeConnectionTestID = nil
        connectionTestStatus = .idle
        onAuthorizationSettingsChanged()
    }

    var body: some View {
        VStack(spacing: 0) {
            SpeechSettingsHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SpeechSettingsSection(title: L10n.text("speechSettings.section.authentication"), systemImage: "key.horizontal") {
                        VStack(alignment: .leading, spacing: 14) {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                SpeechSettingsFieldRow(label: "Region") {
                                    TextField(L10n.text("speechSettings.region.placeholder"), text: $settings.region)
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: "Speech Key") {
                                    SecureField(L10n.text("speechSettings.speechKey.placeholder"), text: $settings.speechKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    SpeechSettingsSection(title: L10n.text("speechSettings.section.check"), systemImage: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: 12) {
                            SpeechSettingsStatusRow(
                                title: L10n.text("speechSettings.connectionTest"),
                                state: connectionTestStatus.title,
                                tint: connectionTestStatus.tint
                            )

                            HStack {
                                SpeechConnectionTestButton(
                                    isEnabled: canTestConnection && !connectionTestStatus.isTesting,
                                    action: testConnection
                                )

                                Spacer()
                            }
                            .controlSize(.large)

                            Text(connectionHintMessage)
                                .font(.caption)
                                .foregroundStyle(connectionHintTint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SpeechSettingsSection(title: L10n.text("speechSettings.section.captionOutput"), systemImage: "captions.bubble") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(availableSpeechOutputLanguages) { language in
                                OutputLanguageToggleRow(
                                    language: language,
                                    isRequired: SpeechSettings.requiredOutputLanguageIDs.contains(language.id),
                                    selectedLanguageIDs: $settings.selectedOutputLanguageIDs
                                )
                            }
                        }
                    }

                    SpeechSettingsSection(title: L10n.text("speechSettings.section.segmentation"), systemImage: "timer") {
                        SpeechSegmentationTimeoutControl(
                            timeoutMilliseconds: $settings.sentenceSilenceTimeoutMilliseconds
                        )
                    }

                    SpeechSettingsSection(title: L10n.text("speechSettings.section.phraseHints"), systemImage: "text.badge.checkmark") {
                        SpeechPhraseHintsEditor(
                            selectedScope: $selectedPhraseHintScope,
                            newPhraseText: $newPhraseHintText,
                            phraseHintsByScope: $settings.phraseHintsByScope
                        )
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()

                Button(L10n.text("common.done")) {
                    saveSettings()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 680, height: 760)
        .onDisappear {
            saveSettings()
        }
        .onChange(of: settings.region) {
            markConnectionTestChanged()
        }
        .onChange(of: settings.speechKey) {
            markConnectionTestChanged()
            onSpeechKeyChanged()
        }
    }
}

enum SpeechConnectionTestStatus {
    case idle
    case testing
    case success
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            L10n.text("speechConnection.idle")
        case .testing:
            L10n.text("speechConnection.testing")
        case .success:
            L10n.text("speechConnection.success")
        case .failure:
            L10n.text("speechConnection.failure")
        }
    }

    var message: String {
        switch self {
        case .idle:
            ""
        case .testing:
            L10n.text("speechConnection.message.testing")
        case .success:
            L10n.text("speechConnection.message.success")
        case .failure(let message):
            message
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .testing:
            .blue
        case .success:
            .green
        case .failure:
            .red
        }
    }

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }
}

struct SpeechSettingsHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("speechSettings.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.text("speechSettings.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: SpeechSDKAvailability.versionLabel, systemImage: "shippingbox", tint: .blue)
        }
        .padding(24)
    }
}

struct SpeechSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title, systemImage: systemImage)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpeechSettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        GridRow {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            content
        }
    }
}

struct SpeechConnectionTestButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Label(L10n.text("speechSettings.testConnection"), systemImage: "network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isEnabled ? Color.accentColor : Color(nsColor: .disabledControlTextColor).opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isEnabled ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityHint(isEnabled ? L10n.text("speechSettings.testConnection.hint") : L10n.text("speechSettings.testConnection.disabledHint"))
    }
}

struct OutputLanguageToggleRow: View {
    let language: SpeechOutputLanguage
    let isRequired: Bool
    @Binding var selectedLanguageIDs: Set<String>

    private var isSelected: Binding<Bool> {
        Binding {
            isRequired || selectedLanguageIDs.contains(language.id)
        } set: { newValue in
            if isRequired {
                selectedLanguageIDs.insert(language.id)
            } else if newValue {
                selectedLanguageIDs.insert(language.id)
            } else {
                selectedLanguageIDs.remove(language.id)
            }
        }
    }

    var body: some View {
        Toggle(isOn: isSelected) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .font(.subheadline.weight(.medium))
                    Text(language.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isRequired {
                    Text(L10n.text("speechSettings.outputLanguage.required"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isRequired)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private enum SpeechPhraseHintLayout {
    static let maximumVisibleRows = 10
    static let rowHeight: CGFloat = 40
    static let emptyListHeight: CGFloat = 72
    static let dividerHeight: CGFloat = 1
}

struct SpeechPhraseHintsEditor: View {
    @Binding var selectedScope: SpeechPhraseHintScope
    @Binding var newPhraseText: String
    @Binding var phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]

    private var canAddPhrase: Bool {
        !newPhraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remainingCapacity > 0
    }

    private var remainingCapacity: Int {
        SpeechSettings.remainingPhraseHintCapacity(
            for: selectedScope,
            in: phraseHintsByScope
        )
    }

    private var selectedPhraseHints: Binding<[SpeechPhraseHint]> {
        Binding {
            phraseHintsByScope[selectedScope, default: []]
        } set: { newValue in
            phraseHintsByScope[selectedScope] = newValue
        }
    }

    private var phraseHints: [SpeechPhraseHint] {
        phraseHintsByScope[selectedScope, default: []]
    }

    private var phraseListHeight: CGFloat {
        guard !phraseHints.isEmpty else {
            return SpeechPhraseHintLayout.emptyListHeight
        }

        let visibleRows = min(phraseHints.count, SpeechPhraseHintLayout.maximumVisibleRows)
        let visibleDividers = max(visibleRows - 1, 0)
        return CGFloat(visibleRows) * SpeechPhraseHintLayout.rowHeight
            + CGFloat(visibleDividers) * SpeechPhraseHintLayout.dividerHeight
    }

    private var capacityMessage: String {
        let normalizedPhraseHintsByScope = SpeechSettings.normalizedPhraseHintsByScope(phraseHintsByScope)
        let sharedCount = normalizedPhraseHintsByScope[.shared, default: []].count

        switch selectedScope {
        case .shared:
            let mandarinCount = SpeechSettings.phraseHintRecognitionCount(for: .mandarin, in: phraseHintsByScope)
            let englishCount = SpeechSettings.phraseHintRecognitionCount(for: .english, in: phraseHintsByScope)

            return L10n.text(
                "speechSettings.phraseHints.capacity.shared",
                sharedCount,
                SpeechSettings.maximumPhraseHintsPerRecognition,
                mandarinCount,
                SpeechSettings.maximumPhraseHintsPerRecognition,
                englishCount,
                SpeechSettings.maximumPhraseHintsPerRecognition
            )
        case .mandarin, .english:
            let scopeCount = normalizedPhraseHintsByScope[selectedScope, default: []].count
            let recognitionCount = sharedCount + scopeCount

            return L10n.text(
                "speechSettings.phraseHints.capacity.language",
                sharedCount,
                selectedScope.rawValue,
                scopeCount,
                recognitionCount,
                SpeechSettings.maximumPhraseHintsPerRecognition
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker(L10n.text("speechSettings.phraseHints.scope"), selection: $selectedScope) {
                    ForEach(SpeechPhraseHintScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Text(capacityMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(remainingCapacity > 0 ? Color.secondary : Color.red)
                    .monospacedDigit()
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if phraseHints.isEmpty {
                        Text(L10n.text("speechSettings.phraseHints.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: SpeechPhraseHintLayout.emptyListHeight)
                    } else {
                        ForEach(selectedPhraseHints) { phraseHint in
                            SpeechPhraseHintRow(phraseHint: phraseHint) {
                                let id = phraseHint.wrappedValue.id
                                phraseHintsByScope[selectedScope, default: []].removeAll { $0.id == id }
                            }

                            if phraseHint.wrappedValue.id != phraseHints.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(height: phraseListHeight)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 8) {
                TextField(L10n.text("speechSettings.phraseHints.add.placeholder"), text: $newPhraseText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPhrase)

                Button(action: addPhrase) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .disabled(!canAddPhrase)
                .help(L10n.text("speechSettings.phraseHints.add"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func addPhrase() {
        let normalizedText = newPhraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        var nextPhraseHints = phraseHints
        nextPhraseHints.append(SpeechPhraseHint(text: normalizedText))
        phraseHintsByScope[selectedScope] = SpeechSettings.normalizedPhraseHintsByScope(
            [selectedScope: nextPhraseHints]
        )[selectedScope, default: []]
        newPhraseText = ""
    }
}

struct SpeechPhraseHintRow: View {
    @Binding var phraseHint: SpeechPhraseHint
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("speechSettings.phraseHints.item.placeholder"), text: $phraseHint.text)
                .textFieldStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L10n.text("speechSettings.phraseHints.delete"))
        }
        .padding(.horizontal, 10)
        .frame(height: SpeechPhraseHintLayout.rowHeight)
    }
}

struct SpeechSegmentationTimeoutControl: View {
    @Binding var timeoutMilliseconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L10n.text("speechSettings.segmentation.silenceTimeout"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .leading)

                TextField(
                    L10n.text("speechSettings.segmentation.silenceTimeout"),
                    value: $timeoutMilliseconds,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)

                Stepper(
                    L10n.text("speechSettings.segmentation.silenceTimeout"),
                    value: $timeoutMilliseconds,
                    in: SpeechSettings.minimumSentenceSilenceTimeoutMilliseconds...SpeechSettings.maximumSentenceSilenceTimeoutMilliseconds,
                    step: 100
                )
                .labelsHidden()

                Text("ms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.text("speechSettings.segmentation.silenceTimeout.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SpeechSettingsStatusRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(state)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
    }
}
