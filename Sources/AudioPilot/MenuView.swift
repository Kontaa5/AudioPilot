import AVFoundation
import SwiftUI

/// Aufgebaut wie das Ton-Modul im Kontrollzentrum: ein großer Hauptregler, darunter die Geräte
/// als Liste (blauer Kreis = aktiv), dann die Apps mit schmalen Reglern. Raster: Einzug 8, Symbol 24.
struct MenuView: View {
    @EnvironmentObject var mixer: Mixer
    @Environment(\.openSettings) private var openSettings
    @State private var tab = 0
    @State private var expanded: String?
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let c = mixer.conflictApp { Notice(text: "\(c) läuft auch – bitte beenden, sonst stören sich die Apps.") }
            if let e = mixer.lastError {
                Notice(text: e)
                MenuRow(action: openPrivacy) { Text("Datenschutz-Einstellungen …") }
            }
            if let g = mixer.switchGuard { GuardBanner(guard: g, release: { mixer.releaseGuard() }) }
            if tab == 0 { outputTab } else { inputTab }
            Separator()
            footer
        }
        .font(.system(size: 13))
        .padding(.horizontal, 6).padding(.vertical, 10)
        .frame(width: 340)
        .onAppear { mixer.menuVisible = true }
        .animation(.snappy(duration: 0.2), value: mixer.switchGuard)
        .onDisappear { mixer.menuVisible = false; expanded = nil; showAll = false }
    }

    // MARK: Kopf / Fuß

    private var header: some View {
        HStack(spacing: 8) {
            Text(tab == 0 ? "Ton" : "Mikrofon").font(.system(size: 13, weight: .semibold))
            if mixer.healing {
                Badge(symbol: "arrow.triangle.2.circlepath", text: "Repariere …", color: .secondary)
            } else if mixer.callActive && mixer.settings.callBoostOn {
                Badge(symbol: "phone.fill", text: "Anruf-Boost", color: .green)
            }
            Spacer()
            HStack(spacing: 2) {
                TabButton(symbol: "speaker.wave.2.fill", active: tab == 0) { tab = 0 }
                TabButton(symbol: "mic.fill", active: tab == 1) { tab = 1 }
            }
            .padding(2)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 8).padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            MenuRow(action: { NSApp.activate(); openSettings() }) { Text("Einstellungen …") }
            RoundButton(symbol: "arrow.triangle.2.circlepath", help: "Reparieren: alle Umleitungen neu aufbauen und Ausgabe kurz anstoßen (passiert normalerweise automatisch)", action: mixer.repair)
            RoundButton(symbol: "power", help: "Beenden (⌘Q)") { mixer.shutdown(); NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.trailing, 4)
    }

    // MARK: Ausgabe

    private var outputTab: some View {
        let out = mixer.defaultOutput
        let vol = mixer.volumes[out] ?? mixer.settings.softMaster
        return VStack(alignment: .leading, spacing: 0) {
            VolumeRow(value: vol, symbol: speakerSymbol(vol)) { mixer.setVolume(device: out, $0) }
                .help(mixer.volumes[out] == nil ? "Software-Lautstärke (Gerät hat keinen eigenen Regler)" : "Lautstärke")

            SectionTitle("Ausgabe")
            ForEach(mixer.sortedOutputs) { dev in
                DeviceRow(device: dev, active: dev.id == out) { mixer.selectOutput(dev.id) }
            }
            if mixer.needsBluetoothPermission {
                MenuRow(action: mixer.enableBluetooth) {
                    IconCircle(symbol: "airpods", active: false).opacity(0.6)
                    Text("AirPods vom iPhone holen …").foregroundStyle(.secondary)
                }
                .help("Zeigt gekoppelte Kopfhörer zum Verbinden an (fragt einmal nach Bluetooth-Zugriff)")
            }
            ForEach(mixer.bluetooth) { bt in
                BluetoothRow(device: bt, busy: mixer.connecting == bt.id) { mixer.connectBluetooth(bt) }
            }

            Separator()
            SectionTitle("Apps")
            if mixer.apps.isEmpty { Caption("Gerade spielt keine App Ton ab.") }
            let list = sortedApps
            ForEach(showAll ? list : Array(list.prefix(3))) { app in
                AppRow(app: app, expanded: expanded == app.id) {
                    withAnimation(.snappy(duration: 0.22)) { expanded = expanded == app.id ? nil : app.id }
                }
            }
            if list.count > 3 {
                MenuRow(action: { withAnimation(.snappy(duration: 0.22)) { showAll.toggle() } }) {
                    HStack(spacing: 6) {
                        Text(showAll ? "Weniger anzeigen" : "Alle anzeigen (\(list.count))").foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAll ? 180 : 0))
                    }
                }
            }
        }
    }

    /// Spielende Apps nach Lautstärke (lauteste zuerst), dann der Rest nach Name.
    private var sortedApps: [AudioApp] {
        let rank = Dictionary(mixer.ranking.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return mixer.apps.enumerated().sorted { a, b in
            let ka = (a.element.isPlaying ? 0 : 1, rank[a.element.id] ?? .max, a.offset)
            let kb = (b.element.isPlaying ? 0 : 1, rank[b.element.id] ?? .max, b.offset)
            return ka < kb
        }.map(\.element)
    }

    private func speakerSymbol(_ v: Float) -> String {
        v <= 0.001 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    // MARK: Eingang

    private var inputTab: some View {
        let inp = mixer.defaultInput
        return VStack(alignment: .leading, spacing: 0) {
            if let v = mixer.inputVolumes[inp] {
                VolumeRow(value: v, symbol: v <= 0.001 ? "mic.slash.fill" : "mic.fill") { mixer.setInputVolume(inp, $0) }
            }
            SectionTitle("Eingang")
            ForEach(mixer.inputs) { dev in
                DeviceRow(device: dev, active: dev.id == inp) { mixer.selectInput(dev.id) }
            }
            if mixer.inputs.isEmpty { Caption("Kein Mikrofon gefunden.") }

            Separator()
            SectionTitle("Mikrofonmodus")
            MenuRow(action: { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }) {
                IconCircle(symbol: "waveform.badge.mic", active: mixer.micMode == .voiceIsolation)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.modeName(mixer.micMode))
                    Text("Sprachisolierung filtert Hintergrundgeräusche").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .help("Öffnet Apples Auswahl. Funktioniert, während eine App (FaceTime, Zoom …) das Mikrofon nutzt.")
        }
    }

    private static func modeName(_ m: AVCaptureDevice.MicrophoneMode) -> String {
        switch m {
        case .voiceIsolation: return "Sprachisolierung"
        case .wideSpectrum: return "Breites Spektrum"
        default: return "Standard"
        }
    }

    private func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Geräte-Zeile (wie ein WLAN-Netz)

private struct DeviceRow: View {
    let device: AudioDevice
    let active: Bool
    let select: () -> Void

    var body: some View {
        MenuRow(action: select) {
            IconCircle(symbol: device.symbol, active: active)
            Text(verbatim: device.name).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// Gekoppelte Kopfhörer, die gerade nicht am Mac hängen (z. B. am iPhone) – Klick holt sie her.
private struct BluetoothRow: View {
    let device: BTDevice
    let busy: Bool
    let connect: () -> Void

    var body: some View {
        MenuRow(action: connect) {
            IconCircle(symbol: device.symbol, active: false).opacity(0.6)
            Text(verbatim: device.name).lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text("Verbinden").font(.system(size: 11, weight: .medium)).foregroundStyle(.tint)
            }
        }
        .help("Zum Mac holen – auch wenn sie gerade am iPhone verbunden sind")
    }
}

/// Hinweis nach automatischem Ausgabewechsel: Ton ist aus / pausiert, bis man ihn wieder einschaltet.
private struct GuardBanner: View {
    let `guard`: SwitchGuard
    let release: () -> Void

    var body: some View {
        let paused = !`guard`.paused.isEmpty
        HStack(spacing: 10) {
            Image(systemName: paused ? "pause.fill" : "speaker.slash.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(Color.orange))
            VStack(alignment: .leading, spacing: 1) {
                Text(paused ? "Pausiert" : "Ton aus").font(.system(size: 12, weight: .semibold))
                Text("Ausgabe hat gewechselt").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: release) {
                Text(paused ? "Weiterspielen" : "Ton an").font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

// MARK: - App-Zeile (+ aufklappbarer EQ / Kompressor / Ausgabe)

private struct AppRow: View {
    @EnvironmentObject var mixer: Mixer
    let app: AudioApp
    let expanded: Bool
    let toggle: () -> Void
    @State private var hover = false
    /// Sofort umschalten statt auf CoreAudio zu warten (Spotify meldet „spielt“ noch Sekunden nach der Pause).
    @State private var optimistic: Bool?

    var body: some View {
        let s = mixer.setting(app)
        let routed = mixer.isRouted(app)
        let effects = (s.eq.on && !s.eq.isNeutral) || s.comp.on
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { mixer.update(app) { $0.muted.toggle() } } label: {
                    ZStack {
                        if let icon = app.icon { Image(nsImage: icon).resizable() } else { IconCircle(symbol: "app.fill", active: false) }
                        if s.muted {
                            Circle().fill(.black.opacity(0.55))
                            Image(systemName: "speaker.slash.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .opacity(app.isPlaying || s.muted ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .help(s.muted ? "Ton an" : "Stumm")

                let player = MediaControl.handles(app.id)
                Text(verbatim: app.name).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    .frame(width: player ? 70 : 96, alignment: .leading)   // 70 + Knopf 18 + Abstand 8 = 96 → Regler bündig
                    .help(routed ? (mixer.targetDevice(app)?.name ?? app.name) : app.name)

                if player {
                    let playing = optimistic ?? app.isPlaying
                    Button {
                        let want = !playing
                        optimistic = want
                        MediaControl.playPause(app.id)
                        // Spätestens nach 15 s wieder der echte Zustand.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { if optimistic == want { optimistic = nil } }
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 18, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(playing ? "Pausieren" : "Abspielen")
                    .onChange(of: app.isPlaying) { _, now in if now == optimistic { optimistic = nil } }
                }

                MeterReader(meters: mixer.meters, appID: app.id) { level in
                    ThinSlider(value: s.volume, range: 0...mixer.settings.maxBoost, mark: 1, level: level) { v in
                        mixer.update(app) { $0.volume = v }
                    }
                }
                .opacity(s.muted ? 0.4 : 1)

                Percent(s.volume)
                    .frame(width: 36, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { mixer.update(app) { $0.volume = 1 } }
                    .help("Klicken = 100 % (oder Doppelklick auf den Regler)")

                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(effects || routed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(hover || expanded ? 0.1 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
                .help("EQ, Kompressor, Ausgabe")
            }
            .padding(.horizontal, 8).frame(height: 32)

            if expanded {
                AppDetail(app: app)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(expanded ? 0.06 : 0)))
        .padding(.vertical, 1)
    }
}

private struct AppDetail: View {
    @EnvironmentObject var mixer: Mixer
    @Environment(\.openWindow) private var openWindow
    let app: AudioApp

    private func openCompressor() {
        NSApp.activate()
        openWindow(id: "compressor", value: app.id)
    }

    var body: some View {
        let s = mixer.setting(app)
        VStack(alignment: .leading, spacing: 10) {
            DetailRow("Ausgabe") {
                Menu {
                    Button("Systemausgabe") { mixer.update(app) { $0.deviceUID = nil } }
                    Divider()
                    ForEach(mixer.outputs) { d in
                        Button { mixer.update(app) { $0.deviceUID = d.uid } } label: { Text(verbatim: d.name) }
                    }
                } label: {
                    Text(verbatim: s.deviceUID.flatMap { u in mixer.outputs.first { $0.uid == u }?.name } ?? "Systemausgabe")
                }
                .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
            }

            DetailRow("Equalizer") {
                Menu {
                    ForEach(EQSettings.presets, id: \.name) { p in
                        Button(p.name) { mixer.update(app) { $0.eq.bands = p.bands; $0.eq.on = true } }
                    }
                } label: { Text(EQSettings.presets.first { $0.bands == s.eq.bands }?.name ?? "Eigene") }
                .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
                Toggle("", isOn: Binding(get: { s.eq.on }, set: { v in mixer.update(app) { $0.eq.on = v } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }

            EQCurve(bands: s.eq.bands, on: s.eq.on) { i, v in
                mixer.update(app) { if i < $0.eq.bands.count { $0.eq.bands[i] = v }; $0.eq.on = true }
            }

            DetailRow("Kompressor") {
                Menu {
                    ForEach(CompressorSettings.presets, id: \.name) { p in
                        Button(p.name) { mixer.update(app) { $0.comp = p.c } }
                    }
                    Divider()
                    Button("Anpassen …", action: openCompressor)
                } label: { Text(s.comp.presetName ?? "Eigene") }
                .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
                Button(action: openCompressor) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Kompressor-Fenster: Schwelle, Verhältnis, Attack, Release, Makeup")
                Toggle("", isOn: Binding(get: { s.comp.on }, set: { v in mixer.update(app) { $0.comp.on = v } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            .help("Gleicht laut und leise an – gut für Filme und Anrufe.")

            HStack {
                Spacer()
                Button("Zurücksetzen") { mixer.update(app) { $0 = AppSetting() } }
                    .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }
}

private struct DetailRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content
        }
        .frame(minHeight: 18)
    }
}

private struct MeterReader<Content: View>: View {
    @ObservedObject var meters: Meters
    let appID: String
    @ViewBuilder let content: (Float) -> Content
    var body: some View { content(meters.levels[appID] ?? 0) }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Bausteine im Kontrollzentrum-Stil

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            .padding(.horizontal, 8).padding(.vertical, 8)
    }
}

private struct Badge: View {
    let symbol: String
    let text: String
    let color: Color
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

private struct Notice: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(verbatim: text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.12)))
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

private struct TabButton: View {
    let symbol: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(active ? Color.accentColor : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Runder Symbol-Knopf (Reparieren, Beenden).
private struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.14 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Runder Symbol-Kreis wie bei WLAN-Netzen: blau gefüllt = aktiv.
struct IconCircle: View {
    let symbol: String
    let active: Bool
    var body: some View {
        ZStack {
            Circle().fill(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1)))
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .frame(width: 24, height: 24)
    }
}

/// Ganze Zeile klickbar, beim Überfahren grau hinterlegt (wie Menüeinträge).
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content; Spacer(minLength: 0) }
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Percent: View {
    let value: Float
    init(_ value: Float) { self.value = value }
    var body: some View {
        Text(verbatim: "\(Int((value * 100).rounded())) %")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(value > 1.001 ? Color.orange : Color.secondary)
    }
}

// MARK: - Regler

private func fraction(_ v: Float, _ r: ClosedRange<Float>) -> CGFloat {
    guard r.upperBound > r.lowerBound, v.isFinite else { return 0 }
    return CGFloat((min(max(v, r.lowerBound), r.upperBound) - r.lowerBound) / (r.upperBound - r.lowerBound))
}

/// Hauptlautstärke: Symbol, Regler, Prozent – gleiche Optik wie die App-Zeilen, nur etwas kräftiger.
private struct VolumeRow: View {
    let value: Float
    let symbol: String
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 24)
                .animation(nil, value: symbol)
            ThinSlider(value: value, range: 0...1, knob: 16, onChange: onChange)
            Text(verbatim: "\(Int((value * 100).rounded())) %")
                .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 8).frame(height: 28)
    }
}

/// Schmaler Regler mit Knopf (wie die Regler in den Systemeinstellungen).
/// `mark` = kleiner Strich (100 % bei Boost), an dem der Knopf leicht einrastet (mit Trackpad-Klick-Gefühl);
/// Doppelklick setzt auf `mark` zurück. `level` = Pegel als Schimmer in der Füllung.
struct ThinSlider: View {
    let value: Float
    let range: ClosedRange<Float>
    var mark: Float? = nil
    var level: Float = 0
    var knob: CGFloat = 14
    let onChange: (Float) -> Void
    @State private var snapped = false
    private var track: CGFloat { knob > 14 ? 5 : 4 }
    private static let snapPixels: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = knob / 2 + (w - knob) * fraction(value, range)
            let boosted = mark.map { value > $0 + 0.001 } ?? false
            let tint = boosted ? Color.orange : Color.accentColor
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14)).frame(height: track)
                Capsule().fill(tint).frame(width: x, height: track)
                if level > 0.001 {
                    Capsule().fill(Color.white.opacity(0.55))
                        .frame(width: x * CGFloat(min(level, 1)), height: track - 2)
                        .padding(.leading, 1)
                }
                if let mark {
                    Capsule().fill(Color.primary.opacity(0.3))
                        .frame(width: 2, height: 8)
                        .offset(x: knob / 2 + (w - knob) * fraction(mark, range) - 1)
                }
                Circle().fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: x - knob / 2)
            }
            .frame(width: w, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let px = min(max(g.location.x - knob / 2, 0), max(w - knob, 1))
                var v = range.lowerBound + Float(px / max(w - knob, 1)) * (range.upperBound - range.lowerBound)
                if let mark {
                    let markPx = (w - knob) * fraction(mark, range)
                    let inSnap = abs(px - markPx) < Self.snapPixels
                    if inSnap { v = mark }
                    if inSnap && !snapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                    snapped = inSnap
                }
                onChange(v)
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { if let mark { onChange(mark) } })
        }
        .frame(height: knob + 4)
    }
}
