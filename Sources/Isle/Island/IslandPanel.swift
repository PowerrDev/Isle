/*
 *  IslandPanel.swift
 *  Isle
 *
 *  The borderless, transparent, non-activating panel that hosts the island. It
 *  floats above the menu bar on every Space, including full-screen ones, and
 *  never steals focus unless search explicitly asks for keyboard input.
 */

import AppKit

final class IslandPanel: NSPanel {

    /** When `true`, the panel may become key so the search field can receive typing. */
    var allowsKeyStatus = false

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }
}
