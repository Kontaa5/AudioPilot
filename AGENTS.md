# SoundController – Übergabe für KI-Assistenten

Lies diese Datei zuerst. Sie beschreibt, was der Nutzer will, wie er arbeiten will und wo das Projekt steht.
(`CLAUDE.md` verweist hierher, damit Claude Code und andere Agenten dieselbe Quelle nutzen.)

## Ziel

Eigene macOS-Menüleisten-App zur Tonsteuerung, inspiriert von **FineTune** und **SoundSource** (auch eqMac, Background Music, ToothFairy). Die besten Pro-Funktionen übernehmen, aber:

- **KISS**: nur offizielle Apple-APIs „Befehle schicken“ (CoreAudio HAL, Process Taps, IOBluetooth, AppleScript an Spotify/Musik, SMAppService). Keine privaten Frameworks (z. B. kein MediaRemote), kein Kernel-/HAL-Treiber.
- **Security first** (Skill `/insurance-security`, siehe unten).
- **Design: clean Apple-Look**, homogen wie das WLAN-/Ton-Modul im Kontrollzentrum. Der Nutzer ist beim Design sehr kritisch („sieht scheiße aus“ → komplett überarbeiten). Lieber schlicht, schmal, ruhig.

## Wie der Nutzer arbeiten will (unbedingt einhalten)

- Antworten **kurz, auf Deutsch, in Stichworten**.
- Bei Aufgaben immer als **Checkliste** berichten, auch zwischendurch:
  🔄 mache gerade · ✅ erledigt (und wie geprüft) · ⚠️ Probleme mit Ursache · ⏳ offen / brauche dich · 🔒 Security nach jeder Code-Änderung (was geprüft, was offen, Gesamt-%).
- **Nie „geht nicht“ ohne Prozentzahl** („70 % sicher, weil …“ + wie man es prüft).
- **Keine Testtöne abspielen** (kein `afplay` o. Ä.) beim Weiterbauen – ausdrücklich gewünscht.
- **Nie Schlüsselbund, Passwörter, Systemeinstellungen anfassen**, auch keine Abfrage, die ein Passwort-Popup auslöst. Kein `sudo`, kein `killall coreaudiod` ohne Nachfrage.
- **Keine SSH-/Remote-Befehle** von selbst (löst Touch ID aus). Nur pushen, wenn er es sagt – einmal, ohne Zusatzprüfungen.
- **Nach jeder Änderung: committen** (Git-Repo, Branch `main`) und **AGENTS.md aktuell halten** – ausdrücklicher Wunsch des Nutzers.
- Fremde Daten nie ungeprüft in HTML/Shell/SQL; hochgeladene Dateien nie ausführen oder als HTML rendern.

## Wünsche des Nutzers (Features)

1. Ausgabe- und Mikrofon-Gerät wählen, Lautstärke regeln. ✅
2. Lautstärke **pro App** mit Boost bis 400 % (Grund: bei FaceTime wird Spotify sehr leise). ✅
3. **Anruf-Boost**: während eines Anrufs andere Apps automatisch lauter. ✅
4. **EQ pro App** (10 Band, Presets) + **Kompressor** pro App, eigenes Ausgabegerät pro App. ✅
5. **Bei Ausgabewechsel schützen** – nicht nur Spotify, sondern generell:
   - lieber **Ton ganz ausschalten** (Hardware-Mute am neuen Gerät); wo Gerät nicht stumm schaltbar → per Umleitung stumm + Spotify/Musik pausieren,
   - dazu **Popup „Ton an“ / „Weiterspielen“**: daheim ein Klick und es geht weiter, in der Öffentlichkeit geht nichts laut los. ✅ (in v3 gebaut, noch nicht real getestet)
