# Spielstand übertragen: Alte App (Web/Capacitor) → GOOBY 5 (Godot)

**Stand: 2026-07-25 (FIX-6).** Antwort auf die User-Frage *„Wo genau überträgt
man seinen Save Game von davor?"* — es gibt jetzt DREI Wege, alle laufen durch
dieselbe geprüfte Migrationskette (`scripts/state/migration_v4.gd`,
v0–v4 → v5). Vor JEDER Übernahme wird der aktuelle Stand automatisch
gesichert (`user://save_v5.pre_import.json`) — ein Import kann nichts
endgültig zerstören.

Screenshots in diesem Dokument: `/tmp/gooby-godot/artifacts/FIX6/`.

---

## Weg A — Automatisch beim ersten Start (iOS, ohne Plugin)

**Für wen:** iPhone/iPad-Spieler, die die neue App ÜBER die alte installieren.

Die alte App ist ein Capacitor-Web-Spiel mit derselben Bundle-Id
(`com.permissionmaxed.gooby`). Sie spiegelt seit v1 jeden Speichervorgang
zusätzlich nach `NSUserDefaults` (Datei
`Library/Preferences/com.permissionmaxed.gooby.plist`, Key
`CapacitorStorage.gooby.save`, Wert = kompletter Spielstand als JSON).

**Schritt für Schritt:**

1. Die alte Gooby-App **NICHT löschen**. Die neue .ipa mit derselben
   Bundle-Id einfach darüber installieren (TestFlight/Sideload). iOS ersetzt
   nur das App-Bundle — der Datencontainer (`Library/`) bleibt erhalten.
   (Löschen + Neuinstallieren wischt dagegen alles weg!)
2. Neue App starten. Sie liest die NSUserDefaults-Datei **selbst** — der
   Binär-Plist-Parser (`scripts/state/import/bplist.gd`) läuft in reinem
   GDScript, es ist **kein natives Plugin nötig** (der eigene
   Sandbox-Container ist per `FileAccess` lesbar).
3. Wird ein Alt-Spielstand gefunden, erscheint die Karte
   **„Alter Spielstand gefunden!"** mit Quelle „alte Gooby-App (iOS)" —
   Screenshot `transfer_02_auto_gefunden.png`.
4. „Vorschau ansehen" → Zusammenfassung („Level 12 · 4640 Münzen ·
   20 Sticker · 8 Outfits", inkl. aller Umzugs-Hinweise) →
   **„Übernehmen"** — fertig.

**Ehrliche iOS-Bewertung (was geht wirklich):**

| Quelle im Alt-Container | Lesbar ohne Plugin? | Status |
| --- | --- | --- |
| `Library/Preferences/….plist` (NSUserDefaults-Spiegelung) | **Ja** — eigener bplist00-Parser in GDScript | **Implementiert**, ist der Hauptweg |
| `Library/WebKit/**/LocalStorage/*.sqlite3` (WKWebView-localStorage) | Nein — SQLite-Binärformat | Bewusst nicht gebaut; die Preferences-Spiegelung trägt denselben Stand. Nur URALT-Installationen ohne jedes Update hätten NUR localStorage → für die gilt Weg B |
| Natives Plugin (`LegacySaveReader`, ~40 Zeilen ObjC `stringForKey:`) | — | Nicht nötig; der Code probiert es trotzdem ZUERST, falls es je gebaut wird (`Engine.get_singleton("LegacySaveReader")`), und fällt dann auf den Plist-Parser zurück |

**Einschränkung heute:** Der Boot-Flow (`scripts/boot/main.gd`, gehört W1a)
ruft das Angebot beim allerersten Start noch nicht auf — Handoff
`/tmp/gooby-godot/handoffs/FIX6-boot-request.md` liegt bereit (~6 Zeilen).
Bis dahin erreicht man dieselbe Auto-Erkennung über Weg B: der
Transfer-Screen sucht beim Öffnen selbstständig.

---

## Weg B — Manuell per Text oder Datei (alle Plattformen)

**Für wen:** alle — auch Android/Desktop, oder wenn die alte App auf einem
ANDEREN Gerät lebt.

1. **In der alten App:** Einstellungen → **„Spielstand exportieren"**
   (siehe Weg C). Der Spielstand landet als Text in der Zwischenablage
   und/oder als Datei `gooby-spielstand-JJJJ-MM-TT.json`.
