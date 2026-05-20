import SwiftUI

struct HeaderView: View {
    let isCaptionSessionActive: Bool
    let captionSessionStartedAt: Date?
    let captionSessionElapsedTime: TimeInterval
    let captionProcessingPhase: CaptionProcessingPhase
    let canToggleCaptionSession: Bool
    let canEnterSpeakerCaptionMode: Bool
    let captionSessionDisabledReason: String?
    let onToggleCaptionSession: () -> Void
    let onEnterSpeakerCaptionMode: () -> Void

    private var captionButtonTitle: String {
        isCaptionSessionActive ? L10n.text("caption.stop") : L10n.text("caption.start")
    }

    private var captionButtonSystemImage: String {
        isCaptionSessionActive ? "stop.fill" : "play.fill"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiveCaption Portal")
                    .font(.system(size: 22, weight: .semibold))
                Text(L10n.text("app.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CaptionSessionTimer(startedAt: captionSessionStartedAt, elapsedTime: captionSessionElapsedTime)

            Button {
                onEnterSpeakerCaptionMode()
            } label: {
                Label(L10n.text("caption.enterSpeakerMode"), systemImage: "person.wave.2")
            }
            .controlSize(.large)
            .disabled(!canEnterSpeakerCaptionMode)
            .help(L10n.text("caption.enterSpeakerMode.hint"))

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
            .help(
                canToggleCaptionSession
                    ? captionButtonTitle
                    : captionSessionDisabledReason ?? L10n.text("caption.disabled.unavailable")
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct CaptionSessionTimer: View {
    let startedAt: Date?
    let elapsedTime: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formattedElapsedTime(at: context.date))
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(startedAt == nil ? .secondary : .primary)
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityLabel(L10n.text("caption.timer.accessibilityLabel"))
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
        let seconds = Int(elapsed) % 60

        return String(format: "%02d:%02d", minutes, seconds)
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