6. **Notch-Popup**, wenn AirPods/ein Gerät sich verbindet. ✅
7. **AirPods**: wenn sie am iPhone hängen → mit einem Klick zum Mac holen („Verbinden“ im Menü). Standard-Verhalten über Prioritätsliste. ✅ (v3, ungetestet, ~70 %)
8. **Bevorzugte Ausgabe / Prioritätsliste**: automatisch zum wichtigsten verfügbaren Gerät wechseln, Reihenfolge in den Einstellungen änderbar. ✅ (v3)
9. **Hub/Monitor-Problem**: USB-C→DisplayPort über Hub ist ausgewählt, aber stumm. Manuelle Lösung des Nutzers war: FineTune beenden, `killall coreaudiod`, Monitor ab-/anstecken, FineTune starten. → App soll das **selbst heilen** und „nie abkacken“. ✅ Watchdog + „Anstoßen“ (Ausgabe kurz weg und zurück), ungetestet mit echtem Hub (~60–70 %).
10. **Einstellungsfenster**, gut gegliedert (Tabs): Menüleisten-Symbol wählbar (cleaner Lautsprecher) **oder eigenes Bild hochladen**. ✅ (v3)
11. Fußleiste: Einstellungen, Reparieren, **Beenden mit Icon** (⏻, ⌘Q). ✅
13. **Lautsprecher dürfen nicht kaputtgehen**: Limiter am Ende der DSP hält jedes umgeleitete Signal unter −1 dBFS (offline getestet: 400 % + EQ +12 dB → max. −1,0 dBFS). ✅
14. **Kompressor mit echten Reglern** (Schwelle, Verhältnis, Attack, Release, Makeup, Knie) + Voreinstellungen, im **eigenen Fenster** mit Kennlinie und Absenkungs-Anzeige; im Menü nur Voreinstellung + Schalter + Knopf zum Fenster. ✅
15. App-Lautstärke: **Doppelklick = 100 %**, beim Ziehen **leichtes Einrasten** bei 100 % (mit Trackpad-Haptik). ✅
16. **EQ als Kurve** statt 10 Schiebern (cleaner): Punkte senkrecht ziehen, Doppelklick = 0 dB, rastet bei 0 dB ein; Kurve nutzt dieselbe Filterformel wie der Ton (`DSPState.coefficients/response`). ✅
17. **Menüleisten-Symbol folgt dem Gerät**: Kopfhörer → Kopfhörer-Symbol, AirPods/Pro/Max → passendes AirPods-Symbol (abschaltbar). ✅
18. **Buy-me-a-coffee-Link** des Nutzers: `https://buymeacoffee.com/suntinger` (vom Nutzer selbst angegeben). Steht fest in `Support.swift`, öffnet nur im Browser (https + Host geprüft), Einstellungen → Allgemein → „Über“. ✅
19. Apps mit WebKit (z. B. „Glasbox“) erscheinen mit richtigem Namen und Icon: WebKit-Hilfsprozesse heißen „<App> Graphics and Media“ usw. und werden über diesen Namen ihrer App zugeordnet. ✅
20. **Mikrofon**: EQ/Kompressor/Boost aufs Mikrofon nur mit virtuellem Treiber möglich → vom Nutzer **abgelehnt („ohne Treiber“)**. Stattdessen im Mikrofon-Tab: Mikrofon-Lautstärke + Knopf „Mikrofonmodus“ (Apples Auswahl Standard / Sprachisolierung / Breites Spektrum über `AVCaptureDevice.showSystemUserInterface(.microphoneModes)`, aktiver Modus wird angezeigt). Keine eigene Mikrofon-Pegelanzeige (würde den orangen Mikrofon-Punkt auslösen). ✅
12. Hauptregler **nicht zu groß** – v2 hatte einen dicken Kontrollzentrum-Balken, das war ihm zu groß; App-Regler (schmal mit Knopf) fand er gut. → v3: Hauptregler im gleichen schmalen Stil.

## Stand (2026-10-30)

- **v5 ist in `/Applications/SoundController.app` installiert und läuft** (zuletzt: Mikrofonmodus-Knopf, EQ-Kurve, Geräte-Symbol in der Menüleiste, Coffee-Link, WebKit-Zuordnung). Davor v4: alles aus v3 (schmaler Hauptregler, Schutz bei Ausgabewechsel, Priorität, AirPods holen, eigenes Symbol, Einstellungs-Tabs) + Limiter, Profi-Kompressor im eigenen Fenster, Doppelklick/Einrasten bei 100 %.
- Einstellungs-Format: Kompressor heißt jetzt `comp` (Objekt). Der alte Wert `compressor` (0…1) wird ignoriert.
- Geprüft: Design per Offscreen-Render (hell/dunkel, alle Tabs), böser Input für Settings-JSON und Bild-Upload (alles abgefangen), Hardened Runtime, 0 Netzwerk-Sockets, Einzel-Instanz. Render-Hilfen wieder entfernt.
- Bluetooth wird erst nach Klick auf „AirPods vom iPhone holen …“ abgefragt (sonst Berechtigungs-Popup schon beim Öffnen des Menüs).
- **Noch nicht mit echter Hardware getestet**: AirPods ab/an (Schutz + Popup „Ton an“), AirPods vom iPhone holen (~70 %), Hub/Monitor-Selbstheilung (~60–70 %), Anruf-Boost bei FaceTime, Stummschalten per Umleitung bei Geräten ohne Mute.

## Architektur (Sources/SoundController)