2. **In der neuen App:** Einstellungen → **„Spielstand übertragen"**
   (Settings-Zeile: Handoff `FIX6-settings-request.md` an FIX-1; der Screen
   selbst ist fertig und unter der Route `state/transfer` registriert).
   Screenshot `transfer_01_leer.png`.
3. Den Text in das Feld **„Aus der alten App einfügen"** einfügen und
   **„Prüfen"** drücken — oder auf Desktops **„Aus Datei laden"**.
4. Die Vorschau **„Gefunden! Das steckt drin:"** zeigt Level, Münzen
   (inkl. +250 Umzugsbonus und ggf. Urlaubs-Erstattung), Sticker, Outfits,
   Möbel im Umzugskarton und ALLE Umzugs-Hinweise (auch was verloren geht).
   Screenshot `transfer_03_vorschau.png`. Nichts wird ohne Bestätigung
   verändert — „Abbrechen" geht immer.
5. **„Übernehmen"**: der bisherige Stand wird zuerst nach
   `user://save_v5.pre_import.json` gesichert, dann ersetzt der migrierte
   Stand den Spielstand (`GameState.import_state`, persistiert sofort).
   Erfolgsmeldung „Geschafft! Dein Gooby ist umgezogen." —
   Screenshot `transfer_04_erfolg.png`.
6. Kaputte/fremde Eingaben werden mit klarer Fehlerkarte abgelehnt
   (kein Crash, nichts überschrieben).

**Bonus — Gerätewechsel neue App → neue App:** dieselbe Seite hat
„Als GOOBY5-Code kopieren" (Export des v5-Standes als Code); der Code wird
vom selben „Prüfen"-Feld wieder angenommen.

---

## Weg C — Export-Knopf in der alten Web-App

Minimaler Eingriff in `GOOBY/src/ui/settingsScreen.js` (+ 3 Strings):
Einstellungen → Karte unten, **„Spielstand exportieren"** (direkt über
„Spielstand zurücksetzen") — Screenshot `web_export_knopf.png`.

