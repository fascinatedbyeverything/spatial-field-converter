import SwiftUI

/// Per-object detail editor. Shows label/scientific, source key, behavior picker,
/// volume slider, loop toggle, locked toggle, and the (x, y, z) of the first
/// position keyframe. Edits flow back via Binding into composition.objects[i].
public struct ObjectInspectorView: View {
    @Binding public var composition: Composition
    public let selectedObjectIndex: Int?

    public init(composition: Binding<Composition>, selectedObjectIndex: Int?) {
        self._composition = composition
        self.selectedObjectIndex = selectedObjectIndex
    }

    public var body: some View {
        Group {
            if let i = selectedObjectIndex, composition.objects.indices.contains(i) {
                detail(at: i)
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private func detail(at i: Int) -> some View {
        let plan = composition.objects[i]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(plan.label).font(.headline)
                if let s = plan.scientific, !s.isEmpty {
                    Text(s).italic().foregroundStyle(.secondary)
                }
                Spacer()
                Text("#\(i + 1)").foregroundStyle(.tertiary)
            }
            Text(plan.sourceClipR2Key)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Divider()

            HStack {
                Text("Behavior").frame(width: 90, alignment: .leading)
                Picker("", selection: $composition.objects[i].behavior) {
                    ForEach(BehaviorHint.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Volume").frame(width: 90, alignment: .leading)
                Slider(value: $composition.objects[i].volume, in: 0...1)
                Text(String(format: "%.2f", plan.volume))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption.monospaced())
            }

            HStack {
                Toggle("Loop", isOn: $composition.objects[i].loop)
                Toggle("Locked", isOn: $composition.objects[i].locked)
                    .help("Locked objects are preserved on Re-roll")
            }

            Divider()

            positionSection(i: i)

            Divider()

            HStack {
                Text("Start").frame(width: 90, alignment: .leading)
                Text(timeString(plan.startSec))
                    .font(.caption.monospaced())
                Spacer()
                Text("Length")
                Text(durationString(plan.durationSec))
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func positionSection(i: Int) -> some View {
        let plan = composition.objects[i]
        let kf = plan.positionCurve.first ?? PositionKeyframe(timeSec: 0, x: 0, y: 0, z: 0)
        VStack(alignment: .leading, spacing: 4) {
            Text("Position (first keyframe)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                axisField(label: "x", value: kf.x) { x in
                    setKeyframe(i: i, x: x, y: kf.y, z: kf.z)
                }
                axisField(label: "y", value: kf.y) { y in
                    setKeyframe(i: i, x: kf.x, y: y, z: kf.z)
                }
                axisField(label: "z", value: kf.z) { z in
                    setKeyframe(i: i, x: kf.x, y: kf.y, z: z)
                }
            }
        }
    }

    @ViewBuilder
    private func axisField(label: String, value: Float, onCommit: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 12)
            TextField("", value: Binding(get: { value },
                                          set: { newVal in onCommit(max(-1, min(1, newVal))) }),
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }

    private func setKeyframe(i: Int, x: Float, y: Float, z: Float) {
        guard composition.objects.indices.contains(i) else { return }
        if composition.objects[i].positionCurve.isEmpty {
            composition.objects[i].positionCurve = [
                PositionKeyframe(timeSec: 0, x: x, y: y, z: z)]
        } else {
            let t = composition.objects[i].positionCurve[0].timeSec
            composition.objects[i].positionCurve[0] =
                PositionKeyframe(timeSec: t, x: x, y: y, z: z)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack {
            Spacer()
            Text("Select an object on the timeline or space view")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    private func timeString(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
    private func durationString(_ d: Double) -> String {
        if d < 10 { return String(format: "%.1fs", d) }
        return String(format: "%.0fs", d)
    }
}
