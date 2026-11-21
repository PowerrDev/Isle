/*
 *  IslandShape.swift
 *  Isle
 *
 *  The island's outline. Floating, it is a continuous-corner rounded rectangle.
 *  In the notch style its top edge is flush with the screen and concave ears
 *  flare outward, so it reads as an extension of the camera housing rather
 *  than an object placed beneath it.
 */

import SwiftUI

struct IslandShape: Shape {

    var isNotchStyle: Bool

    /** The concave flare at each top corner. Ignored in the floating style. */
    var earRadius: CGFloat

    /** The convex rounding at the bottom corners (and the top corners when floating). */
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, cornerRadius) }
        set {
            earRadius = newValue.first
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard isNotchStyle else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }

        let ear = min(earRadius, rect.width / 4, rect.height / 2)
        let corner = min(cornerRadius, rect.height - ear, (rect.width - ear * 2) / 2)

        /*
         Traced clockwise from the top-left, in SwiftUI's top-down coordinates:

             ⌒╮                    ╭⌒      ← ears curve from the screen edge into the body
               │                  │
               ╰──────────────────╯       ← rounded bottom corners
         */
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
                          control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + corner, y: rect.maxY),
                          control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - corner),
                          control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
