import SwiftUI

public struct InspectorView: View {
    @ObservedObject var pipeline: ConversionPipeline

    public init(pipeline: ConversionPipeline) {
        self.pipeline = pipeline
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(pipeline.jobs.count) file\(pipeline.jobs.count == 1 ? "" : "s") queued")
                    .font(.headline)
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
                .disabled(pipeline.isRunning || pipeline.jobs.isEmpty)
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
                                TextField("Title", text: $job.title)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(pipeline.isRunning)
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
