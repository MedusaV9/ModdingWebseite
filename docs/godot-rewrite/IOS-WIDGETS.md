# iOS-Widgets und Live Activities (GOOBY-WIDGETS)

Echte Home-Screen-Widgets, Lock-Screen-Accessories und Live Activities für
das Godot-4.4.1-Spiel — umgesetzt über einen Godot-iOS-Plugin- +
WidgetKit-Extension-Ansatz. Diese Datei beschreibt die Architektur, was
Sideload-Signierer können müssen, die bekannten Grenzen und wie man testet.

## Architektur in einem Bild

```
Godot (GDScript)                          iOS nativ (Swift/ObjC)
────────────────────────────              ─────────────────────────────────
GameState ──Signale──▶ WidgetBridge       goobykit.a (goobykit_init)
                        │  Autoload          │ NSClassFromString
                        │  2-s-Poll +        ▼
                        │  Pause-Flush     GoobyKitRuntime.swift (App-Target)
                        ▼                    │ pollt Outbox (2 s + Lifecycle)
        WidgetSnapshot.build()               │
        WidgetSnapshot.live_activity_plan()  ├─▶ App-Group-NSUserDefaults
                        │                    │   + WidgetCenter.reloadAllTimelines()
                        ▼                    └─▶ ActivityKit start/update/end
        GoobyKitBridge (Datei-Outbox)              (iOS 16.2+)
        Documents/goobykit/
          widget_snapshot.json            GoobyWidgets.appex (PlugIns/)
          live_activity.json  ◀──liest──  SwiftUI-Widgets + Live-Activity-UI
                                          (liest App-Group-Snapshot)
```

### Godot-Seite (auf Linux voll testbar)

- `scripts/platform/widget_snapshot.gd` — **pure Logik**: baut aus dem
  Save-State den Widget-Snapshot (Münzen, Stimmung/Emoji, Kernstats,
  Tagesquest-Fortschritt, Streak, Countdown, deutscher Statustext) und den
  Live-Activity-Plan (Urlaub / Schlaf / Tagesbonus-Serie). Zeit, Zeitzone,
  Übersetzer und Quest-Pool werden injiziert → `tests/unit/test_widget_snapshot.gd`.
- `scripts/platform/goobykit_bridge.gd` — die Plugin-Anbindung mit der
  geforderten API `set_widget_data(json)`, `start_live_activity(json)`,
  `update_live_activity(json)`, `end_live_activity()`, `is_supported()`.
  Auf iOS schreibt sie atomar (tmp + rename) in die Datei-Outbox
  `user://goobykit/` (= `Documents/goobykit/`); auf allen anderen
  Plattformen ist sie ein No-op. Live-Activity-Kommandos tragen eine
  Sequenznummer, die einen App-Neustart überlebt.
- `scripts/platform/widget_bridge.gd` — Autoload `WidgetBridge`: beobachtet
  GameState-Signale (`vacation_changed`, `coins_changed`, `stats_changed`,
  `slice_changed`, `gooby_events`, `state_loaded`), pollt zusätzlich alle
  2 s (fängt signal-lose Änderungen wie den Schlaf-Start) und flusht hart
  bei `NOTIFICATION_APPLICATION_PAUSED`/Focus-Out — der letzte Moment vor
  dem Suspend. Schreib-Debounce: identische Snapshots werden nicht erneut
  geschrieben. Die Start/Update/End-Zustandsmaschine der Live Activity
  vergleicht Plan-`kind` und -Inhalt. **Minimal-invasiv:** kein fremdes
  Kernskript wird angefasst — Reise-/Schlaf-Trigger kommen über die
  bestehenden GameState-Signale + Poll.

### Native Seite (baut die CI auf macOS)

