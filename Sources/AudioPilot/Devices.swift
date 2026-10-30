import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let isInput: Bool

    var isMonitor: Bool { transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI }
    var isHeadphones: Bool { ["airpods", "airpodspro", "airpodsmax", "headphones"].contains(symbol) }

    /// Alle Symbole, die `symbol` liefern kann (Whitelist für gespeicherte Geräte).
    static let symbols: Set<String> = ["airpodsmax", "airpodspro", "airpods", "laptopcomputer", "mic.fill", "headphones",
                                       "display", "airplayaudio", "cable.connector", "waveform", "speaker.wave.2.fill"]

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if isInput {
            return transport == kAudioDeviceTransportTypeBuiltIn ? "laptopcomputer" : "mic.fill"
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        default: return "speaker.wave.2.fill"
        }
    }
}

enum Devices {
    private static func list(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        CA.array(CA.system, kAudioHardwarePropertyDevices, initial: AudioDeviceID(0)).compactMap { id in
            guard !CA.array(id, kAudioDevicePropertyStreams, scope, initial: AudioStreamID(0)).isEmpty,
                  let uid = CA.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(AppTap.uidPrefix) else { return nil }   // eigene private Aggregates ausblenden
            let name = CA.string(id, kAudioObjectPropertyName) ?? uid
            let transport = CA.get(id, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
            return AudioDevice(id: id, uid: uid, name: name, transport: transport, isInput: scope == CA.input)
        }
    }

    static func outputs() -> [AudioDevice] { list(scope: CA.output) }
    static func inputs() -> [AudioDevice] { list(scope: CA.input) }

    static var defaultOutput: AudioDeviceID {
        CA.get(CA.system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0)) ?? 0
    }

    static var defaultInput: AudioDeviceID {
        CA.get(CA.system, kAudioHardwarePropertyDefaultInputDevice, initial: AudioDeviceID(0)) ?? 0
    }

    /// Setzt Ausgabe + Systemtöne auf das Gerät (offizielle HAL-Properties).
    static func setDefaultOutput(_ id: AudioDeviceID) {
        CA.set(CA.system, kAudioHardwarePropertyDefaultOutputDevice, CA.global, CA.main, id)
        CA.set(CA.system, kAudioHardwarePropertyDefaultSystemOutputDevice, CA.global, CA.main, id)
    }

    static func setDefaultInput(_ id: AudioDeviceID) {
        CA.set(CA.system, kAudioHardwarePropertyDefaultInputDevice, CA.global, CA.main, id)
    }

    static func isAlive(_ id: AudioDeviceID) -> Bool {
        (CA.get(id, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) ?? 0) != 0
    }

    /// Elemente, über die das Gerät Hardware-Lautstärke anbietet (Master oder Kanal 1/2). Leer = keine.
    private static func volumeElements(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        if CA.settable(id, kAudioDevicePropertyVolumeScalar, scope, CA.main) { return [CA.main] }
        return [1, 2].filter { CA.settable(id, kAudioDevicePropertyVolumeScalar, scope, $0) }
    }

    static func volume(_ id: AudioDeviceID, input: Bool = false) -> Float? {
        let scope = input ? CA.input : CA.output
        let els = volumeElements(id, scope)
        guard !els.isEmpty else { return nil }
        let vals = els.compactMap { CA.get(id, kAudioDevicePropertyVolumeScalar, scope, $0, initial: Float32(0)) }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Float(vals.count)
    }

    static func setVolume(_ id: AudioDeviceID, _ v: Float, input: Bool = false) {
        let scope = input ? CA.input : CA.output
        let v = min(max(v, 0), 1)
        for el in volumeElements(id, scope) { CA.set(id, kAudioDevicePropertyVolumeScalar, scope, el, Float32(v)) }
        if CA.settable(id, kAudioDevicePropertyMute, scope) {
            CA.set(id, kAudioDevicePropertyMute, scope, CA.main, UInt32(v == 0 ? 1 : 0))
        }
    }

    static func canMute(_ id: AudioDeviceID) -> Bool { CA.settable(id, kAudioDevicePropertyMute, CA.output) }

    static func setMute(_ id: AudioDeviceID, _ on: Bool) {
        CA.set(id, kAudioDevicePropertyMute, CA.output, CA.main, UInt32(on ? 1 : 0))
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool {
        (CA.get(id, kAudioDevicePropertyMute, CA.output, initial: UInt32(0)) ?? 0) != 0
    }

    static func nominalRate(_ id: AudioDeviceID) -> Double {
        CA.get(id, kAudioDevicePropertyNominalSampleRate, initial: Float64(48000)) ?? 48000
    }
}

/// Ein Prozess, den CoreAudio kennt (macOS 14.2+ Process-Objekte).
struct AudioProc {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isOutput: Bool
    let isInput: Bool

    static func all() -> [AudioProc] {
        CA.array(CA.system, kAudioHardwarePropertyProcessObjectList, initial: AudioObjectID(0)).compactMap { obj in
            guard let pid = CA.get(obj, kAudioProcessPropertyPID, initial: pid_t(0)), pid > 0 else { return nil }
            return AudioProc(
                objectID: obj, pid: pid,
                bundleID: CA.string(obj, kAudioProcessPropertyBundleID) ?? "",
                isOutput: (CA.get(obj, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0,
                isInput: (CA.get(obj, kAudioProcessPropertyIsRunningInput, initial: UInt32(0)) ?? 0) != 0)
        }
    }
}