| Datei | Inhalt |
|---|---|
| `App.swift` | `MenuBarExtra` (.window) + `Settings`-Szene; Symbol: stumm-Symbol bei Schutz, Telefon bei Anruf, eigenes Bild oder SF Symbol (optional mit Lautstärke). Nur eine Instanz. |
| `CA.swift` | Dünner Wrapper um CoreAudio-Properties (get/set/array/string/listen). |
| `Devices.swift` | `AudioDevice` (Symbol, `isMonitor`, `isHeadphones`, Symbol-Whitelist), Default-Geräte, Lautstärke, Mute, `AudioProc` (Prozessliste). |
| `AppTap.swift` | Pro App: `CATapDescription` (Original stumm) → privates Aggregate-Device (UID-Präfix `SoundController-`) → IOProc → DSP. |
| `DSP.swift` | Echtzeit-sicher: 10 Biquads, Kompressor, Gain-Rampe, Soft-Clip, Pegel. Kein Heap, kein Warten auf Locks (`withLockIfAvailable`, Atomics). |
| `Mixer.swift` | Zentrale Logik: Geräte, Apps gruppieren (Helfer → Eltern-App), Taps auf Hintergrund-Queue bauen, Watchdog/Selbstheilung, Anruf-Erkennung, Prioritätsliste, `SwitchGuard` (Schutz bei Ausgabewechsel), Bluetooth, eigenes Symbol. |
| `Settings.swift` | Codable-Einstellungen (`settings.v2` in UserDefaults), `clamp()` prüft alles beim Laden (Bereiche, Whitelists, Längen). Kaputte Daten → `.broken`-Backup. |
| `MenuView.swift` | Menü: Kopf (Ton/Mikrofon), Schutz-Banner, Hauptregler, Geräte (nach Priorität), gekoppelte BT-Kopfhörer „Verbinden“, Apps mit schmalen Reglern + aufklappbarem EQ/Kompressor/Ausgabe, Fuß. |
| `SettingsView.swift` | Tabs: Allgemein (Schutz beim Wechsel, Popup, Selbstheilung, Login), Geräte (Priorität, Bluetooth), Apps (Boost, Anruf-Boost, Reset), Menüleiste (Symbole, eigenes Bild). |
| `NotchPopup.swift` | Schwarzes Popup aus der Notch, mit optionalem Knopf und Dauer. |
| `MediaControl.swift` | Feste AppleScripts: Spotify/Musik nur pausieren, wenn sie spielen; merken und später `play`. |
| `Bluetooth.swift` | IOBluetooth: gekoppelte Audio-Geräte lesen, asynchron verbinden. |
| `IconStore.swift` | Eigenes Symbol: nur Rasterbilder (PNG/JPEG/HEIC/TIFF/GIF/BMP), ≤ 5 MB, ≤ 10 000 px, per ImageIO auf 64 px neu gezeichnet, als PNG unter festem Namen in Application Support. |

Bauen: `./build.sh` (SwiftPM, Release, ad-hoc signiert, Hardened Runtime, nur Entitlement `automation.apple-events`). Installieren: App beenden, `build/SoundController.app` nach `/Applications` kopieren, starten. Nach jedem Neubau fragt macOS evtl. erneut nach „Systemaudio-Aufnahme“ (ad-hoc-Signatur).

Design prüfen ohne Ton: temporär einen Offscreen-Renderer (`NSHostingView` → PNG) per Env-Variable einbauen, Bilder ansehen, danach **restlos entfernen** und prüfen, dass die Nutzer-Einstellungen unverändert sind (`defaults export com.gabrielsuntinger.SoundController -` vorher/nachher vergleichen).

## Security-Regeln (`/insurance-security`)

- Vor Schlüsselbund/Zertifikaten/Passwörtern/Systemeinstellungen, Löschen fremder Daten, Git-History-Umschreiben, Veröffentlichen/Pushen: **fragen**.
- Persönliche Daten (z. B. Impressum) nur vom Nutzer.
- Fixes **mit bösem Input testen** (NaN, riesige Werte, falsche Typen, kaputtes JSON, 10-MB-Strings, Pfade/HTML als Symbolname, kaputte/riesige Bilder).
- Bericht als Checkliste + Tabelle + Gesamt-Sicherheits-%.
- Bisher geprüft (v2): Hardened Runtime blockt `DYLD_INSERT_LIBRARIES`, 0 Netzwerk-Sockets, alle fremden Namen per `Text(verbatim:)`, keine Force-Unwraps, Settings-Clamp mit bösem Input. Gesamt ~90 %.

## Bewusst nicht gemacht (nur nach Rückfrage)

- Lautstärketasten für Geräte ohne Hardware-Regler (bräuchte Bedienungshilfen-/Eingabe-Berechtigung).
- Pausieren von Browsern/anderen Playern (bräuchte Media-Tasten-Events mit Bedienungshilfen-Recht oder private APIs).
- AirPods automatisch vom iPhone wegnehmen ohne Klick (zu übergriffig, z. B. mitten im Telefonat) – nur per Klick „Verbinden“. Das macOS-eigene „Mit diesem Mac verbinden“ stellt der Nutzer selbst ein.
- Developer-ID-Signatur/Notarisierung (nur nötig, wenn die App verteilt wird).
