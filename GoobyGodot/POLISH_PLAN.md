# POLISH_PLAN — GOOBY Godot (Audit + priorisierte Wellen)

Stand: 17. August 2026, Branch `cursor/gooby-godot-82d4` (Subtree-Snapshot der
Linie `cursor/gooby-godot-loop-2-d1d8`, nach W21 + EVAL-2026-08-Fixwellen).
Werkzeug-Baseline dieses Audits: Godot 4.4.1 headless (offizielles Release),
Import-Gate `tools/ci/check_imports.py` (1426 Ziele, 0 fehlend), Boot-Smoke
Exit 0, Haupt-Test-Runner (Baseline-Lauf, s. §5).

## 0. Ehrliche Einordnung (WICHTIG vor jeder weiteren Welle)

Der Kundenauftrag lautet „langweilig, teils buggy, es fehlt Post-Processing,
Animationen, Polish“. Der Code-Befund ist differenzierter: **das Fundament
existiert bereits weitgehend** — wer hier blind „Juice-Grundsysteme neu baut“,
erzeugt Doppelstrukturen und bricht die 3.800-Tests-Suite. Vorhandene Systeme
(verifiziert im Code, nicht nur in Doku):

| Beauftragtes Fundament | Ist-Zustand |
|---|---|
| Tween-Helper (Bounce/Squash für Buttons) | **existiert**: `MotionKit` (verbindliche Motion-Grammatik, Reduced-Motion-gated) + `SquishButton` (Squish + Haptik zentral) + `JuiceKit` (Minigames) |
| Übergangs-Manager (Fades/Wipes) | **existiert**: `SceneRouter` + `LoadingVeil` mit Blütenblätter-Wipe (`loading_veil_wipe.gd`), Iris-Fallback, Reduced-Motion-Fade, `DOOR_TRAVEL` |
| Partikel (Herzen/Sterne/Konfetti) | **existiert verteilt**: `GoobyFeelings`/`EmoteSymbol` (Herzen u. a.), `MotionKit.papier_puff`, Konfetti in Feier-Beats, Krümel in `FuetterRegie` |
| Post-Processing (Glow/Vignette/Farbtint, mobil) | **existiert**: `PostFx`-Autoload (`/root/Fx`): Vignette + Tageszeit-Tint (1 Draw-Call, ALU-only), Emotions-Puls, Glow/ Sättigung am Szenen-Env, DoF-Andeutung; Stufen aus/dezent/hoch über `QualityService` |
| Belichtung | **kalibriert**: `LichtKalibrierung` (Filmic, Exposure-Profile, Nebel) in Haus/Garten/Stadt/Ranch angewandt (EVAL-Lens-B Befund 6 → behoben) |
| Blinzeln/Idle des Pets | **existiert**: `GoobyRig`/`gooby_expressions` (Blinzeln), Idle-Akte + Seelen-System (Laune, Absichten, 12 Emotionen) |
| Tageszeit-Tint Haupt-Screen | **existiert**: `SeeleRunner` → `Fx.set_tageszeit()`; Raumlicht folgt Uhrzeit (`HomeLicht`/`RaumLicht`) |

**Die echten Lücken** (Code-verifiziert, Quellen: `UserFeedback.md` W21-Welle-E-
Queue + EVAL-2026-08 A/B/C + eigene Code-Sichtung):

1. **Universelles Tap-Feedback fehlt** — es gibt KEIN globales visuelles
   Feedback auf Welt-/Screen-Taps (nur Buttons squishen). Dopamin-Top-Item
   der GPT-Re-Evals. Kein `tap_feedback`-Treffer im gesamten Repo.
2. **Fütter-Finale fehlt** — `FuetterRegie.ablauf()` endet nach dem Schluck
   mit einer Emotion, aber ohne Sättigungs-Feier (kein Stat-Beat, kein
   Herzchen-Burst, kein hörbares „satt & glücklich“-Finale). Dopamin-Top-2.
3. **Kein Kamera-Idle-Sway** — `HomeCameraRig` kann Follow/Pan/Build, aber
   die Kamera steht im Ruhezustand vollkommen statisch (kein Atmen).
4. **Innenräume ohne Umgebungsbewegung** — der Garten hat `GartenLeben`,
   die 4 Innenräume haben NICHTS Bewegtes außer Gooby selbst (keine
   Staub-Motes im Fensterlicht, kein Umgebungs-Flimmern). EVAL-Lens-B:
   „sichtbares Leben fehlt“.
