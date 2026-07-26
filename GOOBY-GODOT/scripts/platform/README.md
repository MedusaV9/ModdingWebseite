# scripts/platform — Geräte, Qualität, Benachrichtigungen, Haptik (RW-7)

Zentrale Plattform-Schicht nach `docs/godot-rewrite/RANCH-DLC-IDEAS-4.md` §3/§4.

| Datei | Zweck |
|---|---|
| `device_profile.gd` | Geräteklasse aus Speicher/Display/Refresh (pur, testbar) |
| `quality_profiles.gd` | Profil-Bündel Niedrig/Mittel/Hoch + Auto-Auflösung (Doc §4.2) |
| `quality_service.gd` | Autoload `Quality`: wendet Settings WIRKLICH auf Godot an |
| `perf_governor.gd` | Notbremse: dauerhafter FPS-Einbruch → eine Stufe runter |
| `color_filter.gd` | Farbfehlsichtigkeits-/Kontrast-Overlay (Daltonisierung) |
| `notify_rules.gd` | Kategorien, Gates, Ruhezeiten (pur, testbar) |
| `notification_service.gd` | Autoload `Notify`: Planung + In-App-Zustellung |
| `haptics.gd` | Haptik-Stufen (aus/dezent/normal/stark) |

## Ehrlichkeit: Was kommt beim Spieler wirklich an?

**Benachrichtigungen.** Godot hat KEINE portable Local-Notification-API.
Der Dienst plant idempotent (id ersetzt), filtert nach Kategorie-Gates und
Ruhezeiten (Standard 21–8 Uhr, Fälliges wird auf das Ruhezeit-Ende
verschoben) — aber zugestellt wird heute nur das **In-App-Banner, solange
die App läuft**. Auf einem iPhone mit geschlossener App kommt **nichts** an,
bis zwei Dinge existieren: (1) das native iOS-Plugin
(`UNUserNotificationCenter`, Andockpunkt `_os_schedule()` in
`notification_service.gd`) und (2) eine **signierte** App — eine unsignierte
App startet auf keinem iPhone; AltStore/Sideloadly signieren beim
Installieren, das kostenlose Profil läuft nach 7 Tagen ab (Doc §3.8).
APNs-Remote-Pushes brauchen zusätzlich das bezahlte Developer Program.

**Haptik.** `Input.vibrate_handheld()` wirkt auf Android sofort; auf iOS
erst im signierten Build. Core-Haptics-Muster (Hufschläge etc.) brauchen
das native Plugin — die Stufen-Parameter sind hier schon definiert.

**120 Hz.** `Engine.max_fps = 120` wird nur gesetzt, wenn das Display
ProMotion meldet (`DeviceProfile`); der iOS-Export braucht zusätzlich
`display/window/ios/allow_high_refresh_rate` (Godot-Default: an). Ob ein
Gerät die 8,33 ms hält, entscheidet die Notbremse zur Laufzeit — kein
Marketing-Schalter.

## Wirkungs-Nachweis (welcher Regler → welche Godot-Einstellung)

Siehe Kopfkommentar von `quality_service.gd` und die Tests
`tests/unit/test_settings_quality.gd` (jede Zeile wird dort gemessen).
