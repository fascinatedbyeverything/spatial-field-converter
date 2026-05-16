import SwiftUI

public struct InspectorView: View {
    @ObservedObject var pipeline: ConversionPipeline
    /// Observed separately so SwiftUI re-renders when playback state changes.
    @ObservedObject var previewPlayer: PreviewPlayer

    public init(pipeline: ConversionPipeline) {
        self.pipeline = pipeline
        self.previewPlayer = pipeline.previewPlayer
    }

    /// True if any enabled pending row has an empty / whitespace-only title.
    /// Used to gate Convert + Upload so users can't ship "mic1234" by accident.
    private var hasUnnamedEnabledRow: Bool {
        pipeline.jobs.contains { job in
            job.enabled
            && job.status != .alreadyConverted
            && job.status != .done
            && job.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pipeline.jobs.count) file\(pipeline.jobs.count == 1 ? "" : "s") queued")
                        .font(.headline)
                    if previewPlayer.isPlaying {
                        Text("▶ Previewing — make sure AirPods Max Spatial Audio is on (Control Center → Spatial Audio)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()

                Toggle(isOn: $pipeline.soundAnalysisEnabled) {
                    HStack(spacing: 4) {
                        Text("Sound analysis")
                        Text("(v0.2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(true)
                .help("On-device sound classification (bird chirps, vehicles, music, etc.) — coming in v0.2. Will run post-upload as a separate background pass and write events.json metadata for AI placement and library grouping.")

                Button("Clear") {
                    pipeline.removeAllJobs()
                }
                .disabled(pipeline.isRunning || pipeline.jobs.isEmpty)

                Button("Convert + Upload") {
                    Task { await pipeline.runAll() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(pipeline.isRunning || pipeline.jobs.isEmpty || hasUnnamedEnabledRow)
                .help(hasUnnamedEnabledRow
                      ? "Some queued recordings still need a name. Type a title for each row before uploading."
                      : "Convert and upload the queued recordings to R2.")
            }
            .padding()

            Divider()

            // File list
            List {
                ForEach($pipeline.jobs) { $job in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: $job.enabled)
                            .labelsHidden()
                            .disabled(pipeline.isRunning || job.status == .alreadyConverted)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Name this recording (required)", text: $job.title)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(pipeline.isRunning)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(job.title.trimmingCharacters(in: .whitespaces).isEmpty
                                                    && job.enabled
                                                    && job.status != .alreadyConverted
                                                    && job.status != .done
                                                    ? Color.orange.opacity(0.7)
                                                    : Color.clear,
                                                    lineWidth: 1.5)
                                    )

                                let isThisRowPlaying = previewPlayer.isPlaying &&
                                    previewPlayer.currentFile?.path.contains(job.slug ?? "___nope___") == true
                                Button(action: {
                                    Task { await previewRow(job) }
                                }) {
                                    Image(systemName: isThisRowPlaying ? "stop.fill" : "play.fill")
                                }
                                .help(isThisRowPlaying ? "Stop preview" : "Preview spatial bed via AirPods")
                                .disabled(pipeline.isRunning && !isThisRowPlaying)

                                statusBadge(job.status)
                            }
                            Text(job.sourceURL.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let r2Key = job.r2Key, !r2Key.isEmpty {
                                Text("R2 → \(r2Key)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.green)
                            } else if let slug = job.slug {
                                Text("slug: \(slug)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if let err = job.errorMessage {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @MainActor
    private func previewRow(_ job: ConversionPipeline.Job) async {
        // If something is already playing, stop it.
        if previewPlayer.isPlaying {
            previewPlayer.stop()
            return
        }

        guard let index = pipeline.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        do {
            let bedURL = try await pipeline.prepareForPreview(at: index)
            try previewPlayer.play(bedURL)
        } catch {
            // Error is already surfaced in the row's errorMessage via prepareForPreview.
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: ConversionPipeline.JobStatus) -> some View {
        switch status {
        case .pending:
            Text("queued").font(.caption).foregroundStyle(.secondary)
        case .alreadyConverted:
            Text("already in R2").font(.caption).foregroundStyle(.orange)
        case .converting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("converting…").font(.caption).foregroundStyle(.blue)
            }
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("uploading…").font(.caption).foregroundStyle(.blue)
            }
        case .done:
            Text("✓ done").font(.caption).foregroundStyle(.green)
        case .failed:
            Text("✗ failed").font(.caption).foregroundStyle(.red)
        }
    }
}
