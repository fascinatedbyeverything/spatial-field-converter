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

    // MARK: - Body

    public var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 180, maxWidth: 240)

            mainView
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
        HStack {
            if let updated = index.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if index.isLoading {
                ProgressView().controlSize(.mini)
                Text("Loading…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await index.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(index.isLoading)
            .help("Re-download index + events from R2")
        }
        .padding(8)
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
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No events loaded")
                    .font(.callout)
                Text("Click Refresh to download the catalog from R2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh Now") {
                    Task { await index.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
                downloadError: downloadErrors[event.id]
            ) {
                Task { await togglePlay(event) }
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
    let onPlay: () -> Void

    // Category-derived: species events are "birdnet" or similar label-driven;
    // apple-soundanalysis events tend to be category-level labels.
    private var isSpeciesEvent: Bool {
        event.source == "birdnet" || event.scientific != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Play / stop button
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
            .help(isPlaying ? "Stop" : "Play from this timestamp")

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
