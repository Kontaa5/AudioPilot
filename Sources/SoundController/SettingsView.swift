import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen wie bei Apple-Apps: Tabs oben, je Tab ein gruppiertes Formular.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("Allgemein", systemImage: "gearshape") }
            DevicesTab().tabItem { Label("Geräte", systemImage: "hifispeaker.2") }
            AppsTab().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            IconTab().tabItem { Label("Menüleiste", systemImage: "menubar.rectangle") }
        }
        .frame(width: 520)
    }
}

// MARK: - Allgemein

private struct GeneralTab: View {
    @EnvironmentObject var mixer: Mixer
    @State private var loginItem = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(selection: $mixer.settings.switchAction) {
                    Text("Ton ausschalten").tag(SwitchAction.mute)
                    Text("Musik pausieren").tag(SwitchAction.pause)
                    Text("Nichts tun").tag(SwitchAction.nothing)
                } label: {
                    Text("Wenn die Ausgabe von selbst wechselt")
                    Text("Z. B. AirPods raus → Lautsprecher. Ein Popup bietet „Ton an“ bzw. „Weiterspielen“ – so geht unterwegs nichts laut los, daheim reicht ein Klick.")
                }
                .pickerStyle(.menu)
                if mixer.settings.switchAction == .mute {
                    Text("Geräte ohne eigenen Stumm-Schalter (z. B. Monitor über DisplayPort) werden per Umleitung stumm geschaltet; Spotify und Musik werden zusätzlich pausiert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Auch beim Wechsel auf Kopfhörer", isOn: $mixer.settings.guardHeadphones)
                    .disabled(mixer.settings.switchAction == .nothing)
            } header: { Text("Schutz beim Gerätewechsel") }

            Section("Verhalten") {
                Toggle("Popup an der Notch bei neuem Gerät", isOn: $mixer.settings.notchPopup)
                Toggle(isOn: $mixer.settings.autoHeal) {
                    Text("Selbstheilung")
                    Text("Hängende Umleitungen neu bauen, Monitor-Ton nach dem Anstecken anstoßen, nach Ruhezustand neu verbinden.")
                }
                Toggle("Beim Anmelden starten", isOn: Binding(get: { loginItem }, set: setLoginItem))
            }

            Section {
                LabeledContent {
                    Button { Support.openCoffee() } label: { Label("Buy me a coffee", systemImage: "cup.and.saucer.fill") }
                } label: {
                    Text("Gefällt dir SoundController?")
                    Text("Kostenlos und ohne Werbung – über einen Kaffee freue ich mich.")
                }
                Label("Alles läuft lokal. Keine Netzwerkverbindungen, nichts wird aufgenommen oder gespeichert.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Über") }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        loginItem = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Geräte (Priorität)

private struct DevicesTab: View {
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $mixer.settings.autoSwitch) {
                    Text("Automatisch zum wichtigsten Gerät wechseln")
                    Text("Kommt ein Gerät weiter oben dazu (oder fällt das aktuelle weg), wird dorthin gewechselt.")
                }
                ForEach(Array(mixer.settings.priority.enumerated()), id: \.element.uid) { i, d in
                    PriorityRow(rank: i + 1, device: d,
                                connected: mixer.outputs.contains { $0.uid == d.uid },
                                active: mixer.currentOutput?.uid == d.uid,
                                isFirst: i == 0, isLast: i == mixer.settings.priority.count - 1,
                                move: { mixer.movePriority(d.uid, by: $0) },
                                forget: { mixer.forgetDevice(d.uid) })
                }
                .disabled(!mixer.settings.autoSwitch)
            } header: { Text("Reihenfolge der Ausgabegeräte") }

            Section {
                Toggle(isOn: $mixer.settings.showBluetooth) {
                    Text("Gekoppelte Kopfhörer im Menü zeigen")
                    Text("AirPods, die gerade am iPhone hängen, erscheinen mit „Verbinden“ – ein Klick holt sie zum Mac.")
                }
                Text("Ob AirPods sich von selbst mit dem Mac verbinden, stellst du in den Systemeinstellungen → Bluetooth → AirPods (i) → „Mit diesem Mac verbinden“ ein.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("AirPods & Bluetooth") }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PriorityRow: View {
    let rank: Int
    let device: KnownDevice
    let connected: Bool
    let active: Bool
    let isFirst: Bool, isLast: Bool
    let move: (Int) -> Void
    let forget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(rank)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 16)
            IconCircle(symbol: device.symbol, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: device.name).lineLimit(1)
                Text(active ? "Aktiv" : connected ? "Verbunden" : "Nicht verbunden")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                SmallIcon("chevron.up", help: "Nach oben") { move(-1) }.disabled(isFirst)
                SmallIcon("chevron.down", help: "Nach unten") { move(1) }.disabled(isLast)
                SmallIcon("xmark", help: "Vergessen") { forget() }.disabled(connected)
            }
        }
    }
}

