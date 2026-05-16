import Foundation
import AppKit
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// ExportService — CSV and Markdown export for timeline events and search results.
// Pure functions; all file I/O goes through NSSavePanel.
// ---------------------------------------------------------------------------

public enum ExportService {

    // MARK: - CSV helpers

    /// Wrap a single cell value in CSV quoting rules.
    /// Doubles inner quotes; wraps field if it contains comma, quote, or newline.
    static func csvCell(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    static func csvRow(_ cells: [String]) -> String {
        cells.map { csvCell($0) }.joined(separator: ",")
    }

    // MARK: - Per-recording events CSV (from timeline.json events array)

    /// Build a CSV string from a timeline's events.
    /// Columns: time_display, time_sec, kind, label, scientific, source, confidence, duration_sec
    public static func buildEventsCSV(events: [R2CatalogIndex.TimelineData.Event]) -> String {
        let header = csvRow(["time_display","time_sec","kind","label","scientific","source","confidence","duration_sec"])
        let rows = events.map { e in
            csvRow([
                e.timeDisplay,
                String(e.timeSec),
                e.kind,
                e.label,
                e.scientific ?? "",
                e.source,
                String(format: "%.4f", e.confidence),
                String(e.durationSec)
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Search results CSV (from LibraryView filtered events)

    /// Columns: source_slug, time_display, time_sec, kind, label, scientific, source, confidence, duration_sec
    public static func buildSearchResultsCSV(events: [R2CatalogIndex.IndexedEvent]) -> String {
        let header = csvRow(["source_slug","time_display","time_sec","kind","label","scientific","source","confidence","duration_sec"])
        let rows: [String] = events.map { e in
            let kind = (e.source == "birdnet" || e.scientific != nil) ? "species" : "category"
            return csvRow([
                e.sourceSlug,
                formatTime(e.startSec),
                String(e.startSec),
                kind,
                e.label,
                e.scientific ?? "",
                e.source,
                String(format: "%.4f", e.confidence),
                String(e.durationSec)
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Full archive CSV (all events across all sources)

    /// Columns: source_slug, source_category, time_display, time_sec, kind, label, scientific, source, confidence, duration_sec
    public static func buildFullArchiveCSV(events: [R2CatalogIndex.IndexedEvent]) -> String {
        let header = csvRow(["source_slug","source_category","time_display","time_sec","kind","label","scientific","source","confidence","duration_sec"])
        let rows: [String] = events.map { e in
            let kind = (e.source == "birdnet" || e.scientific != nil) ? "species" : "category"
            return csvRow([
                e.sourceSlug,
                e.sourceCategory,
                formatTime(e.startSec),
                String(e.startSec),
                kind,
                e.label,
                e.scientific ?? "",
                e.source,
                String(format: "%.4f", e.confidence),
                String(e.durationSec)
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Save panel helpers

    /// Present an NSSavePanel and write `content` to the chosen URL.
    /// `defaultName`: suggested filename (e.g. "events.csv")
    /// `allowedExtension`: file extension without dot (e.g. "csv")
    @MainActor
    public static func saveText(_ content: String,
                                 defaultName: String,
                                 allowedExtension: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [utType(for: allowedExtension)]
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// Present an NSSavePanel to copy a local file to a user-chosen destination.
    @MainActor
    public static func saveFile(from sourceURL: URL,
                                 defaultName: String,
                                 allowedExtension: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [utType(for: allowedExtension)]
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: sourceURL, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Private helpers

    private static func formatTime(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private static func utType(for ext: String) -> UTType {
        switch ext.lowercased() {
        case "csv":  return .commaSeparatedText
        case "md":   return UTType(filenameExtension: "md") ?? .plainText
        default:     return .plainText
        }
    }
}
