/*
 *  SearchEngine.swift
 *  Isle
 *
 *  A Spotlight-style search across applications, files, arithmetic, and the
 *  web.
 *
 *  Applications are indexed off the main thread when search opens and released
 *  when it closes. Files come from the existing Spotlight index through
 *  NSMetadataQuery, so Isle never crawls the disk.
 */

import AppKit
import SwiftUI

// MARK: - Result

struct SearchResult: Identifiable, Equatable {

    enum Kind {
        case calculation
        case application
        case file
        case web
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let url: URL?
    let icon: NSImage?
    let symbolName: String?

    /** A stable identity, so rows animate rather than being rebuilt on every keystroke. */
    var id: String { "\(kind):\(url?.path ?? title)" }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
}

// MARK: - Engine

@Observable
final class SearchEngine {

    // MARK: Layout

    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let maximumResultCount = 8
    private static let resultsBottomPadding: CGFloat = 14

    // MARK: State

    var query = ""
    var selectedIndex = 0
    private(set) var results: [SearchResult] = []

    /** The height the island needs to show the bar and every result. */
    var contentHeight: CGFloat {
        guard !results.isEmpty else { return Self.barHeight }
        return Self.barHeight + CGFloat(results.count) * Self.rowHeight + Self.resultsBottomPadding
    }

    var selectedResult: SearchResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    // MARK: Private State

    private struct Application {
        let name: String
        let lowercasedName: String
        let initials: String
        let url: URL
    }

    private static let fileSearchDelay: TimeInterval = 0.18
    private static let maximumApplicationResults = 4
    private static let maximumFileResults = 4

    @ObservationIgnored private var applications: [Application]?
    @ObservationIgnored private var isIndexingApplications = false
    @ObservationIgnored private var instantResults: [SearchResult] = []
    @ObservationIgnored private var fileResults: [SearchResult] = []
    @ObservationIgnored private var metadataQuery: NSMetadataQuery?
    @ObservationIgnored private var metadataObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingFileSearch: DispatchWorkItem?

    // MARK: Lifecycle

    /** Indexes applications in the background so the first keystroke is instant. */
    func prepare() {
        guard applications == nil, !isIndexingApplications else { return }
        isIndexingApplications = true

        DispatchQueue.global(qos: .userInitiated).async {
            let index = Self.indexApplications()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                applications = index
                isIndexingApplications = false
                if !trimmedQuery.isEmpty { update() }
            }
        }
    }

    /** Clears the query and releases everything search allocated. */
    func reset() {
        cancelFileSearch()
        query = ""
        selectedIndex = 0
        results = []
        instantResults = []
        fileResults = []
        applications = nil
    }

    // MARK: Querying

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /** Recomputes results for the current query. Call whenever `query` changes. */
    func update() {
        let query = trimmedQuery
        cancelFileSearch()
        fileResults = []
        selectedIndex = 0

        guard !query.isEmpty else {
            instantResults = []
            publish()
            return
        }

        var instant: [SearchResult] = []
        if let value = Calculator.evaluate(query) {
            instant.append(SearchResult(kind: .calculation, title: Calculator.format(value),
                                        subtitle: "Press Return to copy", url: nil,
                                        icon: nil, symbolName: "equal.circle.fill"))
        }
        instant += matchingApplications(for: query).map { application in
            SearchResult(kind: .application, title: application.name, subtitle: "Application",
                         url: application.url, icon: NSWorkspace.shared.icon(forFile: application.url.path),
                         symbolName: nil)
        }
        instantResults = instant
        publish()

        /* Debounce file searches so fast typing doesn't start a query per keystroke. */
        if query.count >= 2 {
            let search = DispatchWorkItem { [weak self] in self?.startFileSearch(for: query) }
            pendingFileSearch = search
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fileSearchDelay, execute: search)
        }
    }

    private func publish() {
        let query = trimmedQuery
        var combined = instantResults
        combined += fileResults.prefix(max(0, Self.maximumResultCount - 1 - combined.count))
        if !query.isEmpty {
            combined.append(SearchResult(kind: .web, title: "Search the web for “\(query)”", subtitle: "",
                                         url: nil, icon: nil, symbolName: "globe"))
        }
        guard combined != results else { return }
        withAnimation(.islandMorph) { results = combined }
    }

    // MARK: Selection

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + offset), results.count - 1)
    }

    func activate(_ result: SearchResult) {
        switch result.kind {
        case .application:
            if let url = result.url {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .file:
            if let url = result.url { NSWorkspace.shared.open(url) }
        case .calculation:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.title, forType: .string)
        case .web:
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
            if let url = components.url { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Applications

    private func matchingApplications(for query: String) -> [Application] {
        guard let applications else { return [] }
        let needle = query.lowercased()

        /* Lower scores rank higher: name prefix, word prefix, substring, then initials. */
        func score(_ application: Application) -> Int? {
            let name = application.lowercasedName
            if name.hasPrefix(needle) { return 0 }
            if name.contains(" " + needle) { return 1 }
            if name.contains(needle) { return 2 }
            if application.initials.hasPrefix(needle) { return 3 }
            return nil
        }

        typealias Match = (application: Application, score: Int)

        var matches: [Match] = []
        for application in applications {
            if let score = score(application) {
                matches.append((application, score))
            }
        }
        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.application.name.count < rhs.application.name.count
        }
        return matches.prefix(Self.maximumApplicationResults).map(\.application)
    }

    private static func indexApplications() -> [Application] {
        let directories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        let fileManager = FileManager.default
        let urls = directories.flatMap { directory in
            (try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: directory),
                                                  includingPropertiesForKeys: nil,
                                                  options: .skipsHiddenFiles)) ?? []
        } + [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

        var seenNames = Set<String>()
        var index: [Application] = []
        for url in urls where url.pathExtension == "app" {
            let name = url.deletingPathExtension().lastPathComponent
            guard seenNames.insert(name).inserted else { continue }
            let lowercased = name.lowercased()
            let initials = String(lowercased.split(separator: " ").compactMap(\.first))
            index.append(Application(name: name, lowercasedName: lowercased, initials: initials, url: url))
        }
        return index
    }

    // MARK: Files

    private func startFileSearch(for query: String) {
        let metadataQuery = NSMetadataQuery()
        metadataQuery.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(query)*")
        metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope]
        metadataQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        metadataObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: metadataQuery, queue: .main
        ) { [weak self] _ in
            self?.finishFileSearch(metadataQuery, for: query)
        }
        self.metadataQuery = metadataQuery
        metadataQuery.start()
    }

    private func finishFileSearch(_ metadataQuery: NSMetadataQuery, for query: String) {
        metadataQuery.disableUpdates()

        var found: [SearchResult] = []
        let home = NSHomeDirectory()
        for index in 0..<min(metadataQuery.resultCount, 40) where found.count < Self.maximumFileResults {
            guard let item = metadataQuery.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.hasSuffix(".app"), !path.contains("/Library/")
            else { continue }

            let url = URL(fileURLWithPath: path)
            let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
            found.append(SearchResult(kind: .file, title: url.lastPathComponent, subtitle: folder,
                                      url: url, icon: NSWorkspace.shared.icon(forFile: path), symbolName: nil))
        }

        cancelFileSearch()
        guard trimmedQuery == query else { return }
        fileResults = found
        publish()
    }

    private func cancelFileSearch() {
        pendingFileSearch?.cancel()
        pendingFileSearch = nil
        metadataQuery?.stop()
        metadataQuery = nil
        if let metadataObserver {
            NotificationCenter.default.removeObserver(metadataObserver)
            self.metadataObserver = nil
        }
    }
}
