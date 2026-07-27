# PROJECT: ECLIPSE — Trailer V2 Storyboard (30 s · 4K60 · Video-Clips + „Worst Enemy")

**Anlass (F-094, `UserFeedback.md` Z. 13–14):** „der Trailer muss verbessert werden und nutze auch npcs und gameplay scenen einbauen trailer bessere Songs verwenden nutze bitte explizit den Song […] Worst Enemy feat. goldN by Shawn Williams".
**V2-Deltas gegenüber V1:** (1) echte Gameplay-**Video-Clips** statt Ken-Burns-Stills, (2) **NPCs/Mobs prominent** (mind. 4 Szenen), (3) Musik = **„Worst Enemy feat. goldN" — Shawn Williams** (Musicbed, f-Moll, 128 BPM, ~2:02; Permission liegt laut User vor; ~30-s-Ausschnitt).
**Unverändert aus V1:** Format 3840×2160 @ 60 fps = 1800 Frames, Letterbox 2.35:1, Farbwelt/Typo/FX aus `motion_design.md`, Render-Pipeline aus `remotion_tech.md`, Capture-Werkzeuge/Koordinaten aus `capture_plan.md` (§0–§1 dort bleiben die Referenz für mc.sh/fire.sh/RCON/Fenster-Setup).

**Capture-Realität:** headless llvmpipe-Client (DISPLAY=:1, ~5–15 fps Render), Aufnahme via ffmpeg **x11grab @ fixe 60 fps** (1920×1080). Da x11grab mit fester Framerate sampelt, ruckeln nicht die Partikel, sondern die *Bewegungen im Spiel* (4–12 Dupe-Frames pro Game-Frame). Gegenmittel: langsame Kamerafahrten, partikellastige Motive, Block-Display-Schwärme, Boss-Idle — und vor allem **Speed-Up in Remotion (2–4×)**, der Dupe-Frames auf effektive 15–60 Unikate/s verdichtet. Pro Clip 8–20 s Rohmaterial, in Remotion auf 1,9–3,75 s getrimmt/beschleunigt.

---

## 1) Song-Struktur & Beat-Grid (Platzhalter bis Audio-Download)

**Track:** „Worst Enemy feat. goldN" — Shawn Williams · f-Moll · **128 BPM** · ~2:02 (≈ 65 Takte).

### 1.1 Beat-Mathematik @ 60 fps

- 128 BPM = 128/60 = **2,1333 Beats/s** → **1 Beat = 28,125 Frames**.
- 1 Takt (4 Beats, Downbeat-Raster) = **112,5 Frames = 1,875 s**.
- 30 s = 1800 Frames = **exakt 16 Takte** — der Trailer ist ein sauberer 16-Takter, jeder Schnitt liegt AUF einem Downbeat.

### 1.2 Downbeat-/Schnitt-Grid (Frames gerundet; .5 aufgerundet)

| Takt | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | Ende |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Frame | 0 | 113 | 225 | 338 | **450** | 563 | 675 | 788 | **900** | 1013 | 1125 | 1238 | 1350 | 1463 | 1575 | 1688 | 1800 |

`CUT = [0, 113, 225, 338, 450, 563, 675, 788, 900, 1013, 1125, 1238, 1350, 1463, 1575, 1688, 1800]` — als Konstante nach `trailer/src/lib/timings.ts`. Beat n = `round(n × 28.125)`; Halbbeat-Raster (56,25 F) nur für Glitch-Blitze innerhalb einer Szene.

### 1.3 Geplante Musik-Dramaturgie (typische Trailer-Struktur, wird nach Download verifiziert)

| Trailer-Takte | Frames | Musik-Soll | Bild |
|---|---|---|---|
| 1–4 (Intro) | 0–450 | ruhig: Intro/Verse-Ausschnitt, Vocal-Hook leise | Akt I: Cold Open + Limbo (langsam) |
| **5** (DROP 1) | **450** | **Drop/Chorus-Einsatz** — härtester Hit des Fensters | Sky-Rift reißt auf |
| 5–8 | 450–900 | Drop-Sektion 1 | Rift → Altar-POV → Wand-Kämpfe |
| **9** (Impact 2) | **900** | 2. Drop-Runde / Chorus-Wiederholung (typisch bei 128-BPM-Tracks: 8-Takt-Perioden) | Herold-Ankunft „Tag 7." |
| 9–14 | 900–1575 | Drop-Sektion 2, dichteste Stelle | Sturm/Dorf → Sturmkampf → Fährmann |
| 15 | 1575–1688 | letzter Fill / Outro-Auftakt | End-Helix |
| 16 (Abriss) | **1688** | harter Abriss auf Downbeat 16 + Sub-Tail | Schwarzes Loch → Endcard |

### 1.4 Analyse- und Schnitt-Prozedur nach dem Download (PFLICHT vor dem Feinschnitt)

