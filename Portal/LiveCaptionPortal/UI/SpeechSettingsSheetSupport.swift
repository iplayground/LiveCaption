import SwiftUI

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

enum AzureOpenAIConnectionTestStatus {
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
            L10n.text("azureOpenAI.connection.message.idle")
        case .testing:
            L10n.text("azureOpenAI.connection.message.testing")
        case .success:
            L10n.text("azureOpenAI.connection.message.success")
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
    var title = L10n.text("speechSettings.testConnection")
    let isEnabled: Bool
    var accessibilityHint = L10n.text("speechSettings.testConnection.hint")
    var disabledAccessibilityHint = L10n.text("speechSettings.testConnection.disabledHint")
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Label(title, systemImage: "network")
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
        .accessibilityHint(isEnabled ? accessibilityHint : disabledAccessibilityHint)
    }
}

struct SpeechSegmentationTimeoutControl: View {
    @Binding var timeoutMilliseconds: Int

    var body: some View {
        let range = ClosedRange(
            uncheckedBounds: (
                lower: SpeechSettings.minimumSentenceSilenceTimeoutMillis,
                upper: SpeechSettings.maximumSentenceSilenceTimeoutMillis
            )
        )

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
                    in: range,
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
