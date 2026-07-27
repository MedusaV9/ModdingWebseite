# WOAH-01 MANSION GLITCH DOME — Status „Die Kuppel, in die man nicht hineinsehen kann"

Über dem Woodland-Mansion-Landmark (`eclipse:mansion`, Stage 4) steht eine opake,
grün pulsierende Glitch-Halbkugel (Shell-Radius 48–72, aus Footprint + Dachhöhe
abgeleitet, Zentrum 8 Blöcke über Grund). Hinein sieht man NIE (CPU-Hülle schreibt
Depth, shader-los = Iris-fest); innen läuft der grüne Outline+Scanline-Vollbild-Pass.
Ein GeckoLib-„Glitch Emitter" (3-Bein-Sockel, zwei gegenläufige Kupferringe,
pulsierender Kern, Antenne mit 200-Block-Himmelsstrahl) steht davor: 8 Nahkampf-Treffer
(10-t-i-Frames, Riss-Feedback in Tint/Jitter/Photon) starten eine 150-t-Zerstörungs-
sequenz mit ~240 BlockDisplay-Scherben, Loot-Drop und 3 Nachbeben.

## Was gebaut wurde

### Server (`woah/mansiondome/`)

- **`MansionDomeState`** — SavedData: Status (UNARMED/ACTIVE/COLLAPSING/DESTROYED),
  Dimension, Geometrie (centre/shellRadius/groundY/roofY), Gerät (Pos/UUID/
  hitsRemaining), zoneId, collapseStartGameTime, lootDropped, Aftershock-Plan,
  testDome-Flag.
- **`MansionDomeService`** — der Besitzer: armt beim `StructurePendingRegistry`-PLACED
  des Mansion-Site (+ Reconcile bei ServerStarted), Geometrie-Ableitung über
  Heightmap-Proben, persistente `dome`-GlitchZone (Radius +8 Pad, permanent), Gerät-
  Spawn/Respawn-Wächter, Beat-Replayer für die Kollaps-Timeline **t0** Gerät-Tod
  (Anim + Cue) → **t10** Shake 0.6 → **t20** Loot (4 Glitch-Shards + 500 XP am Gerät,
  `lootDropped`-Latch) → **t30** Shatter (Payload-Detail stoppt Hülle/Beam,
  `DomeShatterFx.begin`, `CUE_DOME_SHATTER_BURST(a=shellRadius)`,
  `EVENT_STORM_SHATTER` + `GENERIC_EXPLODE.value()`, Shake 1.0) → **t80** Zone-Fadeout
  (60 t) → **t150** DESTROYED + 3 Nachbeben (à 60 s Abstand, kleine Shard-Ringe +
  Flicker-Cue). Cursor-basiert: Restart mitten im Kollaps holt verpasste Beats in
  einem Tick nach (Loot nur einmal). `arm`/`setHits`/`devDestroy`/`reset` für Dev.
