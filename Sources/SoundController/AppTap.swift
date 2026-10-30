import CoreAudio
import Foundation

struct TapError: Error, CustomStringConvertible {
    let step: String, status: OSStatus
    var description: String { "\(step) fehlgeschlagen (OSStatus \(status))" }
}

/// Fängt den Ton einer App ab (Apple Process Tap, Original wird stummgeschaltet),
/// verstärkt/EQt ihn und gibt ihn über ein privates Aggregate-Device auf dem Ausgabegerät aus.
/// Wird nur auf der Tap-Queue gebaut/gestoppt; `params` ist threadsicher.
final class AppTap: @unchecked Sendable {
    static let uidPrefix = "SoundController-"
    let processIDs: [AudioObjectID]
    let outputUID: String
    let params = DSPParams()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(processIDs: [AudioObjectID], outputUID: String, gain: Float, setting: AppSetting) throws {
        self.processIDs = processIDs
        self.outputUID = outputUID
        params.update(gain: gain, setting: setting)

        let desc = CATapDescription(stereoMixdownOfProcesses: processIDs)
        desc.uuid = UUID()
        desc.name = "SoundController"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var err = AudioHardwareCreateProcessTap(desc, &tapID)
        guard err == noErr else { throw TapError(step: "Tap erstellen", status: err) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundController",
            kAudioAggregateDeviceUIDKey: Self.uidPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard err == noErr else { stop(); throw TapError(step: "Aggregate-Device", status: err) }

        let dsp = DSPState(sampleRate: Devices.nominalRate(aggID), params: params)
        let params = self.params
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, outData, _ in
            dsp.process(input: inData, output: outData, params: params)
        }
        guard err == noErr else { stop(); throw TapError(step: "IOProc", status: err) }
        err = AudioDeviceStart(aggID, procID)
        guard err == noErr else { stop(); throw TapError(step: "Start", status: err) }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
            self.procID = nil
        }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }

    deinit { stop() }
}
