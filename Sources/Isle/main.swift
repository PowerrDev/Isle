/*
 *  main.swift
 *  Isle
 *
 *  The application entry point. Isle runs as an agent: it has no Dock icon, no
 *  visible menu bar, and no windows other than the island and, on demand, its
 *  Settings window.
 */

import AppKit

// MARK: - Application Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var islandController: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        islandController = IslandController()
    }
}

// MARK: - Edit Menu

/**
 Installs a hidden main menu containing the standard Edit commands.

 Agent applications never display a menu bar, but AppKit still routes
 ⌘A, ⌘C, ⌘V, ⌘X, and ⌘Z through the main menu's key equivalents. Without
 this menu, those shortcuts silently do nothing in the search field.
 */
private func installEditMenu() {
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        .keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let editItem = NSMenuItem()
    editItem.submenu = editMenu

    let mainMenu = NSMenu()
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
}

// MARK: - Launch

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
installEditMenu()
application.run()
