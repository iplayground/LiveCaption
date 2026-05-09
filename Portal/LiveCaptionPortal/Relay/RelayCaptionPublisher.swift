import Foundation

struct RelayCaptionPublishOutcome {
    var publishedAt: Date?
    var connectionStatus: RelayConnectionStatus?
    var logs: [PortalWorkflowLog] = []
}

enum RelayCaptionPublisher {
    static func publish(
        _ input: RelayCaptionPublishInput,
        settings: RelaySettings,
        speechKey: String,
        retryLimit: Int
    ) async -> RelayCaptionPublishOutcome {
        for attempt in 1...retryLimit {
            do {
                let result = try await settings.publishCaptionEvent(input, speechKey: speechKey)
                return RelayCaptionPublishOutcome(publishedAt: result.publishedAt)
            } catch {
                let isFinalAttempt = attempt == retryLimit
                let log = PortalWorkflowLog(
                    level: isFinalAttempt ? .error : .warning,
                    title: L10n.text("log.relay.publishFailed"),
                    detail: L10n.text(
                        "log.relay.publishFailedDetail",
                        attempt,
                        retryLimit,
                        error.localizedDescription
                    )
                )

                guard !isFinalAttempt else {
                    return RelayCaptionPublishOutcome(connectionStatus: .failed, logs: [log])
                }

                try? await Task.sleep(for: .seconds(attempt))
            }
        }

        return RelayCaptionPublishOutcome()
    }
}
