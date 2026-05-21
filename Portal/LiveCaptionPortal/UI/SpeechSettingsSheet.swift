import SwiftUI

struct SpeechSettingsSheet: View {
    @Binding var settings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTested: (SpeechConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onAuthorizationSettingsChanged: () -> Void
    let onSpeechKeyChanged: () -> Void
    let onAzureOpenAIConnectionTesting: () -> Void
    let onAzureOpenAIConnectionTested: () -> Void
    let onAzureOpenAIConnectionFailed: (_ logDetail: String) -> Void
    let onAzureOpenAISettingsChanged: () -> Void
    @State private var connectionTestStatus = SpeechConnectionTestStatus.idle
    @State private var azureOpenAIConnectionTestStatus = AzureOpenAIConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?
    @State private var activeAzureOpenAIConnectionTestID: UUID?
    @State private var selectedPhraseHintScope = SpeechPhraseHintScope.shared
    @State private var newPhraseHintText = ""
}

extension SpeechSettingsSheet {
    private var canTestConnection: Bool {
        settings.hasAuthorizationMaterial && !settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTestAzureOpenAIConnection: Bool {
        settings.hasAzureOpenAIRealtimeConfiguration
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

        return L10n.text(
            "speechSettings.requirements.missing",
            missingItems.joined(separator: L10n.text("list.separator"))
        )
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

    private func testAzureOpenAIConnection() {
        settings.save()
        let testID = UUID()
        activeAzureOpenAIConnectionTestID = testID
        azureOpenAIConnectionTestStatus = .testing
        onAzureOpenAIConnectionTesting()
        let settingsToTest = settings

        Task {
            do {
                try await settingsToTest.testAzureOpenAIConnection()

                await MainActor.run {
                    guard activeAzureOpenAIConnectionTestID == testID else {
                        return
                    }

                    azureOpenAIConnectionTestStatus = .success
                    onAzureOpenAIConnectionTested()
                }
            } catch {
                let message = error.localizedDescription
                let logDetail = (error as? AzureOpenAIRealtimeTranslationError)?.diagnosticDescription ?? message

                await MainActor.run {
                    guard activeAzureOpenAIConnectionTestID == testID else {
                        return
                    }

                    azureOpenAIConnectionTestStatus = .failure(message)
                    onAzureOpenAIConnectionFailed(logDetail)
                }
            }
        }
    }

    private func markConnectionTestChanged() {
        activeConnectionTestID = nil
        connectionTestStatus = .idle
        onAuthorizationSettingsChanged()
    }

    private func markAzureOpenAIConnectionTestChanged() {
        activeAzureOpenAIConnectionTestID = nil
        azureOpenAIConnectionTestStatus = .idle
        onAzureOpenAISettingsChanged()
    }

    var body: some View {
        VStack(spacing: 0) {
            SpeechSettingsHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.authentication"),
                        systemImage: "key.horizontal"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                SpeechSettingsFieldRow(label: "Region") {
                                    TextField(L10n.text("speechSettings.region.placeholder"), text: $settings.region)
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: "Speech Key") {
                                    SecureField(
                                        L10n.text("speechSettings.speechKey.placeholder"),
                                        text: $settings.speechKey
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.check"),
                        systemImage: "checkmark.seal"
                    ) {
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

                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.captionOutput"),
                        systemImage: "captions.bubble"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(availableSpeechOutputLanguages) { language in
                                OutputLanguageDisplayModeRow(
                                    language: language,
                                    isRequired: SpeechSettings.requiredOutputLanguageIDs.contains(language.id),
                                    selectedLanguageIDs: $settings.selectedOutputLanguageIDs,
                                    portalVisibleLanguageIDs: $settings.portalVisibleOutputLanguageIDs
                                )
                            }
                        }
                    }

                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.accurateCaption"),
                        systemImage: "sparkles"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(
                                L10n.text("azureOpenAI.accurateCaptionEnabled"),
                                isOn: $settings.isAccurateCaptionEnabled
                            )

                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                SpeechSettingsFieldRow(label: L10n.text("azureOpenAI.endpoint")) {
                                    TextField(
                                        L10n.text("azureOpenAI.endpoint.placeholder"),
                                        text: $settings.azureOpenAIEndpointURLString
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: L10n.text("azureOpenAI.transcriptionDeployment")) {
                                    TextField(
                                        L10n.text("azureOpenAI.transcriptionDeployment.placeholder"),
                                        text: $settings.azureOpenAITranscriptionDeploymentName
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: L10n.text("azureOpenAI.translationDeployment")) {
                                    TextField(
                                        L10n.text("azureOpenAI.translationDeployment.placeholder"),
                                        text: $settings.azureOpenAITranslationDeploymentName
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: L10n.text("azureOpenAI.apiKey")) {
                                    SecureField(
                                        L10n.text("azureOpenAI.apiKey.placeholder"),
                                        text: $settings.azureOpenAIAPIKey
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            SpeechSettingsStatusRow(
                                title: L10n.text("azureOpenAI.connectionTest"),
                                state: azureOpenAIConnectionTestStatus.title,
                                tint: azureOpenAIConnectionTestStatus.tint
                            )

                            HStack {
                                SpeechConnectionTestButton(
                                    title: L10n.text("azureOpenAI.testConnection"),
                                    isEnabled: canTestAzureOpenAIConnection
                                        && !azureOpenAIConnectionTestStatus.isTesting,
                                    accessibilityHint: L10n.text("azureOpenAI.testConnection.hint"),
                                    disabledAccessibilityHint: L10n.text("azureOpenAI.testConnection.disabledHint"),
                                    action: testAzureOpenAIConnection
                                )

                                Spacer()
                            }
                            .controlSize(.large)

                            Text(azureOpenAIConnectionTestStatus.message)
                                .font(.caption)
                                .foregroundStyle(azureOpenAIConnectionTestStatus.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.segmentation"),
                        systemImage: "timer"
                    ) {
                        SpeechSegmentationTimeoutControl(
                            timeoutMilliseconds: $settings.sentenceSilenceTimeoutMilliseconds
                        )
                    }

                    SpeechSettingsSection(
                        title: L10n.text("speechSettings.section.phraseHints"),
                        systemImage: "text.badge.checkmark"
                    ) {
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
        .onChange(of: settings.isAccurateCaptionEnabled) {
            markAzureOpenAIConnectionTestChanged()
        }
        .onChange(of: settings.azureOpenAIEndpointURLString) {
            markAzureOpenAIConnectionTestChanged()
        }
        .onChange(of: settings.azureOpenAITranscriptionDeploymentName) {
            markAzureOpenAIConnectionTestChanged()
        }
        .onChange(of: settings.azureOpenAITranslationDeploymentName) {
            markAzureOpenAIConnectionTestChanged()
        }
        .onChange(of: settings.azureOpenAIAPIKey) {
            markAzureOpenAIConnectionTestChanged()
        }
    }
}
