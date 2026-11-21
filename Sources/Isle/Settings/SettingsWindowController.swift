/*
 *  SettingsWindowController.swift
 *  Isle
 *
 *  Presents the Settings window. The window and its view hierarchy are created
 *  on demand and released when the window closes, so they cost no memory while
 *  unused.
 */

import AppKit
import SwiftUI

final class SettingsWindowController {

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show(preferences: Preferences) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(preferences: preferences))
            let window = NSWindow(contentViewController: controller)
            window.title = "Isle Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.release()
            }
            self.window = window
        }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func release() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        /* Defer so AppKit finishes closing before the window is deallocated. */
        DispatchQueue.main.async { [weak self] in self?.window = nil }
    }
}
