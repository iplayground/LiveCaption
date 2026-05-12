import AppKit
import SwiftUI

struct StatusSidebar: View {
    let inputLanguage: InputLanguage
    let captionSessionStatus: CaptionSessionStatus
    let areConfigurationControlsLocked: Bool
    @Binding var speechSettings: SpeechSettings
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    @Binding var azureOpenAIConnectionStatus: AzureOpenAIConnectionStatus
    @Binding var relaySettings: RelaySettings
    @Binding var relayConnectionStatus: RelayConnectionStatus
    let relayPublishedCaptionCounts: [CaptionQualityMode: Int]
    let relayLastPublishedAt: Date?
    let logEntries: [LogEntry]
    let onLogEvent: (LogLevel, String, String) -> Void
    let onRelayConnectionTested: (RelayConnectionTestResult) -> Void
    @State private var projectionSettingsPanelPresenter = ProjectionSettingsPanelPresenter()
    @State private var isSpeechSettingsPresented = false
    @State private var isRelaySettingsPresented = false
    @AppStorage("projectionCapture.displayMode") private var projectionCaptureDisplayMode = ProjectionPreviewDisplayMode.inline.rawValue

    private var areProjectionSettingsLocked: Bool {
        areConfigurationControlsLocked
    }

    private var usesProjectionCaptureWindow: Bool {
        ProjectionPreviewDisplayMode.mode(for: projectionCaptureDisplayMode) == .window
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: L10n.text("projectionSettings.panelTitle"), systemImage: "rectangle.dashed") {
                    projectionControls
                }

