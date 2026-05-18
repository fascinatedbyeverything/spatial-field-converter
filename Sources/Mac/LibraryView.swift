import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// LibraryView — search / browse / play detected sound events from the R2 archive.
// ---------------------------------------------------------------------------

public struct LibraryView: View {

    @EnvironmentObject private var index: R2CatalogIndex
    @StateObject private var player: PreviewPlayer = PreviewPlayer()

    // Active Set binding — mutations propagate to ContentView → ComposeView.
    @Binding var activeSet: SetData
    let setStore: SetStore

    // Search / filter state
    @State private var query: String = ""
    @State private var minConfidence: Double = 0.5
    @State private var selectedSourceSlug: String? = nil

    // Currently-playing event id
    @State private var playingEventID: UUID? = nil

    // Per-row download progress (slug → Bool)
    @State private var downloading: [String: Bool] = [:]
    @State private var downloadErrors: [UUID: String] = [:]

    // Gather state
    @State private var isGathering: Bool = false
    @State private var gatherProgress: String = ""
    @State private var gatherProgressFraction: Double = 0.0
    @State private var gatherError: String? = nil

    // Active Set picker — local slugs from SetStore
    @State private var localSetSlugs: [String] = []
    @State private var isSavingSet: Bool = false

    public init(activeSet: Binding<SetData>, setStore: SetStore) {
        self._activeSet = activeSet
        self.setStore = setStore
    }

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
                    ScriptView(sourceSlug: slug,
                               sourceCategory: source.sourceCategory,
                               activeSet: $activeSet)
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
            activeSetBar

            Divider()

            filtersBar

            Divider()

            if let err = index.loadError {
                errorBanner(err)
            }