- `GOOBY-GODOT/ios/plugins/goobykit/` — das Godot-iOS-Plugin:
  - `goobykit.gdip` + `goobykit_bootstrap.mm` → `goobykit.a`
    (baut `tools/ci/build_goobykit.sh` VOR dem Export; Preset-Schalter
    `plugins/goobykit=true`). Der Godot-Exporter generiert den Aufruf von
    `goobykit_init()` beim Engine-Start; die Datei ist bewusst ObjC++
    (C++-Symbol-Mangling wie bei den offiziellen godot-ios-plugins) und
    **godot-header-frei** — die CI braucht keinen Godot-Quellbaum.
  - `GoobyKitRuntime.swift` (wird ins App-Target injiziert): pollt die
    Outbox, spiegelt den Snapshot nach
    `NSUserDefaults(suiteName: "group.com.permissionmaxed.gooby.shared")`,
    ruft `WidgetCenter.reloadAllTimelines()` und fährt die ActivityKit-
    Live-Activity (Start nur im Vordergrund, `NSSupportsLiveActivities`
    setzt das Inject-Skript in die App-Info.plist).
- `GOOBY-GODOT/ios/widgets/` — die WidgetKit-Extension (Target
  `GoobyWidgets`, min iOS 16.2, Bundle-Id
  `com.permissionmaxed.gooby.widgets`):
  - `GoobyKitShared.swift` — geteilter Code (App + Extension): App-Group-
    Konfiguration, toleranter Snapshot-Decoder, `GoobyActivityAttributes`.
  - `GoobyWidgets.swift` — Widgets **Gooby-Status** (Small/Medium +
    accessoryCircular/Inline), **Tagesquest** (Small + accessoryRectangular),
    **Countdown** (Medium + accessoryRectangular, tickend via
    `Text(timerInterval:)`); Platzhalter-Zustand ohne Daten. Alles deutsch.
  - `GoobyLiveActivityWidget.swift` — Live-Activity-UI (Lock Screen +
    Dynamic Island) für die Fälle `vacation`, `sleep`, `daily`.
- `tools/ci/inject_widgets.rb` (ruby-Gem `xcodeproj`, idempotent) hängt
  nach dem Godot-Export das Extension-Target ins Xcode-Projekt, injiziert
  die Swift-Laufzeit ins App-Target, schreibt beide Entitlements und
  bettet die `.appex` unter `PlugIns/` ein.
- `tools/ci/verify_widgets.py` prüft die fertige IPA forensisch
  (Extension eingebettet, WidgetKit-Extension-Point, App-Group in beiden
  Entitlements, `NSSupportsLiveActivities`, Symbol-Spuren der Swift-Laufzeit).

## Snapshot-Schema (Version 1)

`widget_snapshot.json` (Godot → App Group, Schlüssel `gooby.widget.snapshot`):

| Feld | Inhalt |
| --- | --- |
| `v`, `generatedAtMs` | Schema-Version, Erzeugungszeit (Epoch ms) |
| `nickname` | Gooby-Spitzname aus `meta.goobyNickname` |
| `coins` | `economy.coins` |
| `stats.hunger/energy/hygiene/fun` | Kernstats 0–100 (gerundet) |
| `mood.value/band/emoji` | Stimmung + Band (`ecstatic`…`miserable`) + Emoji |
| `sleep.sleeping/wakeAtMs` | Schlafzustand |
| `vacation.phase/destId/destName/returnAtMs/pickupByMs` | Urlaubs-Slice (Zielname lokalisiert) |
| `quests.claimed/claimable/total` | Tagesquest-Brett (nur heutiges Brett) |
| `daily.streak/claimedToday/nextResetMs` | Tagesbonus-Serie + Reset um lokale Mitternacht |
| `countdown.kind/endsAtMs/label` | Nächstes Ereignis (`sleepWake`, `vacationReturn`, `vacationPickup`, `dailyReady`, `dailyReset`) |
| `statusText` | Deutsche Statuszeile (Schlaf/Urlaub/niedrigster Stat/Stimmung) |

## Live-Activity-Anwendungsfälle

| `kind` | Wann | Countdown bis |
| --- | --- | --- |
| `vacation` | Gooby ist verreist (`away`) bzw. wartet am Flughafen (`return_ready`/`overdue`) | Rückkehr bzw. Abholfrist |
| `sleep` | Gooby schläft (Langzeit-Aktion) | Aufwachzeit |
| `daily` | Tagesbonus heute geholt und Serie ≥ 3 | Reset um lokale Mitternacht |

Getriggert wird über die GameState-Beobachtung in `widget_bridge.gd` —
Start/Update/End entscheidet der Plan-Abgleich, die native Seite gleicht
zusätzlich über die Sequenznummer ab (App-Neustart-sicher).

