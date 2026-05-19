import SwiftUI

struct PortalEnvironmentTransferActions {
    var canImport: Bool
    var importSettings: () -> Void
    var exportSettings: () -> Void
}

private struct PortalEnvironmentTransferActionsKey: FocusedValueKey {
    typealias Value = PortalEnvironmentTransferActions
}

extension FocusedValues {
    var portalEnvironmentTransferActions: PortalEnvironmentTransferActions? {
        get { self[PortalEnvironmentTransferActionsKey.self] }
        set { self[PortalEnvironmentTransferActionsKey.self] = newValue }
    }
}

struct PortalEnvironmentCommands: Commands {
    @FocusedValue(\.portalEnvironmentTransferActions) private var transferActions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L10n.text("portalEnvironment.transfer.import.menuTitle")) {
                transferActions?.importSettings()
            }
            .disabled(transferActions?.canImport != true)

            Button(L10n.text("portalEnvironment.transfer.export.menuTitle")) {
                transferActions?.exportSettings()
            }
            .disabled(transferActions == nil)

            Divider()
        }
    }
}
