/*
 *  Components.swift
 *  Isle
 *
 *  Small reusable views: artwork, the animated waveform, and transport buttons.
 */

import SwiftUI

// MARK: - Artwork

/** Album artwork, falling back to the player's icon and then to a glyph. */
struct ArtworkView: View {

    let image: NSImage?
    let fallback: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.fill(.white.opacity(0.1))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if let fallback {
                Image(nsImage: fallback)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(cornerRadius * 0.5)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .clipShape(shape)
    }
}

// MARK: - Waveform

/**
 Five bars rising left to right, animated on the render server.

 While paused, the bars collapse to dots. Repeating animations run in Core
 Animation rather than in our process, so the waveform costs almost no CPU.
 */
struct WaveformView: View {

    let isPlaying: Bool
    let color: Color

    private static let peaks: [CGFloat] = [0.3, 0.45, 0.7, 0.85, 1.0]
    private static let periods: [Double] = [0.38, 0.46, 0.33, 0.52, 0.41]
    private static let spacing: CGFloat = 2

    @State private var isRaised = false

    var body: some View {
        GeometryReader { geometry in
            let count = Self.peaks.count
            let barWidth = max(2, (geometry.size.width - Self.spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(spacing: Self.spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth,
                               height: barHeight(at: index, maximum: geometry.size.height, minimum: barWidth))
                        .animation(animation(at: index), value: isRaised)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .id(isPlaying)   /* Restart the repeating animations cleanly when playback toggles. */
        .onAppear { isRaised = isPlaying }
    }

    private func barHeight(at index: Int, maximum: CGFloat, minimum: CGFloat) -> CGFloat {
        guard isPlaying else { return minimum }
        let peak = maximum * Self.peaks[index]
        return isRaised ? peak : max(minimum, peak * 0.35)
    }

    private func animation(at index: Int) -> Animation {
        isPlaying
            ? .easeInOut(duration: Self.periods[index]).repeatForever(autoreverses: true)
            : .spring(response: 0.35, dampingFraction: 0.8)
    }
}

// MARK: - Transport Button

/** A playback control with a squircle hover highlight and a springy press. */
struct TransportButton: View {

    let symbolName: String
    let pointSize: CGFloat
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        /* A continuous-corner rounded rectangle at 30% of its side reads as a squircle. */
        let side = pointSize * 2
        let squircle = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)

        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
            }
            action()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: pointSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(squircle.fill(.white.opacity(isHovering ? 0.14 : 0)))
                .scaleEffect(isPressed ? 0.84 : 1)
                .contentShape(squircle)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isHovering = hovering }
        }
    }
}