1. Quelle → `worst_enemy_src.(wav|mp3)`; Loudness-/Energie-Profil wie in `sound_design.md` §1: `ffmpeg -af ebur128` Momentary im 100-ms-Raster + `astats`-Onsets → realen **Drop-Zeitpunkt `T_drop`** und echten BPM-Feinwert bestimmen (Nominal 128, Live-Wert kann 127,8–128,2 sein → Beat-Grid ggf. auf gemessenen Wert nachziehen).
2. **Quell-Fenster:** `T_drop − 7,5 s` bis `T_drop + 22,5 s` (Drop landet auf Takt 5 = Frame 450). Hat der Song keine 7,5 s brauchbares Ruhe-Material vor dem Drop: Intro des Songs (erste 4 Takte) davorschneiden, Crossfade 1 Takt vor dem Drop-Fenster (gleicher Track/Key → unhörbar, Rezept analog `sound_design.md` §2).
3. **Alternative bei spätem/zweitem Drop:** Drop stattdessen auf Takt 9 (Frame 900) legen — dann Szenen V03–V05 als „Build" abmischen (Text-Pops statt Impact-Hits) und die SFX-Gruppe um +450 Frames schieben. Entscheidung nach Gehör am realen Track.
4. Abriss auf Downbeat 16 = **Frame 1688 = Trailer-28,13 s** = Quell-`T_drop` + 20,63 s (`afade=t=out:d=0.05`); darunter der bewährte Sub-Tail: `eclipse_totality` 128,2–134,2 s, Lowpass 120 Hz (identisches Rezept `sound_design.md` §2/§5) — hält die Endcard „im Mod-Klang". Da der Tail nur ~1,8 s Raum hat, Fade-out des Tails auf 29,3 s ziehen und letzte ~40 Frames digital still (apad auf exakt 30,000 s).
5. 2-Pass-`loudnorm` auf **−14 LUFS / −1,5 dBTP**, 48 kHz stereo PCM → **`trailer/public/audio/worst_enemy_30s.wav`**. Kommandoblock: `sound_design.md` §5 wiederverwenden (nur Eingang/atrim-Werte tauschen).

---

## 2) Szenen-Liste V2 (11 Szenen · Summe exakt 1800 Frames)

Alle Setup-Syntaxen sind **gegen den Code verifiziert** (Quellen in §6). RCON = `python3 tools/rcon/rcon.py "<cmd>"`; ⚠️CHAT = muss aus dem Client-Chat kommen (`/tmp/mc.sh cmd "..."`), Spieler `Tester` (Op). Kamera-`/tp`-Konvention und Werkzeuge: `capture_plan.md` §0–§1. Video-Aufnahme: `/tmp/rec.sh <name> <sekunden>` — Rezept:

```bash
#!/usr/bin/env bash
# /tmp/rec.sh — x11grab-Video-Capture (Fenster-Offset WIN_X/WIN_Y vorher aus /tmp/mc.sh geom)
NAME=$1; DUR=${2:-20}
ffmpeg -y -f x11grab -framerate 60 -video_size 1920x1080 -i :1+${WIN_X:-0},${WIN_Y:-0} \
  -t "$DUR" -c:v libx264 -preset ultrafast -crf 14 -pix_fmt yuv420p \
  "/tmp/clips_raw/${NAME}.mp4"
```

### AKT I — Ruhe (Takte 1–4)

**V01 · Frames 0–225 · 3,75 s — „Schwarze Sonne" (Spektakel, Kamerafahrt)**
- **Bild:** Eclipse-Himmel über der schwebenden Altar-Insel, Altar-Aura Stufe 5 (Motes, Runen-Orbit, Lichtsäule, Lichtbänder — Photon-Partikel, llvmpipe-sicher). Fade-in aus Schwarz (F0–24).
- **Kamera:** langsamer Spectator-**Push-in** von Norden auf die Insel (geradlinige Dolly, kein Orbit — bei 5–15 fps am saubersten).
- **Capture:** RCON `eclipse day set 12` → `eclipse altar set 5` → `time set 6000` → `weather clear` → `gamemode spectator Tester` → `tp Tester 0 96 -130 0 -6`; 15 s FX-Rampe warten; F1; Aufnahme starten; W-Taste halten (`xdotool keydown w`, Spectator-Speed per Scroll auf Minimum) ~20 s Richtung Insel. Alternative mit Server-Kamera: `dev replay play intro ECLIPSE_ON` (FX-only) bzw. `/eclipsefx cutscene play intro_v3_flight` ⚠️CHAT (holt alle Spieler — solo egal).
- **Roh:** 20 s → **Remotion:** playbackRate **2×** (nutzt ~7,5 s der besten Fahrt), Rest-Trim; Text T1.
- **Übergang:** harter Cut auf F225.

**V02 · Frames 225–450 · 3,75 s — „Das Geisterschiff" (NPC-Szene 1: Limbo-Wesen)**
- **Bild:** Geisterschiff im Limbo-Nebel, **Deckhands rudern auf den Bänken** (Crew spawnt automatisch: `GhostShipBuilder` → `DeckhandEntity.ensureCrew`, Ruder animiert via `OarAnimator`), Laternen (`eclipse:drift_lantern`).
- **Kamera:** langsame **Längs-Dolly** am Rumpf entlang (Bug → Heck), Deckhands + Ruder groß im Bild.
- **Capture:** RCON `eclipse tp_limbo Tester` → `gamemode spectator Tester` → `effect give Tester minecraft:night_vision 3600 0 true` → `execute in eclipse:limbo run tp Tester 24 72 -14 45 8` (seitlich vor dem Bug, Schiffszentrum (0,~64,0), Rumpf x±19/z±4); Aufnahme; langsam W halten, diagonal am Rumpf entlang ~20 s. Optional-Plus: `eclipse boss ferryman summon` (RCON, spawnt im Limbo) für eine Fährmann-Silhouette am Heck — danach sofort `eclipse boss ferryman kill`.
- **Roh:** 20 s → **Remotion:** playbackRate **1,5–2×** (Ruderbewegung soll sichtbar bleiben!), Text T2.
- **Übergang:** Glitch-Cut (6 F, `Glitch.tsx`) exakt auf den DROP bei F450.

