import SwiftUI

enum CaptionSessionStatus {
    case notStarted
    case ready
    case captioning
    case stopping
    case completed
    case completedWithWarning
    case failed

    var title: String {
        switch self {
        case .notStarted:
            L10n.text("session.notStarted")
        case .ready:
            L10n.text("session.ready")
        case .captioning:
            L10n.text("session.captioning")
        case .stopping:
            L10n.text("session.stopping")
        case .completed:
            L10n.text("session.completed")
        case .completedWithWarning:
            L10n.text("session.completedWithWarning")
        case .failed:
            L10n.text("session.failed")
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted:
            "pause.circle.fill"
        case .ready:
            "checkmark.circle.fill"
        case .captioning:
            "dot.radiowaves.left.and.right"
        case .stopping:
            "hourglass"
        case .completed:
            "checkmark.seal.fill"
        case .completedWithWarning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted:
            .secondary
        case .ready:
            .blue
        case .captioning:
            .green
        case .stopping:
            .orange
        case .completed:
            .green
        case .completedWithWarning:
            .orange
        case .failed:
            .red
        }
    }

    var locksProjectionSettings: Bool {
        locksConfigurationControls
    }

    var blocksKeyboardEvents: Bool {
        locksConfigurationControls
    }

    var locksConfigurationControls: Bool {
        switch self {
        case .captioning, .stopping:
            true
        case .notStarted, .ready, .completed, .completedWithWarning, .failed:
            false
        }
    }
}

struct SessionStatusValue: View {
    let status: CaptionSessionStatus

    var body: some View {
        HStack {
            Text(L10n.text("session.status"))
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: status.title, systemImage: status.systemImage, tint: status.tint)
        }
        .font(.subheadline)
    }
}

struct SessionCaptureValue: View {
    let isCapturing: Bool

    private var title: String {
        isCapturing ? L10n.text("audio.capturing") : L10n.text("audio.notCapturing")
    }

    private var tint: Color {
        isCapturing ? .green : .orange
    }

    private var systemImage: String {
        isCapturing ? "waveform" : "mic.slash.fill"
    }

    var body: some View {
        HStack {
            Text(L10n.text("audio.capture"))
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: title, systemImage: systemImage, tint: tint)
        }
        .font(.subheadline)
    }
}

struct SessionStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(height: 22)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.36), lineWidth: 1)
            }
    }
}

struct SessionMetricValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(minWidth: 28, minHeight: 22)
                .background(Color.secondary.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.36), lineWidth: 1)
                }
        }
        .font(.subheadline)
    }
}

struct SpeechAuthorizationValue: View {
    let status: SpeechAuthorizationStatus

    private var systemImage: String {
        switch status {
        case .unauthorized:
            "key.fill"
        case .unverified:
            "questionmark.circle.fill"
        case .verifying:
            "arrow.triangle.2.circlepath"
        case .authorized:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack {
            Text(L10n.text("speech"))
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: status.title, systemImage: systemImage, tint: status.tint)
        }
        .font(.subheadline)
    }
}

struct RelayConnectionValue: View {
    let status: RelayConnectionStatus

    private var systemImage: String {
        switch status {
        case .notConfigured:
            "antenna.radiowaves.left.and.right.slash"
        case .unverified:
            "questionmark.circle.fill"
        case .testing:
            "arrow.triangle.2.circlepath"
        case .connected:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack {
            Text("Relay")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(
                title: status.title,
                systemImage: systemImage,
                tint: status.tint
            )
        }
        .font(.subheadline)
    }
}

struct AzureOpenAIConnectionValue: View {
    let status: AzureOpenAIConnectionStatus

    private var systemImage: String {
        switch status {
        case .disabled:
            "sparkles"
        case .unconfigured:
            "questionmark.circle.fill"
        case .unverified:
            "questionmark.circle.fill"
        case .testing:
            "arrow.triangle.2.circlepath"
        case .connected:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .disabled:
            .secondary
        case .unconfigured, .unverified:
            .orange
        case .testing:
            .blue
        case .connected:
            .green
        case .failed:
            .red
        }
    }

    var body: some View {
        HStack {
            Text(L10n.text("azureOpenAI.status"))
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(
                title: status.title,
                systemImage: systemImage,
                tint: tint
            )
        }
        .font(.subheadline)
    }
}

enum SubtitleFileAccessStatus {
    case notConfigured
    case authorized
    case unavailable

    var title: String {
        switch self {
        case .notConfigured:
            L10n.text("common.notConfigured")
        case .authorized:
            L10n.text("subtitle.fileAccess.authorized")
        case .unavailable:
            L10n.text("subtitle.fileAccess.unavailable")
        }
    }

    var systemImage: String {
        switch self {
        case .notConfigured:
            "questionmark.circle.fill"
        case .authorized:
            "checkmark.seal.fill"
        case .unavailable:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notConfigured:
            .secondary
        case .authorized:
            .green
        case .unavailable:
            .red
        }
    }
}

struct SubtitleFileAccessValue: View {
    let status: SubtitleFileAccessStatus

    var body: some View {
        HStack {
            Text(L10n.text("subtitle.filePermission"))
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: status.title, systemImage: status.systemImage, tint: status.tint)
        }
        .font(.subheadline)
    }
}

struct PermissionRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(state)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
