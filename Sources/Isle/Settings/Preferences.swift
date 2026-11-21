/*
 *  Preferences.swift
 *  Isle
 *
 *  User preferences, persisted in UserDefaults and observed by the island so
 *  changes apply live.
 */

import Foundation

/** How the island is presented on screen. */
enum IslandStyle: String, CaseIterable, Identifiable {

    /** The notch style on displays with a camera housing, otherwise floating. */
    case automatic

    /** Grows out of the camera housing, flush with the top of the screen. */
    case notch

    /** A free-standing pill just below the top of the screen. */
    case floating

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .notch: "Notch"
        case .floating: "Floating"
        }
    }
}

@Observable
final class Preferences {

    static let shared = Preferences()

    private enum Key {
        static let glassTint = "GlassTint"
        static let islandStyle = "IslandStyle"
    }

    /** The island's presentation. */
    private(set) var islandStyle: IslandStyle

    /**
     How opaque the search glass is, from `0` (clear Liquid Glass)
     to `1` (solid black).
     */
    private(set) var glassTint: Double

    private init() {
        glassTint = UserDefaults.standard.object(forKey: Key.glassTint) as? Double ?? 0
        islandStyle = UserDefaults.standard.string(forKey: Key.islandStyle)
            .flatMap(IslandStyle.init(rawValue:)) ?? .automatic
    }

    func setIslandStyle(_ style: IslandStyle) {
        islandStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Key.islandStyle)
    }

    func setGlassTint(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        glassTint = clamped
        UserDefaults.standard.set(clamped, forKey: Key.glassTint)
    }
}
