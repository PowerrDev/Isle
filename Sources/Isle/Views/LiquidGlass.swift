/*
 *  LiquidGlass.swift
 *  Isle
 *
 *  Bridges AppKit's Liquid Glass into SwiftUI.
 *
 *  On macOS 26 and later this uses NSGlassEffectView; earlier systems fall back
 *  to a behind-window NSVisualEffectView. Both sample the desktop behind the
 *  panel, which SwiftUI materials can't do inside a transparent window.
 */

import AppKit
import SwiftUI

struct LiquidGlass: NSViewRepresentable {

    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .clear   /* The more refractive, see-through variant. */
            glassView.cornerRadius = cornerRadius
            return glassView
        }

        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        return effectView
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = view as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }
}