### AKT II — Drop-Sektion 1 (Takte 5–8)

**V03 · Frames 450–563 · 1,9 s — „Der Himmel bricht" (Spektakel, DROP-Hit)**
- **Bild:** Sky-Rift reißt bei Tagesanbruch über der Insel auf, violettes Randglühen.
- **Kamera:** statisch-steil nach oben (Bewegung kommt vom Riss selbst — llvmpipe-freundlich).
- **Capture:** RCON `time set 23000` (Morgengrauen) → `tp Tester 0 90 -25 0 -35`; ⚠️CHAT `/eclipsefx rift 0 135 30 14`; Aufnahme 12 s (Aufreißen + Glühen); ⚠️CHAT `/eclipsefx rift close`.
- **Roh:** 12 s → **Remotion:** playbackRate **3×** (Aufreiß-Moment auf F450 gelegt), Impact-Frame (Weißblitz 1 F) + Shake Heavy; Text T3 (Pop).
- **Risiko/Fallback:** Rift-Renderer ist Veil-lastig → falls auf llvmpipe unsichtbar: **Nether-Öffnung** als Ersatzmotiv (RCON `dev nether replay_fx`, ~47 s FX-only, Rauchsäule+Debris = reine Partikel; Kamera `tp Tester 150 92 150 135 0`) — Text T3 passt auf beide.
- **Übergang:** harter Cut.

**V04 · Frames 563–675 · 1,9 s — „Zahl mit Herzen" (Gameplay-POV 1: Altar-Einzahlung)**
- **Bild:** Ich-Perspektive: Hand mit **Herzfragmenten**, Rechtsklick auf den Altar (0,88,0) → Deposit-FX/goldene Partikel (Deposit-Lane liegt auf `AltarBlock#useItemOn`; Gold-Zeremonie: `AltarBuyCeremony`).
- **Kamera:** First-Person statisch vor dem Altar, leichte Blickbewegung zum aufsteigenden Fragment.
- **Capture:** RCON `gamemode creative Tester` → `give Tester eclipse:heart_fragment 8` → `eclipse altar set 3` → `tp Tester 3 85 3 -135 -10`; F1; Aufnahme 12 s; Rechtsklicks via `DISPLAY=:1 xdotool click 3` im 1-s-Takt (Fenster vorher `windowactivate --sync`).
- **Roh:** 12 s → **Remotion:** playbackRate **2×**, Gold-Akzent im Grade (einziger Gold-Moment vor der Endcard); Text T4.
- **Fallback:** löst der Item-Rechtsklick keine fotogene FX aus → echten Shop-Kauf am Altar-Panel ausführen (Zeremonie-Flug wie V1-Still `heart_ceremony`), oder RCON `dev glitch altar` (violetter Void-Puls) als Ersatz-FX unter dem Wurf.
- **Übergang:** harter Cut.

**V05 · Frames 675–900 · 3,75 s — „Deine Magie" (Gameplay-POV 2: Zauberstab vs. Mobs)**
- **Bild:** Ich-Perspektive: Zauberstab-Casts auf ein anrückendes Mob-Rudel — `glut.feuerball` (PROJECTILE) + `riss.umbra_lanze` (BEAM) auf 3× `eclipse:glitched_husk` + 2× `eclipse:storm_hound`. Photon-Trails/Explosionen animieren auch bei 5 fps flüssig im Capture.
- **Kamera:** First-Person, Position halten (kein Strafing — ruckelt), nur Ziel-Schwenks per Maus.
- **Capture:** RCON `gamemode creative Tester` → `give Tester eclipse:eclipse_wand` → `dev wand set Tester path glut` → `dev wand set Tester level 5` → `dev wand set Tester charge 100` → `eclipse invuln Tester on` → `tp Tester -14 85 0 -90 -5` → `summon eclipse:glitched_husk -26 85 -2` (×3, z −2/0/+2) → `summon eclipse:storm_hound -24 85 4` (×2); F1 (HUD aus — Stab bleibt sichtbar); Aufnahme 18 s; Casts: `xdotool click 3` alle ~1,5 s; für den BEAM-Wechsel Sneak-Rechtsklick (Spell-Cycle) einplanen oder zweiten Take mit `path riss` fahren.
- **Roh:** 18 s (bzw. 2 Takes à 12 s) → **Remotion:** playbackRate **3×** — Speed-Up kaschiert das Mob-Ruckeln exzellent, Treffer wirken snappy; interner Halbbeat-Glitch bei F788 (Takt 8). Text T5.
- **Cleanup:** `kill @e[type=eclipse:glitched_husk]` · `kill @e[type=eclipse:storm_hound]` · `eclipse invuln Tester off`.
- **Übergang:** Glitch-Cut (4 F) auf Impact 2 bei F900.

