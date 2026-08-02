# EVAL2-B — Photon, Cutscenes & Displays (Evaluations-Runde 2, Team B)

**Scope:** Alle 293 `.fx`-Assets (`assets/eclipse/fx/`, inkl. `boss/`), sämtliche
`tools/photon/*_fx.py`-Generatoren + `fxlib.py`-Tooling, alle `*FxRows`-Registrierungen und
`FxCues`/`FxPayloads`-Kopplungen (Server-Sender ↔ Client-Handler), das `cutscene/`-Paket
(Server-Service + Client-Director) samt der 10 Cutscene-JSONs und `tools/repass_cutscenes.py`,
sowie alle Block-/Item-/TextDisplay-Choreographien (Credits, Boss-Intros, Trophäen, Podium,
Sundial, Awards, Wand-Decals). **Methode:** statisch, read-only; `fxlib.py validate --lint`
über den Gesamtbaum, Generator-Doppellauf in einer `/tmp`-Sandbox (Byte-Diff gegen Repo),
eigene Parse-Scans (Enum-Whitelist, Stacking-Metriken, Cue-Kopplungs-Matrix,
Display-Lifecycle-Matrix). Kein Gradle, keine Code-Änderung, kein Live-Client.

**Referenzstand:** `FX_CENSUS_WAVE13.md`, `FX_RESPAWN_HYGIENE_REPORT.md` (F-102/F-103),
`CREDITS_THOUSANDS_REPORT.md`, `WAVE3_NEWFX_REPORT.md`, `WAVE4_*`/`WAVE5_*`/`WAVE6_*`,
`docs/plans_v3/eval/EVAL-4_vfx_sequences.md` (C1/C2-Vorbefunde).

---

## 1. Noten-Tabelle

| Unterbereich | Note | Ein-Satz-Begründung |
|---|---:|---|
| Asset-Qualität / Stacking-Law | **9/10** | Alle seit FX-W11 hinzugekommenen wave4_/wave5_/wave6_-Emitter halten das V2.1-Gesetz nachweislich ein (Birth-Tints ≤ ~0.25 Luminanz, ADD-Basis dunkel, Counts ≤ 40, breite Schalen-Radien 0.3–2.6 mit Thickness-Streuung); der einzige automatische Flag (`beat_credits_afterglow.fx/afterglow_ash`, 90 ALPHA @ 0.93-Luminanz) ist durch die 30×3×24-Block-Funktions-Streuung + Birth-Alpha 0.0 ein sauberer False Positive. |
| fxlib-Determinismus / Enum-Codecs | **8/10** | Voller Generator-Doppellauf in der Sandbox ist byte-identisch UND deckungsgleich mit allen 293 committeten `.fx` (identischer Baum-SHA256 `012829a0…`), alle `arc_mode`/Renderer-Enums und `random_constant a/b`-Codecs valide — aber EIN Quasar-JSON driftet: `sig_fx.py` würde beim Regenerieren den handgetunten Halo-Alpha-Fix (0.28 → zurück auf 0.45) still rückgängig machen (H-1). |
| Kopplungs-Vollständigkeit (SPEC-ONLY) | **9/10** | Kein einziges neues SPEC-ONLY-Asset: alle 39 automatischen Verdachtsfälle der Cue-Matrix lösen sich als client-getriebene `ensureLoop`-Fenster (AltarAuraIdle, TrophyWisps, DragonWisps …), lokale Cue-Wrapper oder Dev-Kommando-Pfade auf; jedes von Java referenzierte `.fx` existiert auf Disk, jede wave3–6-Row hat einen erreichbaren Server-Sender. |
| Credits/Display-Budget & Leak-Sicherheit | **9/10** | Die Tier-Leiter (`CreditsDisplayBudget` VERIFY: Shatter 220+70=290, Formation 300, Blackhole 180, hard cap 1400) ist exakt wie dokumentiert implementiert, `endEvent`/`forceClearNow`/`onServerStopped` flushen alle Tags auf 0, und alle neuen Display-Nutzer (Trophäen via Photon-Loops statt Displays, Podium, Sundial, Awards) haben Scope-Tags + Sweeps — einziger Rest ist die `WandTickService`-Zählerdrift bei Level-Unload (P-2). |
| Cutscene-Robustheit | **9/10** | Die EVAL-4-Criticals sind verifiziert gefixt (`unfreeze`+`restoreReturn` VOR `completeSession` in ACK-, Skip-, Watchdog- und Abort-Pfad; `onServerStopped`-Cleanup existiert), alle 10 JSONs parsen mit monotonen Keyframes und validen Easings, die Client-Seite (CameraDirector, CaptionRenderer, LetterboxLayer, BossIntroOverlay, TitleCardLayer) räumt bei Disconnect/`level == null` restlos auf. |
| Tooling-Gates | **7/10** | `fxlib.py validate --lint` + Baseline-Mechanik (nur-schrumpfende `lint_baseline.txt`) funktionieren als echtes Gate — aber `repass_cutscenes.py` prüft nur eine hartkodierte 9er-Liste und lässt ausgerechnet die längste Cutscene (`end_arrival`, 1000t/10 KF) ungeprüft (P-1), und der Generator-Drift H-1 zeigt, dass ein Byte-Diff-Gate für die Quasar-JSONs fehlt. |

