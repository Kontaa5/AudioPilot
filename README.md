# SoundController

Menüleisten-App (macOS 15+): Ausgabe & Mikrofon wählen, Lautstärke pro App (bis 400 %) mit Pegel, pro App 10-Band-EQ, Kompressor und eigenes Ausgabegerät, Anruf-Boost, Schutz bei Ausgabewechsel (Ton aus/Pausieren + „Ton an“-Popup), Geräte-Priorität, AirPods per Klick vom iPhone holen, Notch-Popup, Selbstheilung, Einstellungen mit eigenem Menüleisten-Symbol.

Für KI-Assistenten: siehe `AGENTS.md`.

## Bauen

```bash
./build.sh && open build/SoundController.app
```

Beim ersten Start fragt macOS nach **Systemaudio-Aufnahme** (nötig für Lautstärke pro App) und beim ersten Pausieren nach **Automation** (Spotify/Musik), bei „AirPods vom iPhone holen“ nach **Bluetooth**.
Ad-hoc-Signatur: nach jedem Neubau fragt macOS evtl. erneut.

## Wie es funktioniert (nur Apple-APIs)

- Ausgabe/Lautstärke: CoreAudio-HAL-Properties.
- Pro App: Apple *Process Tap* (`CATapDescription`, Original stumm) → privates Aggregate-Device → Gain/EQ → Ausgabegerät. Nur Apps, deren Einstellung von 100 % abweicht (oder EQ an), werden umgeleitet.
- Pause: feste AppleScript-Befehle an Spotify/Musik, nur wenn die App läuft.
- Selbstheilung: neu aufbauen bei An-/Abstecken, nach Ruhezustand, nach Neustart von coreaudiod und wenn eine Umleitung 3 s keinen Audio-Callback mehr bekommt; Monitor (DisplayPort/HDMI) wird nach dem Anstecken einmal „angestoßen“. „Reparieren“ macht dasselbe von Hand.
- Stürzt die App ab, verschwinden ihre privaten Umleitungen mit ihr – der Ton läuft dann normal weiter.

## Datenschutz & Haftung

Keine Netzwerkverbindungen, keine Telemetrie, nichts wird aufgenommen oder gespeichert außer den eigenen Einstellungen (`~/Library/Preferences/com.gabrielsuntinger.SoundController.plist`).
Privates Projekt, ohne Gewähr. FineTune und SoundSource werden nur erkannt, um vor Doppelbetrieb zu warnen.
