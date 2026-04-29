import SwiftUI

struct HeaderView: View {
    let isCaptionSessionActive: Bool
    let captionSessionStartedAt: Date?
    let captionSessionElapsedTime: TimeInterval
    let canToggleCaptionSession: Bool
    let captionSessionDisabledReason: String?
    let onToggleCaptionSession: () -> Void

    private var captionButtonTitle: String {
        isCaptionSessionActive ? "停止字幕" : "開始字幕"
    }

    private var captionButtonSystemImage: String {
        isCaptionSessionActive ? "stop.fill" : "play.fill"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiveCaption Portal")
                    .font(.system(size: 22, weight: .semibold))
                Text("現場字幕操作台")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CaptionSessionTimer(startedAt: captionSessionStartedAt, elapsedTime: captionSessionElapsedTime)

            Button {
                onToggleCaptionSession()
            } label: {
                Label(captionButtonTitle, systemImage: captionButtonSystemImage)
                    .frame(minWidth: 104)
            }
            .buttonStyle(
                CaptionSessionButtonStyle(
                    isEnabled: canToggleCaptionSession,
                    role: isCaptionSessionActive ? .stop : .start
                )
            )
            .controlSize(.large)
            .disabled(!canToggleCaptionSession)
            .help(canToggleCaptionSession ? captionButtonTitle : captionSessionDisabledReason ?? "尚無法開始字幕")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct CaptionSessionTimer: View {
    let startedAt: Date?
    let elapsedTime: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            Text(formattedElapsedTime(at: context.date))
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(startedAt == nil ? .secondary : .primary)
                .frame(minWidth: 86, alignment: .trailing)
                .accessibilityLabel("字幕計時")
                .accessibilityValue(formattedElapsedTime(at: context.date))
        }
    }

    private func formattedElapsedTime(at date: Date) -> String {
        let elapsed = if let startedAt {
            max(0, date.timeIntervalSince(startedAt))
        } else {
            max(0, elapsedTime)
        }
        let minutes = Int(elapsed / 60)
        let seconds = elapsed - Double(minutes * 60)

        return String(format: "%02d:%06.3f", minutes, seconds)
    }
}

struct CaptionSessionButtonStyle: ButtonStyle {
    enum Role {
        case start
        case stop
    }

    let isEnabled: Bool
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.72)
    }

    private var activeColor: Color {
        switch role {
        case .start:
            Color.accentColor
        case .stop:
            Color.red
        }
    }

    private var borderColor: Color {
        isEnabled ? activeColor.opacity(0.35) : Color.secondary.opacity(0.28)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color(nsColor: .controlBackgroundColor)
        }

        return isPressed ? activeColor.opacity(0.78) : activeColor
    }
}