**Gesamteindruck:** Die Wellen 2–8 haben die letzte Runde substanziell abgearbeitet: die
SPEC-ONLY-Klasse ist leer, die F-102/F-103-Respawn-Hygiene (TemplateHygiene-Scrub, kein
`createInternalRuntime` auf dem geteilten FXHelper-Cache, isolierte `getFX(loc, false)`-Kopien
mit Write-back) ist vorbildlich dokumentiert und implementiert, und die Display-Budget-Doktrin
wird von jedem neuen Feature respektiert. Was bleibt, sind Tooling-Synchronisations-Lücken
(Generator ↔ committeter Fix, Harness ↔ Asset-Bestand) und eine Zähler-Randbedingung.

---

## 2. Befunde

### CRITICAL

*Keine.* (Die Critical-Klasse der letzten Runde — SPEC-ONLY-FX, CutsceneService-Freeze-Reihenfolge,
Duplicate-ID-Storm — ist vollständig und nachweislich abgebaut, siehe Gut-Befunde §4.)

### HIGH

**H-1 — `sig_fx.py` ist gegen den committeten Verdict-Halo-Fix gedriftet: Regenerieren revertiert ihn still.**
- **Dateien:** `tools/photon/sig_fx.py:530` (`_color_module(..., [(0.0, 0.85), (0.55, 0.45), (1.0, 0.0)])`)
  vs. `assets/eclipse/quasar/emitters/sig_crown_verdict_halo.json:74–87` (committete Alpha-Stops
  `0.85 / 0.28 / 0.0`).
- **Failure-Mechanismus:** Der Repo-Stand trägt einen handgetunten Mid-Stop von **0.28**
  (Halo-Alpha-Abdunkelung); der Generator produziert weiterhin **0.45**. Sandbox-Beweis: der
  komplette Generator-Regenerierungslauf reproduziert alle 293 `.fx` und alle Quasar-JSONs
  byte-identisch — mit exakt dieser EINEN Abweichung (`cmp`-Diff nur für
  `sig_crown_verdict_halo.json`). Der nächste Kollege, der `sig_fx.py` für ein NEUES
  Signature-FX anfasst und pflichtgemäß regeneriert, macht den visuellen Fix unbemerkt
  rückgängig — genau die Fehlerklasse, die das Determinismus-Gesetz verhindern soll.
- **Fix-Vorschlag:** In `sig_fx.py:530` den Mid-Stop auf `(0.55, 0.28)` setzen, regenerieren,
  `git diff --stat = 0` bestätigen. Zusätzlich (siehe P-4) ein Byte-Diff-Gate „Generator-Lauf
  darf den Baum nicht ändern" als CI-/Checkliste-Schritt festschreiben.

### POLISH

