/*
 *  SearchView.swift
 *  Isle
 *
 *  The search field and its results list.
 */

import SwiftUI

struct SearchView: View {

    @Bindable var engine: SearchEngine
    let activate: (SearchResult) -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            resultsList
            Spacer(minLength: 0)
        }
        .onChange(of: engine.query) { engine.update() }
        .onAppear {
            /* Focus after the panel has become key. */
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            TextField("", text: $engine.query,
                      prompt: Text("Search apps, files, or do math").foregroundStyle(.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .focused($isFieldFocused)
        }
        .frame(height: SearchEngine.barHeight)
        .padding(.horizontal, 18)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                SearchResultRow(result: result, isSelected: index == engine.selectedIndex)
                    .onHover { hovering in
                        if hovering { engine.selectedIndex = index }
                    }
                    .onTapGesture { activate(result) }
                    .transition(.islandBlur)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Result Row

private struct SearchResultRow: View {

    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 26, height: 26)

            Text(result.title)
                .font(.system(size: 14, weight: result.kind == .calculation ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !result.subtitle.isEmpty {
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SearchEngine.rowHeight - 2)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.14 : 0))
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = result.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: result.symbolName ?? "questionmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
