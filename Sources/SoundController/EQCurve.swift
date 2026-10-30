import SwiftUI

/// EQ als Kurve (wie in Profi-Apps): 10 Punkte, senkrecht ziehbar, Doppelklick = 0 dB.
/// Die Kurve wird mit denselben Filtern berechnet, die auch den Ton formen (`DSPState.response`).
struct EQCurve: View {
    let bands: [Float]
    let on: Bool
    let onChange: (Int, Float) -> Void
    @State private var active: Int?

    private static let lo: Float = 20, hi: Float = 20000, maxDB: Float = 12
    private static let top: CGFloat = 10, bottom: CGFloat = 18, side: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let plotH = h - Self.top - Self.bottom
            let mid = Self.top + plotH / 2
            let x = { (f: Float) -> CGFloat in
                Self.side + CGFloat(log(f / Self.lo) / log(Self.hi / Self.lo)) * (w - 2 * Self.side)
            }
            let y = { (db: Float) -> CGFloat in mid - CGFloat(max(min(db, Self.maxDB), -Self.maxDB) / Self.maxDB) * plotH / 2 }
            let nearest = { (px: CGFloat) -> Int in
                (0..<EQSettings.freqs.count).min { abs(x(EQSettings.freqs[$0]) - px) < abs(x(EQSettings.freqs[$1]) - px) } ?? 0
            }
            let tint = on ? Color.accentColor : Color.secondary

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(.primary.opacity(0.05)))
                    for db: Float in [-6, 6] {
                        var g = Path(); g.move(to: CGPoint(x: Self.side, y: y(db))); g.addLine(to: CGPoint(x: size.width - Self.side, y: y(db)))
                        ctx.stroke(g, with: .color(.primary.opacity(0.06)), lineWidth: 1)
                    }
                    var zero = Path(); zero.move(to: CGPoint(x: Self.side, y: mid)); zero.addLine(to: CGPoint(x: size.width - Self.side, y: mid))
                    ctx.stroke(zero, with: .color(.primary.opacity(0.16)), lineWidth: 1)

                    var curve = Path(), area = Path()
                    let n = 120
                    for k in 0...n {
                        let f = Self.lo * powf(Self.hi / Self.lo, Float(k) / Float(n))
                        let p = CGPoint(x: x(f), y: y(DSPState.response(bands: bands, at: f)))
                        if k == 0 { curve.move(to: p); area.move(to: CGPoint(x: p.x, y: mid)) }
                        curve.addLine(to: p); area.addLine(to: p)
                    }
                    area.addLine(to: CGPoint(x: x(Self.hi), y: mid)); area.closeSubpath()
                    ctx.fill(area, with: .color(tint.opacity(0.16)))
                    ctx.stroke(curve, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                ForEach(0..<EQSettings.freqs.count, id: \.self) { i in
                    let v = bands[safe: i] ?? 0
                    let px = x(EQSettings.freqs[i])
                    Circle().fill(Color.white)
                        .overlay(Circle().strokeBorder(v != 0 ? tint : Color.black.opacity(0.12), lineWidth: v != 0 ? 1.5 : 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .frame(width: active == i ? 13 : 10, height: active == i ? 13 : 10)
                        .position(x: px, y: y(v))
                    Text(EQSettings.labels[i])
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(active == i ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .position(x: px, y: h - 8)
                }

                if let i = active {
                    Text(verbatim: String(format: "%@%.1f dB · %@ Hz", (bands[safe: i] ?? 0) > 0 ? "+" : "", bands[safe: i] ?? 0, EQSettings.labels[i]))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.regularMaterial))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6).padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let i = active ?? nearest(g.startLocation.x)
                    active = i
                    var db = Float((mid - g.location.y) / (plotH / 2)) * Self.maxDB
                    db = (max(min(db, Self.maxDB), -Self.maxDB) * 2).rounded() / 2
                    if abs(db) < 0.75 { db = 0 }   // leicht bei 0 dB einrasten
                    onChange(i, db)
                }
                .onEnded { _ in active = nil })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { e in onChange(nearest(e.location.x), 0) })
        }
        .frame(height: 104)
        .help("Punkt ziehen = Band anheben/absenken · Doppelklick = 0 dB")
    }
}