                Panel(title: "Speech", systemImage: "waveform.badge.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledValue(label: "Region", value: speechSettings.regionSummary)
                        LabeledValue(label: L10n.text("speech.inputLanguage"), value: inputLanguage.nativeName)
                        LabeledValue(label: L10n.text("speech.outputLanguages"), value: speechSettings.outputLanguageSummary)
                        LabeledValue(label: L10n.text("azureOpenAI.status"), value: azureOpenAIConnectionStatus.title)

                        Button {
                            isSpeechSettingsPresented = true
                        } label: {
                            Label(L10n.text("settings.open"), systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(areConfigurationControlsLocked)
                    }
                }
                .sheet(isPresented: $isSpeechSettingsPresented) {
                    SpeechSettingsSheet(
                        settings: $speechSettings,
                        isPresented: $isSpeechSettingsPresented
                    ) { result in
                        speechAuthorizationStatus = .authorized
                        speechAuthorizationStatus.save()
                        onLogEvent(.info, L10n.text("log.speech.settingsTestSucceeded"), "Region \(result.region)")
                        testRelayConnectionAfterSpeechAuthorization()
                    } onFailure: { message in
                        speechAuthorizationStatus = .failed
                        speechAuthorizationStatus.save()
                        onLogEvent(.error, L10n.text("log.speech.settingsTestFailed"), message)
                    } onAuthorizationSettingsChanged: {
                        speechAuthorizationStatus = .initial(for: speechSettings)
                        speechAuthorizationStatus.save()
                    } onSpeechKeyChanged: {
                        relayConnectionStatus = .initial(for: relaySettings)
                        relayConnectionStatus.save()
                    } onAzureOpenAIConnectionTesting: {
                        azureOpenAIConnectionStatus = .testing
                        azureOpenAIConnectionStatus.save()
                    } onAzureOpenAIConnectionTested: {
                        azureOpenAIConnectionStatus = .connected
                        azureOpenAIConnectionStatus.save()
                        onLogEvent(.info, L10n.text("log.azureOpenAI.connectionTestSucceeded"), "")
                    } onAzureOpenAIConnectionFailed: { message in
                        azureOpenAIConnectionStatus = .failed
                        azureOpenAIConnectionStatus.save()
                        onLogEvent(.error, L10n.text("log.azureOpenAI.connectionTestFailed"), message)
                    } onAzureOpenAISettingsChanged: {
                        azureOpenAIConnectionStatus = .initial(for: speechSettings)
                        azureOpenAIConnectionStatus.save()
                    }
                }

                Panel(title: "Relay", systemImage: "server.rack") {
                    VStack(alignment: .leading, spacing: 12) {
                        RelayURLValue(value: relaySettings.relayURLSummary)
                        LabeledValue(label: L10n.text("relay.roomName"), value: relaySettings.roomNameSummary)
                        LabeledValue(label: L10n.text("relay.trackNumber"), value: relaySettings.trackNumberSummary)
                        LabeledValue(label: L10n.text("relay.lastPublishedAt"), value: relayLastPublishedAtSummary)
                        LabeledValue(label: L10n.text("relay.captionEvents.fast"), value: "\(relayPublishedCaptionCount(for: .fast))")
                        LabeledValue(label: L10n.text("relay.captionEvents.accurate"), value: "\(relayPublishedCaptionCount(for: .accurate))")

                        Button {
                            isRelaySettingsPresented = true
                        } label: {
                            Label(L10n.text("settings.open"), systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(areConfigurationControlsLocked)
                    }
                }
                .sheet(isPresented: $isRelaySettingsPresented) {
                    RelaySettingsSheet(
                        settings: $relaySettings,
                        speechSettings: speechSettings,
                        isPresented: $isRelaySettingsPresented
                    ) {
                        relayConnectionStatus = .testing
                        relayConnectionStatus.save()
                    } onConnectionTested: { result in
                        relayConnectionStatus = .connected
                        relayConnectionStatus.save()
                        onRelayConnectionTested(result)
                        onLogEvent(.info, L10n.text("log.relay.connectionTestSucceeded"), result.logDetail)
                    } onFailure: { message in
                        relayConnectionStatus = .failed
                        relayConnectionStatus.save()
                        onLogEvent(.error, L10n.text("log.relay.connectionTestFailed"), message)
                    } onSettingsChanged: {
                        relayConnectionStatus = .initial(for: relaySettings)
                        relayConnectionStatus.save()
                    }
                }

                Panel(title: L10n.text("panel.recentStatus"), systemImage: "clock.badge") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledValue(label: L10n.text("status.lastEvent"), value: recentStatusLastEventSummary)
                            .help(recentStatusLastEventHelp)
                        LabeledValue(label: L10n.text("status.warning"), value: "\(recentStatusWarningCount)")
                        LabeledValue(label: L10n.text("status.error"), value: "\(recentStatusErrorCount)")
                    }
                }
            }
            .padding(20)
            .frame(width: WindowLayout.statusSidebarWidth)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: WindowLayout.statusSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: areProjectionSettingsLocked) {
            if areProjectionSettingsLocked {
                projectionSettingsPanelPresenter.close()
                isSpeechSettingsPresented = false
                isRelaySettingsPresented = false
            }
        }
        .onChange(of: projectionCaptureDisplayMode) {
            if usesProjectionCaptureWindow {
                projectionSettingsPanelPresenter.close()
            }
        }
    }

    private var projectionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if usesProjectionCaptureWindow {
                Button {
                    focusProjectionCaptureWindow()
                } label: {
                    Label(L10n.text("projectionSettings.showPreviewWindow"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    openProjectionSettings()
                } label: {
                    Label(L10n.text("settings.open"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .disabled(areProjectionSettingsLocked)

                Button {
                    openProjectionCaptureWindow()
                } label: {
                    Label(L10n.text("caption.projectionOpenInWindow"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .disabled(areProjectionSettingsLocked)
            }
        }
    }

    private var relayLastPublishedAtSummary: String {
        guard let relayLastPublishedAt else {
            return L10n.text("common.none")
        }

        return Self.relayLastPublishedAtFormatter.string(from: relayLastPublishedAt)
    }

    private func relayPublishedCaptionCount(for mode: CaptionQualityMode) -> Int {
        relayPublishedCaptionCounts[mode, default: 0]
    }

    private var recentStatusLastEventSummary: String {
        guard let latestLogEntry = logEntries.first else {
            return L10n.text("common.none")
        }

        return "\(latestLogEntry.time) \(latestLogEntry.title)"
    }

    private var recentStatusLastEventHelp: String {
        guard let latestLogEntry = logEntries.first else {
            return L10n.text("common.none")
        }

        guard !latestLogEntry.detail.isEmpty else {
            return recentStatusLastEventSummary
        }

        return "\(recentStatusLastEventSummary)\n\(latestLogEntry.detail)"
    }

    private var recentStatusWarningCount: Int {
        logEntries.filter { $0.level == .warning }.count
    }

    private var recentStatusErrorCount: Int {
        logEntries.filter { $0.level == .error }.count
    }

    private static let relayLastPublishedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private func openProjectionSettings() {
        projectionSettingsPanelPresenter.show(
            inputLanguage: inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages,
            captionPreviewState: captionPreviewState
        )
    }

    private func openProjectionCaptureWindow() {
        projectionSettingsPanelPresenter.close()
        projectionCaptureDisplayMode = ProjectionPreviewDisplayMode.window.rawValue
    }

    private func focusProjectionCaptureWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == L10n.text("caption.projectionWindow.title") }) else {
            openProjectionCaptureWindow()
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func testRelayConnectionAfterSpeechAuthorization() {
        guard relaySettings.isConfigured else {
            return
        }

        relayConnectionStatus = .testing
        relayConnectionStatus.save()

        let settingsToTest = relaySettings
        let speechKey = speechSettings.speechKey

        Task {
            do {
                let result = try await settingsToTest.testConnection(speechKey: speechKey)

                await MainActor.run {
                    relayConnectionStatus = .connected
                    relayConnectionStatus.save()
                    onRelayConnectionTested(result)
                    onLogEvent(.info, L10n.text("log.relay.connectionTestSucceeded"), result.logDetail)
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    relayConnectionStatus = .failed
                    relayConnectionStatus.save()
                    onLogEvent(.error, L10n.text("log.relay.connectionTestFailed"), message)
                }
            }
        }
    }
}

private struct RelayURLValue: View {
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("relay.url"))
                .foregroundStyle(.secondary)

            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(value)
        }
        .font(.subheadline)
    }
}
