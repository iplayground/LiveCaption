import AppKit
import SwiftUI

struct ClickFocusedTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onExitFocus: () -> Void

    func makeNSView(context: Context) -> MouseFocusedNSTextField {
        let textField = MouseFocusedNSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .medium)
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = text
        textField.onExitFocus = onExitFocus
        return textField
    }

    func updateNSView(_ nsView: MouseFocusedNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.placeholderString = placeholder
        nsView.onExitFocus = onExitFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text = textField.stringValue
        }
    }
}

final class MouseFocusedNSTextField: NSTextField {
    var onExitFocus: (() -> Void)?
    private var isHandlingMouseDown = false

    override var acceptsFirstResponder: Bool {
        isHandlingMouseDown
    }

    override func mouseDown(with event: NSEvent) {
        isHandlingMouseDown = true
        super.mouseDown(with: event)
        isHandlingMouseDown = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 48, 53:
            window?.makeFirstResponder(nil)
            onExitFocus?()
        default:
            super.keyDown(with: event)
        }
    }
}
