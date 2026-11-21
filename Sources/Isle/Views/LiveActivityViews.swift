/*
 *  LiveActivityViews.swift
 *  Isle
 *
 *  The compact live activities shown in the collapsed island: now playing and
 *  charging. Content hugs the leading and trailing edges, so in the notch
 *  style it lands on the wings either side of the camera housing.
 */

import SwiftUI

// MARK: - Music

/** Album artwork on the leading edge and a waveform tinted to match it on the trailing edge. */
struct MusicActivityView: View {

    let nowPlaying: NowPlaying
    let height: CGFloat

    private static let inset: CGFloat = 4

    var body: some View {
        let artworkSide = height - Self.inset * 2

        HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, fallback: nowPlaying.playerIcon,
                        cornerRadius: artworkSide * 0.28)
                .frame(width: artworkSide, height: artworkSide)

            Spacer(minLength: 0)

            WaveformView(isPlaying: nowPlaying.isPlaying, color: nowPlaying.accentColor)
                .frame(width: 22, height: min(13, height * 0.46))
        }
        .padding(.leading, Self.inset + 1)
        .padding(.trailing, 12)
        .frame(height: height)
    }
}

// MARK: - Charging

struct ChargingActivityView: View {

    let battery: BatteryMonitor

    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
            Spacer(minLength: 0)
            Text(battery.level, format: .percent.scale(1))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 13)
        .frame(maxHeight: .infinity)
    }
}
