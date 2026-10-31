import AppKit
import AVFoundation
import CoreBluetooth
import CoreAudio
import os

private let log = Logger(subsystem: "com.gabrielsuntinger.SoundController", category: "mixer")

struct AudioApp: Identifiable {
    let id: String          // Bundle-ID der (Eltern-)App
    let name: String
    let icon: NSImage?
    let processIDs: [AudioObjectID]
    let isPlaying: Bool
    let usesMic: Bool
}

/// Schutz nach automatischem Ausgabewechsel: Ton aus bzw. pausiert, bis man „Ton an“ drückt.
enum SwitchGuard: Equatable {
    case muted(AudioDeviceID)      // Hardware-Stumm am neuen Gerät
    case soft(paused: [String])    // alle Apps per Umleitung auf 0, Spotify/Musik zusätzlich pausiert

    var paused: [String] { if case .soft(let p) = self { return p }; return [] }
}

/// Pegelanzeigen getrennt vom Rest, damit 12×/s nur die Meter neu zeichnen.
@MainActor
final class Meters: ObservableObject {
    @Published var levels: [String: Float] = [:]
    @Published var reductions: [String: Float] = [:]   // Kompressor-Absenkung in dB
}

@MainActor
final class Mixer: ObservableObject {
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var defaultOutput: AudioDeviceID = 0
    @Published private(set) var defaultInput: AudioDeviceID = 0
    @Published private(set) var volumes: [AudioDeviceID: Float] = [:]       // nur Geräte mit Hardware-Regler
    @Published private(set) var inputVolumes: [AudioDeviceID: Float] = [:]
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var callActive = false
    @Published private(set) var lastError: String?
    @Published private(set) var conflictApp: String?
    @Published private(set) var healing = false
    @Published private(set) var switchGuard: SwitchGuard?
    @Published private(set) var bluetooth: [BTDevice] = []
    @Published private(set) var connecting: String?
    @Published private(set) var customIcon: NSImage?
    @Published private(set) var micMode = AVCaptureDevice.activeMicrophoneMode   // nur lesen, Apple verwaltet ihn
    @Published var settings = Settings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.iconTemplate != oldValue.iconTemplate { reloadIcon() }
            apply()
        }
    }
    let meters = Meters()
    var compressorWindows = 0                    // offene Kompressor-Fenster (dann laufen die Meter weiter)
    var menuVisible = false {
        didSet { if menuVisible && !oldValue { refreshBluetooth() } }
    }

    private var taps: [String: AppTap] = [:]
    private var failed: [String: Date] = [:]             // nicht im Sekundentakt erneut versuchen
    private var stalls: [String: (count: Int, seen: Int)] = [:]
    private var seen: Set<String> = []
    private var knownDevices: Set<AudioDeviceID> = []
    private var quietUntil = Date().addingTimeInterval(3)  // kein Pausieren/Popup direkt nach Start
    private var manualUntil = Date.distantPast              // Wechsel per Klick im Menü → kein Schutz nötig
    private var wantBluetooth: String?                      // gerade verbundene Kopfhörer → sofort dorthin wechseln
    private var timer: Timer?
    private var meterTimer: Timer?

    private static let conflicting = ["com.finetuneapp.FineTune": "FineTune", "com.rogueamoeba.soundsource": "SoundSource",
                                      "com.bitgapp.eqMac": "eqMac", "com.kazakov.BackgroundMusic": "Background Music"]

    init() {
        customIcon = IconStore.load(template: settings.iconTemplate)
        refreshDevices()
        knownDevices = Set(outputs.map(\.id))
        CA.listen(CA.system, kAudioHardwarePropertyDevices) { [weak self] in self?.devicesChanged() }
        CA.listen(CA.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.defaultChanged() }
        CA.listen(CA.system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.refreshDevices() }
        // coreaudiod neu gestartet (z. B. nach `killall coreaudiod`) → alle Umleitungen sind tot.
        CA.listen(CA.system, kAudioHardwarePropertyServiceRestarted) { [weak self] in
            log.info("coreaudiod neu gestartet → neu aufbauen")
            self?.refreshDevices()
            self?.rebuildAll(after: 1.5)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.quietUntil = Date().addingTimeInterval(4)
                self?.refreshDevices()
                self?.rebuildAll(after: 2)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeters() }
        }
        tick()
    }

    var currentOutput: AudioDevice? { outputs.first { $0.id == defaultOutput } }
    var currentVolume: Float { volumes[defaultOutput] ?? settings.softMaster }

    // MARK: Geräte

    func selectOutput(_ id: AudioDeviceID) {
        manualUntil = Date().addingTimeInterval(2)
        Devices.setDefaultOutput(id)
    }

    /// Ausgaben in der Reihenfolge der Prioritätsliste (Unbekannte hinten).
    var sortedOutputs: [AudioDevice] {
        let rank = Dictionary(settings.priority.enumerated().map { ($1.uid, $0) }, uniquingKeysWith: { a, _ in a })
        return outputs.enumerated().sorted { (rank[$0.element.uid] ?? 1000 + $0.offset) < (rank[$1.element.uid] ?? 1000 + $1.offset) }.map(\.element)
    }

    private func bestOutput() -> AudioDevice? {
        for k in settings.priority { if let d = outputs.first(where: { $0.uid == k.uid }) { return d } }
        return nil
    }

    /// Neue Geräte merken: Kopfhörer vorne (wie macOS), alles andere hinten.
    private func learnDevices() {
        var p = settings.priority
        for d in outputs where !p.contains(where: { $0.uid == d.uid }) {
            let k = KnownDevice(uid: d.uid, name: String(d.name.prefix(120)), symbol: d.symbol)
            if d.isHeadphones { p.insert(k, at: 0) } else { p.append(k) }
        }
        if p.count > 40 { p = Array(p.prefix(40)) }
        if p != settings.priority { settings.priority = p }
    }

    func movePriority(_ uid: String, by delta: Int) {
        guard let i = settings.priority.firstIndex(where: { $0.uid == uid }) else { return }
        let j = min(max(i + delta, 0), settings.priority.count - 1)
        guard i != j else { return }
        settings.priority.swapAt(i, j)
    }

    func forgetDevice(_ uid: String) { settings.priority.removeAll { $0.uid == uid } }

    // MARK: Bluetooth

    /// Bluetooth erst abfragen, wenn erlaubt – sonst würde schon das Öffnen des Menüs die Berechtigungs-Abfrage auslösen.
    var needsBluetoothPermission: Bool { settings.showBluetooth && CBManager.authorization == .notDetermined }

    /// Nur auf Klick: löst einmalig die macOS-Abfrage „Bluetooth“ aus.
    func enableBluetooth() {
        _ = Bluetooth.shared.pairedAudio()
        objectWillChange.send()
        refreshBluetooth()
    }

    func refreshBluetooth() {
        guard settings.showBluetooth, CBManager.authorization == .allowedAlways else { bluetooth = []; return }
        let list = Bluetooth.shared.pairedAudio().filter { !$0.connected }
        if list != bluetooth { bluetooth = list }
    }

    func connectBluetooth(_ dev: BTDevice) {
        guard connecting == nil else { return }
        connecting = dev.id
        wantBluetooth = dev.id
        Bluetooth.shared.connect(dev.id) { [weak self] ok in
            guard let self else { return }
            self.connecting = nil
            if !ok { self.wantBluetooth = nil; self.lastError = "„\(dev.name)“ konnte nicht verbunden werden. Ist das Case offen?" }
            self.refreshBluetooth()
        }
    }

    // MARK: Menüleisten-Symbol

    @discardableResult
    func setCustomIcon(_ url: URL) -> Bool {
        guard IconStore.importIcon(from: url) else { return false }
        reloadIcon()
        if customIcon != nil { settings.menuIcon = Settings.customIcon }
        return customIcon != nil
    }

    func removeCustomIcon() {
        IconStore.remove()
        customIcon = nil
        if settings.menuIcon == Settings.customIcon { settings.menuIcon = Settings.icons[0] }
    }

    private func reloadIcon() { customIcon = IconStore.load(template: settings.iconTemplate) }
    func selectInput(_ id: AudioDeviceID) { Devices.setDefaultInput(id) }

    func setVolume(device id: AudioDeviceID, _ v: Float) {
        if volumes[id] != nil {
            Devices.setVolume(id, v)
            volumes[id] = v
        } else if id == defaultOutput {
            settings.softMaster = v
        }
    }

    func setInputVolume(_ id: AudioDeviceID, _ v: Float) {
        Devices.setVolume(id, v, input: true)
        inputVolumes[id] = v
    }

    private func refreshDevices() {
        outputs = Devices.outputs()
        inputs = Devices.inputs()
        defaultOutput = Devices.defaultOutput
        defaultInput = Devices.defaultInput
        refreshVolumes()
        learnDevices()
    }

    private func refreshVolumes() {
        var v: [AudioDeviceID: Float] = [:]
        for d in outputs { v[d.id] = Devices.volume(d.id) }
        if v != volumes { volumes = v }
        var iv: [AudioDeviceID: Float] = [:]
        for d in inputs { iv[d.id] = Devices.volume(d.id, input: true) }
        if iv != inputVolumes { inputVolumes = iv }
    }

    private func devicesChanged() {
        let before = knownDevices
        refreshDevices()
        knownDevices = Set(outputs.map(\.id))
        // Unsere eigenen Aggregates lösen das Event auch aus – nur echte Änderungen zählen (sonst Endlosschleife).
        guard knownDevices != before else { return }
        // Frische Aggregate-Devices bauen: alte zeigen nach Ab-/Anstecken (Hub, Monitor) oft ins Leere.
        rebuildAll(after: 0.5)
        if menuVisible { refreshBluetooth() }

        guard Date() > quietUntil else { return }
        let added = outputs.filter { !before.contains($0.id) }
        let removed = !before.subtracting(knownDevices).isEmpty
        // macOS wechselt bei AirPods oft selbst – kurz warten, dann passend reagieren.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            // Gerade per Klick verbundene Kopfhörer → dorthin.
            if let want = self.wantBluetooth?.uppercased(),
               let d = self.outputs.first(where: { $0.uid.uppercased().hasPrefix(want) }) {
                self.wantBluetooth = nil
                self.selectOutput(d.id)
            } else if self.settings.autoSwitch, let best = self.bestOutput(), best.id != Devices.defaultOutput,
                      removed || added.contains(where: { $0.id == best.id }) {
                Devices.setDefaultOutput(best.id)   // automatisch → Schutz greift in defaultChanged
            }
            for dev in added where self.outputs.contains(dev) {
                let active = Devices.defaultOutput == dev.id
                // Monitor über Hub/DisplayPort: oft „ausgewählt, aber stumm“ → einmal anstoßen.
                if active && dev.isMonitor && self.settings.autoHeal { self.nudge() }
                guard self.settings.notchPopup, self.switchGuard == nil else { continue }
                if active {
                    NotchPopup.shared.show(symbol: dev.symbol, title: dev.name, subtitle: "Verbunden · Ton läuft hier")
                } else {
                    NotchPopup.shared.show(symbol: dev.symbol, title: dev.name, subtitle: "Verbunden",
                                           action: ("Hier abspielen", { [weak self] in self?.selectOutput(dev.id) }))
                }
            }
        }
    }

    private func defaultChanged() {
        let old = defaultOutput
        refreshDevices()
        guard defaultOutput != old else { return }
        let automatic = Date() > quietUntil && Date() > manualUntil
        if case .muted(let id) = switchGuard, id != defaultOutput { Devices.setMute(id, false); switchGuard = nil }
        if automatic { protectAfterSwitch() }
        rebuildAll(after: 0.3)
        if settings.autoHeal, currentOutput?.isMonitor == true, Date() > quietUntil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.nudge() }
        }
    }

    /// Ausgabe hat von selbst gewechselt (Kopfhörer weg, Gerät neu …): damit in der Öffentlichkeit
    /// nichts laut losgeht, Ton aus bzw. Musik pausieren – mit Popup „Ton an“ / „Weiterspielen“.
    private func protectAfterSwitch() {
        guard settings.switchAction != .nothing, let dev = currentOutput,
              !dev.isHeadphones || settings.pauseOnHeadphones,
              apps.contains(where: \.isPlaying) else { return }
        releaseGuard(resume: false)
        if settings.switchAction == .mute && !dev.isHeadphones && Devices.canMute(dev.id) {
            Devices.setMute(dev.id, true)
            switchGuard = .muted(dev.id)
        } else {
            // Kopfhörer, Gerät ohne Stumm-Schalter oder „Musik pausieren“: Player anhalten und
            // alles andere per Umleitung stumm – so bleibt es still, auch wenn Pausieren nicht klappt.
            switchGuard = .soft(paused: MediaControl.pauseAll())
        }
        let paused = !(switchGuard?.paused.isEmpty ?? true)
        let (title, button) = paused ? ("Pausiert", "Weiterspielen") : ("Ton aus", "Ton an")
        log.info("Ausgabewechsel → Schutz aktiv")
        apply()
        NotchPopup.shared.show(symbol: dev.isHeadphones ? dev.symbol : "speaker.slash.fill", title: title, subtitle: "Ausgabe gewechselt zu \(dev.name)",
                               action: (button, { [weak self] in self?.releaseGuard() }), duration: .infinity)
    }

    /// „Ton an“: Stumm aufheben und ggf. pausierte Player weiterspielen lassen.
    func releaseGuard(resume: Bool = true) {
        guard let g = switchGuard else { return }
        switchGuard = nil
        NotchPopup.shared.hide()
        switch g {
        case .muted(let id): Devices.setMute(id, false)
        case .soft(let p): if resume { MediaControl.resume(p) }
        }
        apply()
    }

    /// Ausgabe kurz auf ein anderes Gerät und zurück – derselbe Effekt wie „Monitor neu einstecken“.
    private func nudge() {
        let current = Devices.defaultOutput
        guard let other = outputs.first(where: { $0.id != current && !$0.isMonitor }) ?? outputs.first(where: { $0.id != current }) else { return }
        log.info("Ausgabe anstoßen")
        quietUntil = Date().addingTimeInterval(3)
        healing = true
        Devices.setDefaultOutput(other.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Devices.setDefaultOutput(current)
            self?.refreshDevices()
            self?.rebuildAll(after: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.healing = false }
        }
    }

    /// Manuell: alles neu (Umleitungen + Ausgabe anstoßen).
    func repair() {
        teardownAll()
        failed.removeAll()
        lastError = nil
        refreshDevices()
        if outputs.count > 1 { nudge() } else { rebuildAll(after: 0.3) }
    }

    // MARK: Apps

    private func tick() {
        refreshVolumes()
        let mode = AVCaptureDevice.activeMicrophoneMode
        if mode != micMode { micMode = mode }
        // Selbst entstummt (Tastatur, Kontrollzentrum) → Schutz ist erledigt.
        if case .muted(let id) = switchGuard, !Devices.isMuted(id) { switchGuard = nil; NotchPopup.shared.hide() }
        let running = NSWorkspace.shared.runningApplications
        conflictApp = running.compactMap { $0.bundleIdentifier.flatMap { Self.conflicting[$0] } }.first

        let regular = running.filter { $0.activationPolicy == .regular }
        var groups: [String: (name: String, icon: NSImage?, ids: [AudioObjectID], playing: Bool, mic: Bool)] = [:]
        var anyMic = false
        let me = Bundle.main.bundleIdentifier ?? "com.gabrielsuntinger.SoundController"
        for p in AudioProc.all() where p.pid != getpid() && p.bundleID != me {
            guard let app = resolve(p, regular: regular) else { continue }
            // Nur echte Apps (oder der FaceTime-Dienst) zählen als Anruf – nicht Siri-Erkennung o. Ä.
            if p.isInput && (app.isRegular || Self.callServices.contains(p.bundleID)) { anyMic = true }
            var g = groups[app.key] ?? (app.name, app.icon, [], false, false)
            g.ids.append(p.objectID)
            g.playing = g.playing || p.isOutput
            g.mic = g.mic || p.isInput
            groups[app.key] = g
        }
        for (k, g) in groups where g.playing { seen.insert(k) }
        seen.formIntersection(groups.keys)

        apps = groups.filter { seen.contains($0.key) }
            .map { AudioApp(id: $0.key, name: $0.value.name, icon: $0.value.icon,
                            processIDs: $0.value.ids.sorted(), isPlaying: $0.value.playing, usesMic: $0.value.mic) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        callActive = anyMic
        apply()
        watchdog()
    }

    private static let webKitSuffixes = [" Graphics and Media", " Web Content", " Networking", " Grafik und Medien", " Webinhalte", " Netzwerk"]
    private static let callServices: Set<String> = ["com.apple.avconferenced", "com.apple.FaceTime", "com.apple.TelephonyUtilities"]

    private func resolve(_ p: AudioProc, regular: [NSRunningApplication]) -> (key: String, name: String, icon: NSImage?, isRegular: Bool)? {
        if let a = NSRunningApplication(processIdentifier: p.pid), a.activationPolicy == .regular, let b = a.bundleIdentifier {
            return (b, a.localizedName ?? b, a.icon, true)
        }
        // Helfer-Prozesse (z. B. com.google.Chrome.helper) der Eltern-App zuordnen.
        if !p.bundleID.isEmpty, let a = regular.first(where: { $0.bundleIdentifier.map { p.bundleID.hasPrefix($0 + ".") } ?? false }),
           let b = a.bundleIdentifier {
            return (b, a.localizedName ?? b, a.icon, true)
        }
        // WebKit-Prozesse heißen „<App> Graphics and Media“ / „<App> Web Content“ → zur App mit diesem Namen.
        if p.bundleID.hasPrefix("com.apple.WebKit") {
            let name = NSRunningApplication(processIdentifier: p.pid)?.localizedName ?? ""
            let owner = Self.webKitSuffixes.compactMap { name.hasSuffix($0) ? String(name.dropLast($0.count)) : nil }.first
            if let owner, !owner.isEmpty, let a = regular.first(where: { $0.localizedName == owner }), let b = a.bundleIdentifier {
                return (b, a.localizedName ?? b, a.icon, true)
            }
            if let a = regular.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
                return ("com.apple.Safari", a.localizedName ?? "Safari", a.icon, true)
            }
        }
        let a = NSRunningApplication(processIdentifier: p.pid)
        let key = p.bundleID.isEmpty ? "pid.\(p.pid)" : p.bundleID
        return (key, a?.localizedName ?? (p.bundleID.isEmpty ? "PID \(p.pid)" : p.bundleID), a?.icon, false)
    }

    func setting(_ app: AudioApp) -> AppSetting { setting(app.id) }
    func setting(_ id: String) -> AppSetting { settings.apps[id] ?? AppSetting() }

    func update(_ app: AudioApp, _ change: (inout AppSetting) -> Void) { update(app.id, change) }

    func update(_ id: String, _ change: (inout AppSetting) -> Void) {
        guard !id.isEmpty, id.count <= 512 else { return }
        var s = setting(id)
        change(&s)
        s.volume = abs(s.volume - 1) < 0.01 ? 1 : min(max(s.volume, 0), settings.maxBoost)
        s.comp.clamp()
        settings.apps[id] = s.isDefault ? nil : s
    }

    /// Name/Symbol für das Kompressor-Fenster, auch wenn die App gerade keinen Ton spielt.
    func appInfo(_ id: String) -> (name: String, icon: NSImage?) {
        if let a = apps.first(where: { $0.id == id }) { return (a.name, a.icon) }
        if let r = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return (r.localizedName ?? id, r.icon) }
        return (id, nil)
    }

    func isRouted(_ app: AudioApp) -> Bool { targetDevice(app)?.id != defaultOutput }

    func targetDevice(_ app: AudioApp) -> AudioDevice? {
        if let uid = setting(app).deviceUID, let d = outputs.first(where: { $0.uid == uid }) { return d }
        return currentOutput
    }

    func effectiveGain(_ app: AudioApp) -> Float {
        let s = setting(app)
        if s.muted { return 0 }
        if case .soft = switchGuard, !isRouted(app) { return 0 }
        var g = s.volume
        if volumes[defaultOutput] == nil && !isRouted(app) { g *= settings.softMaster }
        if callActive && settings.callBoostOn && !app.usesMic { g *= settings.callBoost }
        return g
    }

    // MARK: Taps verwalten

    /// Taps werden auf einer eigenen Queue gebaut/abgebaut: Hängt coreaudiod (z. B. nach Hub-Ab-/Anstecken)
    /// oder wartet macOS auf die Berechtigung, friert das Menü nicht ein.
    private let tapQueue = DispatchQueue(label: "AudioPilot.taps", qos: .userInitiated)
    private var pending: [String: Int] = [:]   // App → Generation des laufenden Aufbaus
    private var generation = 0                 // steigt bei teardownAll → veraltete Ergebnisse verwerfen

    private func apply() {
        var wanted = Set<String>()
        for app in apps {
            guard let out = targetDevice(app) else { continue }
            let s = setting(app)
            let gain = effectiveGain(app)
            let needed = gain != 1 || (s.eq.on && !s.eq.isNeutral) || s.comp.on || out.id != defaultOutput
            guard needed else { continue }
            wanted.insert(app.id)
            if let t = taps[app.id], t.outputUID == out.uid, t.processIDs == app.processIDs {
                t.params.update(gain: gain, setting: s)
                continue
            }
            guard pending[app.id] == nil else { continue }
            if let old = taps.removeValue(forKey: app.id) { tapQueue.async { old.stop() } }
            if let f = failed[app.id], Date().timeIntervalSince(f) < 5 { continue }
            build(app, output: out, gain: gain, setting: s)
        }
        for (k, t) in taps where !wanted.contains(k) {
            taps[k] = nil
            stalls[k] = nil
            tapQueue.async { t.stop() }
        }
    }

    private func build(_ app: AudioApp, output out: AudioDevice, gain: Float, setting: AppSetting) {
        let gen = generation, id = app.id, name = app.name, pids = app.processIDs, q = tapQueue
        pending[id] = gen
        q.async {
            let result = Result { try AppTap(processIDs: pids, outputUID: out.uid, gain: gain, setting: setting) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else {
                        if case .success(let t) = result { q.async { t.stop() } }
                        return
                    }
                    self.pending[id] = nil
                    switch result {
                    case .success(let t):
                        self.taps[id] = t
                        self.failed[id] = nil
                        self.lastError = nil
                        log.info("Tap an: \(id, privacy: .public) → \(out.name, privacy: .public)")
                        self.apply()   // inzwischen geänderte Werte übernehmen / Überflüssiges abbauen
                    case .failure(let error):
                        self.failed[id] = Date()
                        log.error("Tap-Fehler \(id, privacy: .public): \(String(describing: error), privacy: .public)")
                        self.lastError = "\(name): \(error). Ggf. „Systemaudio-Aufnahme“ in den Datenschutz-Einstellungen erlauben."
                    }
                }
            }
        }
    }

    /// Selbstheilung: Läuft der Audio-Callback einer Umleitung 3 s nicht mehr, wird sie neu gebaut.
    private func watchdog() {
        guard settings.autoHeal else { return }
        for (id, t) in taps {
            let c = t.params.callbacks.load(ordering: .relaxed)
            if let prev = stalls[id], prev.seen == c {
                let n = prev.count + 1
                stalls[id] = (n, c)
                if n >= 3 {
                    log.error("Tap hängt: \(id, privacy: .public) → neu bauen")
                    taps[id] = nil
                    stalls[id] = nil
                    failed[id] = nil
                    tapQueue.async { t.stop() }
                }
            } else {
                stalls[id] = (0, c)
            }
        }
    }

    private func updateMeters() {
        guard menuVisible || compressorWindows > 0 else { return }
        var l: [String: Float] = [:], gr: [String: Float] = [:]
        for (id, t) in taps {
            let old = meters.levels[id] ?? 0
            let v = max(t.params.peak, old * 0.82)
            l[id] = v < 0.001 ? 0 : v
            let r = t.params.reduction
            gr[id] = r.isFinite && r > 0.05 ? min(r, 60) : 0
        }
        if l != meters.levels { meters.levels = l }
        if gr != meters.reductions { meters.reductions = gr }
    }

    private func teardownAll() {
        generation += 1
        pending.removeAll()
        stalls.removeAll()
        let all = Array(taps.values)
        taps.removeAll()
        tapQueue.async { all.forEach { $0.stop() } }
    }

    private func rebuildAll(after delay: Double) {
        teardownAll()
        failed.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
    }

    func resetAllApps() { settings.apps.removeAll() }

    func shutdown() {
        teardownAll()
        tapQueue.sync {}   // warten, bis alles abgebaut ist
    }
}
