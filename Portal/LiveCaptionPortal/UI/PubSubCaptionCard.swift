import SwiftUI

struct PubSubCaptionCard: View {
    @ObservedObject var receiver: PubSubCaptionReceiver

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private var statusDetail: String {
        switch receiver.status {
        case .idle:
            L10n.text("pubSub.caption.idleDetail")
        case .negotiating:
            L10n.text("pubSub.caption.connectingDetail")
        case .connected(let group):
            L10n.text("pubSub.caption.connectedDetail", group)
        case .failed(let message):
            message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(receiver.status.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 6) {
                    Text(receiver.status.title)
                        .font(.headline)

                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider()

            VStack(spacing: 12) {
                PubSubCaptionModeSection(
                    title: L10n.text("pubSub.caption.speech"),
                    systemImage: "waveform",
                    tint: .blue,
                    caption: receiver.latestCaption(for: .fast),
                    timeFormatter: Self.timeFormatter
                )

                PubSubCaptionModeSection(
                    title: L10n.text("pubSub.caption.openAI"),
                    systemImage: "sparkles",
                    tint: .purple,
                    caption: receiver.latestCaption(for: .accurate),
                    timeFormatter: Self.timeFormatter
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(receiver.status.tint)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct PubSubCaptionModeSection: View {
    let title: String
    let systemImage: String
    let tint: Color
    let caption: PubSubCaptionEvent?
    let timeFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let caption {
                    Text(timeFormatter.string(from: caption.receivedAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let caption {
                ForEach(caption.sortedCaptions, id: \.languageID) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.languageID)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(item.text)
                            .font(.system(size: 20, weight: .regular))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(L10n.text("pubSub.caption.modeEmpty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint)
                .frame(width: 3)
        }
    }
}