- **`DomeEmitterEntity`** — `EclipseGeoMob`-Muster: nur Spieler-NAHKAMPF zählt
  (Projektile/Magie/Umwelt annulliert), 10-t-i-Frames, `DATA_HITS` synced (Renderer-
  Tint/Jitter + „mehr Funken je kaputter"), Hit-/Death-Anim-Trigger, unbeweglich
  (noGravity/noPush/persistenceRequired), Loot-los (Loot kommt vom Service-Beat).
- **`MansionDomeProtection`** — `LandmarkProtection`-Muster: Break/Place/Explosionen
  im Schutz-Zylinder (shellRadius, groundY−8..roofY+8) annulliert solange
  ACTIVE/COLLAPSING; DevMode-Spieler exempt; Actionbar `message.eclipse.dome_protected`
  + Chime (2-s-Throttle).
- **`DomeShatterFx`** — die Masse: 240 BlockDisplays (200 Hemisphären-Panels nach
  Fibonacci-Verteilung + 40 Äquator-Großplatten, Palette grün getöntes Glas/
  Smaragd/Prismarin), Spawn-Budget 60/t (4 Ticks), Transform-Updates alle 10 t
  (Interpolation überbrückt), Flug 0.35–0.85×r nach außen + Up-Bias, quadratischer
  Gravity-Sag 5–14, Taumel 0.75–2.5 Umdrehungen, Scale→0, Life 80–120 t,
  Spieler-Gate 600, `view_range` 4.0, 400-t-Watchdog + `clearAll`-Sweep über Tag.
- **`MansionDomePayloads`** — eigener Registrar (v1-Gruppe `v1woahdome`):
  `S2CMansionDomePayload(status, dimension, centre, shellRadius, devicePos,
  collapseStartGameTime)`; Voll-Sync bei Login/Dimension-Wechsel/Statuswechsel.
- **`DomeCues`** — 4 Cue-IDs über `FxCues.cue(…)` (Datei FROZEN, nicht angefasst).

### Client (`woah/mansiondome/client/`)

- **`MansionDomeClient`** — Snapshot + geeaste Sichtbarkeit, inside-Test (r −1.5),
  `eclipse:dome_shell`-FEATURE-Row (Feeder: kamera-relatives `DomeCenter` in Doubles,
  `DomeRadius`, `Strength` mit 450→600-Distanz-Ramp + Kollaps-Puls, `Time`, `Detail`;
  innen + `reducedFx` → 0), 48/56-Block-Hysterese-Fenster für die zwei Photon-Loops
  (WINDOWED-Gesetz — Loops nie payload-gefeuert), Drone-Loop
  (`AMBIENT_STORM_DOME_DRONE`, 48-Block-Hörweite, distanz-/statusgeregelt),
  Logout-/Clone-Resets.
- **`DomeShellRenderer`** — die Garantie: CPU-UV-Sphere (2 LODs 24×12 / 12×6,
  RenderLevelStage AFTER_TRANSLUCENT), Pass 1 opakes near-black Hull mit
  Fresnel-Rim (depthWrite an — verdeckt das Innere physisch), Pass 2 additive
  Scroll-Scanlines, Pass 3 Hex-Schimmer (nur nah); innen nur ein dünner Interior-Film;
  Kollaps: Puls + top-down-Peel bis t30, danach aus.
- **`DomeBeamRenderer`** — SupplyBeamRenderer-Klon: 4 gekreuzte additive Planes
  (Core 0.5 / Haze 1.6) + Impact-Disc, `border_glitch.png` up-scroll, Dome-Grün,
  Höhe 200; LOD >192 nur Core, >640 aus; COLLAPSING: 10-Hz-Flackern bis t30, dann
  top-down-Kollaps bis t50.
- **`DomeEmitterRenderer`** — `EclipseGeoRenderer("glitch_emitter")` + Glowmask;
  Schadens-Tint Richtung Rot + Positions-Jitter ab ≤3 Treffern; Selbstregistrierung
  (`DeckhandRenderer.Registration`-Muster).
- **`MansionDomeFxRows`** — 4 Rows: `dome_device_hit` (Leg: zweite 1.35×-Instanz bei
  a ≤ 0.375 oder Death-Beat), `dome_shatter_burst` (Leg: Executor-Scale a/8, Clamp
  1–12), `dome_device_idle` + `dome_beam_base` (AMBIENT, WINDOWED).

### Assets

- **Pipelines**: `pinwheel/post+program/glitch_dome` (Innen: Depth-Laplace- +
  Normal-Outline auf UNVERSCHOBENEN UVs, CRT-Layer auf Pattern-UVs — Merge aus
  glitch_outline + glitch_scanlines, gz-Uniform-Kontrakt von `GlitchZoneFx`) und
  `pinwheel/post+program/dome_shell` (Außen-Garnitur: analytischer Ray-Sphere-Schnitt,
  Heat-Shimmer, Rim-Chroma, Hex-Schimmer, Scanline-Flicker — rein additiv ÜBER der
  opaken CPU-Hülle).
- **GeckoLib**: `geo/entity/glitch_emitter.geo.json` (18 Bones, 128²-Atlas),
  `animations/entity/glitch_emitter.animation.json` (idle 4-s-Loop Ringe/Kern/Antenne,
  hit 0.35 s, death 1.5 s hold-on-last), Texturen via
  `tools/woahdome/gen_glitch_emitter_textures.py` (PIL, Gunmetal/Kupfer/Toxic-Grün,
  Glowmask nur Kern + Antennen-Knauf).
- **Photon**: `tools/photon/woah_dome_fx.py` → 4 `.fx` + `.fxproj`
  (`dome_device_idle`, `dome_beam_base`, `dome_device_hit`, `dome_shatter_burst`) —
  fxlib-validiert, Lint 0 NEW error/warn (nur Palette-Advisories, Dome-Grün ist
  bewusst neu), Loops mit Cull-Boxen, alles ≤ 96 maxParticles, HDR ≤ 2.4.
- **Langdrop**: `docs/plans_v3/langdrop/woah_dome.json` (21 Keys en+de).

## Was funktioniert (verifiziert)

- `javac`-Lauf über alle 18 Feature-Dateien + transitive Repo-Deps gegen die
  NeoForge-21.1.238-/GeckoLib-4.9.2-/Veil-4.3.0-Cache-Jars: **0 Fehler** (auch die
  3 additiv berührten geteilten Dateien kompilieren).
- fxlib `validate --lint`: 4/4 Assets strukturell valide, round-trip-identisch,
  0 neue error/warn-Findings.
- Geo↔Animation-Konsistenz (alle animierten Bones existieren, `animation.
  glitch_emitter.*`-Schlüssel = `EclipseGeoAnimations.animId`-Schema), Pipeline-JSONs
  identisch zum Hausformat, Shader-Uniforms = Feeder-Kontrakte (`GlitchZoneFx` generisch
  / `MansionDomeClient.feedShell`), alle `#include`-Funktionen existieren
  (`eclipse_common`/`eclipse_glitch`/`veil:space_helper` — `storm_volume`-Präzedenz).

## Offen / bewusst nicht gemacht

1. Langdrop-Merge in die echten Lang-Dateien (geteilte Dateien — Hauptagent).
2. Kein Runtime-Test (kein `./gradlew` erlaubt) — RCON-Anleitung unten.
3. Der Interior-Pass nutzt den generischen GlitchZone-Accent-Uniform-Satz; ein
   Mansion-eigener Accent (z. B. per Disc-Profil) wäre ein Follow-up.
4. Aftershock-Shards nutzen `DomeShatterFx` mit kleinem Radius (20) — bewusst
   dieselbe Engine statt einer zweiten.

## RCON-Testanleitung

```
# 0) Als Operator (perm 2). Interior-Post allein (ohne Welt-Setup):
/dev glitch test dome 10

# 1) Test-Kuppel direkt am Spieler (r 40; transient, nie das echte Mansion):
/dev dome arm here
/dev dome status            # ACTIVE, Geometrie, hits 8/8
#    -> Hülle (opak, grün), Beam 200, Gerät sichtbar; innen Outline+Scanlines;
#       Loops/Drone nur im 48-Block-Fenster.

# 2) Hit-Feedback: das Gerät 3-4x mit der Hand/Schwert schlagen (i-Frames 0.5 s)
#    -> Funken werden ab <=3 Resthits sichtbar dichter, Tint/Jitter am Modell.
/dev dome hits 1            # Abkürzung: ein Schlag vor dem Kollaps

# 3) Voller Kollaps (oder letzten Treffer schlagen):
/dev dome destroy
#    -> t0 Death-Anim, t10 Shake, t20 Loot (4 Shards + XP), t30 Hülle->240 Scherben
#       + Schockring + Explosion, t80 Innen-Fade, t150 fertig; danach 3 Nachbeben
#       im Minutentakt.

# 4) Nur die Scherbenschau iterieren (an der Kuppel falls scharf, sonst über dir):
/dev dome shatter

# 5) Zurückspulen und nochmal:
/dev dome reset

# 6) Der echte Pfad (Stage-4-Welt): Mansion platziert -> Dome armt sich selbst.
/dev dome arm               # manuell, falls der Listener verpasst wurde
```

## Risiken

- **Photon-Loop-Optik** ist ungetestet (kein Runtime): Raten/Größen der zwei Loops
  könnten Feintuning brauchen — Generator re-runnen, Werte oben ändern.
- **Shell-Radius-Heuristik** (Footprint 80 + Pads, Clamp 48–72) gegen echte
  Mansion-Größen erst in einer Stage-4-Welt verifizierbar; `arm here <r>` deckt die
  Extreme 12–96 ab.
- **240 BlockDisplays**: Budgets (60/t Spawn, 10-t-Updates, view_range 4) folgen dem
  Plan; auf sehr schwachen Clients bleibt der t30-Beat der teuerste Moment.
- **Parallel-Wave-Merges**: `GlitchZoneEffects.IDS` + `VanillaLandmarks`-Fassade sind
  additiv, aber wenn eine andere Welle dieselben Dateien anfasst, zuerst mergen.
