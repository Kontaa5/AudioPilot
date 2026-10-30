import Foundation
import IOBluetooth

/// Gekoppelte Bluetooth-Kopfhörer (offizielles IOBluetooth). Nur lesen + „Verbinden“ –
/// verbindet man AirPods, die gerade am iPhone hängen, holt macOS sie zum Mac.
struct BTDevice: Identifiable, Equatable {
    let id: String          // Adresse
    let name: String
    let connected: Bool

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        return "headphones"
    }
}

@MainActor
final class Bluetooth: NSObject {
    static let shared = Bluetooth()
    private var done: ((Bool) -> Void)?

    func pairedAudio() -> [BTDevice] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.compactMap { d in
            guard d.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio), let a = d.addressString else { return nil }
            return BTDevice(id: a, name: String((d.name ?? a).prefix(120)), connected: d.isConnected())
        }
    }

    /// Asynchron verbinden (blockiert das Menü nicht). `completion` kommt auf dem Main-Thread.
    func connect(_ address: String, completion: @escaping (Bool) -> Void) {
        guard done == nil, let d = IOBluetoothDevice(addressString: address) else { completion(false); return }
        done = completion
        if d.openConnection(self) != kIOReturnSuccess { finish(false) }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        MainActor.assumeIsolated { finish(status == kIOReturnSuccess) }
    }

    private func finish(_ ok: Bool) {
        let d = done
        done = nil
        d?(ok)
    }
}
