import AppKit
import UniformTypeIdentifiers

struct PortalEnvironmentExportRequest {
    var fileURL: URL
    var selection: PortalEnvironmentExportSelection
}

enum PortalEnvironmentTransferPanel {
    static func exportRequest() -> PortalEnvironmentExportRequest? {
        let savePanel = NSSavePanel()
        let accessory = PortalEnvironmentExportAccessory()
        savePanel.allowedContentTypes = [.json]
        savePanel.accessoryView = accessory.view
        savePanel.canCreateDirectories = true
        savePanel.message = L10n.text("portalEnvironment.transfer.export.message")
        savePanel.nameFieldStringValue = PortalEnvironmentSettings.configurationFileName
        savePanel.title = L10n.text("portalEnvironment.transfer.export.panelTitle")

        guard savePanel.runModal() == .OK,
              let fileURL = savePanel.url
        else {
            return nil
        }

        return PortalEnvironmentExportRequest(fileURL: fileURL, selection: accessory.selection)
    }

    static func importFileURL() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.message = L10n.text("portalEnvironment.transfer.import.message")
        openPanel.title = L10n.text("portalEnvironment.transfer.import.panelTitle")

        guard openPanel.runModal() == .OK else {
            return nil
        }

        return openPanel.url
    }

    static func importSelection(
        availableSections: PortalEnvironmentExportSelection
    ) -> PortalEnvironmentExportSelection? {
        PortalEnvironmentImportSelectionPanel(availableSections: availableSections).runModal()
    }

    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("portalEnvironment.transfer.error.alertTitle")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }
}

private final class PortalEnvironmentImportSelectionPanel {
    private let panel: NSPanel
    private let accessory: PortalEnvironmentSelectionAccessory
    private var accepted = false

    init(availableSections: PortalEnvironmentExportSelection) {
        accessory = PortalEnvironmentSelectionAccessory(
            title: L10n.text("portalEnvironment.transfer.import.optionsTitle"),
            availableSections: availableSections
        )
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 0),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("portalEnvironment.transfer.import.confirmTitle")
        panel.isReleasedWhenClosed = false
        panel.contentView = makeContentView()
    }

    func runModal() -> PortalEnvironmentExportSelection? {
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)

        return accepted ? accessory.selection : nil
    }

    private func makeContentView() -> NSView {
        let titleLabel = NSTextField(labelWithString: L10n.text("portalEnvironment.transfer.import.confirmTitle"))
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        let messageLabel = NSTextField(labelWithString: L10n.text("portalEnvironment.transfer.import.confirmMessage"))
        messageLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0

        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded

        let importButton = NSButton(
            title: L10n.text("portalEnvironment.transfer.import.confirmAction"),
            target: self,
            action: #selector(confirm)
        )
        importButton.bezelStyle = .rounded
        importButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [cancelButton, importButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12

        let spacer = NSView()
        let footerStack = NSStackView(views: [spacer, buttonStack])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY

        let contentStack = NSStackView(views: [
            titleLabel,
            messageLabel,
            accessory.view,
            footerStack,
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalToConstant: 480),
            buttonStack.widthAnchor.constraint(equalToConstant: 220),
        ])

        return contentView
    }

    @objc private func confirm() {
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        accepted = false
        NSApp.stopModal()
    }
}

private final class PortalEnvironmentExportAccessory: NSObject {
    private let selectionAccessory: PortalEnvironmentSelectionAccessory

    let view: NSView

    var selection: PortalEnvironmentExportSelection {
        selectionAccessory.selection
    }

    override init() {
        selectionAccessory = PortalEnvironmentSelectionAccessory(
            title: L10n.text("portalEnvironment.transfer.export.optionsTitle"),
            availableSections: .all
        )
        view = selectionAccessory.view
        super.init()
    }
}

private final class PortalEnvironmentSelectionAccessory: NSObject {
    let view: NSView
    private let azureSpeechAuthorizationButton: NSButton
    private let azureOpenAISettingsButton: NSButton
    private let captionOutputAndSegmentationButton: NSButton
    private let phraseHintsButton: NSButton
    private let relayURLButton: NSButton

    var selection: PortalEnvironmentExportSelection {
        PortalEnvironmentExportSelection(
            includesAzureSpeechAuthorization: azureSpeechAuthorizationButton.state == .on,
            includesAzureOpenAISettings: azureOpenAISettingsButton.state == .on,
            includesCaptionOutputAndSegmentation: captionOutputAndSegmentationButton.state == .on,
            includesPhraseHints: phraseHintsButton.state == .on,
            includesRelayURL: relayURLButton.state == .on
        )
    }

    init(title: String, availableSections: PortalEnvironmentExportSelection) {
        azureSpeechAuthorizationButton = NSButton(
            checkboxWithTitle: L10n.text("portalEnvironment.transfer.export.option.azureSpeechAuthorization"),
            target: nil,
            action: nil
        )
        azureOpenAISettingsButton = NSButton(
            checkboxWithTitle: L10n.text("portalEnvironment.transfer.export.option.azureOpenAI"),
            target: nil,
            action: nil
        )
        captionOutputAndSegmentationButton = NSButton(
            checkboxWithTitle: L10n.text("portalEnvironment.transfer.export.option.captionOutputAndSegmentation"),
            target: nil,
            action: nil
        )
        phraseHintsButton = NSButton(
            checkboxWithTitle: L10n.text("portalEnvironment.transfer.export.option.phraseHints"),
            target: nil,
            action: nil
        )
        relayURLButton = NSButton(
            checkboxWithTitle: L10n.text("portalEnvironment.transfer.export.option.relayURL"),
            target: nil,
            action: nil
        )

        Self.configure(azureSpeechAuthorizationButton, isAvailable: availableSections.includesAzureSpeechAuthorization)
        Self.configure(azureOpenAISettingsButton, isAvailable: availableSections.includesAzureOpenAISettings)
        Self.configure(
            captionOutputAndSegmentationButton,
            isAvailable: availableSections.includesCaptionOutputAndSegmentation
        )
        Self.configure(phraseHintsButton, isAvailable: availableSections.includesPhraseHints)
        Self.configure(relayURLButton, isAvailable: availableSections.includesRelayURL)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let stackView = NSStackView(views: [
            titleLabel,
            azureSpeechAuthorizationButton,
            azureOpenAISettingsButton,
            captionOutputAndSegmentationButton,
            phraseHintsButton,
            relayURLButton,
        ])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view = stackView

        super.init()
    }

    private static func configure(_ button: NSButton, isAvailable: Bool) {
        button.state = isAvailable ? .on : .off
        button.isEnabled = isAvailable
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
    }
}
