import SwiftUI
import AVFoundation
import AppKit

// ---------------------------------------------------------------------------
// ScriptView — per-recording timeline narrative rendered from timeline.json.
// Shows chronological events grouped by scene, with per-event play buttons
// that seek the bed.m4a to that timestamp, plus per-event and per-scene save.
// ---------------------------------------------------------------------------

@MainActor
public struct ScriptView: View {

    let sourceSlug: String
    let sourceCategory: String

    /// Binding to the active Set in ContentView — script events can be added directly.
    @Binding var activeSet: SetData

    @EnvironmentObject private var index: R2CatalogIndex
    @StateObject private var player: PreviewPlayer = PreviewPlayer()

    @State private var timeline: R2CatalogIndex.TimelineData? = nil
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil

    // Which event row is currently playing (by index in events array)
    @State private var playingEventIndex: Int? = nil

    // Download state for bed.m4a
    @State private var isDownloadingBed: Bool = false
    @State private var bedError: String? = nil

    // Saving state
    @State private var isSavingEvent: Int? = nil
    @State private var isSavingScene: Int? = nil
    @State private var saveError: String? = nil

    public init(sourceSlug: String, sourceCategory: String, activeSet: Binding<SetData>) {
        self.sourceSlug = sourceSlug
        self.sourceCategory = sourceCategory
        self._activeSet = activeSet
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            scriptHeader
            Divider()
            if isLoading {
                loadingView
            } else if let err = loadError {
                errorView(err)
            } else if let tl = timeline {
                scriptContent(tl)
            } else {
                emptyView
            }
        }
        .onAppear {
            Task { await loadTimeline() }
        }
        .onChange(of: sourceSlug) { _ in
            Task { await loadTimeline() }
        }
    }

    // MARK: - Header

    private var scriptHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Script")
                    .font(.headline)
                Text(sourceSlug)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            // Export buttons — only when timeline is loaded
            if let tl = timeline {
                exportButtons(tl)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func exportButtons(_ tl: R2CatalogIndex.TimelineData) -> some View {
        Menu {
            Button("Export Script (.md)") {
                exportMarkdown()
            }
            Button("Export Events (.csv)") {
                let csv = ExportService.buildEventsCSV(events: tl.events)
                ExportService.saveText(csv, defaultName: "\(sourceSlug)-events.csv",
                                       allowedExtension: "csv")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private func scriptContent(_ tl: R2CatalogIndex.TimelineData) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if tl.scenes.isEmpty {
                    // No scene metadata — flat event list
                    ForEach(Array(tl.events.enumerated()), id: \.offset) { idx, event in
                        eventRow(event, at: idx)
                        Divider().padding(.leading, 44)
                    }
                } else {
                    // Scene header + nested events
                    ForEach(Array(tl.scenes.enumerated()), id: \.offset) { sceneIdx, scene in
                        sceneHeader(scene, at: sceneIdx)
                        let sceneEvents = tl.events.filter {
                            $0.timeSec >= scene.startSec && $0.timeSec < scene.endSec
                        }
                        let allEvents = tl.events
                        ForEach(Array(sceneEvents.enumerated()), id: \.offset) { _, event in
                            if let globalIdx = allEvents.firstIndex(where: {
                                $0.timeSec == event.timeSec && $0.label == event.label
                            }) {
                                eventRow(event, at: globalIdx)
                                    .padding(.leading, 12) // indent under scene
                                Divider().padding(.leading, 56)
                            }
                        }
                        Divider()
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                    }
                    // Events not covered by any scene
                    let coveredTimes = Set(tl.scenes.flatMap { scene in
                        tl.events.filter {
                            $0.timeSec >= scene.startSec && $0.timeSec < scene.endSec
                        }.map { $0.timeSec }
                    })
                    let uncovered = tl.events.filter { !coveredTimes.contains($0.timeSec) }
                    if !uncovered.isEmpty {
                        Text("Other Events")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(Array(uncovered.enumerated()), id: \.offset) { _, event in
                            if let globalIdx = tl.events.firstIndex(where: {
                                $0.timeSec == event.timeSec && $0.label == event.label
                            }) {
                                eventRow(event, at: globalIdx)
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Scene header

    @ViewBuilder
    private func sceneHeader(_ scene: R2CatalogIndex.TimelineData.Scene, at sceneIdx: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(formatTime(scene.startSec)) – \(formatTime(scene.endSec))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("—")
                        .foregroundStyle(.secondary)
                    Text(scene.label)
                        .font(.caption.weight(.semibold))
                }
                if !scene.dominantCategories.isEmpty {
                    Text("Categories: " + scene.dominantCategories.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !scene.speciesInScene.isEmpty {
                    Text("Species: " + scene.speciesInScene.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Color.green.opacity(0.8))
                }
            }

            Spacer()

            // Save Scene button
            Button {
                Task { await saveScene(scene, at: sceneIdx) }
            } label: {
                if isSavingScene == sceneIdx {
                    ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                } else {
                    Label("Save Scene", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isSavingScene != nil)
            .help("Slice this scene's time range from bed.m4a and save as .m4a")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Event row

    @ViewBuilder
    private func eventRow(_ event: R2CatalogIndex.TimelineData.Event, at idx: Int) -> some View {
        let isSpecies = event.kind == "species"
        let isTransient = isTransientEvent(event.label)
        let isPlaying = playingEventIndex == idx

        HStack(alignment: .top, spacing: 10) {
            // Time + play button
            VStack(spacing: 2) {
                Text(event.timeDisplay)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Button {
                    Task { await togglePlayEvent(event, at: idx) }
                } label: {
                    Group {
                        if isDownloadingBed && playingEventIndex == idx {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 11))
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPlaying ? Color.accentColor : .secondary)
                .help(isPlaying ? "Stop" : "Play source recording at this timestamp")
            }

            // Label block
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.label)
                        .font(.system(size: 13, weight: isSpecies ? .semibold : .regular))
                        .foregroundStyle(eventLabelColor(isSpecies: isSpecies, isTransient: isTransient))

                    if let sci = event.scientific {
                        Text(sci)
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if !event.source.isEmpty {
                        Text(event.source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if event.durationSec > 0 {
                        Text(String(format: "%.1fs", event.durationSec))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    confidenceBar(event.confidence)
                }

                if let err = bedError, playingEventIndex == idx {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let err = saveError, isSavingEvent == idx {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            // Add to Set button
            let tlInput = TimelineEventInput(
                timeSec: event.timeSec,
                kind: event.kind,
                label: event.label,
                scientific: event.scientific,
                confidence: event.confidence,
                durationSec: event.durationSec)
            let alreadyInSet = LibrarySetBridge.contains(
                timelineEvent: tlInput,
                sourceSlug: sourceSlug,
                in: activeSet)
            Button {
                LibrarySetBridge.add(timelineEvent: tlInput,
                                      sourceSlug: sourceSlug,
                                      sourceCategory: sourceCategory,
                                      to: &activeSet)
            } label: {
                Image(systemName: alreadyInSet ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(alreadyInSet ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(alreadyInSet)
            .help(alreadyInSet ? "Already in Set" : "Add to active Set")

            // Per-event Save button
            Button {
                Task { await saveEvent(event, at: idx) }
            } label: {
                if isSavingEvent == idx {
                    ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isSavingEvent != nil)
            .help("Save this event clip (+/-1s) as .m4a")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(rowBackground(isPlaying: isPlaying, isSpecies: isSpecies, isTransient: isTransient))
        .contentShape(Rectangle())
    }

    // MARK: - Color coding

    private func eventLabelColor(isSpecies: Bool, isTransient: Bool) -> Color {
        if isSpecies { return Color.green }
        if isTransient { return Color.orange }
        return Color.primary
    }

    private func rowBackground(isPlaying: Bool, isSpecies: Bool, isTransient: Bool) -> Color {
        if isPlaying { return Color.accentColor.opacity(0.08) }
        if isSpecies { return Color.green.opacity(0.04) }
        if isTransient { return Color.orange.opacity(0.04) }
        return Color.clear
    }

    private func isTransientEvent(_ label: String) -> Bool {
        let transients = ["dog", "car", "door", "horn", "siren", "alarm",
                          "gunshot", "footstep", "knock", "clap", "crash",
                          "bark", "engine", "aircraft", "vehicle", "motorcycle"]
        let lower = label.lowercased()
        return transients.contains(where: { lower.contains($0) })
    }

    @ViewBuilder
    private func confidenceBar(_ confidence: Double) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%.0f%%", confidence * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(NSColor.separatorColor))
                    Capsule()
                        .fill(confidenceColor(confidence))
                        .frame(width: geo.size.width * confidence)
                }
            }
            .frame(width: 36, height: 4)
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5...: return .yellow
        default: return .orange
        }
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading script…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Could not load script")
                .font(.callout)
            Text(err)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No script available")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Playback

    private func togglePlayEvent(_ event: R2CatalogIndex.TimelineData.Event, at idx: Int) async {
        if playingEventIndex == idx {
            player.stop()
            playingEventIndex = nil
            return
        }

        player.stop()
        playingEventIndex = idx
        bedError = nil

        let (bedURL, isLocal) = index.bedURL(for: sourceSlug, category: sourceCategory)

        if !isLocal {
            isDownloadingBed = true
            do {
                let downloaded = try await index.downloadBed(slug: sourceSlug, category: sourceCategory)
                isDownloadingBed = false
                try player.play(downloaded, startAt: event.timeSec,
                                autoStopAfter: event.durationSec > 0 ? event.durationSec : nil)
            } catch {
                isDownloadingBed = false
                bedError = "Download failed: \(error.localizedDescription)"
                playingEventIndex = nil
                return
            }
        } else {
            do {
                try player.play(bedURL, startAt: event.timeSec,
                                autoStopAfter: event.durationSec > 0 ? event.durationSec : nil)
            } catch {
                bedError = "Playback failed: \(error.localizedDescription)"
                playingEventIndex = nil
                return
            }
        }

        // Watch for player stopping externally
        Task {
            while player.isPlaying { try? await Task.sleep(nanoseconds: 200_000_000) }
            if playingEventIndex == idx { playingEventIndex = nil }
        }
    }

    // MARK: - Per-event Save

    private func saveEvent(_ event: R2CatalogIndex.TimelineData.Event, at idx: Int) async {
        isSavingEvent = idx
        saveError = nil
        defer { isSavingEvent = nil }

        // Ensure bed.m4a is available
        let bedURL: URL
        let (localBed, isLocal) = index.bedURL(for: sourceSlug, category: sourceCategory)
        if isLocal {
            bedURL = localBed
        } else {
            do {
                bedURL = try await index.downloadBed(slug: sourceSlug, category: sourceCategory)
            } catch {
                saveError = "Download failed: \(error.localizedDescription)"
                return
            }
        }

        // Default filename
        let labelSlug = AudioSlicer.slugify(event.label)
        let tInt = Int(event.timeSec)
        let defaultName = "\(sourceSlug)__\(labelSlug)__t\(tInt)s.m4a"

        // Show save panel on main actor
        guard let destURL = await showSavePanel(defaultName: defaultName) else { return }

        // Slice with 1s pre/post padding
        let padded = 1.0
        let startSec = max(event.timeSec - padded, 0)
        let endSec = event.timeSec + max(event.durationSec, 0.5) + padded

        do {
            try await AudioSlicer.slice(source: bedURL, startSec: startSec, endSec: endSec,
                                        destination: destURL)
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Per-scene Save

    private func saveScene(_ scene: R2CatalogIndex.TimelineData.Scene, at sceneIdx: Int) async {
        isSavingScene = sceneIdx
        defer { isSavingScene = nil }

        // Ensure bed.m4a is available
        let bedURL: URL
        let (localBed, isLocal) = index.bedURL(for: sourceSlug, category: sourceCategory)
        if isLocal {
            bedURL = localBed
        } else {
            do {
                bedURL = try await index.downloadBed(slug: sourceSlug, category: sourceCategory)
            } catch {
                return
            }
        }

        let labelSlug = AudioSlicer.slugify(scene.label)
        let startInt = Int(scene.startSec)
        let endInt = Int(scene.endSec)
        let defaultName = "\(sourceSlug)__scene__t\(startInt)s-\(endInt)s__\(labelSlug).m4a"

        guard let destURL = await showSavePanel(defaultName: defaultName) else { return }

        do {
            try await AudioSlicer.slice(source: bedURL,
                                        startSec: scene.startSec,
                                        endSec: scene.endSec,
                                        destination: destURL)
        } catch {
            // Errors surfaced via alert
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Save Scene Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - NSSavePanel

    @MainActor
    private func showSavePanel(defaultName: String) async -> URL? {
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

    // MARK: - Timeline load

    private func loadTimeline() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        timeline = nil
        defer { isLoading = false }

        do {
            let tl = try await index.downloadTimeline(slug: sourceSlug, category: sourceCategory)
            timeline = tl
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Markdown export

    private func exportMarkdown() {
        Task {
            do {
                let localMD = try await index.downloadTimelineMD(slug: sourceSlug,
                                                                  category: sourceCategory)
                await MainActor.run {
                    ExportService.saveFile(from: localMD,
                                          defaultName: "\(sourceSlug)-script.md",
                                          allowedExtension: "md")
                }
            } catch {
                if let tl = timeline {
                    let md = buildFallbackMarkdown(from: tl)
                    await MainActor.run {
                        ExportService.saveText(md, defaultName: "\(sourceSlug)-script.md",
                                               allowedExtension: "md")
                    }
                }
            }
        }
    }

    private func buildFallbackMarkdown(from tl: R2CatalogIndex.TimelineData) -> String {
        var lines: [String] = ["# \(sourceSlug)", ""]
        for scene in tl.scenes {
            lines.append("## \(formatTime(scene.startSec)) – \(formatTime(scene.endSec)) — \(scene.label)")
            if !scene.dominantCategories.isEmpty {
                lines.append("*\(scene.dominantCategories.joined(separator: ", "))*")
            }
            lines.append("")
        }
        lines.append("## Events")
        lines.append("")
        for event in tl.events {
            let conf = String(format: "%.0f%%", event.confidence * 100)
            var line = "**\(event.timeDisplay)**  \(event.label)  (\(conf))"
            if let sci = event.scientific { line += " — *\(sci)*" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func formatTime(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