## Was Sideload-Signing können muss

- **App Group:** `group.com.permissionmaxed.gooby.shared` muss beim
  Re-Signieren für **App und Extension** übernommen werden. AltStore und
  SideStore machen das automatisch (sie mappen die Gruppe auf die eigene
  Team-Id, z. B. `group.XYZ.com.permissionmaxed.gooby.shared` — App und
  Extension bleiben konsistent, weil beide zusammen signiert werden). Die
  unsignierte IPA legt die Entitlements-Dateien sichtbar in die Bundles
  (`GOOBY.app/GOOBY.entitlements`,
  `GoobyWidgets.appex/GoobyWidgets.entitlements`).
- **Extension NICHT entfernen:** AltStore bietet beim Install an, App-
  Extensions zu strippen (freie Apple-IDs haben ein 10-App-ID-Limit, die
  Extension belegt eine weitere Id). Wer Widgets will, muss die Extension
  behalten.
- **Live Activities:** brauchen KEIN besonderes Entitlement, nur
  `NSSupportsLiveActivities=true` (steht in der App-Info.plist) und
  iOS 16.2+.

## Bekannte Grenzen

- **Kein Push-Update der Live Activity:** ohne Apple-Push-Zertifikate gibt
  es keine Remote-Updates. Start/Update/End passieren nur, solange die App
  läuft (Vordergrund; der Pause-Flush schreibt den letzten Stand direkt vor
  dem Suspend). Die Countdown-Anzeige selbst tickt nativ weiter
  (`Text(timerInterval:)`), auch wenn die App suspendiert ist.
- **Widget-Daten aktualisieren sich nur bei App-Läufen:** der Snapshot
  entsteht in Godot. Zwischen zwei App-Starts zeigt das Widget den letzten
  Stand; der Countdown-Eintrag kippt immerhin von selbst in den
  „fertig“-Zustand (zweiter Timeline-Eintrag am Countdown-Ende).
- **Min-iOS:** App ab iOS 15 (vorher 14 — Swift-Concurrency-Systemlib nötig,
  s. Kommentar in `export_presets.cfg`), Widgets/Live Activities ab
  iOS 16.2 (Extension-Deployment-Target; darunter installiert die App
  normal, zeigt aber keine Widgets an).
- **Ohne App-Group-Mapping** (manche Signierer unterstützen keine App
  Groups, z. B. schlichte zsign-Wrapper) bleiben die Widgets im
  Platzhalter-Zustand „Öffne GOOBY einmal…“ — die App selbst läuft normal.
- **Freie Apple-ID:** Signatur gilt 7 Tage (wie bisher, s. `IOS-BUILD.md`).

## Testanleitung

**Auf Linux (ohne Mac):**

```bash
# Pure Logik + Bridge-Zustandsmaschine + Outbox:
bash tools/ci/run_godot_isolated.sh godot --headless --path GOOBY-GODOT \
  --script res://tests/run_tests.gd     # enthält test_widget_snapshot/-bridge
```

**CI (jeder Push auf `GOOBY-GODOT/**`):** Job `ios-ipa` baut Plugin +
Extension und verifiziert die Einbettung (`unzip -l`-Beleg + `verify_widgets.py`
— PASS-Zeile in der Job-Summary).

**Auf dem Gerät (iOS 16.2+):**

1. IPA per AltStore/SideStore installieren (Extension NICHT strippen).
2. GOOBY einmal starten (schreibt den ersten Snapshot beim Laden).
3. Home-Screen lang drücken → „+“ → „GOOBY Widgets“ → Gooby-Status /
   Tagesquest / Countdown hinzufügen (Lock-Screen: Sperrbildschirm
   anpassen → Widget-Leiste).
4. Live Activity testen: Gooby ins Bett schicken ODER eine Reise buchen,
   dann App verlassen → Countdown-Karte auf dem Sperrbildschirm bzw. in
   der Dynamic Island. Aufwecken/Abholen beendet die Activity beim
   nächsten App-Lauf.
5. Ohne Daten (frisch installiert, App nie gestartet): Widgets zeigen den
   Platzhalter „Öffne GOOBY einmal, dann füllt sich das Widget.“
