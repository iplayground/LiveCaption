import SwiftUI

struct RelaySettingsSheet: View {
    @Binding var settings: RelaySettings
    let speechSettings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTesting: () -> Void
    let onConnectionTested: (RelayConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onSettingsChanged: () -> Void
    @State private var connectionTestStatus = RelayConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?

    private var settingsStatusTint: Color {
        .orange
    }

    private var settingsStatusTitle: String {
        settings.isConfigured
            ? L10n.text("relaySettings.status.ready")
            : L10n.text("relaySettings.status.incomplete")
    }

    private func saveSettings() {
        settings.normalize()
        settings.save()
    }

    private func testConnection() {
        settings.normalize()
        settings.save()
        let testID = UUID()
        activeConnectionTestID = testID
        connectionTestStatus = .testing
        onConnectionTesting()
        let settingsToTest = settings
        let speechKey = speechSettings.speechKey

        Task {
            do {
                let result = try await settingsToTest.testConnection(speechKey: speechKey)

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .success(result)
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
        onSettingsChanged()
    }

    var body: some View {
        VStack(spacing: 0) {
            RelaySettingsHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SpeechSettingsSection(title: L10n.text("relaySettings.section.connection"), systemImage: "server.rack") {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                            SpeechSettingsFieldRow(label: L10n.text("relaySettings.relayURL")) {
                                TextField(L10n.text("relaySettings.relayURL.placeholder"), text: $settings.relayURLString)
                                    .textFieldStyle(.roundedBorder)
                            }

                            SpeechSettingsFieldRow(label: L10n.text("relaySettings.roomName")) {
                                TextField(L10n.text("relaySettings.roomName.placeholder"), text: $settings.roomName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            SpeechSettingsFieldRow(label: L10n.text("relaySettings.trackNumber")) {
                                Stepper(value: $settings.trackNumber, in: 1...8) {
                                    Text(L10n.text("relaySettings.trackNumber.value", settings.trackNumber))
                                        .font(.subheadline.weight(.medium))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    SpeechSettingsSection(title: L10n.text("relaySettings.section.check"), systemImage: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: 12) {
                            SpeechSettingsStatusRow(
                                title: L10n.text("relaySettings.configuration"),
                                state: connectionTestStatus.title(defaultTitle: settingsStatusTitle),
                                tint: connectionTestStatus.tint(defaultTint: settingsStatusTint)
                            )

                            HStack {
                                RelayConnectionTestButton(
                                    isEnabled: settings.isConfigured && !connectionTestStatus.isTesting,
                                    action: testConnection
                                )

                                Spacer()
                            }
                            .controlSize(.large)

                            Text(connectionTestStatus.message(defaultMessage: settings.validationMessage()))
                                .font(.caption)
                                .foregroundStyle(connectionTestStatus.tint(defaultTint: settingsStatusTint))
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
        .frame(width: 640, height: 520)
        .onDisappear {
            saveSettings()
        }
        .onChange(of: settings.relayURLString) { oldValue, newValue in
            guard RelaySettings(relayURLString: oldValue).normalizedRelayURLString
                != RelaySettings(relayURLString: newValue).normalizedRelayURLString else {
                return
            }

            markConnectionTestChanged()
        }
        .onChange(of: settings.roomName) { oldValue, newValue in
            guard RelaySettings(roomName: oldValue).normalizedRoomName
                != RelaySettings(roomName: newValue).normalizedRoomName else {
                return
            }

            markConnectionTestChanged()
        }
        .onChange(of: settings.trackNumber) {
            markConnectionTestChanged()
        }
    }
}

struct RelaySettingsHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("relaySettings.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.text("relaySettings.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }
}

enum RelayConnectionTestStatus {
    case idle
    case testing
    case success(RelayConnectionTestResult)
    case failure(String)

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }

    func title(defaultTitle: String) -> String {
        switch self {
        case .idle:
            defaultTitle
        case .testing:
            L10n.text("relayConnection.testing")
        case .success:
            L10n.text("relayConnection.success")
        case .failure:
            L10n.text("relayConnection.failure")
        }
    }

    func message(defaultMessage: String) -> String {
        switch self {
        case .idle:
            defaultMessage
        case .testing:
            L10n.text("relayConnection.message.testing")
        case .success(let result):
            L10n.text(
                "relayConnection.message.success",
                result.relayURL.absoluteString,
                result.trackNumber,
                result.viewerAccessCode
            )
        case .failure(let message):
            message
        }
    }

    func tint(defaultTint: Color) -> Color {
        switch self {
        case .idle:
            defaultTint
        case .testing:
            .blue
        case .success:
            .green
        case .failure:
            .red
        }
    }
}

struct RelayConnectionTestButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Label(L10n.text("relaySettings.testConnection"), systemImage: "network")
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
    }
}