private struct SmallIcon: View {
    let symbol: String, help: String, action: () -> Void
    init(_ symbol: String, help: String, action: @escaping () -> Void) { self.symbol = symbol; self.help = help; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        Form {
            Section("Lautstärke") {
                Picker("Maximaler Boost pro App", selection: $mixer.settings.maxBoost) {
                    Text("200 %").tag(Float(2))
                    Text("300 %").tag(Float(3))
                    Text("400 %").tag(Float(4))
                }
            }
            Section("Anrufe") {
                Toggle(isOn: $mixer.settings.callBoostOn) {
                    Text("Anruf-Boost")
                    Text("Während FaceTime, Zoom & Co. werden andere Apps lauter – gegen das automatische Leiserdrehen.")
                }
                if mixer.settings.callBoostOn {
                    LabeledContent("Stärke") {
                        HStack {
                            Slider(value: $mixer.settings.callBoost, in: 1...4)
                            Text(verbatim: "\(Int((mixer.settings.callBoost * 100).rounded())) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Lautstärke, EQ, Kompressor, Ausgabe") {
                    Button("Alle zurücksetzen") { mixer.resetAllApps() }
                }
            } header: { Text("App-Einstellungen") } footer: {
                Text(verbatim: "\(mixer.settings.apps.count) App(s) mit eigenen Einstellungen").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Menüleiste (Symbol)

private struct IconTab: View {
    @EnvironmentObject var mixer: Mixer
    @State private var rejected = false

    var body: some View {
        Form {
            Section("Symbol") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                    ForEach(Settings.icons, id: \.self) { icon in
                        Tile(selected: mixer.settings.menuIcon == icon) { mixer.settings.menuIcon = icon } content: {
                            Image(systemName: icon).font(.system(size: 16))
                        }
                    }
                    Tile(selected: mixer.settings.menuIcon == Settings.customIcon) {
                        if mixer.customIcon != nil { mixer.settings.menuIcon = Settings.customIcon } else { pick() }
                    } content: {
                        if let img = mixer.customIcon { Image(nsImage: img) } else { Image(systemName: "plus").font(.system(size: 14, weight: .medium)) }
                    }
                    .help("Eigenes Symbol")
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Eigenes Bild wählen …", action: pick)
                    if mixer.customIcon != nil {
                        Button("Entfernen", role: .destructive) { mixer.removeCustomIcon() }
                    }
                }
                if rejected {
                    Label("Bild abgelehnt – nur PNG, JPEG, HEIC, TIFF, GIF oder BMP bis 5 MB.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle(isOn: $mixer.settings.iconTemplate) {
                    Text("Eigenes Symbol einfarbig")
                    Text("Wie die Systemsymbole, passt sich hell/dunkel an. Am besten ein PNG mit transparentem Hintergrund.")
                }
                .disabled(mixer.customIcon == nil)
                Toggle(isOn: $mixer.settings.iconFollowsDevice) {
                    Text("Symbol zeigt Kopfhörer & AirPods")
                    Text("Läuft der Ton über Kopfhörer, erscheint deren Symbol – bei AirPods, AirPods Pro und Max das passende.")
                }
                Toggle("Symbol zeigt Lautstärke", isOn: $mixer.settings.iconShowsLevel)
                    .disabled(mixer.settings.menuIcon == Settings.customIcon)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconStore.types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Bild für die Menüleiste wählen"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rejected = !mixer.setCustomIcon(url)
    }
}

private struct Tile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        Button(action: action) {
            content
                .frame(width: 44, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
