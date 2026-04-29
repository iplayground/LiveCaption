import SwiftUI

struct SpeechSettingsSheet: View {
    @Binding var settings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTested: (SpeechConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onAuthorizationSettingsChanged: () -> Void
    @State private var connectionTestStatus = SpeechConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?

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
        .frame(width: 640, height: 660)
        .onDisappear {
            saveSettings()
        }
        .onChange(of: settings.region) {
            markConnectionTestChanged()
        }
        .onChange(of: settings.speechKey) {
            markConnectionTestChanged()
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

            StatusPill(title: "SDK 1.43.0", systemImage: "shippingbox", tint: .blue)
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