### AKT II — Drop-Sektion 2 (Takte 9–12)

**V06 · Frames 900–1125 · 3,75 s — „Tag 7: Der Herold" (NPC-Szene 2: Boss-Spawn-Cutscene)**
- **Bild:** Herold-Ankunfts-Sequenz über dem Altar: violette Säule (t≈0,75 s) → Silhouette (t≈2,75 s) → Materialize (t≈6,5 s) → Spawn (t≈7,5 s) — Beats aus `DevEventCommands`-Timeline (Säule t=15, Silhouette t=55, Materialize t=130, Spawn t=150 Ticks).
- **Kamera:** statisch seitlich, Eclipse hinter dem Herold-Kopf framen (Ring-Motiv aus V1 beibehalten).
- **Capture:** Kamera VORHER: RCON `tp Tester 14 87 0 90 -12` (Spectator) → Aufnahme starten → RCON `dev event start herold` → 14 s laufen lassen (Spawn + 2–3 s Idle/Flug) → RCON `eclipse boss herald kill`.
- **Roh:** 14 s, wiederholbar → **Remotion:** playbackRate **2,5×** (ganze Sequenz Säule→Spawn in 3,75 s), Impact-Frame auf F900; Text T6 (Pop).
- **Übergang:** harter Cut.

**V07 · Frames 1125–1238 · 1,9 s — „Kein Ort ist sicher" (NPC-Szene 3: Dorf + Sturm)**
- **Bild:** Plains-Dorf (Landmark `eclipse:village_plains` bei **(254, ~70, −22)**, r≈40, verifiziert in `DiscMapDefaults`) — Villager im Vordergrund, dahinter zieht eine dunkle Sturmwand auf, Blitz schlägt ein.
- **Kamera:** tiefe Totale durch die Dorfgasse, statisch mit Mini-Drift (Bewegung = Sturm + Villager).
- **Capture:** RCON `time set 6000` → `tp Tester 254 72 -60 0 -3` (creative, Blick Nord in die Gasse); Villager-Bestand prüfen, bei Bedarf `summon minecraft:villager 250 70 -30` (×3–4); ⚠️CHAT an Sturm-Sollposition (hinter dem Dorf) `/eclipsefx storm add 24 64 wall`; 10 s FX-Rampe; Aufnahme 15 s; bei ~8 s ⚠️CHAT `/eclipsefx storm bolt 1.0`; Cleanup ⚠️CHAT `/eclipsefx storm remove`.
- **Roh:** 15 s → **Remotion:** playbackRate **2×**, Blitz-Frame als natürlicher Akzent auf Beat legen; Text T7.
- **Alternative:** passive Fog-Storm-Site (0,−250) statt Dev-Sturm — aber ohne Dorf; das Dorf ist der NPC-Pflichtteil, also Dev-Sturm bevorzugen.
- **Übergang:** Whip-Pan-Fake (6 F) in V08.

**V08 · Frames 1238–1350 · 1,9 s — „Im Auge des Sturms" (Gameplay-POV 3: Kampf + Block-Display-Schwarm)**
- **Bild:** Ich-Perspektive am Gravity Rift: **~218 kreisende Orbital-Block-Displays** (llvmpipe-sichere Geometrie), Spieler castet `stern.kometenschlag` auf 2 anrückende `eclipse:fog_revenant`, Energie-Ring-Puls.
- **Kamera:** First-Person am Kraterrand, Blick in den Orbital-Schwarm.
- **Capture:** RCON `time set 6000` → `tp Tester -174 95 112 50 20` → `dev woah gravity orbitals` (erst tp, dann orbitals — Displays budgetieren bei Spielernähe!) → `dev wand set Tester path stern` → `summon eclipse:fog_revenant -200 80 130` (×2) → `eclipse invuln Tester on`; Aufnahme 15 s; bei ~5 s RCON `dev woah gravity pulse` (Launch-Beat), Casts via `xdotool click 3`.
- **Roh:** 15 s → **Remotion:** playbackRate **3×** — kreisende Displays + Puls-Ring werden im Speed-Up hypnotisch; kein Text (Action clean).
- **Cleanup:** `kill @e[type=eclipse:fog_revenant]`.
- **Übergang:** harter Cut.

### AKT III — Finale (Takte 13–16)

