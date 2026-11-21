/*
 *  NowPlayingCard.swift
 *  Isle
 *
 *  The expanded now-playing card: artwork, track details, a scrubbable progress
 *  bar, and transport controls.
 */

import SwiftUI

struct NowPlayingCard: View {

    let nowPlaying: NowPlaying

    var body: some View {
        VStack(spacing: 0) {
            header
            PlaybackScrubber(nowPlaying: nowPlaying)
                .padding(.top, 12)
            transportControls
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .onAppear {
            /* Let the opening spring settle before asking the player for its exact position. */
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                nowPlaying.synchronizePosition()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(image: nowPlaying.artwork, fallback: nowPlaying.playerIcon, cornerRadius: 10)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.hasTrack ? nowPlaying.title : "Not Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(nowPlaying.hasTrack ? nowPlaying.artist : "Music or Spotify")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            .contentTransition(.opacity)

            Spacer(minLength: 6)

            WaveformView(isPlaying: nowPlaying.isPlaying, color: nowPlaying.accentColor)
                .frame(width: 20, height: 14)
        }
    }

    private var transportControls: some View {
        let isAvailable = nowPlaying.playerBundleIdentifier != nil

        return HStack(spacing: 30) {
            TransportButton(symbolName: "backward.fill", pointSize: 19, action: nowPlaying.skipBackward)
            TransportButton(symbolName: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                            pointSize: 26, action: nowPlaying.togglePlayback)
            TransportButton(symbolName: "forward.fill", pointSize: 19, action: nowPlaying.skipForward)
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.35)
    }
}

// MARK: - Scrubber

/**
 A progress bar the user can click or drag to seek.

 The timeline ticks once per second only while the card is visible and music
 is playing; otherwise it effectively never fires.
 */
private struct PlaybackScrubber: View {

    let nowPlaying: NowPlaying

    @State private var scrubPosition: TimeInterval?
    @State private var isHovering = false

    private var isActive: Bool { isHovering || scrubPosition != nil }

    var body: some View {
        let isTicking = nowPlaying.isPlaying && scrubPosition == nil

        TimelineView(.periodic(from: .now, by: isTicking ? 1 : 3600)) { context in
            let duration = nowPlaying.duration
            let position = scrubPosition ?? nowPlaying.position(at: context.date)

            HStack(spacing: 8) {
                Text(Self.timestamp(position))
                    .frame(width: 34, alignment: .leading)

                track(position: position, duration: duration)

                Text(duration > 0 ? "−" + Self.timestamp(duration - position) : "−:––")
                    .frame(width: 38, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(isActive ? 0.75 : 0.5))
        }
    }

    private func track(position: TimeInterval, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let fraction = duration > 0 ? position / duration : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.85))
                    .frame(width: geometry.size.width * fraction)
                    .animation(scrubPosition == nil ? .linear(duration: 1) : nil, value: position)
            }
            .frame(height: isActive ? 8 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, geometry.size.width > 0 else { return }
                        let fraction = min(max(0, value.location.x / geometry.size.width), 1)
                        scrubPosition = fraction * duration
                    }
                    .onEnded { _ in
                        if let scrubPosition { nowPlaying.seek(to: scrubPosition) }
                        scrubPosition = nil
                    }
            )
        }
        .frame(height: 16)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isHovering = hovering }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
