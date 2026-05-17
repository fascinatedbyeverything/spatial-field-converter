import SwiftUI

/// Curate a Set: keep/reject elements, override behavior hints, name the Set, save.
///
/// Reads + writes `set` via Binding so changes flow back to the parent.
/// `store` is used for explicit Save / Publish actions; autosave is opt-in.
public struct SetCurationPane: View {
    @Binding public var set: SetData
    public let store: SetStore
    public var onSaved: (() -> Void)? = nil
    public var onPublishRequested: ((SetData) -> Void)? = nil

    /// Group elements by label so the user can keep/reject all Cardinals at once.
    private var groups: [LabelGroup] {
        let byLabel = Dictionary(grouping: set.elements, by: { $0.label })
        return byLabel
            .map { LabelGroup(label: $0.key, indices: $0.value.compactMap { el in set.elements.firstIndex(where: { $0.id == el.id }) }) }
            .sorted { lhs, rhs in
                // Kept-something groups first; then by element count descending; then alphabetical.
                let lKept = lhs.indices.contains(where: { set.elements[$0].keep })
                let rKept = rhs.indices.contains(where: { set.elements[$0].keep })
                if lKept != rKept { return lKept }
                if lhs.indices.count != rhs.indices.count { return lhs.indices.count > rhs.indices.count }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    private struct LabelGroup: Identifiable {
        let label: String
        let indices: [Int]
        var id: String { label }
    }

    @State private var saveError: String?

    public init(set: Binding<SetData>,
                store: SetStore,
                onSaved: (() -> Void)? = nil,
                onPublishRequested: ((SetData) -> Void)? = nil) {
        self._set = set
        self.store = store
        self.onSaved = onSaved
        self.onPublishRequested = onPublishRequested
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            elementList
            if let err = saveError {
                Divider()
                Text(err).font(.caption).foregroundStyle(.red).padding(8)
            }
        }
    }

    // MARK: - Header (name + counts + save/publish)

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Set name", text: Binding(
                    get: { set.name },
                    set: { newName in
                        set.name = newName
                        set.slug = SetData.slugify(newName)
                    }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 280)
                HStack(spacing: 12) {
                    Text("slug: \(set.slug)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(keptSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Save") {
                doSave()
            }
            .disabled(set.name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Publish to R2") {
                onPublishRequested?(set)
            }
            .disabled(set.name.trimmingCharacters(in: .whitespaces).isEmpty || set.keptElements.isEmpty)
        }
        .padding()
    }

    private var keptSummary: String {
        let kept = set.elements.filter { $0.keep }.count
        let total = set.elements.count
        return "\(kept) / \(total) kept"
    }

    // MARK: - Element list (grouped by label)

    @ViewBuilder
    private var elementList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.indices, id: \.self) { i in
                        elementRow(at: i)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: LabelGroup) -> some View {
        let keptCount = group.indices.filter { set.elements[$0].keep }.count
        HStack {
            Toggle(isOn: Binding(
                get: { keptCount == group.indices.count },
                set: { newVal in
                    for i in group.indices { set.elements[i].keep = newVal }
                })) {
                Text(group.label).font(.headline)
            }
            .toggleStyle(.checkbox)
            Text("(\(keptCount)/\(group.indices.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func elementRow(at i: Int) -> some View {
        let el = set.elements[i]
        HStack(spacing: 8) {
            Toggle("", isOn: $set.elements[i].keep)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let sci = el.scientific, !sci.isEmpty {
                        Text(sci).font(.caption.italic()).foregroundStyle(.secondary)
                    }
                    Text("conf \(Int(el.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(timeString(el.timeSec))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(durationString(el.durationSec))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("src: \(el.sourceSlug) · kind: \(el.kind)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("Behavior", selection: $set.elements[i].behaviorHint) {
                ForEach(BehaviorHint.allCases, id: \.self) { b in
                    Text(b.rawValue).tag(b)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func timeString(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func durationString(_ d: Double) -> String {
        if d < 10 { return String(format: "%.1fs", d) }
        return String(format: "%.0fs", d) }

    // MARK: - Save

    private func doSave() {
        set.updatedAt = Date()
        do {
            try store.saveLocal(set)
            saveError = nil
            onSaved?()
        } catch {
            saveError = "Save failed: \(error)"
        }
    }
}
