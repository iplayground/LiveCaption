import AppKit
import SwiftUI

@MainActor
final class ProjectionSettingsPanelPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 330, height: 500)
    private let minimumPanelHeight: CGFloat = 320
    private let panelMargin: CGFloat = 12

    func show(
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage],
        captionPreviewState: SpeechCaptionPreviewState
    ) {
        let maximumWidth = Self.currentProjectionCaptureMaximumWidth()

        if let panel {
            panel.contentView = NSHostingView(
                rootView: ProjectionCaptureSettingsInspector(
                    inputLanguage: inputLanguage,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState,
                    maximumWidth: maximumWidth
                )
            )
            positionPanelAvoidingProjectionCapture(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = L10n.text("projectionSettings.title")
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: ProjectionCaptureSettingsInspector(
                inputLanguage: inputLanguage,
                outputLanguages: outputLanguages,
                captionPreviewState: captionPreviewState,
                maximumWidth: maximumWidth
            )
        )
        positionPanelAvoidingProjectionCapture(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    private static func currentProjectionCaptureMaximumWidth() -> Double {
        let window = currentMainWindow()

        return WindowLayout.projectionCaptureMaximumWidth(
            for: window?.contentLayoutRect.width ?? WindowLayout.minimumSize.width
        )
    }

    private static func currentMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && window.isVisible
        } ?? NSApp.mainWindow ?? NSApp.keyWindow
    }

    private func positionPanelAvoidingProjectionCapture(_ panel: NSPanel) {
        guard let mainWindow = Self.currentMainWindow() else {
            panel.center()
            return
        }

        let screenFrame = mainWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? mainWindow.frame
        let projectionFrame = currentProjectionCaptureFrame(in: mainWindow)
        let panelHeight = preferredPanelHeight(avoiding: projectionFrame, on: screenFrame)
        let panelSize = NSSize(width: panelSize.width, height: panelHeight)
        panel.setContentSize(panelSize)

        let candidates = preferredPanelOrigins(
            for: panelSize,
            avoiding: projectionFrame,
            in: mainWindow,
            on: screenFrame
        )

        let panelOrigin = candidates.first { origin in
            let frame = NSRect(origin: origin, size: panelSize)
            return screenFrame.contains(frame) && !frame.intersects(projectionFrame)
        } ?? fallbackPanelOrigin(
            for: panelSize,
            avoiding: projectionFrame,
            on: screenFrame
        )

        panel.setFrame(NSRect(origin: panelOrigin, size: panelSize), display: true)
    }

    private func currentProjectionCaptureFrame(in window: NSWindow) -> NSRect {
        let contentFrame = window.contentLayoutRect
        let storedWidth = UserDefaults.standard.double(forKey: "projectionCapture.width")
        let storedHeight = UserDefaults.standard.double(forKey: "projectionCapture.height")
        let maximumWidth = WindowLayout.projectionCaptureMaximumWidth(for: contentFrame.width)
        let width = min(
            max(storedWidth == 0 ? 720 : storedWidth, WindowLayout.projectionCaptureMinimumWidth),
            maximumWidth
        )
        let height = min(
            max(storedHeight == 0 ? 180 : storedHeight, WindowLayout.projectionCaptureMinimumHeight),
            WindowLayout.projectionCaptureMaximumHeight
        )
        let x = contentFrame.minX + WindowLayout.projectionCaptureHorizontalPadding
        let y = contentFrame.maxY
            - WindowLayout.headerEstimatedHeight
            - WindowLayout.projectionCaptureVerticalPadding
            - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func preferredPanelHeight(avoiding projectionFrame: NSRect, on screenFrame: NSRect) -> CGFloat {
        let availableBelowProjection = projectionFrame.minY - screenFrame.minY - (panelMargin * 2)

        if availableBelowProjection >= minimumPanelHeight {
            return min(panelSize.height, availableBelowProjection)
        }

        return panelSize.height
    }

    private func preferredPanelOrigins(
        for panelSize: NSSize,
        avoiding projectionFrame: NSRect,
        in window: NSWindow,
        on screenFrame: NSRect
    ) -> [NSPoint] {
        let contentFrame = window.contentLayoutRect
        let preferredX = clamped(
            contentFrame.maxX - panelSize.width - 24,
            min: screenFrame.minX + panelMargin,
            max: screenFrame.maxX - panelSize.width - panelMargin
        )
        let sideY = clamped(
            projectionFrame.maxY - panelSize.height,
            min: screenFrame.minY + panelMargin,
            max: screenFrame.maxY - panelSize.height - panelMargin
        )

        return [
            NSPoint(x: preferredX, y: projectionFrame.minY - panelSize.height - panelMargin),
            NSPoint(x: projectionFrame.maxX + panelMargin, y: sideY),
            NSPoint(x: projectionFrame.minX - panelSize.width - panelMargin, y: sideY),
            NSPoint(x: preferredX, y: screenFrame.minY + panelMargin)
        ]
    }

    private func fallbackPanelOrigin(
        for panelSize: NSSize,
        avoiding projectionFrame: NSRect,
        on screenFrame: NSRect
    ) -> NSPoint {
        let belowY = min(
            projectionFrame.minY - panelSize.height - panelMargin,
            screenFrame.maxY - panelSize.height - panelMargin
        )

        return NSPoint(
            x: screenFrame.maxX - panelSize.width - panelMargin,
            y: max(screenFrame.minY + panelMargin, belowY)
        )
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }

        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
