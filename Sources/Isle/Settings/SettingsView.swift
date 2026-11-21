/*
 *  SettingsView.swift
 *  Isle
 *
 *  The Settings window's content: the search glass tint, with a live preview,
 *  plus general options.
 */

import ServiceManagement
import SwiftUI

struct SettingsView: View {

    let preferences: Preferences

    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: Binding(get: { preferences.islandStyle },
                                                   set: { style in
                                                       withAnimation(.islandMorph) { preferences.setIslandStyle(style) }
                                                   })) {
                    ForEach(IslandStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Island")
            } footer: {
                Text("Automatic grows the island out of the notch on MacBooks that have one, and floats it below the menu bar everywhere else.")
                    .foregroundStyle(.secondary)
            }

            Section("Search Glass") {
                GlassPreview(tint: preferences.glassTint)
                    .frame(height: 96)
                    .listRowInsets(EdgeInsets())

                Slider(value: Binding(get: { preferences.glassTint },
                                      set: { preferences.setGlassTint($0) }),
                       in: 0...1) {
                    Text("Tint")
                } minimumValueLabel: {
                    Text("Clear")
                } maximumValueLabel: {
                    Text("Solid")
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }

                LabeledContent("Open Search") {
                    Text("⌘ Space or ⌥ Space")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Preview

/** A miniature search bar over a colorful backdrop, so the tint's effect is visible immediately. */
private struct GlassPreview: View {

    let tint: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .purple, .blue],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            /* High-contrast stripes make the glass's refraction easy to see. */
            HStack(spacing: 14) {
                ForEach(0..<14, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.35)).frame(width: 5)
                }
            }
            .rotationEffect(.degrees(18))

            ZStack {
                LiquidGlass(cornerRadius: 22)
                Color.black.opacity(tint)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                    Spacer()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
            }
            .frame(width: 240, height: 44)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        }
        .clipped()
    }
}
