# E2 — Save-Migration v4→v5 (Eval, Blickwinkel Save-Migration)

Branch `cursor/gooby-godot-rewrite-d1d8`, geprüft am 2026-07-25.
Treiber (Wegwerf, nicht im Repo): `/tmp/gooby-eval-e2/` — `make_extreme_fixtures.mjs`
(erzeugt 3 Extrem-Fixtures mit dem ECHTEN Web-Code), `e2_driver.gd`,
`e2_crash_driver.gd`, `e2_v1_downgrade_driver.gd` (headless via Stub-Projekt
`/tmp/gooby-eval-e2/proj`, Symlink auf `GOOBY-GODOT/scripts`; das echte Projekt
war durch eine parallele Godot-Instanz import-gelockt).

## Verdict

Die Migration ist im Kern **erstaunlich vollständig und web-paritätisch**
(v1-Kette deep-parity, Erstattung laufender Urlaube inkl. Restzeit, Radio-/
Kamera-Grandfathering, additive Counter wie `sickEver`/`holeInOnes` überleben,
Doppel-Migrations- und Downgrade-Schutz sauber). Aber: **eine P0-Crash-Klasse**
(`String == bool` in GDScript ist ein Laufzeitfehler) bricht den dokumentierten
„crasht NIE / bootet IMMER“-Vertrag, und die **Verlustliste ist unvollständig**
(cutscenes/care/difficulty werden stillschweigend verworfen).

---

## P0-1 — `String == bool` crasht die Migration; `load_state` bricht Boot-Vertrag

GDScript wirft bei `==` zwischen `String` und `bool` einen Script-Error
(„Invalid operands“); die Funktion bricht ab und liefert `{}`/`null`. Das Web
benutzt an denselben Stellen typsicheres `=== false`/`=== true` (JS: kein Fehler).

Crash-Stellen (bewiesen, Repro unten):
- `GOOBY-GODOT/scripts/state/migration_v4.gd:220` — `row.get("on") == false`
  (`radio.trims.<id>.on` als String, z. B. `"no"`)
- `GOOBY-GODOT/scripts/state/migration_v4.gd:352` — `v4.get("quickDelivery") == true`
- `GOOBY-GODOT/scripts/state/migration_v4.gd:164` — `sleep.sleeping` String bei
  numerischen Timestamps (der Fuzz-Test kombiniert String-sleeping nur mit
  Junk-Timestamps → Zweig wird nie erreicht)
- `GOOBY-GODOT/scripts/state/save_schema.gd:335` (`radio.playing == true`) —
  hier bricht `_clamp_core` still ab, `normalize` liefert trotzdem `ok=true`:
  **alle Klamps danach (codes-Stamps, gallery, morphs) werden übersprungen**
  (Repro E). Gleiche Klasse: save_schema.gd:288/332/353–356, vacation.gd:157.

Folgen (headless bewiesen, `e2_crash_driver.gd` / `e2_v1_downgrade_driver.gd`):
- `MigrationV4.migrate_any` → `{}` statt `{ok,state,error,report}`
  (migration_v4.gd:63 kaskadiert) — Vertrag aus test_migration_fuzz.gd:5–7 verletzt.
- `MovingBox.import_text` (öffentliche Paste-API des Umzugskoffers!) → `{}`.
- `save_manager.load_state` mit so einer v4-Datei auf Platte → SCRIPT ERROR
  Kaskade (save_manager.gd:158→42), Rückgabe `{}` — **kein Recovery, kein
  Backup, Boot bricht** (Header-Versprechen save_manager.gd:9–13 gebrochen).

Repro:
```
echo '{"v":4,"radio":{"trims":{"a":{"vol":100,"on":"no"}}}}' > save.json
# durch migrate_any / import_text / load_state → Script-Error statt ok=false
```
Fix-Muster: `x is bool and x` bzw. `typeof(x) == TYPE_BOOL` statt `== true/false`
(web save.js macht exakt das mit `===`).

## P1-1 — Vergessene Felder: `cutscenes.seen`, `care.*`, `minigames.difficulty`; Verlustliste unvollständig

Das Web schreibt seit V5/V6 additive Top-Level-Slices OHNE Versionsbump
(mergeDefaults reicht unbekannte Keys durch — save.js:617–624). In ECHTEN
v4-Saves stecken daher:
- `cutscenes.seen` (Replay-Tap-Skip-Latch; Write-Site `GOOBY/src/ui/cutsceneView.js:280–282`,
  Slice `GOOBY/src/systems/cutscene.js:613–634`)
- `care.toiletAt` (`GOOBY/src/home/interactions.js:1870–1871`) und
  `care.sickNotifyAt` (`GOOBY/src/core/notifications.js:180–184`)
