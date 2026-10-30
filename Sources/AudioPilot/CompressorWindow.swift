import SwiftUI

/// Eigenes Fenster pro App: Kompressor mit allen Reglern, Kennlinie und Absenkungs-Anzeige.
struct CompressorWindow: View {
    @EnvironmentObject var mixer: Mixer
    let appID: String

    var body: some View {
        let info = mixer.appInfo(appID)
        let c = mixer.setting(appID).comp
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let icon = info.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: info.name).font(.headline).lineLimit(1)
                    Text("Kompressor").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Voreinstellung", selection: Binding(
                    get: { c.presetName ?? "" },
                    set: { name in
                        guard let p = CompressorSettings.presets.first(where: { $0.name == name }) else { return }
                        mixer.update(appID) { $0.comp = p.c }
                    })) {
                    if c.presetName == nil { Text("Eigene").tag("") }
                    ForEach(CompressorSettings.presets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize()
                Toggle("", isOn: Binding(get: { c.on }, set: { v in mixer.update(appID) { $0.comp.on = v } }))
                    .toggleStyle(.switch).labelsHidden()
            }

            HStack(alignment: .top, spacing: 14) {
                CurveView(c: c)
                    .frame(width: 170, height: 170)
                ReductionMeter(meters: mixer.meters, appID: appID, on: c.on)
                    .frame(width: 22, height: 170)
                VStack(spacing: 10) {
                    let r = CompressorSettings.ranges
                    Param("Schwelle", value: bind(\.threshold), range: r.threshold, step: 0.5, text: { String(format: "%.1f dB", $0) })
                    Param("Verhältnis", value: bind(\.ratio), range: r.ratio, step: 0.1, text: { String(format: "%.1f : 1", $0) })
                    Param("Attack", value: bind(\.attack), range: r.attack, step: 0.1, text: { String(format: "%.1f ms", $0) })
                    Param("Release", value: bind(\.release), range: r.release, step: 5, text: { String(format: "%.0f ms", $0) })
                    Param("Makeup", value: bind(\.makeup), range: r.makeup, step: 0.5, text: { String(format: "+%.1f dB", $0) })
                    Param("Knie", value: bind(\.knee), range: r.knee, step: 0.5, text: { String(format: "%.1f dB", $0) })
                }
                .frame(width: 250)
            }
            .opacity(c.on ? 1 : 0.5)

            HStack {
                Label("Ein Limiter danach hält den Pegel immer unter −1 dB – nichts übersteuert.", systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Zurücksetzen") { mixer.update(appID) { $0.comp = CompressorSettings() } }
            }
        }
        .padding(20)
        .fixedSize()
        .onAppear { mixer.compressorWindows += 1 }
        .onDisappear { mixer.compressorWindows = max(0, mixer.compressorWindows - 1) }
    }

    private func bind(_ kp: WritableKeyPath<CompressorSettings, Float>) -> Binding<Float> {
        Binding(get: { mixer.setting(appID).comp[keyPath: kp] },
                set: { v in mixer.update(appID) { $0.comp[keyPath: kp] = v; $0.comp.on = true } })
    }
}

private struct Param: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let text: (Float) -> String
    init(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float, text: @escaping (Float) -> String) {
        self.title = title; _value = value; self.range = range; self.step = step; self.text = text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: text(value)).font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            // Ohne `step:` (sonst Rasterpunkte) – gerundet wird beim Setzen.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range).controlSize(.small)
        }
    }
}

/// Kennlinie: Eingang (x) → Ausgang (y), −60…0 dB, ohne Makeup. Gestrichelt = 1 : 1.
private struct CurveView: View {
    let c: CompressorSettings

    private func out(_ x: Float) -> Float {
        let over = x - c.threshold, r = max(c.ratio, 1), w = c.knee
        if 2 * over <= -w { return x }
        if w > 0 && 2 * abs(over) < w { let q = over + w / 2; return x - (1 - 1 / r) * q * q / (2 * w) }
        return c.threshold + over / r
    }

    var body: some View {
        Canvas { ctx, size in
            func pt(_ x: Float, _ y: Float) -> CGPoint {
                CGPoint(x: CGFloat((x + 60) / 60) * size.width, y: size.height - CGFloat((y + 60) / 60) * size.height)
            }
            let box = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8)
            ctx.fill(box, with: .color(.primary.opacity(0.05)))
            for v in stride(from: -48, through: -12, by: 12) {
                var g = Path()
                g.move(to: pt(Float(v), -60)); g.addLine(to: pt(Float(v), 0))
                g.move(to: pt(-60, Float(v))); g.addLine(to: pt(0, Float(v)))
                ctx.stroke(g, with: .color(.primary.opacity(0.08)), lineWidth: 1)
            }
            var diag = Path()
            diag.move(to: pt(-60, -60)); diag.addLine(to: pt(0, 0))
            ctx.stroke(diag, with: .color(.primary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var th = Path()
            th.move(to: pt(c.threshold, -60)); th.addLine(to: pt(c.threshold, 0))
            ctx.stroke(th, with: .color(.orange.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            var curve = Path()
            curve.move(to: pt(-60, out(-60)))
            for i in 1...120 { let x = -60 + Float(i) * 0.5; curve.addLine(to: pt(x, out(x))) }
            ctx.stroke(curve, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text("Eingang →").font(.system(size: 9)).foregroundStyle(.tertiary).padding(5)
        }
        .overlay(alignment: .topLeading) {
            Text("↑ Ausgang").font(.system(size: 9)).foregroundStyle(.tertiary).padding(5)
        }
    }
}

/// Wie stark gerade abgesenkt wird (0…24 dB, von oben nach unten).
private struct ReductionMeter: View {
    @ObservedObject var meters: Meters
    let appID: String
    let on: Bool

    var body: some View {
        let gr = on ? (meters.reductions[appID] ?? 0) : 0
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.orange)
                        .frame(height: geo.size.height * CGFloat(min(gr, 24) / 24))
                        .animation(.linear(duration: 0.08), value: gr)
                }
            }
            .frame(width: 8)
            Text(verbatim: String(format: "%.0f", gr)).font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
        }
        .help("Absenkung in dB")
    }
}