**V09 · Frames 1350–1575 · 3,75 s — „Der Fährmann" (NPC-Szene 4 + Gameplay: Boss-Kampf)**
- **Bild:** Fährmann-Arena auf dem Limbo-Deck: Fährmann-Boss (GeckoLib) frontal, Spieler castet `riss.umbra_lanze`-Beams, Phase-2-Eskalation.
- **Kamera:** Take A First-Person (Cast-POV, 12 s) + Take B Third-Person-Front via zweimal `/tmp/mc.sh key F5 2` (Fährmann + Spieler im Profil, 10 s) — im Schnitt A(1 Takt)→B(1 Takt) auf Downbeat 14 (F1463) wechseln.
- **Capture (DESTRUKTIV — als letzte Session, s. §5):** RCON `dev stage backup now trailer_v2_pre` (falls nicht längst geschehen) → `dev ferryman skip_to arena` (teleportiert ALLE aufs Deck, staged Finale) → `eclipse invuln Tester on` → Wand-Prep wie V05 (path riss); Aufnahme 20 s; optional RCON `eclipse boss ferryman phase 2` für die Eskalations-Optik; danach `eclipse boss ferryman kill` + `dev stage revert` (bzw. Welt-Reset, s. §5).
- **Roh:** 20 s (2 Takes) → **Remotion:** playbackRate **2×** (Boss-Animationen lesbar halten), Text T8.
- **Nicht-destruktive Alternative:** RCON `eclipse boss ferryman summon` (spawnt im Limbo, verifiziert in `EclipseCommands#ferrymanSummon`) + Kampf auf dem normalen Schiffsdeck — weniger Arena-Inszenierung, dafür ohne Welt-Verbrauch.
- **Übergang:** Glitch-Cut (4 F).

**V10 · Frames 1575–1688 · 1,9 s — „Der Altar ruft" (Spektakel: End-Ankunft-Helix)**
- **Bild:** violette Energiesäule → Himmels-Maul → Trümmer-Helix (600-Teile-Event; CHARGE-Fenster 8–20 s, SPILL 20–40 s der FX-Timeline).
- **Kamera:** statisch von Südost erhöht (Bewegung = Säule/Helix/Trümmer).
- **Capture:** Kamera VORHER: RCON `tp Tester 65 100 65 135 -25` (Spectator) → Aufnahme starten → RCON `dev event start endarrival fxonly` (**NIE ohne `fxonly`** — baut sonst die End-Disc permanent!) → 40 s mitlaufen lassen (CHARGE + SPILL) → `dev event stop endarrival`.
- **Roh:** 40 s (bestes 8-s-Fenster nutzen) → **Remotion:** playbackRate **4×** — die 50-s-Show als 2-s-Zeitraffer-Detonation; Text T9.
- **Übergang:** radialer Sog beginnt in den letzten 20 Frames (Vorgriff auf V11).

**V11 · Frames 1688–1800 · 1,9 s — „Schwarzes Loch → Endcard" (Spektakel + Titel)**
- **Bild:** Schwarzes Loch frisst den Himmel (Credits-Replay-Phase), radialer Sog zieht das Bild ins Zentrum, daraus morpht der **Eclipse-Ring** (vorhandene Komponenten `BlackHole.tsx`/`EclipseRing.tsx`, Morph-Rezept `motion_design.md` §3e) → Titel-Slam **„PROJECT: ECLIPSE"** bei ~F1720, Subline ab ~F1760. Musik-Abriss exakt auf F1688 + Sub-Tail.
- **Capture:** RCON `execute in minecraft:overworld run tp Tester 0 120 -60 0 -30` → Aufnahme 12 s → RCON `dev replay play credits BLACKHOLE` (FX-only, wiederholbar; NICHT `dev credits start` — beendet Clients + Server!).
- **Roh:** 12 s → **Remotion:** playbackRate **2×** für die ersten ~50 Frames, dann friert der Sog das Bild ein und die 4K-Design-Ebene übernimmt (Ring + Titel sind natives 4K, kein Footage nötig).
- **Risiko/Fallback:** BLACKHOLE-Phase rendert auf llvmpipe evtl. leer → Ersatzphasen `SHATTER`/`BURST` testen; letzter Fallback: V1-Still `credits_blackhole.jpg` als Ken-Burns-BG unter dem 4K-Ring (bewährt aus V1).

**Frame-Kontrolle:** 225+225+113+112+225+225+113+112+225+113+112 = **1800** ✓ (Grid aus §1.2).
**Quoten-Kontrolle:** NPC/Mob-Szenen: V02, V06, V07, V09 (+Mobs in V05/V08) = **4+** ✓ · Gameplay-POV: V04, V05, V08 (+V09-Take A) = **3+** ✓ · Spektakel: V01, V03, V10, V11 ✓ (Nether-Öffnung als V03-Fallback im Pool).

---

## 3) Titel/Text-Overlays (Deutsch — kurz, kraftvoll)

Typo/Stil unverändert aus `motion_design.md` §2 (Bebas Neue Versalien, Space Grotesk Taglines, Gold nur Endcard).

| # | Szene | Wortlaut | Ein (Frame) | Aus (Frame) | Stil |
|---|---|---|---|---|---|
| T1 | V01 | Sieben Tage. | 45–65 | 195–215 | Fade, klein, zentriert |
| T2 | V02 | Der Tod ist erst der Anfang. | 265–285 | 420–440 | Fade, langsam |
| T3 | V03 | Der Himmel bricht. | 455–462 | 540–555 | Pop + Glitch-Zittern (Drop!) |
| T4 | V04 | Zahl mit Herzen. | 580–592 | 650–665 | Fade, Gold-Akzent |
| T5 | V05 | 30 Zauber. Dein Pfad. | 690–702 | 860–875 | Fade, zweizeilig |
| T6 | V06 | Tag 7. | 905–913 | 960–975 | Pop (hart) |
| T7 | V07 | Kein Ort ist sicher. | 1135–1147 | 1215–1230 | Fade |
| T8 | V09 | Der Fährmann wartet. | 1360–1372 | 1540–1555 | Fade, langsam |
| T9 | V10 | Eine Woche. Keine zweite Chance. | 1580–1592 | 1660–1675 | statisch über der Helix |
| T10 | V11 | **PROJECT: ECLIPSE** | 1720 (Slam) | bleibt | Endcard, SLAM-Spring + Gold-Keyline |
| T11 | V11 | Sieben Tage. Ein Ende. | 1760–1780 | bleibt | Subline |

