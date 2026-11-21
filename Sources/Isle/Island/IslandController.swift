/*
 *  IslandController.swift
 *  Isle
 *
 *  Owns the island panel and translates system input into model changes.
 *
 *  The controller never polls. Work happens only in response to mouse movement,
 *  clicks, key presses, hot keys, and system notifications, which keeps Isle at
 *  effectively zero CPU while idle.
 */

import AppKit
import Darwin
import Carbon.HIToolbox
import SwiftUI

final class IslandController {

    // MARK: Properties

    /* Large enough for the tallest search state plus its shadow. */
    private static let canvasSize = CGSize(width: 640, height: 460)
    private static let collapseDelay: TimeInterval = 0.12

    private let model = IslandModel()
    private let panel = IslandPanel()
    private let settingsWindow = SettingsWindowController()

    private var screen: NSScreen
    private var eventMonitors: [Any] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var hotKeys: [HotKey] = []
    private var pendingCollapse: DispatchWorkItem?

    // MARK: Lifecycle

    init() {
        screen = Self.preferredScreen()

        let hostingView = NSHostingView(rootView: IslandView(model: model))
        hostingView.sizingOptions = []   /* The panel's size is fixed; SwiftUI must never resize it. */
        panel.contentView = hostingView

        layoutPanel()
        panel.orderFrontRegardless()

        connectModelActions()
        installEventMonitors()
        installHotKeys()
        observeSystemNotifications()
    }

    deinit {
        eventMonitors.forEach(NSEvent.removeMonitor)
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Setup

    private func connectModelActions() {
        model.openSearch = { [weak self] in self?.openSearch() }
        model.openSettings = { [weak self] in self?.openSettings() }
        model.activate = { [weak self] result in
            self?.model.search.activate(result)
            self?.closeSearch()
        }
        model.battery.onConnectToPower = { [weak self] in
            self?.model.showChargingActivity()
        }
    }

    private func installEventMonitors() {
        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]

        /* Hover tracking: global events cover other apps, local events cover our own panel. */
        addGlobalMonitor(pointerEvents) { [weak self] _ in self?.pointerDidMove() }
        addLocalMonitor(pointerEvents) { [weak self] event in
            self?.pointerDidMove()
            return event
        }

        /* A click anywhere else dismisses search. */
        addGlobalMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeSearch()
        }
        addLocalMonitor(.leftMouseDown) { [weak self] event in
            guard let self, model.isSearching,
                  !islandFrame().contains(NSEvent.mouseLocation) else { return event }
            closeSearch()
            return nil
        }

