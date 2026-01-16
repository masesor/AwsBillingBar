import AppKit
import SwiftUI
import AwsBillingBarCore

/// Custom window that properly accepts keyboard focus in menu bar apps
private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Manages the settings window to ensure proper keyboard focus
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: BillingStore

    init(store: BillingStore) {
        self.store = store
    }

    func showSettings() {
        // Switch to regular app to receive keyboard focus
        NSApp.setActivationPolicy(.regular)

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let settingsView = SettingsView()
            .environment(store)

        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = KeyableWindow(contentViewController: hostingController)
        newWindow.title = "AWS Billing Bar Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 500, height: 420))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        newWindow.level = .normal
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }



    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // Switch back to accessory app when settings closes
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
