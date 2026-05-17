import SwiftUI
import AVFoundation

// ---------------------------------------------------------------------------
// LibraryView — search / browse / play detected sound events from the R2 archive.
// ---------------------------------------------------------------------------

public struct LibraryView: View {

    @EnvironmentObject private var index: R2CatalogIndex
    @StateObject private var player: PreviewPlayer = PreviewPlayer()

    // Search / filter state
    @State private var query: String = ""
    @State private var minConfidence: Double = 0.5
    @State private var selectedSourceSlug: String? = nil

    // Currently-playing event id
    @State private var playingEventID: UUID? = nil

    // Per-row download progress (slug → Bool)
    @State private var downloading: [String: Bool] = [:]
    @State private var downloadErrors: [UUID: String] = [:]

    public init() {}

    // MARK: - Computed

    private var filteredEvents: [R2CatalogIndex.IndexedEvent] {
        index.filtered(query: query, minConfidence: minConfidence, sourceSlug: selectedSourceSlug)
    }

    private var sourceOptions: [R2CatalogIndex.SourceSummary] {
        index.sources
    }

    // Sample clip playback
    @State private var playingClipEventID: UUID? = nil
    @State private var downloadingClip: [UUID: Bool] = [:]
    @State private var clipErrors: [UUID: String] = [:]

    // MARK: - Body