        /* Search navigation. */
        addLocalMonitor(.keyDown) { [weak self] event in
            guard let self, model.isSearching else { return event }
            return handleSearchKey(event) ? nil : event
        }
    }

    private func installHotKeys() {
        let toggleSearch: () -> Void = { [weak self] in
            guard let self else { return }
            model.isSearching ? closeSearch() : openSearch()
        }

        /*
         ⌘Space replaces Spotlight once its shortcut is disabled in System Settings.
         ⌥Space always works as a fallback.
         */
        hotKeys = [cmdKey, optionKey].compactMap { modifiers in
            HotKey(keyCode: kVK_Space, modifiers: modifiers, action: toggleSearch)
        }
    }

    private func observeSystemNotifications() {
        let center = NotificationCenter.default

        notificationObservers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screen = Self.preferredScreen()
            self?.layoutPanel()
        })

        /* Switching apps with ⌘Tab resigns the panel's key status. */
        notificationObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            self?.closeSearch()
        })
    }

    // MARK: Layout

    /** Prefers the built-in display with a camera housing, then the main display. */
    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layoutPanel() {
        let frame = screen.frame

        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            /* The housing occupies the gap between the two auxiliary menu bar areas. */
            model.hasCameraHousing = true
            model.notchSize = CGSize(width: frame.width - leftArea.width - rightArea.width,
                                     height: screen.safeAreaInsets.top)
            model.floatingTopInset = screen.safeAreaInsets.top + 4
        } else {
            /* No housing: stand in a menu-bar-height one for the notch style. */
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            model.hasCameraHousing = false
            model.notchSize = CGSize(width: 185, height: menuBarHeight > 0 ? menuBarHeight : 24)
            model.floatingTopInset = 5
        }

        let size = Self.canvasSize
        panel.setFrame(CGRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: false)
    }

    /** The island's current frame in screen coordinates. */
    private func islandFrame(for size: CGSize? = nil) -> CGRect {
        let size = size ?? model.metrics.size
        let frame = screen.frame
        return CGRect(x: frame.midX - size.width / 2,
                      y: frame.maxY - model.topInset - size.height,
                      width: size.width,
                      height: size.height)
    }

    /**
     The region that keeps the island open while the pointer is inside it.
     It extends to the top edge of the screen so flicking the pointer upward opens the island.
     */
    private func hoverRegion() -> CGRect {
        let size = model.isExpanded ? model.metrics(for: .expanded).size : model.metrics.size
        let margin: CGFloat = model.isExpanded ? 6 : 10
        let island = islandFrame(for: size).insetBy(dx: -margin, dy: 0)
        let bottom = island.minY - margin
        return CGRect(x: island.minX, y: bottom,
                      width: island.width, height: screen.frame.maxY - bottom + 1)
    }

    // MARK: Hover

    private func pointerDidMove() {
        guard !model.isSearching else { return }

        if hoverRegion().contains(NSEvent.mouseLocation) {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            if !model.isExpanded { setExpanded(true) }
            return
        }

        /* Never collapse mid-drag, for example while scrubbing the playback position. */
        let isDragging = NSEvent.pressedMouseButtons & 1 != 0
        guard model.isExpanded, pendingCollapse == nil, !isDragging else { return }

        let collapse = DispatchWorkItem { [weak self] in
            self?.pendingCollapse = nil
            self?.setExpanded(false)
        }
        pendingCollapse = collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: collapse)
    }

    private func setExpanded(_ expanded: Bool) {
        panel.ignoresMouseEvents = !expanded
        if expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(expanded ? .islandOpen : .islandClose) {
            model.isExpanded = expanded
        }
        if !expanded { scheduleMemoryRelief() }
    }

    // MARK: Memory

    /**
     Returns freed heap pages to the system once the closing animation has finished.

     The allocator otherwise keeps pages from search results, icons, and
     rendering buffers mapped, and they continue to count against Isle's footprint.
     */
    private func scheduleMemoryRelief() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !model.isExpanded, !model.isSearching else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    // MARK: Search

    private func openSearch() {
        guard !model.isSearching else { return }
        pendingCollapse?.cancel()
        pendingCollapse = nil

        model.search.prepare()
        panel.allowsKeyStatus = true
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)   /* Non-activating: the frontmost app stays frontmost. */

        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.islandOpen) { model.isSearching = true }
    }

    private func closeSearch() {
        guard model.isSearching else { return }

        withAnimation(.islandClose) {
            model.isSearching = false
            model.isExpanded = false
        }
        model.search.reset()

        panel.allowsKeyStatus = false
        panel.ignoresMouseEvents = true

        /* Reordering the panel returns keyboard focus to the previously active app. */
        panel.orderOut(nil)
        panel.orderFrontRegardless()

        pointerDidMove()
        scheduleMemoryRelief()
    }

    /** Returns `true` when the event was consumed. */
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case kVK_Escape:
            closeSearch()
        case kVK_DownArrow:
            model.search.moveSelection(by: 1)
        case kVK_UpArrow:
            model.search.moveSelection(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let result = model.search.selectedResult { model.activate(result) }
        case kVK_ANSI_Comma where modifiers == .command:
            openSettings()
        default:
            return false
        }
        return true
    }

    // MARK: Settings

    private func openSettings() {
        closeSearch()
        settingsWindow.show(preferences: model.preferences)
    }

    // MARK: Event Monitor Helpers

    private func addGlobalMonitor(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            eventMonitors.append(monitor)
        }
    }

    private func addLocalMonitor(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) {
            eventMonitors.append(monitor)
        }
    }
}
