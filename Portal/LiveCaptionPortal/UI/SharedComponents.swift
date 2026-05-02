import SwiftUI

struct Panel<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer()

                accessory
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

struct CaptionCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 24, weight: .regular))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.blue)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

struct LiveTranscriptCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 28, weight: .medium))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.green)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct AudioSourceMenu: View {
    let devices: [AudioInputDevice]
    let selectedDeviceID: String?
    let selectedDeviceName: String
    let isDisabled: Bool
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            if devices.isEmpty {
                Text(L10n.text("audio.noSourcesDetected"))
            } else {
                ForEach(devices) { device in
                    Button {
                        onSelect(device.id)
                    } label: {
                        if device.id == selectedDeviceID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedDeviceName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(width: WindowLayout.audioSourcePickerWidth, height: 28, alignment: .leading)
            .background(ControlPalette.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(L10n.text("audio.source"))
        .accessibilityValue(selectedDeviceName)
    }
}

struct AudioLevelMeter: View {
    @ObservedObject var levelState: AudioLevelState

    private var decibelText: String {
        "\(Int(levelState.decibels.rounded())) dB"
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(levelState.level))

                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * CGFloat(levelState.peakLevel) - 1))
                }
            }
            .frame(height: 12)
            .accessibilityLabel(L10n.text("audio.inputLevel.accessibilityLabel"))
            .accessibilityValue(decibelText)

            Text(decibelText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

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
