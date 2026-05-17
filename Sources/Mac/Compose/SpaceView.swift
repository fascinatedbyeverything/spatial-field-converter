import SwiftUI

/// Bird's-eye view of object positions on the xz plane (x = left/right,
/// z = front/back). Each object is a colored dot; drag to move. The listener
/// is at (0, 0) in the center of the view. Selection ring shows the active object.
public struct SpaceView: View {
    @Binding public var composition: Composition
    @Binding public var selectedObjectIndex: Int?

    /// Called when a dot is dragged (live, every frame). Use this to update
    /// the ComposePreviewPlayer in real time.
    public var onPositionLiveDrag: ((Int, Float, Float, Float) -> Void)? = nil

    public init(composition: Binding<Composition>,
                 selectedObjectIndex: Binding<Int?>,
                 onPositionLiveDrag: ((Int, Float, Float, Float) -> Void)? = nil) {
        self._composition = composition
        self._selectedObjectIndex = selectedObjectIndex
        self.onPositionLiveDrag = onPositionLiveDrag
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let radius = side / 2 - 8

            ZStack {
                // Background: dome boundary + crosshair
                Circle()
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    .frame(width: radius*2, height: radius*2)
                    .position(x: cx, y: cy)
                Path { p in
                    p.move(to: CGPoint(x: cx - radius, y: cy))
                    p.addLine(to: CGPoint(x: cx + radius, y: cy))
                    p.move(to: CGPoint(x: cx, y: cy - radius))
                    p.addLine(to: CGPoint(x: cx, y: cy + radius))
                }
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)

                // Listener
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    .position(x: cx, y: cy)

                // Object dots
                ForEach(Array(composition.objects.enumerated()), id: \.offset) { (i, plan) in
                    let pos = plan.positionCurve.first
                    let x = CGFloat(pos?.x ?? 0)
                    let z = CGFloat(pos?.z ?? 0)
                    let px = cx + x * radius
                    let py = cy - z * radius    // z+ = forward = "up" on screen

                    Circle()
                        .fill(color(for: plan.behavior))
                        .frame(width: selectedObjectIndex == i ? 16 : 12,
                               height: selectedObjectIndex == i ? 16 : 12)
                        .overlay(
                            Circle()
                                .stroke(selectedObjectIndex == i ? Color.accentColor : Color.clear,
                                        lineWidth: 2)
                                .frame(width: 22, height: 22))
                        .position(x: px, y: py)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    let nx = Float(max(-1, min(1, (g.location.x - cx) / radius)))
                                    let nz = Float(max(-1, min(1, (cy - g.location.y) / radius)))
                                    setObjectPosition(index: i, x: nx, z: nz)
                                    selectedObjectIndex = i
                                })
                        .onTapGesture {
                            selectedObjectIndex = (selectedObjectIndex == i) ? nil : i
                        }
                }
            }
        }
    }

    private func setObjectPosition(index: Int, x: Float, z: Float) {
        guard composition.objects.indices.contains(index) else { return }
        if composition.objects[index].positionCurve.isEmpty {
            composition.objects[index].positionCurve = [
                PositionKeyframe(timeSec: 0, x: x, y: 0, z: z)
            ]
        } else {
            // Preserve y; overwrite x/z. Static-position-only for v1.1.
            let kf0 = composition.objects[index].positionCurve[0]
            composition.objects[index].positionCurve[0] =
                PositionKeyframe(timeSec: kf0.timeSec, x: x, y: kf0.y, z: z)
        }
        onPositionLiveDrag?(index, x, 0, z)
    }

    private func color(for b: BehaviorHint) -> Color {
        switch b {
        case .sustained: return .blue
        case .discrete:  return .orange
        case .oneShot:   return .red
        case .flyby:     return .purple
        }
    }
}
