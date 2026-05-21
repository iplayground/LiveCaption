import SwiftUI

extension ContentView {
func publishCaptionEventToRelay(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) {
        guard isCaptionSessionActive,
              relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        guard canPublishCaptionEventToRelay(event, mode: mode) else {
            return
        }

        guard let relayInput = RelayCaptionPublishInput(
            event: event,
            mode: mode,
            sessionID: relayCaptionSessionID,
            inputLanguage: event.inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages
        ) else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey

        Task.detached {
            let outcome = await RelayCaptionPublisher.publish(
                relayInput,
                settings: settingsToPublish,
                speechKey: speechKey,
                retryLimit: relayPublishRetryLimit
            )

            await MainActor.run {
                if let publishedAt = outcome.publishedAt {
                    relayLastPublishedAt = publishedAt
                    relayPublishedCaptionCounts[mode, default: 0] += 1
                }

                outcome.logs.forEach(appendLog)

                if let connectionStatus = outcome.connectionStatus {
                    relayConnectionStatus = connectionStatus
                    relayConnectionStatus.save()
                }
            }
        }
    }

    func canPublishCaptionEventToRelay(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) -> Bool {
        guard mode == .accurate else {
            return true
        }

        let translations = event.captionModes[mode]?.translations ?? [:]
        let missingLanguageIDs = missingOpenAITranslationLanguageIDs(
            in: translations,
            inputLanguage: event.inputLanguage
        )
        guard missingLanguageIDs.isEmpty else {
            appendMissingOpenAITranslationDiagnostic(missingLanguageIDs)
            return false
        }

        return true
    }

    func appendMissingOpenAITranslationDiagnostic(_ missingLanguageIDs: [String]) {
        appendOpenAITranslationDiagnostic(
            AzureOpenAIRealtimeTranslationDiagnostic(
                level: .warning,
                detail: [
                    "phase=relaySkipped",
                    "reason=missingTranslations",
                    "missingLanguages=\(missingLanguageIDs.joined(separator: ","))",
                ].joined(separator: "; ")
            )
        )
    }

    func publishPortalStatusToRelay(_ status: String) {
        guard relayConnectionStatus == .connected else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishPortalStatus(status, speechKey: speechKey)
        }
    }

    func refreshPortalStatusHeartbeat() {
        guard relayConnectionStatus == .connected,
              !isCaptionSessionActive else {
            stopPortalStatusHeartbeat()
            return
        }
        startPortalStatusHeartbeat()
    }

    func startPortalStatusHeartbeat() {
        guard portalStatusHeartbeatTask == nil else {
            return
        }
        portalStatusHeartbeatTask?.cancel()
        portalStatusHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: portalStatusHeartbeatInterval)
                guard !Task.isCancelled else {
                    return
                }
                let settingsToPublish = await MainActor.run {
                    relaySettings
                }
                let speechKey = await MainActor.run {
                    speechSettings.speechKey
                }
                _ = try? await settingsToPublish.markPortalActivity(speechKey: speechKey)
            }
        }
    }

    func stopPortalStatusHeartbeat() {
        portalStatusHeartbeatTask?.cancel()
        portalStatusHeartbeatTask = nil
    }

    func publishSessionStartedToRelay() {
        guard relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishSessionStatus(
                "started",
                sessionID: relayCaptionSessionID,
                speechKey: speechKey
            )
        }
    }

    func publishSessionStoppedToRelayIfNeeded() {
        guard relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        self.relayCaptionSessionID = nil
        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishSessionStatus(
                "stopped",
                sessionID: relayCaptionSessionID,
                speechKey: speechKey
            )
        }
    }

    func publishCaptionAvailabilityToRelayIfNeeded() {
        guard relayConnectionStatus == .connected else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        let sessionID = relayCaptionSessionID
        let modes = availableCaptionModesForRelay()
        let languages = speechSettings.selectedOutputLanguages
        let availability = RelayCaptionAvailability(
            sessionID: sessionID,
            captionModes: modes,
            languages: languages
        )
        guard availability != lastPublishedCaptionAvailability else {
            return
        }
        lastPublishedCaptionAvailability = availability
        Task.detached {
            _ = try? await settingsToPublish.publishCaptionAvailability(
                sessionID: sessionID,
                captionModes: modes,
                languages: languages,
                speechKey: speechKey
            )
        }
    }

    func availableCaptionModesForRelay() -> [CaptionQualityMode] {
        if speechSettings.isAccurateCaptionEnabled && azureOpenAIConnectionStatus == .connected {
            return [.fast, .accurate]
        }
        return [.fast]
    }
}
