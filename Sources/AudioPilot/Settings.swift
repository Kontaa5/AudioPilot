import Foundation

/// 10-Band-EQ (32 Hz … 16 kHz), Werte in dB −12…+12.
struct EQSettings: Codable, Equatable {
    static let freqs: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let presets: [(name: String, bands: [Float])] = [
        ("Neutral", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Mehr Bass", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        ("Weniger Bass", [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
        ("Stimme", [-4, -3, -1, 1, 3, 4, 3, 1, 0, -2]),
        ("Höhen", [0, 0, 0, 0, 0, 0, 1, 3, 5, 6]),
        ("Loudness", [5, 4, 2, 0, -1, 0, 0, 2, 4, 5]),
        ("Laptop-Lautsprecher", [-6, -3, 2, 3, 1, 0, 0, 1, 2, 2]),
    ]

    var on = false
    var bands: [Float] = Array(repeating: 0, count: 10)

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        bands = try c.decodeIfPresent([Float].self, forKey: .bands) ?? bands
    }

    var isNeutral: Bool { bands.allSatisfy { $0 == 0 } }
}

/// Kompressor wie in Audio-Programmen. Bereiche siehe `clamp`.
struct CompressorSettings: Codable, Equatable {
    var on = false
    // Standard = Voreinstellung „Sanft“
    var threshold: Float = -18   // dB
    var ratio: Float = 2         // x : 1
    var attack: Float = 20       // ms
    var release: Float = 250     // ms
    var makeup: Float = 3        // dB
    var knee: Float = 8          // dB (weicher Einsatz)

    static let ranges = (threshold: Float(-60)...0, ratio: Float(1)...20, attack: Float(0.1)...100,
                         release: Float(10)...1000, makeup: Float(0)...24, knee: Float(0)...12)

    static let presets: [(name: String, c: CompressorSettings)] = [
        ("Sanft", .init(on: true, threshold: -18, ratio: 2, attack: 20, release: 250, makeup: 3, knee: 8)),
        ("Musik", .init(on: true, threshold: -14, ratio: 2.5, attack: 30, release: 300, makeup: 2, knee: 6)),
        ("Sprache", .init(on: true, threshold: -24, ratio: 3, attack: 5, release: 120, makeup: 6, knee: 6)),
        ("Film / Nacht", .init(on: true, threshold: -30, ratio: 4, attack: 10, release: 300, makeup: 9, knee: 6)),
        ("Stark", .init(on: true, threshold: -36, ratio: 8, attack: 2, release: 100, makeup: 12, knee: 4)),
    ]

    init() {}
    init(on: Bool, threshold: Float, ratio: Float, attack: Float, release: Float, makeup: Float, knee: Float) {
        self.on = on; self.threshold = threshold; self.ratio = ratio; self.attack = attack
        self.release = release; self.makeup = makeup; self.knee = knee
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = CompressorSettings()
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        threshold = try c.decodeIfPresent(Float.self, forKey: .threshold) ?? def.threshold
        ratio = try c.decodeIfPresent(Float.self, forKey: .ratio) ?? def.ratio
        attack = try c.decodeIfPresent(Float.self, forKey: .attack) ?? def.attack
        release = try c.decodeIfPresent(Float.self, forKey: .release) ?? def.release
        makeup = try c.decodeIfPresent(Float.self, forKey: .makeup) ?? def.makeup
        knee = try c.decodeIfPresent(Float.self, forKey: .knee) ?? def.knee
    }

    /// Name der passenden Voreinstellung (Ein/Aus egal), sonst nil.
    var presetName: String? {
        Self.presets.first { var p = $0.c; p.on = on; return p == self }?.name
    }

    mutating func clamp() {
        func c(_ v: Float, _ r: ClosedRange<Float>, _ d: Float) -> Float { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : d }
        let def = CompressorSettings(), r = Self.ranges
        threshold = c(threshold, r.threshold, def.threshold)
        ratio = c(ratio, r.ratio, def.ratio)
        attack = c(attack, r.attack, def.attack)
        release = c(release, r.release, def.release)
        makeup = c(makeup, r.makeup, def.makeup)
        knee = c(knee, r.knee, def.knee)
    }
}

struct AppSetting: Codable, Equatable {
    var volume: Float = 1        // 0…4 (400 %)
    var muted = false
    var eq = EQSettings()
    var comp = CompressorSettings()
    var deviceUID: String?       // nil = Systemausgabe folgen

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        eq = try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? EQSettings()
        comp = (try? c.decodeIfPresent(CompressorSettings.self, forKey: .comp)) ?? CompressorSettings()
        deviceUID = try c.decodeIfPresent(String.self, forKey: .deviceUID)
    }

    var isDefault: Bool { volume == 1 && !muted && !eq.on && comp == CompressorSettings() && deviceUID == nil }
}

/// Ein Ausgabegerät, das schon einmal da war – für die Prioritätsliste.
struct KnownDevice: Codable, Equatable, Identifiable {
    var uid: String
    var name: String
    var symbol: String
    var id: String { uid }
}

/// Was passiert, wenn die Ausgabe von selbst wechselt (z. B. AirPods raus → Lautsprecher).
enum SwitchAction: String, Codable, CaseIterable {
    case mute, pause, nothing
}