**P-1 — `repass_cutscenes.py` validiert 9 von 10 Cutscenes: `end_arrival` fehlt in der hartkodierten Liste.**
- **Datei:** `tools/repass_cutscenes.py:248–249` (`ids = ["intro_v3_ship", …, "credits_helm"]`),
  Erfolgsmeldung `:259` („all 9 paths").
- **Failure-Mechanismus:** `end_arrival.json` ist mit 1000 Ticks und 10 Keyframes die längste
  Cutscene des Mods und läuft komplett am Parse-/i18n-/Grammatik-Gate vorbei — eine künftige
  Keyframe-Regression (nicht-monotone `t`, ungültiges Easing, tote Caption-Keys) würde erst
  im Spiel auffallen. (Manuelle Nachprüfung dieser Runde: aktuell sauber — monotone Keyframes,
  nur `easeInOutSine`/`easeInOutQuart`, 0 Events, da `EndArrivalSequence.java:447 ff.` die
  Captions serverseitig treibt.)
- **Fix-Vorschlag:** `ids` per `sorted(CUT.glob("*.json"))` ableiten (Ein-Zeilen-Fix) und die
  „all N paths"-Meldung dynamisch machen; Events-los ist für `end_arrival` legitim und braucht
  keine Sonderbehandlung.

**P-2 — `WandTickService`-Scorch-Decals: Zähler-Starvation, wenn das Level vor dem Discard-Task entlädt.**
- **Datei:** `src/main/java/dev/projecteclipse/eclipse/wand/WandTickService.java:106–109`
  (Discard-Task dekrementiert `liveScorchDecals`) + `:195–196` (Task-Drop „level unloaded
  since scheduling — drop the FX quietly“).
- **Failure-Mechanismus:** Entlädt die Dimension zwischen Spawn und Ablauf (`lifeTicks` bis
  ~mehrere Sekunden), wird der Task still verworfen — das Decrement läuft nie, `liveScorchDecals`
  (Cap `MAX_SCORCH_DECALS = 24`, Gate `:85`) driftet monoton nach oben und verhungert die
  Feuerwelle/Magmasprung-Decals bis zum Server-Neustart (Boot-Sweep `:148` setzt auf 0 zurück).
  Die getaggten Displays selbst bleiben bis dahin im gespeicherten Chunk (Boot-Sweep fängt sie,
  `SCORCH_TAG` macht sie `/kill`-bar) — Leak ist also begrenzt, die Starvation ist der eigentliche Schaden.
- **Fix-Vorschlag:** Im Drop-Zweig von `tickTasks()` decal-bewusste Tasks trotzdem „abrechnen"
  (z. B. Task um ein optionales `onDrop`-Runnable erweitern, das `liveScorchDecals` dekrementiert),
  ODER den Zähler ganz streichen und das Cap-Gate pro Spawn via
  `level.getEntities(BLOCK_DISPLAY, tag)`-Count prüfen (24 Entities, vernachlässigbar).

**P-3 — Lint-Baseline-Burndown: 27 grandfathered Verstöße warten seit FX-W11.**
- **Datei:** `tools/photon/lint_baseline.txt` (33 Zeilen, ~27 Einträge; ausschließlich
  `LINT-LINEAR-CURVE` und `LINT-ALPHA-NOSORT`, z. B. `boss/roar_shockwave.fx|LINT-LINEAR-CURVE|roar_column.sizeOverLifetime.size[0]`).
- **Failure-Mechanismus:** Kein Laufzeitrisiko — aber jede Baseline-Zeile ist ein legitimiertes
  Qualitäts-Delta (harte Größen-Pops durch lineare Ein-Segment-Kurven; Sortier-Artefakte bei
  ALPHA ohne Depth-Sort), und die Baseline-Mechanik („count may only go down") ist nur so gut
  wie ihr tatsächlicher Burndown.
- **Fix-Vorschlag:** Pro Polish-Welle 5–7 Einträge fixen (Kurve → 2-Segment-Ease bzw.
  `sortMode` setzen), Zeile löschen; die 4 `boss/tyrant_*`-Einträge zuerst (sichtbarste Assets).

**P-4 — Kein Byte-Diff-Gate für Generator-Läufe; `validate --lint` prüft Enums nur beim Authoring.**
- **Dateien:** `tools/photon/fxlib.py` (Enum-Validierung in `_validate_shape_arc`/`_validate_renderer`
  läuft im Author-/Write-Pfad; `read_fx_file` parst fremde `.fx` ohne Enum-Whitelist-Pass),
  fehlendes Checklisten-/CI-Gate für „Regenerat == Repo".
- **Failure-Mechanismus:** H-1 blieb genau deshalb unentdeckt: Es gibt kein Gate, das nach einem
  Generator-Lauf `git diff`-Leere erzwingt, und ein handeditiertes `.fx` mit ungültigem
  `renderMode`/`arc_mode`-String (die `wizard_star_call`-NPE-Klasse) würde `validate --lint`
  passieren, solange nur die Author-Pfade validieren. (Mein unabhängiger Whitelist-Scan über
  alle String-Felder aller 293 `.fx` war diese Runde vollständig sauber.)
- **Fix-Vorschlag:** (a) `fxlib.py validate` um einen Read-Path-Enum-Whitelist-Pass erweitern
  (`arc_mode`, `renderMode`, `sortMode`, NumberFunction-`type`-Tags); (b) in `PHOTON-QUALITY.md`
  einen Pflichtschritt „nach jedem Generator-Edit: Vollregenerat + `git status` leer" verankern.

**P-5 — Watch-Item `beat_credits_afterglow.fx/afterglow_ash`: hellste ALPHA-Birth-Tint des Neubestands.**
- **Datei:** `assets/eclipse/fx/beat_credits_afterglow.fx` (Emitter `afterglow_ash`: 90 ALPHA-Partikel,
  Farbstop 0 = `0.93/0.94/0.97`, generiert aus dem Beats-Generator).
- **Failure-Mechanismus:** Aktuell KEIN Verstoß — die Funktions-Shape streut über
  `(randomA-0.5)*30 / randomC*3 / (randomB-0.5)*24` Blöcke und Birth-Alpha ist 0.0 (Fade-in),
  Stacking ist damit physisch ausgeschlossen. Aber der Emitter ist der einzige des gesamten
  Neubestands, der das Gesetz NUR über Streuung statt über dunkle Tints erfüllt — wer die
  Shape später enger zieht (z. B. für eine Nahaufnahme-Variante), erzeugt sofort einen
  weißen Konvergenz-Blob.
- **Fix-Vorschlag:** Ein-Zeilen-Kommentar im Beats-Generator („Streuung IST der Stacking-Guard —
  Shape nicht verengen ohne Tint-Abdunkelung") oder Birth-Stop vorsorglich auf ≤ 0.6 Luminanz ziehen.

---

## 3. Top-5 Polish-Kandidaten (Impact / Aufwand)

| # | Kandidat | Impact | Aufwand |
|---|---|---|---|
| 1 | **H-1: `sig_fx.py:530` Alpha-Stop auf 0.28 synchronisieren** — verhindert stillen Revert eines committeten visuellen Fixes beim nächsten Generator-Lauf | Hoch (Fix-Verlust-Prävention) | Minimal (1 Zeile + Regenerat-Diff-Check) |
| 2 | **P-1: `repass_cutscenes.py` auf Glob umstellen** — die längste Cutscene bekommt ihr Tooling-Gate zurück | Hoch (Gate-Lücke) | Minimal (1–2 Zeilen) |
| 3 | **P-2: Scorch-Decal-Zähler drop-sicher machen** — beendet die einzige gefundene Display-Budget-Randlücke | Mittel (Feature-Starvation, kein Leak) | Klein (Task-`onDrop` oder Entity-Count-Gate) |
| 4 | **P-4: Byte-Diff-Gate + Read-Path-Enum-Whitelist in fxlib** — macht die H-1-Fehlerklasse strukturell unmöglich und schließt die `wizard_star_call`-Klasse für Handedits | Mittel-Hoch (Prävention) | Mittel (~50 Zeilen fxlib + Doku-Absatz) |
| 5 | **P-3: Baseline-Burndown starten (zuerst die 4 `boss/tyrant_*`-Einträge)** | Mittel (sichtbare Assets) | Mittel (pro Eintrag Kurven-/Sort-Tuning + Sichtprüfung) |

---

## 4. Explizite Gut-Befunde (geprüft und sauber)

1. **Determinismus-Vollbeweis:** Kompletter Generator-Doppellauf in `/tmp`-Sandbox → beide Läufe
   byte-identisch, UND der regenerierte `fx/`-Baum hasht identisch zum Repo
   (SHA256 `012829a0…` über alle 293 Dateien). Die UUID5-Disziplin hält.
2. **Enum-/Codec-Fallen:** Whitelist-Scan aller String-Enums (`arc_mode`, `renderMode`,
   `sortMode`, NumberFunction-Tags) über alle 293 `.fx`: 0 Treffer außerhalb der bekannten
   Photon-Enums; `random_constant`-Codecs tragen durchgängig `a`/`b`. Die
   `wizard_star_call`-NPE-Klasse ist im Bestand ausgestorben.
3. **`fxlib.py validate --lint`** läuft grün über den Gesamtbaum (Baseline-Mechanik greift;
   keine NEUEN Verstöße seit FX-W11).
4. **SPEC-ONLY leer:** Cue-Kopplungs-Matrix über alle `FxCues.cue(...)`-Definitionen — jede
   Row hat einen erreichbaren Server-Sender (`sendFxEvent`) oder ist ein dokumentierter
   client-getriebener `ensureLoop`/`releaseLoop`-Fall (AltarAuraIdle-Fenster,
   `Wave5BossFxRows`-Trophäen-Wisps, `wave6_dragon_wisp`); die drei Vorrunden-Fälle
   (Orin star_call, Lantern flicker, Stalker smear) sind verdrahtet.
5. **Kein totes Asset-Wiring:** Jedes von Java referenzierte `.fx` existiert (inkl. der über
   String-Konkatenation/Quality-Tiers aufgebauten IDs); die drei Custom-Shader-Referenzen
   (`soft_particle`, `fresnel_shell`, `rgb_split_distort`) haben ihre JSONs unter `shaders/core/`.
6. **F-102/F-103-Hygiene:** `PhotonBridge.TemplateHygiene` scrubt Szenen-Residuen beim Spawn
   (`PhotonBridge.java:633–634`), Introspektions-Zähler (`hygieneDirtyScrubs`) vorhanden;
   `StormPhotonFx`/`StormNearfieldFx` mutieren NIE den geteilten `FXHelper`-Cache (isolierte
   `getFX(loc, false)`-Snapshots, Pristine-Write-back on release, „NIEMALS
   `createInternalRuntime()`"-Doktrin im Javadoc verankert); Logout → `destroyAll()`-Session-Flush
   (`PhotonBridge.java:772–775`).
7. **EVAL-4 C1/C2 gefixt:** `CutsceneService` ruft `FreezeService.unfreeze` + `restoreReturn`
   VOR `completeSession` in allen vier Endpfaden (ACK `:814–817`, Skip `:880–884`, Watchdog
   `:923–926`, Abort `:560–562`); `onServerStopped`-Cleanup `:942`; Logout-Pfad `:936`.
8. **Cutscene-Assets:** Alle 10 JSONs parsen; `repass_cutscenes.py` bestätigt für seine 9 IDs
   Parse-/i18n-/Grammatik-Regeln plus plausible Kinematik (keine Velocity-Jumps > 0.12 b/t);
   `end_arrival` manuell nach denselben Regeln geprüft: sauber.
9. **Client-Cutscene-Robustheit:** `CaptionRenderer` (Queue-Cap 8, `onLoggingOut`-Clear `:245`),
   `CameraDirector` (Disconnect-Hard-Snap-Doktrin `:472`), `BossIntroOverlay` (Clear bei
   `level == null` `:88–92` + CenterStageArbiter-Release), `TitleCardLayer`
   (`onLoggingOut` `:177–178`).
10. **Credits-Budget & Leak-Gates:** `CreditsDisplayBudget`-Tier-Leiter exakt wie dokumentiert
    (VERIFY `:118–119`: hard cap 1400, Shatter 220+70=290, Formation 300, Blackhole 180;
    Kamera-/Sky-Drain-Zyklen 240–390t laut `CREDITS_THOUSANDS_REPORT.md`); `endEvent`
    (`CreditsSequence.java:816`), `forceClearNow` (`:869`), `onServerStopped` (`:628`) flushen
    restlos; Peaks pro Tier liegen dokumentiert unter den Caps.
11. **Display-Lifecycle-Matrix:** Alle Block-/Item-/TextDisplay-Spawner tragen Scope-Tags und
    hängen an Join-/Boot-Sweeps bzw. Stop-Clears (F-084-Doktrin) — Trophäen-Monumente laufen
    als Photon-Loops statt Displays (kein Budget-Druck), Podium/Sundial/Awards/MinigamePortal
    getaggt + gesweept; einzige Randlücke ist P-2.
12. **Stacking-Law-Neubestand:** Alle wave3_/wave4_/wave5_/wave6_-Emitter: dunkle Birth-Tints
    (typisch 0.02–0.25 Luminanz), ADD-Emitter mit dunkler Basis + HDR ≤ 1.45, Counts 1–96 mit
    breiten Schalen; Loop-Emitter (`wave5_trophy_wisp`, `wave6_dragon_wisp`) mit 6+2 Partikeln
    bewusst minimal.

---

*EVAL2-B — statisches Audit, Runde 2. Einzige Schreiboperation: dieser Report.*
