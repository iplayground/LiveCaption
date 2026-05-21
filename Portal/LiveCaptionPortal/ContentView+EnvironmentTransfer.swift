import SwiftUI

extension ContentView {
func exportPortalEnvironmentSettings() {
        speechSettings.save()
        relaySettings.save()

        guard let exportRequest = PortalEnvironmentTransferPanel.exportRequest() else {
            return
        }

        do {
            try PortalEnvironmentSettings(
                speechSettings: speechSettings,
                relaySettings: relaySettings
            )
            .writeConfiguration(to: exportRequest.fileURL, selection: exportRequest.selection)
            appendLog(
                level: .info,
                title: L10n.text("log.portalEnvironment.settingsExported"),
                detail: exportRequest.fileURL.path
            )
        } catch {
            PortalEnvironmentTransferPanel.showError(error.localizedDescription)
            appendLog(
                level: .error,
                title: L10n.text("log.portalEnvironment.settingsExportFailed"),
                detail: error.localizedDescription
            )
        }
    }

    func importPortalEnvironmentSettings() {
        guard !isCaptionSessionActive else {
            return
        }

        guard let fileURL = PortalEnvironmentTransferPanel.importFileURL() else {
            return
        }

        do {
            let availableSections = try PortalEnvironmentSettings.availableImportSections(from: fileURL)
            guard let selectedSections = PortalEnvironmentTransferPanel.importSelection(
                availableSections: availableSections
            ) else {
                return
            }

            let importedSettings = try PortalEnvironmentSettings.importedConfiguration(
                from: fileURL,
                preservingLocalSettings: PortalEnvironmentSettings(
                    speechSettings: speechSettings,
                    relaySettings: relaySettings
                ),
                selection: selectedSections
            )
            speechSettings = importedSettings.speechSettings
            relaySettings = importedSettings.relaySettings
            speechSettings.save()
            relaySettings.save()
            if importedSettings.includedSections.includesAzureSpeechAuthorization {
                speechAuthorizationStatus = .initial(for: speechSettings)
                speechAuthorizationStatus.save()
            }
            if importedSettings.includedSections.includesAzureOpenAISettings {
                azureOpenAIConnectionStatus = .initial(for: speechSettings)
                azureOpenAIConnectionStatus.save()
            }
            if importedSettings.includedSections.includesRelayURL {
                relayConnectionStatus = .initial(for: relaySettings)
                relayConnectionStatus.save()
            }
            appendLog(level: .info, title: L10n.text("log.portalEnvironment.settingsImported"), detail: fileURL.path)
        } catch {
            PortalEnvironmentTransferPanel.showError(error.localizedDescription)
            appendLog(
                level: .error,
                title: L10n.text("log.portalEnvironment.settingsImportFailed"),
                detail: error.localizedDescription
            )
        }
    }
}