- `minigames.difficulty` (zuletzt gewählte Schwierigkeit) — wird in
  `minigames.legacy` NICHT mit kopiert (migration_v4.gd:334–340 nimmt nur
  best/bestByDiff/endlessBest/beaten/lastPlayDay)

`_map_v4_to_v5` (migration_v4.gd:244–410) liest keins davon; `migration.lost`
(:396, Ausgabe siehe Treiber-Log) erwähnt sie nicht → **stiller Datenverlust,
Verlustliste nicht vollständig/ehrlich** (per Eval-Rubrik „Datenverlust = P0“;
praktischer Impact klein: Godot-Cutscene hat ohnehin einen Skip-Button ab 2 s,
toiletAt ist ein Cooldown). Ebenfalls still verworfen: `recap.pendingLevel`
(die lost-Notiz nennt nur `recap.baseline`). Vacation/themePark/Counter
(`sickEver`, `holeInOnes`, `photoXpDay/Today`) überleben dagegen korrekt —
verifiziert mit `v4_endgame.json`.

## P2-1 — Park-Slice komplett ungeklampt (Cheater-Werte überleben)

Web `themePark.sliceOf` klemmt alle Zähler auf 0..99999 und whitelistet
Ride-IDs (`GOOBY/src/systems/themePark.js:47–90`). Godot: weder
migration_v4.gd:330–331 noch `SaveSchema._clamp_core` normalisieren `park`.
Bewiesen: `visits=1e15`, `rides.coaster=-5`, unbekannte Ride-ID `ufo` und
`handsUp=1e15` landen unverändert im v5-State (Cheater-Fixture).

## P2-2 — Web-Paritätsbruch: numerische Strings werden zu Defaults statt koerziert

Web `validate()` koerziert Leaf-Strings lenient (`Number("62")→62`,
save.js:619/651–657); Godots `_num/_num_nan` (migration_v4.gd:639–651) mappen
Strings auf 0/NaN→Default. Bewiesen: `stats.hygiene:"62"` → Web behält 62,
Godot setzt 85; `coins:"5000"` würde zu 0(+250). Betrifft nur hand-editierte
Saves — aber genau die kommen per Umzugskoffer-Paste.

## P2-3 — Fixture-Lücke

`tests/fixtures/v4_*.json` sind echt web-generiert (gut; midgame/maxed mit
aktivem Urlaub + themePark), enthalten aber **kein** `cutscenes`/`care`/
`sickEver`/`holeInOnes` (tools/fixtures/make_v4_fixtures.mjs setzt sie nie) —
deshalb konnte kein Test P1-1 fangen. Der Fuzz-Test (test_migration_fuzz.gd:144–148)
hat trims-Junk ohne String-`on` → P0-1 unentdeckt.

## P3 — Beobachtungen
- `gallery.lastAddedAt/hintShown`, `quests.day/rerolledDay`, `onboarding.step`,
  `modifiers.dayCoins` verworfen — transient, akzeptabel (teils via lost-Liste).
- Counter werden verbatim (auch negativ) übernommen — Paritäts-konform, Web
  floort erst beim Lesen.
- Refund auch bei `phase=returnReady/overdue` (Reise faktisch beendet) — Design-
  Entscheidung, dokumentiert in notes.

## Verifiziert OK (hart getestet, headless)
- **Endgame-Fixture** (L40, 85 Sticker, 42 Outfits, laufender space-Urlaub,
  Park): coins 123456+250+350 ✔, Restzeit 216000000 ms (60 h) ✔, trips/visited
  bleiben ✔, Radio-Grandfathering + recapHeard ✔, Kamera + legacyCount 40 ✔.
- **Uralt-v1** durch die ganze Kette: coins 583, back-Slot, musicMuted,
  Radio-Grant, carrot 0 bleibt 0 (E20), deep-Parität zur Web-Kette ✔.
- **Umzugskoffer-Format**: Web-devPanel exportiert RAW JSON via
  `JSON.stringify(store.get())` → Clipboard (`GOOBY/src/ui/devPanel.js:1136–1144`)
  — der Header-Claim in moving_box_import.gd:6–9 („KEIN base64“) stimmt;
  Import des kompletten Exports (inkl. additiver Slices) funktioniert ✔.
  GOOBY5-Code-Roundtrip + CRC-Manipulations-Abwehr ✔.
- **Doppel-Migration**: v5-Reimport ohne zweiten +250-Bonus ✔; `migrate_any`
  lehnt v5 ab ✔. **Downgrade**: v6 wird von import_text/normalize/migrate_any
  abgelehnt; save_manager recovert + sichert nach `.corrupt` ✔.
- **Cheater-Klamps**: level 9999→40, stats ±1e308→[0,100], weight→95,
  doubleCoinsUntil/lockUntil→now+24 h, gallery→40, 60 Plots→6, plotsOwned→6,
  visited-Junk raus, trims geklampt ✔ (coins 9.9e15 bleibt — wie Web, kein Cap).