            if filteredEvents.isEmpty && !index.isLoading {
                emptyState
            } else {
                resultsList
            }
        }
        .sheet(isPresented: $isGathering) {
            gatherProgressSheet
        }
        .onAppear {
            localSetSlugs = setStore.listLocalSlugs()
        }
    }

    // MARK: - Active Set bar

    private var activeSetBar: some View {
        HStack(spacing: 10) {
            Text("Set:")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Picker: in-progress set + any saved local sets
            Menu {
                Button {
                    // Keep current in-progress set (no-op on selection)
                } label: {
                    HStack {
                        Text(activeSet.name)
                        if localSetSlugs.isEmpty || !localSetSlugs.contains(activeSet.slug) {
                            Text("(in progress)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(true) // current item — just shows state

                if !localSetSlugs.isEmpty {
                    Divider()
                    ForEach(localSetSlugs, id: \.self) { slug in
                        Button(slug) {
                            if let loaded = try? setStore.loadLocal(slug: slug) {
                                activeSet = loaded
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(activeSet.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: 200)

            Button {
                // Generate a slug and reset
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let slug = "set-\(formatter.string(from: Date()))"
                activeSet = SetData(
                    name: "Untitled Set",
                    slug: slug,
                    createdAt: Date(),
                    updatedAt: Date(),
                    sources: [],
                    elements: [])
                localSetSlugs = setStore.listLocalSlugs()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("New empty Set")

            Button {
                isSavingSet = true
                do {
                    try setStore.saveLocal(activeSet)
                    localSetSlugs = setStore.listLocalSlugs()
                } catch {
                    // Swallow — UI has no alert here; real failure is auditable via SetStore
                }
                isSavingSet = false
            } label: {
                if isSavingSet {
                    ProgressView().controlSize(.mini)
                } else {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Save active Set locally")
            .disabled(isSavingSet)

            Spacer()

            // Element count badge
            if !activeSet.elements.isEmpty {
                Text("\(activeSet.elements.count) in Set")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Gather progress sheet

    private var gatherProgressSheet: some View {
        VStack(spacing: 18) {
            Text("Gathering Clips")
                .font(.headline)
            ProgressView(value: gatherProgressFraction)
                .frame(width: 280)
            Text(gatherProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(28)
        .frame(minWidth: 340)
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

            // Gather buttons
            Button {
                Task { await gatherToFolder() }
            } label: {
                Label("Gather…", systemImage: "folder.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filteredEvents.isEmpty || isGathering)
            .help("Slice each result into individual clips and save to a folder")

            Button {
                Task { await gatherAsSingleFile() }
            } label: {
                Label("Gather File…", systemImage: "waveform.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filteredEvents.isEmpty || isGathering)
            .help("Concatenate all result clips into one .m4a with silence between")

            // "Add all matching → Set" — only shown when a search query is active.
            if !query.isEmpty {
                Button {
                    addAllFilteredToSet()
                } label: {
                    Label("Add all → Set", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(filteredEvents.isEmpty)
                .help("Add all \(filteredEvents.count) visible result(s) to the active Set")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Add all filtered events to active Set

    private func addAllFilteredToSet() {
        let inputs = filteredEvents.map { event in
            IndexedEventInput(
                sourceSlug: event.sourceSlug,
                sourceCategory: event.sourceCategory,
                startSec: event.startSec,
                durationSec: event.durationSec,
                label: event.label,
                scientific: event.scientific,
                confidence: event.confidence)
        }
        LibrarySetBridge.addAll(indexedEvents: inputs,
                                 recordingCategory: inputs.first?.sourceCategory ?? "",
                                 to: &activeSet)
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
            } else if index.allEvents.isEmpty {
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
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No results")
                    .font(.callout)
                Text("Try a different search or lower the confidence threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var resultsList: some View {
        List(filteredEvents) { event in
            let input = IndexedEventInput(
                sourceSlug: event.sourceSlug,
                sourceCategory: event.sourceCategory,
                startSec: event.startSec,
                durationSec: event.durationSec,
                label: event.label,
                scientific: event.scientific,
                confidence: event.confidence)
            EventRow(
                event: event,
                isPlaying: playingEventID == event.id,
                isDownloading: downloading[event.sourceSlug] == true,
                downloadError: downloadErrors[event.id],
                isPlayingClip: playingClipEventID == event.id,
                isDownloadingClip: downloadingClip[event.id] == true,
                clipError: clipErrors[event.id],
                isInSet: LibrarySetBridge.contains(indexedEvent: input, in: activeSet)
            ) {
                Task { await togglePlay(event) }
            } onPlayClip: {
                Task { await togglePlayClip(event) }
            } onAddToSet: {
                LibrarySetBridge.add(indexedEvent: input,
                                      from: event.sourceCategory,
                                      to: &activeSet)
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

    // MARK: - Gather to Folder

    @MainActor
    private func gatherToFolder() async {
        let events = filteredEvents
        guard !events.isEmpty else { return }

        // Pick destination folder
        guard let folderURL = await showOpenPanelForFolder() else { return }

        isGathering = true
        gatherError = nil
        gatherProgress = "Starting…"
        gatherProgressFraction = 0

        defer {
            isGathering = false
            gatherProgress = ""
            gatherProgressFraction = 0
        }

        let total = events.count
        var bedCache: [String: URL] = [:]

        for (i, event) in events.enumerated() {
            gatherProgress = "Slicing \(i + 1) of \(total) — \(event.label)"
            gatherProgressFraction = Double(i) / Double(total)

            // Get bed.m4a (download once per slug)
            let bedURL: URL
            if let cached = bedCache[event.sourceSlug] {
                bedURL = cached
            } else {
                let (localBed, isLocal) = index.bedURL(for: event.sourceSlug,
                                                        category: event.sourceCategory)
                if isLocal {
                    bedURL = localBed
                    bedCache[event.sourceSlug] = localBed
                } else {
                    do {
                        let downloaded = try await index.downloadBed(slug: event.sourceSlug,
                                                                      category: event.sourceCategory)
                        bedURL = downloaded
                        bedCache[event.sourceSlug] = downloaded
                    } catch {
                        gatherProgress = "Download failed for \(event.sourceSlug): \(error.localizedDescription)"
                        continue
                    }
                }
            }

            let labelSlug = AudioSlicer.slugify(event.label)
            let confPct = Int(event.confidence * 100)
            let tStart = Int(event.startSec)
            let filename = "\(event.sourceSlug)__\(labelSlug)__t\(tStart)s__c\(String(format: "%03d", confPct)).m4a"
            let destURL = folderURL.appendingPathComponent(filename)

            let padded = 1.0
            let sliceStart = max(event.startSec - padded, 0)
            let sliceEnd = event.startSec + max(event.durationSec, 0.5) + padded

            do {
                try await AudioSlicer.slice(source: bedURL,
                                            startSec: sliceStart,
                                            endSec: sliceEnd,
                                            destination: destURL)
            } catch {
                // Non-fatal: log and continue
                print("[Gather] Slice failed for \(filename): \(error)")
            }
        }

        gatherProgress = "Done — \(total) clips saved"
        gatherProgressFraction = 1.0
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    // MARK: - Gather as Single File

    @MainActor
    private func gatherAsSingleFile() async {
        let events = filteredEvents
        guard !events.isEmpty else { return }

        guard let destURL = await showSavePanelM4A(defaultName: "gathered-clips.m4a") else { return }

        isGathering = true
        gatherError = nil
        gatherProgress = "Starting…"
        gatherProgressFraction = 0

        defer {
            isGathering = false
            gatherProgress = ""
            gatherProgressFraction = 0
        }

        // Determine cache dir: library-cache on external drive
        let cacheDir = PreferencesStore.stagingDirectory
            .appendingPathComponent("library-cache")
            .appendingPathComponent("gather-temp-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            gatherProgress = "Could not create temp directory: \(error.localizedDescription)"
            return
        }

        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        // Ensure silence clip
        let silenceURL = PreferencesStore.stagingDirectory
            .appendingPathComponent("library-cache")
            .appendingPathComponent("silence-1s-mono-48k.m4a")
        do {
            try await AudioSlicer.ensureSilenceClip(at: silenceURL)
        } catch {
            gatherProgress = "Silence generation failed: \(error.localizedDescription)"
            return
        }

        let total = events.count
        var clipURLs: [URL] = []
        var bedCache: [String: URL] = [:]

        // Sort events chronologically across all sources
        let sortedEvents = events.sorted { $0.startSec < $1.startSec }

        for (i, event) in sortedEvents.enumerated() {
            gatherProgress = "Slicing \(i + 1) of \(total) — \(event.label)"
            gatherProgressFraction = Double(i) / Double(total) * 0.9

            let bedURL: URL
            if let cached = bedCache[event.sourceSlug] {
                bedURL = cached
            } else {
                let (localBed, isLocal) = index.bedURL(for: event.sourceSlug,
                                                        category: event.sourceCategory)
                if isLocal {
                    bedURL = localBed
                    bedCache[event.sourceSlug] = localBed
                } else {
                    do {
                        let downloaded = try await index.downloadBed(slug: event.sourceSlug,
                                                                      category: event.sourceCategory)
                        bedURL = downloaded
                        bedCache[event.sourceSlug] = downloaded
                    } catch {
                        print("[Gather] Download failed for \(event.sourceSlug): \(error)")
                        continue
                    }
                }
            }

            let labelSlug = AudioSlicer.slugify(event.label)
            let clipURL = cacheDir.appendingPathComponent("\(String(format: "%05d", i))__\(labelSlug).m4a")

            let padded = 1.0
            let sliceStart = max(event.startSec - padded, 0)
            let sliceEnd = event.startSec + max(event.durationSec, 0.5) + padded

            do {
                try await AudioSlicer.slice(source: bedURL,
                                            startSec: sliceStart,
                                            endSec: sliceEnd,
                                            destination: clipURL)
                clipURLs.append(clipURL)
            } catch {
                print("[Gather] Slice failed: \(error)")
            }
        }

        guard !clipURLs.isEmpty else {
            gatherProgress = "No clips were sliced successfully."
            return
        }

        gatherProgress = "Concatenating \(clipURLs.count) clips…"
        gatherProgressFraction = 0.92

        do {
            try await AudioSlicer.concat(clips: clipURLs, silenceURL: silenceURL, destination: destURL)
        } catch {
            gatherProgress = "Concat failed: \(error.localizedDescription)"
            return
        }

        gatherProgress = "Done — \(clipURLs.count) clips concatenated"
        gatherProgressFraction = 1.0
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    // MARK: - Panels

    @MainActor
    private func showOpenPanelForFolder() async -> URL? {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose Folder"
            panel.message = "Select folder to save gathered clips"
            panel.begin { response in
                cont.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    @MainActor
    private func showSavePanelM4A(defaultName: String) async -> URL? {
        await withCheckedContinuation { cont in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = defaultName
            panel.allowedContentTypes = [.mpeg4Audio]
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.begin { response in
                cont.resume(returning: response == .OK ? panel.url : nil)
            }
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
    let isInSet: Bool
    let onPlay: () -> Void
    let onPlayClip: () -> Void
    let onAddToSet: () -> Void

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

            // Add to Set button
            Button(action: onAddToSet) {
                Image(systemName: isInSet ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isInSet ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isInSet ? "Already in Set" : "Add to active Set")
            .disabled(isInSet)
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
