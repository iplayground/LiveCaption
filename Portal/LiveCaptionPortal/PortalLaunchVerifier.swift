import Foundation

struct PortalRelayLaunchVerificationResult {
    let status: RelayConnectionStatus
    let connectionTestResult: RelayConnectionTestResult?
    let log: PortalWorkflowLog
}

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

    static func verifyRelayConnection(
        relaySettings: RelaySettings,
        speechKey: String
    ) async -> PortalRelayLaunchVerificationResult {
        do {
            let result = try await relaySettings.testConnection(speechKey: speechKey)
            return PortalRelayLaunchVerificationResult(
                status: .connected,
                connectionTestResult: result,
                log: PortalWorkflowLog(
                    level: .info,
                    title: L10n.text("log.relay.connectionTestSucceeded"),
                    detail: result.logDetail
                )
            )
        } catch {
            return PortalRelayLaunchVerificationResult(
                status: .failed,
                connectionTestResult: nil,
                log: PortalWorkflowLog(
                    level: .error,
                    title: L10n.text("log.relay.connectionTestFailed"),
                    detail: error.localizedDescription
                )
            )
        }
    }
}
