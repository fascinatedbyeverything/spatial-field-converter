import SwiftUI

/// Horizontal time strip showing every ObjectPlan as a colored block at its
/// startSec / durationSec. Click a block to select it. The bed is shown as a
/// thin band along the top.
public struct TimelineView: View {
    @Binding public var composition: Composition
    @Binding public var selectedObjectIndex: Int?

    public init(composition: Binding<Composition>,
                 selectedObjectIndex: Binding<Int?>) {
        self._composition = composition
        self._selectedObjectIndex = selectedObjectIndex
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dur = max(composition.durationSec, 1.0)
            ZStack(alignment: .topLeading) {
                // Background grid: tick every 30s
                let tickEvery = 30.0
                let tickCount = Int(dur / tickEvery) + 1
                ForEach(0..<tickCount, id: \.self) { i in
                    let x = CGFloat(Double(i) * tickEvery / dur) * w
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                }
                // Bed band along the top 16pt
                Rectangle()
                    .fill(Color.green.opacity(0.2))
                    .frame(height: 16)
                Text("BED").font(.caption2).foregroundStyle(.green).padding(.leading, 4)

                // Object blocks: stacked rows below the bed band
                ForEach(Array(composition.objects.enumerated()), id: \.offset) { (i, plan) in
                    let row = i % 18      // 18 visible rows max; wrap above that
                    let rowHeight: CGFloat = (h - 16) / 18.0
                    let y = 16 + CGFloat(row) * rowHeight
                    let x = CGFloat(plan.startSec / dur) * w
                    let blockW = max(2, CGFloat(plan.durationSec / dur) * w)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: plan.behavior).opacity(selectedObjectIndex == i ? 0.95 : 0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(selectedObjectIndex == i ? Color.accentColor : Color.clear, lineWidth: 1.5))
                        .frame(width: blockW, height: max(rowHeight - 2, 4))
                        .position(x: x + blockW/2, y: y + rowHeight/2)
                        .help("\(plan.label) — \(timeString(plan.startSec)) for \(durationString(plan.durationSec))")
                        .onTapGesture {
                            selectedObjectIndex = (selectedObjectIndex == i) ? nil : i
                        }
                }
            }
        }
    }

    private func color(for b: BehaviorHint) -> Color {
        switch b {
        case .sustained: return .blue
        case .discrete:  return .orange
        case .oneShot:   return .red
        case .flyby:     return .purple
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