Der Knopf:
1. serialisiert den kompletten aktuellen Stand (`store.get()`) als JSON,
2. kopiert ihn in die Zwischenablage (Toast „Spielstand kopiert!"),
3. bietet ihn zusätzlich als Datei-Download an (Desktop-Browser),
4. fällt auf ein Text-Fenster zum manuellen Kopieren zurück, wenn die
   Zwischenablage blockiert ist (WKWebView der alten iOS-App).

Funktional verifiziert (CDP-Klicktest): Klick liefert parsebaren
v4-Save-JSON (`v=4`, 35 Top-Level-Felder), keine JS-Fehler; `npm run lint`
(eslint) und `npm test` in `GOOBY/` bleiben grün.

---

## Migrations-Feldliste (was kommt an, was nicht)

Geprüft gegen **5 echte v4-Fixtures** (`tests/fixtures/v4_fresh|midgame|
maxed|extras|urlaub.json`) — alle 5 laufen unverändert durch die ECHTE
Web-Kette (`GOOBY/src/core/save.js: load()`), sind also beweisbar echte
Alt-Spielstände. Tests: `tests/unit/test_state_migration.gd` +
`tests/unit/test_migration_transfer.gd` (Feldlisten-Vertrag über alle 5).

**Übernommen (1:1 oder besser):**

| Feld (alt) | Ziel (v5) | Anmerkung |
| --- | --- | --- |
| `coins` | `economy.coins` | verbatim **+ 250 Umzugsbonus**; laufender Urlaub wird zusätzlich erstattet |
| `level` | `progression.level` | 1:1 (Klemme 1–40) |
| `stats` (Hunger/Energie/Hygiene/Spaß) | `gooby.stats` | verbatim |
| `sleep`, `grumpyUntil`, `health`, `weight` | `gooby.*` | verbatim |
| `stickers` (85er-ID-Raum) | `stickers` | Set identisch, Zeitstempel bleiben |
| `outfits` (owned + equipped) | `cosmetics.outfits` | verbatim |
| `skins` | `cosmetics.fur` | verbatim (owned + equipped) |
| `furniture.owned` | `home.storage` | ALLE Möbel in den **Umzugskarton** (Anzahl bleibt); `home.movingDay=true` |
| `decor` (Tapeten/Böden) | `decor` | verbatim |
| `inventory`, `items` | `inventory.food` / `inventory.items` | verbatim (verbrauchtes bleibt verbraucht) |
| `garden` (Beete, Fortschritt, Dünger) | `garden.grid` | verbatim, `plotsOwned` bleibt |
| `vacation.trips/visited/archive/postcards` | `vacation.*` | Sammelpass, Reise-Historie, Postkarten-Archiv verbatim |
| laufender Urlaub | `migration.interruptedVacation` | Reise wird beendet, **Reisepreis erstattet**, Restzeit dokumentiert |
| `achievements` (unlocked + alle Counter) | `achievements` | verbatim (Counter-Superset) |
| `minigames.best/bestByDiff/endlessBest/beaten` | `minigames.legacy` | als „Web-Rekorde" erhalten |
| `minigames.plays/difficulty` | `minigames.*` | verbatim |
| `daily` (Streak), `collections`, `quests.completedTotal` | gleichnamig | verbatim |
| `profile` (Spielzeit, Distanz, Fotozähler, coinsEarned/Spent) | `profile` / `economy` | verbatim |
| `radio` (Sender, Trims, recapHeard) | `radio` | verbatim + Radio-Besitz-Grandfathering |
| `codes` (eingelöste Codes, Buffs) | `codes` | verbatim |
| `recap.history` | `recap.history` | verbatim |
| `gallery.count` | `gallery.legacyCount` | Zähler bleibt (für Erfolge) |
| Fotos gemacht? | `camera.owned=true` | Kamera-Grandfathering |
| `care.toiletAt` | `bad.kloLastMs` | Klo-Cooldown übernommen |
| `settings` (Sprache, Lautstärken, UI-Skalierung, …) | `settings.imported` | zur Übernahme durch den Settings-Screen |
| `nougat` | `easterEggs.nougat` | verbatim |
| `themePark` | `park` | verbatim |
| `onboarding.done` | `onboarding.done` | kein zweites Onboarding |

**Nicht übernommen (ehrlich, mit Grund) — steht auch in der Vorschau und in
`state.migration.lost`:**

| Feld (alt) | Grund |
| --- | --- |
| `xp` (Rest-XP im Level) | neue Multiplayer-Levelkurve in v5 — Level bleibt 1:1, Rest-XP verfällt |
| `furniture.placed` (Slot-Layout) | altes Slot-System ↔ neues freies Grid nicht abbildbar → **Umzugstag-Flow**: alles steht im Umzugskarton |
| Fotos (Galerie-Bilder) | lagen in IndexedDB-Blobs der WebView — physisch nicht exportierbar; der Zähler bleibt |
| `quests.active` | neues Quest-System; `completedTotal` bleibt |
| `modifiers` | Modifikator-System wird neu ausgerollt (frischer Seed) |
| `recap.baseline/pendingLevel` | wird nach dem Import neu gesnapshottet; History bleibt |
| `cutscenes.seen` | Godot-Cutscenes sind ab 2 s überspringbar — Latch überflüssig |
| `care.sickNotifyAt` | Notification-Planung wird in Godot neu aufgebaut |
| `settings.goobyWeltQuality` | Gooby-Welt-Feature existiert in v5 nicht mehr |
| Freunde | die alte Web-App hatte **kein** Freunde-System — es gibt nichts zu übertragen (Multiplayer/Freundescodes sind neu in v5) |

---

## Verifikation (Kurzfassung)

- `tests/unit/test_migration_transfer.gd`: 12 Tests — bplist-Parser
  (Roundtrip + Müll-Ablehnung), Legacy-Leser (exakter Key + Prefix-Plan-B),
  Vorschau aus echtem Fixture, Datei==Text-Determinismus, Vorsicherung vor
  Übernahme, kompletter Screen-Ablauf (Einfügen/Fehler/Auto-Karte),
  Feldlisten-Vertrag über alle 5 Fixtures, Urlaub-Sonderfall.
- `tests/unit/test_state_migration.gd`: Feld-für-Feld-Asserts (W1d).
- Haupt-Runner: **1179 Tests, 0 Fehler**; `gdlint`/`gdformat` sauber.
- Fixtures gegen die ECHTE Web-Kette validiert (Node,
  `GOOBY/src/core/save.js: load()` — 5/5 unverändert akzeptiert).
