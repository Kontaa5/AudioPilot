import AppKit

/// Pausiert/startet Musik-Apps über ihre offizielle AppleScript-Schnittstelle.
/// Feste Skripte, keine fremden Daten darin. Nur laufende Apps (sonst würde AppleScript sie starten).
enum MediaControl {
    private static let players = ["com.spotify.client", "com.apple.Music"]

    static func handles(_ bundleID: String) -> Bool { players.contains(bundleID) }

    /// Pausiert nur, was gerade spielt. Gibt zurück, welche Apps pausiert wurden (zum Weiterspielen).
    static func pauseAll() -> [String] {
        players.filter { id in
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return false }
            let script = """
            tell application id "\(id)"
                if player state is playing then
                    pause
                    return true
                end if
                return false
            end tell
            """
            var err: NSDictionary?
            return NSAppleScript(source: script)?.executeAndReturnError(&err).booleanValue ?? false
        }
    }

    private static let queue = DispatchQueue(label: "AudioPilot.media", qos: .userInitiated)

    /// Play/Pause für den Knopf im Menü (nur Spotify/Musik, nur wenn sie laufen).
    /// Im Hintergrund: Apple Events können dauern, das Menü soll nicht hängen.
    static func playPause(_ id: String) {
        guard players.contains(id), !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return }
        queue.async {
            var err: NSDictionary?
            NSAppleScript(source: #"tell application id "\#(id)" to playpause"#)?.executeAndReturnError(&err)
        }
    }

    static func resume(_ ids: [String]) {
        for id in ids where players.contains(id) && !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            var err: NSDictionary?
            NSAppleScript(source: #"tell application id "\#(id)" to play"#)?.executeAndReturnError(&err)
        }
    }
}
