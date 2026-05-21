import AppKit
import IOKit.pwr_mgt
import SwiftUI

struct KeyboardEventBlocker: NSViewRepresentable {
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled = false
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .flagsChanged]
            ) { [weak self] event in
                self?.isEnabled == true ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else {
                return
            }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            removeMonitor()
        }
    }
}

final class SleepPreventionController {
    private var assertionIDs: [IOPMAssertionID] = []

    func startPreventingSleep() {
        guard assertionIDs.isEmpty else {
            return
        }

        assertionIDs = [
            createAssertion(type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString),
            createAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString),
        ].compactMap { $0 }
    }

    func stopPreventingSleep() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    deinit {
        stopPreventingSleep()
    }

    private func createAssertion(type: CFString) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LiveCaption Portal caption session" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            return nil
        }

        return assertionID
    }
}