5. **UI-Sound-Hook nicht zentral** — `SquishButton` feuert Haptik, aber
   KEINEN Ton; `ui_click` wird nur in ~10 Screens ad hoc gespielt. Folge:
   die meisten Knöpfe im Spiel sind stumm.
6. **MG-HUD-Kit nur in ~9 von 38 Spielen** (`mg_hud_kit.gd`-Konsumenten).
7. **GvZ über Render-Budget**: 371 Draw Calls (Budget ≤250), 619k Primitive
   (EVAL-Lens-C, L8-Snapshot).
8. **Boot-Leak**: konstanter ObjectDB-Leak beim nackten Boot
   (`GDScriptFunctionState`, Exit-Pfad `LoadingVeil.cover()`), verschmutzt
   jeden CI-Lauf und maskiert neue Leaks.
9. **Visuals-Rückstand Welt** (EVAL-Lens-B 4,0/10): Hufingen fast leer,
   Ranch-Fernsicht ohne mittlere Dichte, Funkelpark-Whitebox, Stadt-Orte
   nur per Textlabel unterscheidbar — das sind CONTENT-Wellen, keine
   Systemarbeit.
10. **Progression ohne Zielarchitektur** (EVAL-Lens-A 5,5/10 Progression):
    viele Leisten, keine Priorität; Multiplayer zeigt out-of-the-box auf
    localhost.

## 1. Gameplay-Loops (Audit-Ergebnis)

Alle vier Kern-Loops sind vorhanden und getestet: **Füttern** (Kühlschrank
2.0, 44 Speisen, Fütter-Sequenz mit Bogenflug/Bissen/Emotion), **Pflegen**
(4 Bedürfnisse, Schlaf, Krankheit/Tierarzt, Gewicht, Offline-Verfall),
**Spielen** (38 Minigames mit Sternen/Rekorden/Spotlight/Geistern, Streicheln,
Ball-Wurf), **Dekorieren** (Grid-Baumodus mit 207 Möbeln, Garten, Werkstatt).
Dazu Stadt (12 Orte), Ranch-Open-World, 3 DLC-Loops, Sticker/Erfolge/Quests.
Schwäche ist nicht die Existenz der Loops, sondern (a) Momente ohne Feier
(Lücken 1–5) und (b) fehlende Verzahnung der Belohnungen (Lücke 10).

## 2. Screens/Szenen-Durchgang

107 `.tscn` + prozedurale Screens; der W1c-UI-Runner prüft > 27.000 Checks
über 34+ Screens × 4 Formate (inkl. echter iPhone-Metriken seit W20). Die
Screen-Wache ist grün; die verbleibenden Screen-Findings sind qualitativ
(EVAL-Lens-B §6): iPhone-HUD-Randdichte, Profil wirkt formularhaft,
Sprechblasen-Zwischenzustand „mitten im Satz“ beim Tippen.

## 3. Bug-Liste (verifiziert, priorisiert)

| # | Bug | Beleg | Schwere |
|---|---|---|---|
| B1 | Boot-ObjectDB-Leak (`GDScriptFunctionState` im `LoadingVeil.cover()`-Pfad) | EVAL-C §2, `--verbose`-Boot | mittel (maskiert echte Leaks) |
| B2 | GvZ L8 reißt Render-Budget (371/250 Calls, 619k Primitive) | EVAL-C §3.2 | mittel (Perf auf Gerät) |
| B3 | Stumme Buttons: kein zentraler UI-Sound-Hook (Lücke 5) | Code (`squish_button.gd`) | mittel (Feel) |
| B4 | `Invalid polygon data, triangulation failed` im W1c-Veil-Test | EVAL-C §1.2 (lokal + CI), Baseline-Lauf prüft Reproduktion | niedrig |
| B5 | Haupt-Runner wertet Tests trotz `SCRIPT ERROR` als grün; RID-/Resource-Leaks am Suiten-Ende | EVAL-C §1.4 | mittel (Gate-Ehrlichkeit) |
| B6 | Qualitäts-Notify (`show_banner` bei Auto-Downgrade) läuft nicht über die Toast-Lane → kann Overlays überlagern | W21-E-Queue, `quality_service.gd` | niedrig |
| B7 | Geburtstags-Blase vs. Tagesbonus nicht entzerrt (Overlay-Timing) | W21-E-Queue | niedrig |
| B8 | Chip-Label-Clipping im Bau-Item-Blatt | W21-E-Queue | niedrig |

## 4. Priorisierte Wellen

