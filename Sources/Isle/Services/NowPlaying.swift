/*
 *  NowPlaying.swift
 *  Isle
 *
 *  Tracks playback in Music and Spotify through the distributed notifications
 *  both apps broadcast on every state change. This uses no private frameworks
 *  and no polling.
 *
 *  The playback position is extrapolated from the last known anchor, so nothing
 *  ticks while the island is collapsed. Artwork is fetched once per track,
 *  downsampled to a small thumbnail, and reduced to a single accent color.
 */

import AppKit
import ImageIO
import SwiftUI

@Observable
final class NowPlaying {

    // MARK: Track State

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var isPlaying = false
    private(set) var playerBundleIdentifier: String?
    private(set) var playerIcon: NSImage?

    /** The album artwork, downsampled to `artworkPixelSize`. */
    private(set) var artwork: NSImage?

    /** A legible tint derived from the artwork, used for the waveform. */
    private(set) var accentColor = Color.white

    /** The track length in seconds, or `0` when unknown. */
    private(set) var duration: TimeInterval = 0

    var hasTrack: Bool { !title.isEmpty }

    // MARK: Private State

    private static let artworkPixelSize = 96

    private static let players: [(notification: String, bundleIdentifier: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    /* An ephemeral session with no URL cache keeps artwork downloads out of memory. */
    private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    @ObservationIgnored private var anchorPosition: TimeInterval = 0
    @ObservationIgnored private var anchorDate = Date()
    @ObservationIgnored private var artworkTrackKey = ""
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let scripts = ScriptRunner()

    // MARK: Lifecycle

    init() {
        let center = DistributedNotificationCenter.default()
        for player in Self.players {
            observers.append(center.addObserver(
                forName: .init(player.notification), object: nil, queue: .main
            ) { [weak self] notification in
                self?.playerDidChange(notification.userInfo ?? [:], bundleIdentifier: player.bundleIdentifier)
            })
        }
    }

    deinit {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
    }

    // MARK: Position

    /** The extrapolated playback position at `date`, clamped to the track length. */
    func position(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? date.timeIntervalSince(anchorDate) : 0
        let position = max(0, anchorPosition + elapsed)
        return duration > 0 ? min(position, duration) : position
    }

    private func setAnchor(_ position: TimeInterval) {
        anchorPosition = position
        anchorDate = Date()
    }

    // MARK: Notifications

    private func playerDidChange(_ info: [AnyHashable: Any], bundleIdentifier: String) {
        let state = info["Player State"] as? String ?? ""
        let currentPosition = position(at: Date())

        withAnimation(.islandMorph) {
            guard state != "Stopped" else {
                if playerBundleIdentifier == bundleIdentifier { clearTrack() }
                return
            }

            let newTitle = info["Name"] as? String ?? title
            let trackChanged = newTitle != title || playerBundleIdentifier != bundleIdentifier

            title = newTitle
            artist = info["Artist"] as? String ?? ""
            isPlaying = state == "Playing"

            /* Spotify reports Duration (ms) and Playback Position (s); Music reports Total Time (ms). */
            if let milliseconds = Self.number(info["Duration"] ?? info["Total Time"]) {
                duration = milliseconds / 1000
            }
            if let seconds = Self.number(info["Playback Position"]) {
                setAnchor(seconds)
            } else {
                setAnchor(trackChanged ? 0 : currentPosition)
            }

            if playerBundleIdentifier != bundleIdentifier {
                playerBundleIdentifier = bundleIdentifier
                playerIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
            }

            if trackChanged {
                artwork = nil
                accentColor = .white
            }
        }

        /* Give the player a moment to update its current track before asking for artwork. */
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.loadArtworkIfNeeded()
        }
    }

    private func clearTrack() {
        isPlaying = false
        title = ""
        artist = ""
        artwork = nil
        accentColor = .white
        duration = 0
        artworkTrackKey = ""
        setAnchor(0)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let integer as Int: Double(integer)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }

    // MARK: Transport

    func togglePlayback() {
        setAnchor(position(at: Date()))
        isPlaying.toggle()
        send("playpause")
    }

    func skipForward() { send("next track") }

    func skipBackward() { send("previous track") }

    /** Moves playback to `seconds` and updates the local anchor immediately. */
    func seek(to seconds: TimeInterval) {
        guard let identifier = playerBundleIdentifier else { return }
        let target = duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
        setAnchor(target)
        scripts.run("tell application id \"\(identifier)\" to set player position to "
                    + String(format: "%.2f", target), cacheable: false)
    }

    /** Re-reads the exact position from the player. Called when the expanded card appears. */
    func synchronizePosition() {
        guard let identifier = playerBundleIdentifier, hasTrack,
              let seconds = scripts.run("tell application id \"\(identifier)\" to get player position")?.doubleValue
        else { return }
        setAnchor(seconds)
    }

    private func send(_ command: String) {
        guard let identifier = playerBundleIdentifier else { return }
        scripts.run("tell application id \"\(identifier)\" to \(command)")
    }

    // MARK: Artwork

    private func loadArtworkIfNeeded() {
        guard let identifier = playerBundleIdentifier, hasTrack else { return }
        let trackKey = identifier + "\u{1F}" + title + "\u{1F}" + artist
        guard trackKey != artworkTrackKey else { return }
        artworkTrackKey = trackKey

        if identifier == "com.spotify.client" {
            guard let address = scripts.run("tell application id \"\(identifier)\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: address) else { return }

            Self.artworkSession.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let thumbnail = Self.thumbnail(from: data) else { return }
                DispatchQueue.main.async {
                    guard self?.artworkTrackKey == trackKey else { return }
                    self?.applyArtwork(thumbnail)
                }
            }.resume()
        } else if let data = scripts.run("tell application id \"\(identifier)\" to get raw data of artwork 1 of current track")?.data {
            /* Decoding is the expensive part, so do it off the main thread. */
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let thumbnail = Self.thumbnail(from: data) else { return }
                DispatchQueue.main.async {
                    guard self?.artworkTrackKey == trackKey else { return }
                    self?.applyArtwork(thumbnail)
                }
            }
        }
    }

    private func applyArtwork(_ image: CGImage) {
        withAnimation(.easeOut(duration: 0.25)) {
            artwork = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            accentColor = Self.accentColor(of: image)
        }
    }

    /** Decodes straight to a small thumbnail; the full-size cover is never held in memory. */
    private static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkPixelSize,
        ] as CFDictionary)
    }

    /** Averages the artwork to one pixel, then lifts it so it reads clearly on black. */
    private static func accentColor(of image: CGImage) -> Color {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return .white }

        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255,
                              green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255,
                              alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(hue: hue, saturation: min(saturation, 0.5), brightness: max(brightness, 0.8))
    }
}
