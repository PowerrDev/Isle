/*
 *  IslandModel.swift
 *  Isle
 *
 *  The observable state of the island: which presentation is showing, how large
 *  it is, and the services that feed it. Views read from this model; only the
 *  controller and the services write to it.
 */

import SwiftUI

// MARK: - Presentation

/** The mutually exclusive presentations of the island, in priority order. */
enum IslandMode: Equatable {
    case idle
    case music
    case charging
    case expanded
    case search
}

/**
 The geometry of the island for a given mode.

 In the floating style the island is a rounded rectangle and `earRadius` is
 zero. In the notch style its top edge is flush with the screen and
 `earRadius` sizes the concave flares that blend it into the bezel.
 */
struct IslandMetrics: Equatable {
    var size: CGSize
    var cornerRadius: CGFloat
    var earRadius: CGFloat = 0

    /** The height reserved at the top for the camera housing; content starts below it. */
    var contentTopInset: CGFloat = 0
}

/** Fixed dimensions, in points, for each presentation. */
enum IslandLayout {
    static let idleSize = CGSize(width: 76, height: 23)
    static let liveSize = CGSize(width: 176, height: 28)
    static let expandedSize = CGSize(width: 340, height: 178)
    static let expandedCornerRadius: CGFloat = 38
    static let searchWidth: CGFloat = 500
}

// MARK: - Model

@Observable
final class IslandModel {

    // MARK: State

    var isExpanded = false
    var isSearching = false
    private(set) var isShowingChargingActivity = false

    // MARK: Display

    /** Whether the island's screen has a camera housing. */
    var hasCameraHousing = false

    /** The camera housing's size, or a stand-in matching the menu bar on displays without one. */
    var notchSize = CGSize(width: 185, height: 24)

    /** The gap above the island in the floating style. */
    var floatingTopInset: CGFloat = 5

    // MARK: Services

    let nowPlaying = NowPlaying()
    let battery = BatteryMonitor()
    let search = SearchEngine()
    let preferences = Preferences.shared

    // MARK: Actions

    /* Set by the controller; views invoke these without knowing about windows. */
    @ObservationIgnored var openSearch: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var activate: (SearchResult) -> Void = { _ in }

    @ObservationIgnored private var chargingDismissal: DispatchWorkItem?

    // MARK: Derived State

    var mode: IslandMode {
        if isSearching { return .search }
        if isExpanded { return .expanded }
        if isShowingChargingActivity { return .charging }
        if nowPlaying.isPlaying { return .music }
        return .idle
    }

    /** Whether the island grows out of the camera housing rather than floating below it. */
    var usesNotchStyle: Bool {
        switch preferences.islandStyle {
        case .automatic: hasCameraHousing
        case .notch: true
        case .floating: false
        }
    }

    /** The gap between the top of the screen and the island. */
    var topInset: CGFloat { usesNotchStyle ? 0 : floatingTopInset }

    var metrics: IslandMetrics { metrics(for: mode) }

    func metrics(for mode: IslandMode) -> IslandMetrics {
        usesNotchStyle ? notchMetrics(for: mode) : floatingMetrics(for: mode)
    }

    private func floatingMetrics(for mode: IslandMode) -> IslandMetrics {
        switch mode {
        case .idle:
            IslandMetrics(size: IslandLayout.idleSize,
                          cornerRadius: IslandLayout.idleSize.height / 2)
        case .music, .charging:
            IslandMetrics(size: IslandLayout.liveSize,
                          cornerRadius: IslandLayout.liveSize.height / 2)
        case .expanded:
            IslandMetrics(size: IslandLayout.expandedSize,
                          cornerRadius: IslandLayout.expandedCornerRadius)
        case .search:
            /* A radius of half the bar height makes the bar a perfect capsule. */
            IslandMetrics(size: CGSize(width: IslandLayout.searchWidth, height: search.contentHeight),
                          cornerRadius: SearchEngine.barHeight / 2)
        }
    }

    private func notchMetrics(for mode: IslandMode) -> IslandMetrics {
        let notch = notchSize

        switch mode {
        case .idle:
            /* Exactly covers the housing, so at rest the island is invisible. */
            let ear: CGFloat = 6
            return IslandMetrics(size: CGSize(width: notch.width + ear * 2, height: notch.height),
                                 cornerRadius: min(10, notch.height / 3), earRadius: ear)

        case .music, .charging:
            /* Live activities sit on wings either side of the housing. */
            let ear: CGFloat = 8
            let wing = notch.height + 18
            return IslandMetrics(size: CGSize(width: notch.width + (wing + ear) * 2, height: notch.height),
                                 cornerRadius: min(12, notch.height / 2.5), earRadius: ear)

        case .expanded:
            let ear: CGFloat = 14
            let width = max(IslandLayout.expandedSize.width, notch.width + 160) + ear * 2
            return IslandMetrics(size: CGSize(width: width, height: notch.height + IslandLayout.expandedSize.height - 10),
                                 cornerRadius: 34, earRadius: ear, contentTopInset: notch.height - 10)

        case .search:
            let ear: CGFloat = 14
            return IslandMetrics(size: CGSize(width: IslandLayout.searchWidth + ear * 2,
                                              height: notch.height + search.contentHeight),
                                 cornerRadius: SearchEngine.barHeight / 2, earRadius: ear,
                                 contentTopInset: notch.height)
        }
    }

    // MARK: Live Activities

    /** Briefly presents the charging activity, then returns to the previous mode. */
    func showChargingActivity(for duration: TimeInterval = 2.8) {
        chargingDismissal?.cancel()
        withAnimation(.islandMorph) { isShowingChargingActivity = true }

        let dismissal = DispatchWorkItem { [weak self] in
            withAnimation(.islandMorph) { self?.isShowingChargingActivity = false }
        }
        chargingDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
    }
}

// MARK: - Animations

extension Animation {

    /** Opening: quick, with a touch of overshoot. */
    static let islandOpen = Animation.spring(response: 0.42, dampingFraction: 0.68)

    /** Closing: settles without bouncing so the island tucks cleanly away. */
    static let islandClose = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /** Content-driven changes such as a live activity appearing. */
    static let islandMorph = Animation.spring(response: 0.5, dampingFraction: 0.72)
}
