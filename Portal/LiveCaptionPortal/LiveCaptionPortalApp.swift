//
//  LiveCaptionPortalApp.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI
import AppKit
import Darwin

@main
struct LiveCaptionPortalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("LiveCaption Portal", id: "main") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var singleInstanceLockFileDescriptor: CInt = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock(), !isAnotherInstanceRunning else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard singleInstanceLockFileDescriptor >= 0 else {
            return
        }

        flock(singleInstanceLockFileDescriptor, LOCK_UN)
        close(singleInstanceLockFileDescriptor)
        singleInstanceLockFileDescriptor = -1
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func acquireSingleInstanceLock() -> Bool {
        let lockFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("io.iplayground.LiveCaptionPortal.lock")
        let fileDescriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard fileDescriptor >= 0 else {
            return false
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return false
        }

        singleInstanceLockFileDescriptor = fileDescriptor
        return true
    }

    private var isAnotherInstanceRunning: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentProcessIdentifier }
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }?
            .activate()
    }
}
