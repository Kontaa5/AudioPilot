import AppKit
import SwiftUI

@main
struct AudioPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var mixer = Mixer()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(mixer)
        } label: {
            if mixer.switchGuard != nil {
                Image(systemName: "speaker.slash.fill")
            } else if mixer.callActive && mixer.settings.callBoostOn {
                Image(systemName: "phone.and.waveform.fill")
            } else if mixer.settings.iconFollowsDevice, let d = mixer.currentOutput, d.isHeadphones {
                Image(systemName: d.symbol)   // Kopfhörer bzw. AirPods / Pro / Max
            } else if mixer.settings.menuIcon == Settings.customIcon, let icon = mixer.customIcon {
                Image(nsImage: icon)
            } else {
                // Eigenes Symbol gewählt, Datei aber weg → Standard statt leerer Fläche.
                Image(systemName: Settings.icons.contains(mixer.settings.menuIcon) ? mixer.settings.menuIcon : Settings.icons[0],
                      variableValue: mixer.settings.iconShowsLevel ? Double(mixer.currentVolume) : nil)
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Kompressor", id: "compressor", for: String.self) { $appID in
            if let appID { CompressorWindow(appID: appID).environmentObject(mixer) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        SwiftUI.Settings {
            SettingsView().environmentObject(mixer)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nur eine Instanz – zwei Instanzen würden doppelt Taps bauen.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
        }
    }
}