struct Settings: Codable, Equatable {
    static let icons = ["speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.fill", "speaker.wave.2",
                        "hifispeaker.fill", "hifispeaker", "homepod.fill", "waveform", "slider.horizontal.3"]
    static let customIcon = "custom"

    var apps: [String: AppSetting] = [:]
    var callBoostOn = true
    var callBoost: Float = 2.5
    var softMaster: Float = 1     // Software-Lautstärke für Geräte ohne Hardware-Regler (z. B. DisplayPort)
    var maxBoost: Float = 4
    var switchAction = SwitchAction.mute
    var guardHeadphones = false   // auch beim Wechsel auf Kopfhörer stumm schalten
    var notchPopup = true
    var autoHeal = true           // hängende Umleitungen neu bauen, Monitor-Ton anstoßen
    var menuIcon = "speaker.wave.2.fill"
    var iconShowsLevel = false
    var iconTemplate = true       // eigenes Symbol einfarbig wie Systemsymbole
    var iconFollowsDevice = true  // bei Kopfhörern/AirPods deren Symbol zeigen
    var priority: [KnownDevice] = []
    var autoSwitch = true         // immer zum wichtigsten verfügbaren Gerät wechseln
    var showBluetooth = true      // gekoppelte, nicht verbundene Kopfhörer zum Verbinden anzeigen

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Settings()
        apps = try c.decodeIfPresent([String: AppSetting].self, forKey: .apps) ?? [:]
        callBoostOn = try c.decodeIfPresent(Bool.self, forKey: .callBoostOn) ?? def.callBoostOn
        callBoost = try c.decodeIfPresent(Float.self, forKey: .callBoost) ?? def.callBoost
        softMaster = try c.decodeIfPresent(Float.self, forKey: .softMaster) ?? def.softMaster
        maxBoost = try c.decodeIfPresent(Float.self, forKey: .maxBoost) ?? def.maxBoost
        switchAction = (try? c.decodeIfPresent(SwitchAction.self, forKey: .switchAction)) ?? def.switchAction
        guardHeadphones = try c.decodeIfPresent(Bool.self, forKey: .guardHeadphones) ?? def.guardHeadphones
        notchPopup = try c.decodeIfPresent(Bool.self, forKey: .notchPopup) ?? def.notchPopup
        autoHeal = try c.decodeIfPresent(Bool.self, forKey: .autoHeal) ?? def.autoHeal
        menuIcon = try c.decodeIfPresent(String.self, forKey: .menuIcon) ?? def.menuIcon
        iconShowsLevel = try c.decodeIfPresent(Bool.self, forKey: .iconShowsLevel) ?? def.iconShowsLevel
        iconTemplate = try c.decodeIfPresent(Bool.self, forKey: .iconTemplate) ?? def.iconTemplate
        iconFollowsDevice = try c.decodeIfPresent(Bool.self, forKey: .iconFollowsDevice) ?? def.iconFollowsDevice
        priority = (try? c.decodeIfPresent([KnownDevice].self, forKey: .priority)) ?? []
        autoSwitch = try c.decodeIfPresent(Bool.self, forKey: .autoSwitch) ?? def.autoSwitch
        showBluetooth = try c.decodeIfPresent(Bool.self, forKey: .showBluetooth) ?? def.showBluetooth
    }

    private static let key = "settings.v2"

    static func load() -> Settings {
        UserDefaults.standard.removeObject(forKey: "settings.v1")   // altes Format (v1) wird nicht mehr gebraucht
        guard let data = UserDefaults.standard.data(forKey: key) else { return Settings() }
        do {
            var s = try JSONDecoder().decode(Settings.self, from: data)
            s.clamp()
            return s
        } catch {
            // Kaputte Daten sichern statt still überschreiben.
            UserDefaults.standard.set(data, forKey: key + ".broken")
            return Settings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Werte aus der Datei nie blind übernehmen (z. B. NaN, 1000 % oder fremde Symbolnamen).
    mutating func clamp() {
        func c(_ v: Float, _ lo: Float, _ hi: Float, _ d: Float) -> Float { v.isFinite ? min(max(v, lo), hi) : d }
        maxBoost = [2, 3, 4].contains(maxBoost) ? maxBoost : 4
        for k in apps.keys {
            guard var a = apps[k] else { continue }
            a.volume = c(a.volume, 0, maxBoost, 1)
            a.comp.clamp()
            a.eq.bands = (0..<10).map { i in i < a.eq.bands.count ? c(a.eq.bands[i], -12, 12, 0) : 0 }
            if let u = a.deviceUID, u.isEmpty || u.count > 512 { a.deviceUID = nil }
            apps[k] = a.isDefault ? nil : a
        }
        callBoost = c(callBoost, 1, 4, 2.5)
        softMaster = c(softMaster, 0, 1, 1)
        if !(Self.icons.contains(menuIcon) || menuIcon == Self.customIcon) { menuIcon = Self.icons[0] }
        var seen = Set<String>()
        priority = priority.compactMap { d in
            guard !d.uid.isEmpty, d.uid.count <= 512, seen.insert(d.uid).inserted else { return nil }
            return KnownDevice(uid: d.uid, name: String(d.name.prefix(120)),
                               symbol: AudioDevice.symbols.contains(d.symbol) ? d.symbol : "speaker.wave.2.fill")
        }
        if priority.count > 40 { priority = Array(priority.prefix(40)) }
    }
}