### Welle 1 — „Spürbar am Haupt-Screen“ (DIESE Runde)

Regel: nur echte Lücken schließen, keine Doppelsysteme; alles
Reduced-Motion-fair, mobil billig, testgedeckt, DE/EN-paritätisch.

1. **TapFeedback-Autoload** (Lücke 1): globaler, gepoolter Touch-Ripple +
   Mini-Sparkle auf jedem Tap (CanvasLayer über UI, `MOUSE_FILTER_IGNORE`,
   rein `_draw`-basiert, 0 Assets), Reduced Motion = dezenter Einzelring,
   abschaltbar über bestehende Einstellungs-Mechanik.
2. **Fütter-Finale** (Lücke 2): nach dem Schluck ein Sättigungs-Beat —
   Herzchen-/Funkel-Burst am Gooby (3D, CPUParticles, gepoolt-billig),
   „+Sättigung“-Feier über die bestehende `GoobyFeelings`/`PostFx`-Kette,
   HUD-Stat-Puls; Reduced Motion: nur Ton + Endzustand.
3. **Kamera-Idle-Sway** (Lücke 3): sanftes Sinus-Atmen des `HomeCameraRig`
   im Wohnmodus (Amplitude cm-Bereich, pure Funktion, testbar), pausiert
   bei Pan/Baumodus, aus bei Reduced Motion.
4. **RaumLeben** (Lücke 4): Staub-Motes im Fensterlicht + dezentes
   Fenster-Funkeln für Innenräume (an `RoomBase` angehängt, Tageszeit-
   abhängig, im Baumodus aus, unter Qualitätsstufe „aus“ deaktiviert).
5. **Zentraler UI-Sound-Hook** (B3): `ui_click` zentral in `SquishButton`
   (button_down), Doppel-Sound-Schutz; die redundanten Ad-hoc-Aufrufe der
   Screens werden dedupliziert.
6. **Bug-Fixes**: B1 (Boot-Leak-Pfad), B4 (sofern im Baseline-Lauf
   reproduziert), B6 (Qualitäts-Notify in Toast-Lane) + Befunde aus dem
   Baseline-Testlauf dieser Runde.

### Welle 2 — Juice/Feedback in der Fläche + Performance

- MG-HUD-Kit-Rollout auf alle 38 Spiele (Lücke 6) inkl. Feier-Beats.
- GvZ-Render-Pass (B2): Turm-/Zombie-Instancing, Partikel-Deckel,
  Budget-Wächter als Test für die 5 EVAL-Lastszenen.
- Event-„Ansage“-Vorlauf, Home-Ruhe-HUD Richtung ≤5 %, B7/B8.
- Runner-/Test-Gate härten (B5): `SCRIPT ERROR` = rot, Leak-Zähler-Gate.

### Welle 3 — Content/Look (Art-Direction, EVAL-Lens-B-Queue)

- Hufingen-Plaza set-dressen (Lens-B Prio 2), Ranch mittlere Dichteebene
  (Prio 3), Zonen-Hero-Landmarken (Prio 4).
- Stadt: Fassaden-Ikonen statt Riesen-Textlabels (Prio 5), Orts-Silhouetten
  (Prio 6), sichtbares Straßenleben (Prio 12).
- Funkelpark-Rekomposition + Crowd (Prio 7/8), Garten-Randkulisse (Prio 9).
- Profil-„Pass“ materialisieren (Papier/Stempel/Sticker, Prio 19).

### Welle 4 — Progression/Verzahnung (EVAL-Lens-A)

- Zielarchitektur: EIN sichtbarer roter Faden (Tages-/Wochenziele, die
  Loops verzahnen), Belohnungen, die Entscheidungen ändern (statt nur
  Coins/Zähler).
- Multiplayer-Produktrealität: Default-Serverkonfiguration ehrlich machen
  (Offline-First-Kommunikation statt localhost-Illusion).
- Minigame-Tiefe für die Top-8-Spiele (Modifier sichtbar machen,
  Meta-Belohnungen).

## 5. Verifikation dieser Runde

- Import-Gate: 1426 Ziele, 0 fehlend (1 Durchlauf).
- Boot-Smoke headless: Exit 0.
- Haupt-Runner-Baseline + W1c-Runner: Ergebnisse im Runden-Bericht;
  jede Welle-1-Änderung bringt eigene Wächter-Tests mit.
- Pflicht vor jedem Push: `bash tools/ci/preflight.sh` (AGENTS.md).
