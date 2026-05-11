import Foundation

enum PortalLaunchVerifier {
    static func verifySpeechAuthorization(settings: SpeechSettings) async -> (
        status: SpeechAuthorizationStatus,
        log: PortalWorkflowLog
    ) {
        do {
            let result = try await settings.testConnection()
            return (
                .authorized,
                PortalWorkflowLog(
                    level: .info,
                    title: L10n.text("log.speech.reauthorizationSucceeded"),
                    detail: "Region \(result.region)"
                )
            )
        } catch {
            return (
                .failed,
                PortalWorkflowLog(
                    level: .error,
                    title: L10n.text("log.speech.reauthorizationFailed"),
                    detail: error.localizedDescription
                )
            )
        }
    }

    static func verifyRelayConnection(relaySettings: RelaySettings, speechKey: String) async -> (
        status: RelayConnectionStatus,
        connectionTestResult: RelayConnectionTestResult?,
        log: PortalWorkflowLog
    ) {
        do {
            let result = try await relaySettings.testConnection(speechKey: speechKey)
            return (
                .connected,
                result,
                PortalWorkflowLog(
                    level: .info,
                    title: L10n.text("log.relay.connectionTestSucceeded"),
                    detail: result.logDetail
                )
            )
        } catch {
            return (
                .failed,
                nil,
                PortalWorkflowLog(
                    level: .error,
                    title: L10n.text("log.relay.connectionTestFailed"),
                    detail: error.localizedDescription
                )
            )
        }
    }
}
