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
                Text("未偵測到音訊來源")
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
        .accessibilityLabel("音訊來源")
        .accessibilityValue(selectedDeviceName)
    }
}

struct AudioLevelMeter: View {
    let level: Float
    let peakLevel: Float
    let decibels: Float

    private var decibelText: String {
        "\(Int(decibels.rounded())) dB"
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
                        .frame(width: proxy.size.width * CGFloat(level))

                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * CGFloat(peakLevel) - 1))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("音訊輸入音量")
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

struct SessionStatusValue: View {
    var body: some View {
        HStack {
            Text("狀態")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: "尚未開始", systemImage: "pause.circle.fill", tint: .secondary)
        }
        .font(.subheadline)
    }
}

struct SessionCaptureValue: View {
    let isCapturing: Bool

    private var title: String {
        isCapturing ? "收音中" : "未收音"
    }

    private var tint: Color {
        isCapturing ? .green : .orange
    }

    private var systemImage: String {
        isCapturing ? "waveform" : "mic.slash.fill"
    }

    var body: some View {
        HStack {
            Text("收音")
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
            Text("Speech 授權")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: status.title, systemImage: systemImage, tint: status.tint)
        }
        .font(.subheadline)
    }
}

struct RelayConnectionValue: View {
    var body: some View {
        HStack {
            Text("Relay")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: "未連線", systemImage: "antenna.radiowaves.left.and.right.slash", tint: .orange)
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
            "未設定"
        case .authorized:
            "已授權"
        case .unavailable:
            "無法存取"
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
            Text("檔案權限")
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
