/*
 *  IslandView.swift
 *  Isle
 *
 *  The root view. It draws the island's shape, then swaps its content for the
 *  current mode. Size and corner radii are driven by the model, so a single
 *  spring animates the outline and the content together.
 */

import SwiftUI

struct IslandView: View {

    let model: IslandModel

    var body: some View {
        let metrics = model.metrics
        let mode = model.mode
        let isNotchStyle = model.usesNotchStyle
        let shape = IslandShape(isNotchStyle: isNotchStyle,
                                earRadius: metrics.earRadius,
                                cornerRadius: metrics.cornerRadius)

        content(for: mode, metrics: metrics)
            .padding(.horizontal, metrics.earRadius)
            .frame(width: metrics.size.width, height: metrics.size.height)
            .background {
                IslandBackground(shape: shape,
                                 isSearching: mode == .search,
                                 height: metrics.size.height,
                                 solidHeight: metrics.contentTopInset + SearchEngine.barHeight,
                                 cornerRadius: metrics.cornerRadius,
                                 tint: model.preferences.glassTint)
            }
            .overlay {
                /* A hairline rim keeps the floating island legible against dark wallpapers. */
                if !isNotchStyle {
                    shape.stroke(.white.opacity(0.08), lineWidth: 1)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture {
                if mode == .expanded { model.openSearch() }
            }
            .shadow(color: .black.opacity(shadowOpacity(for: mode, isNotchStyle: isNotchStyle)),
                    radius: shadowRadius(for: mode),
                    y: shadowRadius(for: mode) * 0.4)
            .contextMenu { IslandMenu(openSettings: model.openSettings) }
            .padding(.top, model.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(for mode: IslandMode, metrics: IslandMetrics) -> some View {
        ZStack(alignment: .top) {
            switch mode {
            case .idle:
                Color.clear
            case .music:
                MusicActivityView(nowPlaying: model.nowPlaying, height: metrics.size.height)
                    .transition(.islandBlur)
            case .charging:
                ChargingActivityView(battery: model.battery)
                    .transition(.islandBlur)
            case .expanded:
                NowPlayingCard(nowPlaying: model.nowPlaying)
                    .padding(.top, metrics.contentTopInset)
                    .transition(.islandBlur)
            case .search:
                SearchView(engine: model.search, activate: model.activate)
                    .padding(.top, metrics.contentTopInset)
                    .transition(.islandBlur)
            }
        }
    }

    private func shadowOpacity(for mode: IslandMode, isNotchStyle: Bool) -> Double {
        switch mode {
        case .idle: isNotchStyle ? 0 : 0.25   /* Over the housing the island must stay invisible. */
        case .music, .charging: isNotchStyle ? 0.2 : 0.45
        case .expanded, .search: 0.45
        }
    }

    private func shadowRadius(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle, .music, .charging: 5
        case .expanded: 14
        case .search: 20
        }
    }
}

// MARK: - Background

/**
 Solid black for the island's resting states. While searching, black covers
 only the housing and the search bar, then melts into Liquid Glass below.
 */
private struct IslandBackground: View {

    let shape: IslandShape
    let isSearching: Bool
    let height: CGFloat
    let solidHeight: CGFloat
    let cornerRadius: CGFloat
    let tint: Double

    private static let meltHeight: CGFloat = 26

    var body: some View {
        ZStack(alignment: .top) {
            if isSearching {
                Group {
                    LiquidGlass(cornerRadius: cornerRadius)
                    Color.black.opacity(tint)
                    specularRim
                }
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                Color.black
                    .frame(height: isSearching ? solidHeight : height)
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: isSearching ? Self.meltHeight : 0)
                Spacer(minLength: 0)
            }
        }
    }

    /** A bright edge fading toward the bottom, like light catching the glass. */
    private var specularRim: some View {
        shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)],
                                    startPoint: .top, endPoint: .bottom),
                     lineWidth: 2)
    }
}

// MARK: - Context Menu

private struct IslandMenu: View {

    let openSettings: () -> Void

    var body: some View {
        Button("Settings…", action: openSettings)
        Divider()
        Button("Quit Isle") { NSApp.terminate(nil) }
    }
}

// MARK: - Transitions

private struct IslandBlurModifier: ViewModifier {

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 5 : 0)
            .opacity(isActive ? 0 : 1)
            .scaleEffect(isActive ? 0.86 : 1, anchor: .top)
    }
}

extension AnyTransition {

    /** Content fades, blurs, and shrinks toward the top edge as the island reshapes. */
    static var islandBlur: AnyTransition {
        .modifier(active: IslandBlurModifier(isActive: true),
                  identity: IslandBlurModifier(isActive: false))
    }
}