V08 bleibt bewusst textfrei (dichteste Action). Alternativ-Sublines aus V1-`storyboard.md` §4 bleiben gültig („Die Sonne kommt nicht wieder.").

---

## 4) Remotion-Umbau-Plan (V1 → V2)

### 4.1 Komponenten

| V1 | V2 | Details |
|---|---|---|
| `components/Still.tsx` (Ken-Burns auf `<Img>`) | **NEU `components/Clip.tsx`**: `<OffthreadVideo src={staticFile('clips/…')} trimBefore={…} trimAfter={…} playbackRate={…} muted />` | `trimBefore/trimAfter` in Composition-Frames (60 fps), `muted` zwingend (Audio kommt zentral); leichter Rest-Ken-Burns (scale 1.02→1.06) über dem Video-Wrapper beibehalten — kaschiert 1080p→4K-Upscale zusätzlich. |
| `lib/shots.ts` (Still-Manifest) | `lib/clips.ts`: `{src, trimBefore, trimAfter, playbackRate, cutIn, cutOut, textId}` | `cutIn/cutOut` aus `CUT[]` (§1.2); Assertion: Σ Szenendauern = 1800. |
| `Glitch.tsx`, `Overlays.tsx` (Grade/Vignette/Grain/Letterbox), `TextCard.tsx`, `EclipseRing.tsx`, `BlackHole.tsx`, `Debris.tsx` | **unverändert weiterverwenden** | Grade-Timeline aus `motion_design.md` §1.4 auf die neuen Akt-Grenzen (F450/F900/F1688) mappen; `Debris.tsx` optional als Parallax-Layer über V10/V11. |
| Stills in `public/stills/` | **behalten als Fallback** | Pro Szene ist der V1-Still der definierte Notnagel (§2-Fallbacks); `Clip.tsx` bekommt ein `fallbackStill`-Prop. |

Achtung, bewusste Abweichung von `remotion_tech.md` §6 („OffthreadVideo nicht nötig"): V2 nutzt Videoquellen, der Video-Extraktions-Pfad ist jetzt gewollt. Konsequenzen: `--concurrency` beim 4K-Render eher **2** statt 3 (OffthreadVideo-Frame-Extraktion kostet RAM), Testrender-Hochrechnung neu messen (`remotion_tech.md` §4/§7-Prozedur unverändert anwenden).

### 4.2 Audio

- `public/audio/trailer_music.wav` (day_final-Mix) → **ersetzen** durch `public/audio/worst_enemy_30s.wav` (Herstellung §1.4). `TrailerAudio`-Volume-Envelope neu auf §1.3-Dramaturgie: Fade-in F0–45, Duck vor Drop F430–450, voll ab F450, Abriss ist ins WAV gebacken (F1688), Safety-Fade F1755–1800.
- **SFX beibehalten wo passend** (alle liegen schon konvertiert in `public/audio/`): `sfx_impact` auf F450 + F900 (Drop-Layer) · `sfx_glitch` auf Glitch-Cuts (F444, F894, F1346) · `sfx_bell` in V02 (~F300) und V09 (~F1360, Fährmann-Signatur) · `sfx_sub_boom` auf F1688 (Abriss/Endcard) · `sfx_unlock` auf F1720 (Titel-Slam) · `sfx_whisper` unter V01/V02 (−12 dB). **Entfallen:** `sfx_riser` (F-Moll-128-BPM-Track bringt eigenen Build mit — erst nach Song-Analyse entscheiden, ob der Riser doch unter Takt 4 gelegt wird).
- Ducking-Regeln unverändert aus `sound_design.md` §4.2.

### 4.3 Clip-Dateien

- **Struktur:** `trailer/public/clips/v01_eclipse_island.mp4 … v11_blackhole.mp4` (11 Dateien, snake_case wie Szenen-IDs).
- **Spez pro Clip:** 1920×1080 @ **60 fps konstant**, H.264 High, `yuv420p`, `+faststart`, **max 15 MB**. Transcode-Rezept (aus Roh-Capture, nur grob vorgetrimmt — der Feintrim passiert in Remotion): `ffmpeg -i raw.mp4 -ss <in> -t <len> -vf fps=60 -c:v libx264 -crf 18 -maxrate 8M -bufsize 16M -preset slow -pix_fmt yuv420p -an -movflags +faststart v0X_name.mp4` (8 Mbit/s-Cap ⇒ 15-s-Clip ≈ 15 MB Obergrenze; `-an` — Rohton ist wertlos).
- Clips enthalten **Originalgeschwindigkeit** + 2 s Rand vor/hinter dem Nutzfenster; `playbackRate`/Trim ausschließlich in Remotion (jederzeit nachjustierbar ohne Re-Encode).
- Git: Clips gesamt ≈ 60–120 MB → `public/clips/` in `.gitignore` aufnehmen und nur das finale MP4 committen (wie `out/`), ODER Clips via CRF 20 unter ~8 MB/Stück drücken, falls sie ins Repo sollen — Entscheidung beim Umbau, Default: **gitignore**.

### 4.4 Render

- Kommandos/Verifikation unverändert `remotion_tech.md` §7 (swangle, JPEG q95, `--video-bitrate=20M`, ffprobe-Gate < 95 MiB, `+faststart`), nur `--concurrency=2` als neuer Default wegen Video-Dekodierlast; Fallback-Leiter §8 (Scale 0.5 → Upscale) gilt weiter.

---

## 5) Capture-Reihenfolge / Regie-Plan

**Grundregeln:** Ein Client-Login pro Session (Rezept `capture_plan.md` §0.1–0.2, Multiplayer-Join über 127.0.0.1 — kein zweiter `runServer`, `run/world`-Lock!). **Vorab einmalig:** RCON `dev stage backup now trailer_v2_pre`. Alles Destruktive ans Ende. Aufnahme-Skript `/tmp/rec.sh` (Rezept in §2); Fensterposition vorher via `/tmp/mc.sh geom` in die x11grab-Offsets (`WIN_X`/`WIN_Y`) übernehmen.

| # | Cluster | Szenen | geteilter State / Begründung |
|---|---|---|---|
| 0 | Setup | — | Server + Client hoch, Fenster 1920×1080, `weather clear`, Backup, `dev viewdist pin Tester 12` |
| 1 | **Altar-Insel (0,88,0), Tag** | V01 → V04 → V05 → V06 | `day set 12`/`altar set 5` einmal setzen; erst die ruhige Fahrt (V01), dann POV-Szenen (V04/V05 creative), dann Herold (V06, hinterlässt kurz Boss → sofort killen) |
| 2 | **Altar-Insel, Morgengrauen** | V03 | `time set 23000` nur für diesen Shot; Rift öffnen/schließen |
| 3 | **Altar-Insel, Event-Show** | V10 | `dev event start endarrival fxonly` färbt den Himmel ~50 s um → als LETZTES am Altar |
| 4 | **Dorf (254,−22)** | V07 | eigener Ort; Dev-Sturm add → bolt → remove; Villager ggf. nachsummonen |
| 5 | **Gravity Rift (−239,167)** | V08 | erst tp, dann `orbitals` (Display-Budget braucht Spielernähe), `pulse` während der Aufnahme |
| 6 | **Limbo** | V02 | Dimensions-Hop `eclipse tp_limbo`; Deckhands sind immer da; NV-Effekt |
| 7 | **Overworld-Himmel, Replay** | V11 | `dev replay play credits BLACKHOLE` = FX-only, aber Screen-Takeover → nach den normalen Shots |
| 8 | **DESTRUKTIV (eigene Session, ganz zuletzt)** | V09 | `dev ferryman skip_to arena` = staged Finale (Weltverbrauch); danach `eclipse boss ferryman kill` + `dev stage revert`; falls der Stage-Revert die Limbo-/Arena-Reste nicht vollständig zurückdreht: Welt aus Backup zurückkopieren (Server vorher stoppen) |
| 9 | Cleanup | — | `eclipse altar set 0` · `eclipse day set 1` · `time set 6000` · `/eclipsefx rift close` · `/eclipsefx storm remove` · `dev glitch clear` · Bosse/Mobs killen · `eclipse invuln Tester off` |

**Destruktiv-Merkliste (nur bewusst + zuletzt):** `dev ferryman skip_to arena` / `dev start_ferryman` (staged Finale) · `dev event start endarrival` OHNE `fxonly` (baut End-Disc) · `dev nether open` (gräbt Krater) · `dev credits start` (**beendet Clients + Server** — für den Trailer IMMER `dev replay play credits …`).

**Session-Ökonomie:** Cluster 1–7 sind in einer Client-Session in ~60–90 min abfahrbar (inkl. FX-Rampen und Wiederholungs-Takes). Cluster 8 als separate Session einplanen, damit ein nötiger Welt-Reset die fertigen Captures nicht gefährdet.

---

## 6) Verifikations-Anhang (Code-Belege)

**Entity-Typen (Registry-Namen, Namespace `eclipse:`)** — Quellen: `entity/EclipseEntities.java`, `entity/fog/FogEntities.java` + `FogEliteEntities.java`, `entity/boss/fog/FogBossEntities.java`, `entity/boss/rift/RiftEntities.java`, `entity/glitch/GlitchEntities.java`, `entity/wizard/WizardEntities.java`, `entity/pale/PaleEntities.java`, `entity/dungeon/DungeonEntities.java`, `entity/ambient/AmbientEntities.java`:
`the_other`, `gazer`, `umbral_stalker`, **`deckhand`** (Limbo-Crew, Auto-Spawn via `GhostShipBuilder`→`DeckhandEntity.ensureCrew`, Ruder via `OarAnimator`), `sunmote`, **`herald`**, **`ferryman`**, `herald_shard`, **`fog_revenant`**, **`storm_hound`**, `fog_colossus`, **`fog_tyrant`**, **`rift_warden`**, `pale_sentinel`, `eclipse_cultist`, `shadow_bolt`, `drift_lantern`, `wizard_orin`, **`glitched_husk`**, `glitched_hound`, `glitched_tick`.

**Verwendete Commands (Datei-Belege):**
- `/dev event start herold [here]`, `/dev event start endarrival [fxonly]`, `stop` — `devtools/dev/DevEventCommands.java`, `DevEndArrivalCommands.java`
- `/dev start_ferryman`, `/dev ferryman skip_to arena`, `/dev ferryman status` — `DevFerrymanCommands.java`
- `/eclipse boss herald summon|kill`, `/eclipse boss ferryman summon|kill|phase <1-3>` — `admin/EclipseCommands.java` (Z. 161–174; `ferrymanSummon` spawnt in `eclipse:limbo`)
- `/dev replay list|play <id> <phase>|revert` (u. a. `credits BLACKHOLE|SHATTER|BURST`, `intro ECLIPSE_ON|FLIGHT`, `expansion SKYWARD`) — `DevReplayCommands.java`
- `/dev nether replay_fx|open|stop|status` — `DevNetherCommands.java`
- `/dev woah gravity build|pulse|orbitals|tp|status`, `/dev woah chrono …` — `woah/…` (siehe `capture_plan.md` §1)
- `/dev wand set <p> path|level|xp|charge`, `/dev wand xp|level` — `DevWandCommands.java`
- `/dev altar lock|unlock|status|offer enable|disable|list` — `DevAltarCommands.java`; Altar-Deposit-Lane: `ritual/AltarBlock.java` (`useItemOn`); Gold-Zeremonie: `economy/AltarBuyCeremony.java`; Item `eclipse:heart_fragment`: `registry/EclipseItems.java`
- `/dev glitch add|test|color|remove|clear|list|altar` — `DevGlitchCommands.java`; `/dev dome …` — `DevMansionDomeCommands.java`; `/dev backrooms tp|flicker` — `DevBackroomsCommands.java`
- `/dev structure list [filter]|place configured|template <id> [pos] [exact]` — `DevStructureCommands.java`
- `/dev stage backup now <name>`, `/dev stage revert` — `DevStageCommands.java`; `/dev limbo pvp|status` — `DevLimboCommands.java`
- `/eclipsefx storm add|remove|bolt`, `/eclipsefx rift … / rift close`, `/eclipsefx cutscene play <id>`, `/eclipsefx viewdist` (⚠️CHAT) und `/eclipse altar set`, `/eclipse day set`, `/eclipse tp_limbo`, `/eclipse freeze|invuln`, `/dev viewdist pin` — am Live-Server verifiziert (siehe `capture_plan.md` §1, RCON-Checks 2026-07-27)
- **Zauber (30 Stück, 3 Pfade × 10)** — `wand/WandSpells.java`: fotogen für POV-Beams/Projektile: `glut.glutstoss` (BEAM), `glut.feuerball` (PROJECTILE), `glut.inferno` (GROUND), `riss.umbra_lanze` (BEAM), `stern.kometenschlag` (GROUND), `stern.himmelsgericht` (GROUND, Kometen).
- **Dorf:** Landmark `eclipse:village_plains` @ (254, −22), r≈40 — `worldgen/DiscMapDefaults.java` Z. 169. Weitere Landmark-Koordinaten ebd. (Mansion 219/−219, Gravity −239/167, Nether-Breach 85/85, Fog-Storms 0/−250 + −173/−173, Outpost −192/−34).

---

## 7) Risiko-Liste (Top-Captures) & Fallbacks

| Rang | Capture | Risiko | Fallback |
|---|---|---|---|
| 1 | **V09 Fährmann-Arena** | destruktives staged Finale (`skip_to arena`), viele Akteure + FX bei 5–15 fps, Twin-Take-Choreo | Stufe 1: nicht-destruktiv `eclipse boss ferryman summon` auf dem Schiffsdeck + `phase 2`; Stufe 2: V1-Stills `ferryman_close`/`limbo_ship` mit Ken-Burns (Szene wird Still-Insel im Video-Trailer) |
| 2 | **V11 Blackhole-Replay** | Credits-BLACKHOLE ist Veil-Post-FX → auf llvmpipe evtl. leerer Himmel | Ersatzphasen `SHATTER`/`BURST`; sonst V1-Still `credits_blackhole.jpg` unter dem nativen 4K-Ring-Morph (Endcard bleibt in jedem Fall natives 4K-Design) |
| 3 | **V03 Sky-Rift** | Rift-Renderer Veil-lastig → möglicherweise unsichtbar | Motivtausch auf **Nether-Öffnung** `dev nether replay_fx` (Partikel-Rauchsäule, llvmpipe-sicher, Kamera (150,92,150)); Text T3 passt unverändert |

Sichere Bänke (reine Partikel/Displays/Geometrie, funktionieren immer): V01 Altar-Aura, V02 Geisterschiff+Deckhands, V05/V08 Photon-Casts + Orbital-Displays, V06 Herold-Säule, V07 Sturmwand, V10 Helix-Trümmer.
