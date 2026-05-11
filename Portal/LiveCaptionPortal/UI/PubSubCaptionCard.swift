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

            if let latestCaption = receiver.latestCaption {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("pubSub.caption.latest"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(Self.timeFormatter.string(from: latestCaption.receivedAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ForEach(latestCaption.sortedCaptions, id: \.languageID) { caption in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caption.languageID)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(caption.text)
                                .font(.system(size: 20, weight: .regular))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text(L10n.text("pubSub.caption.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