    public var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 180, maxWidth: 240)

            if let slug = selectedSourceSlug,
               let source = sourceOptions.first(where: { $0.id == slug }) {
                // Vertical split: events list on top, script panel beneath
                VSplitView {
                    mainView
                    ScriptView(sourceSlug: slug, sourceCategory: source.sourceCategory)
                        .environmentObject(index)
                        .frame(minHeight: 180)
                }
            } else {
                mainView
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sourceRow(slug: nil, label: "All Recordings",
                              count: index.allEvents.count)

                    ForEach(sourceOptions) { source in
                        sourceRow(slug: source.id, label: source.id,
                                  count: eventCount(for: source.id))
                    }
                }
                .padding(8)
            }

            Spacer()

            Divider()

            refreshFooter
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func sourceRow(slug: String?, label: String, count: Int) -> some View {
        Button {
            selectedSourceSlug = slug
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectedSourceSlug == slug
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var refreshFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if index.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading catalog…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            } else if let updated = index.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            } else {
                Text("Not yet loaded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            }

            Button {
                Task { await index.refresh() }
            } label: {
                Label("Refresh Catalog", systemImage: "arrow.clockwise.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(index.isLoading)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Main area

    private var mainView: some View {
        VStack(spacing: 0) {
            filtersBar

            Divider()

            if let err = index.loadError {
                errorBanner(err)
            }

            if index.allEvents.isEmpty && !index.isLoading {
                emptyState
            } else {
                resultsList
            }
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search species, category, or recording…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .frame(maxWidth: 340)

            HStack(spacing: 6) {
                Text("Min conf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $minConfidence, in: 0...1, step: 0.05)
                    .frame(width: 100)
                Text(String(format: "%.0f%%", minConfidence * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            Spacer()

            Text("\(filteredEvents.count) result\(filteredEvents.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Export search results CSV
            Menu {
                Button("Export Results (.csv)") {
                    let csv = ExportService.buildSearchResultsCSV(events: filteredEvents)
                    ExportService.saveText(csv,
                                          defaultName: "search-results.csv",
                                          allowedExtension: "csv")
                }
                .disabled(filteredEvents.isEmpty)

                Button("Export Full Catalog (.csv)") {
                    let csv = ExportService.buildFullArchiveCSV(events: index.allEvents)
                    ExportService.saveText(csv,
                                          defaultName: "full-catalog.csv",
                                          allowedExtension: "csv")
                }
                .disabled(index.allEvents.isEmpty)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export results or full catalog as CSV")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if index.isLoading {
                ProgressView()
                Text("Downloading catalog from R2…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !query.isEmpty || minConfidence > 0 {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No results")
                    .font(.callout)
                Text("Try a different search or lower the confidence threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 4)
                Text("No recordings indexed")
                    .font(.title3.weight(.semibold))
                Text("Hit Refresh to load the field-recording catalog from R2.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button {
                    Task { await index.refresh() }
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var resultsList: some View {
        List(filteredEvents) { event in
            EventRow(
                event: event,
                isPlaying: playingEventID == event.id,
                isDownloading: downloading[event.sourceSlug] == true,
                downloadError: downloadErrors[event.id],
                isPlayingClip: playingClipEventID == event.id,
                isDownloadingClip: downloadingClip[event.id] == true,
                clipError: clipErrors[event.id]
            ) {
                Task { await togglePlay(event) }
            } onPlayClip: {
                Task { await togglePlayClip(event) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.inset)
    }

    // MARK: - Playback

    @MainActor
    private func togglePlay(_ event: R2CatalogIndex.IndexedEvent) async {
        // Stop if already playing this event
        if playingEventID == event.id {
            player.stop()
            playingEventID = nil
            return
        }

        // Stop whatever was playing
        player.stop()
        playingEventID = nil
        downloadErrors.removeValue(forKey: event.id)

        let slug = event.sourceSlug
        let category = event.sourceCategory

        // Check if bed.m4a is available locally
        let (bedURL, isLocal) = index.bedURL(for: slug, category: category)

        if !isLocal {
            // Need to download from R2
            downloading[slug] = true
            do {
                let downloadedURL = try await index.downloadBed(slug: slug, category: category)
                downloading[slug] = false
                try player.play(downloadedURL, startAt: event.startSec, autoStopAfter: event.durationSec)
                playingEventID = event.id
            } catch {
                downloading[slug] = false
                downloadErrors[event.id] = "Download failed: \(error.localizedDescription)"
                return
            }
        } else {
            do {
                try player.play(bedURL, startAt: event.startSec, autoStopAfter: event.durationSec)
                playingEventID = event.id
            } catch {
                downloadErrors[event.id] = "Playback failed: \(error.localizedDescription)"
                return
            }
        }

        // Watch for player stopping externally (auto-stop boundary or end of file)
        Task {
            while player.isPlaying { try? await Task.sleep(nanoseconds: 200_000_000) }
            if playingEventID == event.id { playingEventID = nil }
        }
    }

    @MainActor
    private func togglePlayClip(_ event: R2CatalogIndex.IndexedEvent) async {
        if playingClipEventID == event.id {
            player.stop()
            playingClipEventID = nil
            return
        }

        player.stop()
        playingEventID = nil
        playingClipEventID = nil
        clipErrors.removeValue(forKey: event.id)

        // Check local cache first
        let localClipURL = index.sampleClipLocalURL(event: event)
        let isLocal = FileManager.default.fileExists(atPath: localClipURL.path)

        let clipURL: URL
        if isLocal {
            clipURL = localClipURL
        } else {
            downloadingClip[event.id] = true
            do {
                clipURL = try await index.downloadSampleClip(event: event)
                downloadingClip[event.id] = false
            } catch {
                downloadingClip[event.id] = false
                clipErrors[event.id] = "Clip download failed: \(error.localizedDescription)"
                return
            }
        }

        do {
            try player.play(clipURL)
            playingClipEventID = event.id
        } catch {
            clipErrors[event.id] = "Clip playback failed: \(error.localizedDescription)"
            return
        }

        Task {
            while player.isPlaying { try? await Task.sleep(nanoseconds: 200_000_000) }
            if playingClipEventID == event.id { playingClipEventID = nil }
        }
    }

    // MARK: - Helpers

    private func eventCount(for slug: String) -> Int {
        index.allEvents.filter { $0.sourceSlug == slug }.count
    }
}

// ---------------------------------------------------------------------------
// EventRow — one search result row
// ---------------------------------------------------------------------------

private struct EventRow: View {
    let event: R2CatalogIndex.IndexedEvent
    let isPlaying: Bool
    let isDownloading: Bool
    let downloadError: String?
    let isPlayingClip: Bool
    let isDownloadingClip: Bool
    let clipError: String?
    let onPlay: () -> Void
    let onPlayClip: () -> Void

    // Category-derived: species events are "birdnet" or similar label-driven;
    // apple-soundanalysis events tend to be category-level labels.
    private var isSpeciesEvent: Bool {
        event.source == "birdnet" || event.scientific != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Source play / stop button
            Button(action: onPlay) {
                Group {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPlaying ? Color.accentColor : .primary)
            .help(isPlaying ? "Stop" : "Play source recording at this timestamp")

            // Sample clip play button — only for species events
            if isSpeciesEvent {
                Button(action: onPlayClip) {
                    Group {
                        if isDownloadingClip {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isPlayingClip ? "stop.circle.fill" : "play.circle")
                                .font(.system(size: 12))
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPlayingClip ? Color.orange : Color.secondary)
                .help(isPlayingClip ? "Stop clip" : "Play isolated sample clip")
            }

            // Main info
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSpeciesEvent ? Color.green : Color.primary)

                    if let sci = event.scientific {
                        Text(sci)
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(event.sourceSlug)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(formatTime(event.startSec))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.1fs", event.durationSec))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    confidenceView
                }

                if let err = downloadError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                if let err = clipError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .background(isPlaying ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }

    private var confidenceView: some View {
        HStack(spacing: 4) {
            Text(String(format: "%.0f%%", event.confidence * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.separatorColor))
                    Capsule()
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * event.confidence)
                }
            }
            .frame(width: 40, height: 4)
        }
    }

    private var confidenceColor: Color {
        switch event.confidence {
        case 0.8...: return .green
        case 0.5...: return .yellow
        default: return .orange
        }
    }

    private func formatTime(_ sec: Double) -> String {
        let totalSec = Int(sec)
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%d:%02d", m, s)
    }
}
