import AppKit

/// Unterstützen-Link. Fest im Code (kein Nutzer-/Dateiinhalt), wird nur im Browser geöffnet –
/// die App selbst baut nie eine Netzwerkverbindung auf.
enum Support {
    static let coffee = URL(string: "https://buymeacoffee.com/suntinger")

    static func openCoffee() {
        guard let url = coffee, url.scheme == "https", url.host == "buymeacoffee.com" else { return }
        NSWorkspace.shared.open(url)
    }
}
