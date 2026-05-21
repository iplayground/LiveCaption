import AppKit
import SwiftUI

@MainActor
final class ProjectionCaptureWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var isClosingProgrammatically = false
    private let settingsInspectorHeight = 170.0
    private let frameStorageKey = "portal.projectionCaptureWindow"

    func update(
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage],
        captionPreviewState: SpeechCaptionPreviewState,
        isPresented: Bool,
        areConfigurationControlsLocked: Bool
    ) {
        guard isPresented else {
            close()
            return
        }

        let maximumContentWidth = Self.maximumContentWidth()
        let content = ProjectionCaptureWindowContent(
            inputLanguage: inputLanguage,
            outputLanguages: outputLanguages,
            captionPreviewState: captionPreviewState,
            maximumContentWidth: maximumContentWidth,
            settingsInspectorHeight: settingsInspectorHeight,
            areConfigurationControlsLocked: areConfigurationControlsLocked
        )

        if let window {
            window.contentView = NSHostingView(rootView: content)
            clearTextFieldFocus(in: window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize(maximumContentWidth: maximumContentWidth)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("caption.projectionWindow.title")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.contentView = NSHostingView(rootView: content)
        if !WindowFrameRestoration.restore(window: window, storageKey: frameStorageKey) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        clearTextFieldFocus(in: window)
        self.window = window
    }

    func close() {
        guard let window else {
            return
        }

        isClosingProgrammatically = true
        window.close()
        isClosingProgrammatically = false
        self.window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            WindowFrameRestoration.save(window: window, storageKey: frameStorageKey)
        }

        window = nil

        if !isClosingProgrammatically {
            UserDefaults.standard.set(
                ProjectionPreviewDisplayMode.inline.rawValue,
                forKey: "projectionCapture.displayMode"
            )
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        saveFrame(from: notification)
    }

    private func initialContentSize(maximumContentWidth: Double) -> NSSize {
        let storedWidth = UserDefaults.standard.double(forKey: "projectionCapture.width")
        let storedHeight = UserDefaults.standard.double(forKey: "projectionCapture.height")
        let width = min(
            max(storedWidth == 0 ? 720 : storedWidth, WindowLayout.projectionCaptureMinimumWidth),
            maximumContentWidth
        )
        let height = min(
            max(storedHeight == 0 ? 180 : storedHeight, WindowLayout.projectionCaptureMinimumHeight),
            WindowLayout.projectionCaptureMaximumHeight
        )

        return NSSize(width: width, height: height + settingsInspectorHeight)
    }

    private static func maximumContentWidth() -> Double {
        let visibleWidths = NSScreen.screens.map {
            Double($0.visibleFrame.width - (WindowLayout.projectionCaptureHorizontalPadding * 2))
        }

        return max(
            WindowLayout.projectionCaptureMinimumWidth,
            visibleWidths.max() ?? WindowLayout.projectionCaptureMinimumWidth
        )
    }

    private func saveFrame(from notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        WindowFrameRestoration.save(window: window, storageKey: frameStorageKey)
    }

    private func clearTextFieldFocus(in window: NSWindow) {
        window.makeFirstResponder(nil)
    }
}
