# WOAH-05 ECHO-HAIN — Status

Implementierung von `docs/plans_v3/woah/PLAN-05_echo_grove.md`. Feature-Code in
`dev.projecteclipse.eclipse.woah.echogrove` (+ Client in `client/echo` und
`client/entity/echo`); geteilte Dateien nur über die sanktionierten Ausnahmen
(Details: `woah_echo_wiring.md` daneben).

## Gebaut (fertig, kompiliert)

**Server** (`woah/echogrove/`, 18 Klassen):

- `EchoGroveSites` — Landmark-Materialisierung im FogStormSites-Muster: Stage-4-Listener
  → `StructurePendingRegistry`-Async-Placer → `SitePrep.preparePlateau` →
  `EchoGroveTerraformer` → `SitePrep.finish`; Restart-Sweep für verwaiste
  Szenen-Displays + Kollisionswarnung, wenn die Landmark-Row nicht frozen ist.
  `materializeNow` mit Callback-Überladung für den Dev-Command.
- `EchoGroveTerraformer` — budgetiertes Carving der Nebelmulde (r30, Kosinus-Bowl T5,
  Pale-Moss/Podzol/Grob-Erde-Mix, Rest-Pfützen), Bone-Block-Wurzeln, Dead-Bush-Inseln,
  ~14 bleiche Pale-Oak-Bäume (gehasht deterministisch, KEEP_CLEAR um Szenen-Plätze),
  Erinnerungs-Baum (12 h, Stripped-Pale-Oak + Bone-Krone) mit Probe-Block
  (Verdite/Glow-Lichen-Anker für die Client-Grade), Szenen-Props (Bank, Stollen-Mund,
  3 Laternenpfähle), statische Glimmer-BlockDisplays (Tag `eclipse_echo_static`,
  UUIDs in SavedData) + 10 Orbs (5 verloren + 5 Baum; `respawnOrbs` für reset).
  Probe-Block = `WAXED_OXIDIZED_COPPER_BULB` in der Baumkrone (`EchoGroveLayout.probePos`).
- `EchoScenes` — Szenen-Datenmodell (Pose/Keyframe/Actor/Prop/Scene), JSON-Load aus
  `data/eclipse/echo_scenes/` bei `ServerStartedEvent` (ResourceManager, Datapack-
  überschreibbar) mit 5 Code-Defaults als Fallback; Catmull-Rom-Sampling.
- `EchoSceneService` — LOD-Ticker (nur < 64 Blöcke Spieler-Distanz), Loop-Instanzen
  mit Fade-in/out (30 t), `playOnce` (verstärkt neben dem Spieler, pro Spieler max. 1),
  Gather-Modus fürs Finale (radiale Keyframes zum Baum), dynamische Props
  (Tag `eclipse_echo_scene`), Actor-/Instanz-Zensus für status.
- `EchoOverlayBuilder` — 620er-BlockDisplay-Overlay-Pool (Scale-0.02 geparkt,
  Batch-Spawn 50/t im 128-Block-Fenster, deterministische Specs aus den
  Terraformer-Offsets), 4 Aufwachs-Wellen (`pushWave` mit Interpolation),
  Brightness-Steps, Finale-Blüten-Set + Afterglow-Kronen (15 %),
  Tag `eclipse_echo_overlay`, Restart-Sweep.
- `MemoryFloodService` — Flut-Timer (~1800 t ±200; Afterglow 1200 t), Gate: Spieler
  < 96 Blöcke; Timeline 160 t (Wellen wachsen → golden halten → Asche-Rückblende),
  Cue `woah_echo_flood` an alle Spieler < 256; Spieluhr-Motiv server-sequenziert aus
  `NOTE_BLOCK_CHIME`/`NOTE_BLOCK_BELL` (12-Noten-Phrase in a-Moll auf dem
  Vanilla-Pitch-Raster 0–24, 6-t-Grid; `NOTE_FALLBACK`-Flip-Konstante für den
  späteren `echo_music_box.ogg`-Umstieg) + 3-Ton-Abgabe-Chime.
- `MemoryOrbEntity` — interagierbares No-AI-Mob (0.5×0.5, unverwundbar, persistent):
  verlorene Orbs → Einsaug-Cue + 1× `memory_mote` + Whisper-Caption (collect einmalig,
  Bitmaske in SavedData); Baum-Orbs → Lore-Whisper (`echo.eclipse.memory.<n>`,
  Gazer-Whisper vol 0.35 pitch 0.7, 3-s-Cooldown) + verstärktes `playOnce`; Abgabe
  per `memory_mote`-Rechtsklick → `DATA_LIT`, Chime, bei 5/5 Finale.
- `EchoGhostEntity`/`EchoGhostWolfEntity` (+ `EchoActor`-Interface) — No-AI/No-Physics/
  unverwundbar auf dem LogoutGhostEntity-Chassis (Wolf extends `Wolf` für das
  `WolfModel`, Interaktionen totgelegt, `isInSittingPose` auf `ACTION_SIT` gemappt);
  Synced-Data ACTION/FADE/CHILD/GLOW, Bewegung server-getrieben, `shouldBeSaved=false`.
- `EchoFinaleSequence` — Timeline 620 t (Flut erzwungen mit holdTicks=600 → Gather →
  Blüten-Set + `CUE_ECHO_BLOOM_RAIN` + Motiv 2× → Belohnung am Baumfuß:
  `echo_blossom` + 3 Diamanten + 16 Pale-Oak-Leaves + 500 XP in 10 Orbs +
  `AWARD_STING` + TITLE-Caption → Afterglow persistiert).
- `EchoGroveState` — SavedData `eclipse_echo_grove.dat` (placed, treeCenter,
  collectedOrbs-Bitmaske, deposited, finaleDone, staticDisplayUuids, orbUuids);
  `EchoGrovePayloads` — eigener Registrar (`v1woahecho`) für `S2CEchoGrovePayload`
  (Login + jede Änderung); `EchoGroveEntities`/`EchoGroveItems` — eigene
  DeferredRegisters (unter dem WOAH-05-Anker); `EchoGroveCues` — 4 Cue-Ids via
  `FxCues.cue(...)`; `EchoGroveLayout` — geteilte Geometrie (Landmark-Read + Fallback
  0/310, Bowl, Probe-Pos); `EchoGroveDevCommands` — §9-Befehle am `/dev woah`-Literal.

**Client** (`client/echo/` + `client/entity/echo/`, 10 Klassen):

- `EchoGroveFx` — Veil-GRADE `eclipse:echo_grade` (VeilPostController, GRADE-Priorität,
  Uniforms Amount/Warmth/AfterglowFloor/Time/Detail; Distanz-Rampe 70→90 Blöcke +
  Probe-Block-Check alle 20 t) + Photon-Loop-Fenster (Ground-Fog, Spores, Tree-Lights;
  Materialize < 80 / Release > 100, Retry 20 t) + Flut-Warmth-Easing.
- `EchoPhotonFxRows` — selbstregistrierende Rows (FMLClientSetupEvent): 3 Loops +
  4 Cues; Flood-Leg latcht die Grade-Warmth und terminiert die Asche (+20 t);
  Spores-Variante nach `FxBudget.qualityTier()` (`_lite` für Tier 0/1).
- `EchoOrbGlowFx` — Orb-Attach-Loops (nearest-8, attach < 48/release > 50,
  `echo_orb_glow`/`_lit` nach `DATA_LIT`); `EchoGroveClientState` — Payload-Mirror.
- `EchoGhostRenderer` (PlayerModel, translucent, Fade/Glow, Kind-Scale, Sitz-/Winke-
  Posen, MoonGlowLayer), `EchoGhostWolfRenderer` (WolfModel translucent),
  `MemoryOrbRenderer` (Kamera-Billboard, `entityTranslucentEmissive`, Puls + Warmth-
  Tint), `EchoRenderers` — Registrierung.

**Assets:** 11 Photon-`.fx`+`.fxproj` via `tools/photon/echo_grove_fx.py` (gzip-NBT,
generator-validiert, Alpha-Sort-Lints behoben); `echo_grade`-Pipeline/Programm/`.fsh`;
5 Szenen-JSONs; Loot-Table `event/echo_grove_finale.json` (referenziell); Item-Modelle
+ prozedurale Texturen via `tools/skins/gen_echo_textures.py` (echo_ghost 64×64,
glow, wolf 64×32, memory_orb 32×32, 2× Item 16×16 — PIL/numpy, deterministisch).
**Docs:** Langdrop `woah_echo.json` (en_us+de_de, Key-Parität + Code-Abdeckung
geprüft), `woah_echo_sounds.json` (0 neue Sound-Events), `woah_echo_wiring.md`.

## Verifikation (ohne gradlew, Regel-konform)

- `javac` gegen `build/moddev/artifacts/neoforge-21.1.238.jar` + Gradle-Cache-Deps
  (Veil 4.3.0): **alle 28 Feature-Klassen + `WoahFeatures` fehlerfrei** (105 .class
  inkl. transitiv gezogener Repo-Quellen, 0 errors).
- Alle 5 Szenen-JSONs gegen den `EchoScenes.parseScene`-Vertrag geprüft (Pflichtfelder,
  sortierte Keyframes); alle 11 `.fx` als gzip-NBT round-trip-gelesen
  (`fxlib.py dump`); Generator idempotent re-run.
- Langdrop: en/de-Parität (36 Keys) + alle Code-Keys abgedeckt (Skript-Check).
- Texturen als RGBA mit korrekten Dimensionen verifiziert.

## Offen (bewusst — gesperrte Dateien / spätere Welle)

1. **Lang-Merge**: `docs/plans_v3/langdrop/woah_echo.json` → `en_us.json`/`de_de.json`.
   Ohne Merge erscheinen rohe Keys (funktional, aber hässlich).
2. **Audio-Upgrade**: `music/echo_music_box.ogg` (+ optional `echo_grove.ogg`,
   `echo_wind.ogg`) via TREBLO — Definitionen + Flip-Anleitung in
   `woah_echo_sounds.json`; bis dahin trägt der Note-Block-Fallback.
3. **Optional**: Cue-Konstanten nach `FxCues`, Items nach `EclipseItems`,
   `echo_blossom` in die Collections-Allowlist (`ItemLexiconService`) — reine
   Konsolidierung, kein Funktionsloch.
4. **Kein In-Game-Lauf**: `./gradlew` war gesperrt; Runtime-Verhalten (Shader-Kompilat,
   Photon-Spawns, Display-Wellen-Timing) steht beim zentralen Build/Testlauf aus.

## RCON-Testanleitung

```
# 1) Hain erzwingen (Stage-Gate-Bypass; async budgetiert, ein paar Sekunden) + Status
dev woah echo spawn
dev woah echo status

# 2) Hinfliegen (Landmark 0/310; Mulde liegt unter Terrain-Höhe)
execute as @p run tp @s 0 85 310

# 3) Szenen prüfen: < 64 Blöcke warten → Geister faden ein und loopen.
#    Einzelszene verstärkt neben dem Spieler:
execute as @p run dev woah echo scene dog_fetch

# 4) Erinnerungs-Flut erzwingen (Overlays wachsen in 4 Wellen, Grade golden, Asche)
dev woah echo flood
dev woah echo flood 600

# 5) Quest von Hand: 5 verlorene Orbs (Rechtsklick) → 5 Motes an Baum-Orbs abgeben.
#    Abkürzung fürs Finale (setzt deposited=5, startet die Sequenz):
execute as @p run dev woah echo finale

# 6) Reset (Orbs respawnen, Szenen despawnen, Pool re-parkt; Terrain bleibt):
dev woah echo reset
dev woah echo status

# 7) Aufräum-/Zensus-Helfer:
kill @e[tag=eclipse_echo_scene]      # Szenen-Displays (Service respawnt sie)
give @p eclipse:memory_mote          # Abgabe-Test ohne Sammeln
```

Erwartung: `status` zeigt `placed=true`, Pool 620/620 nach dem ersten Fenster;
Flut = 620 Overlays wachsen in 4 Wellen auf, Grade wird golden, Motiv klimpert,
Asche fällt beim Ausklang; Finale = Echos versammeln sich am Baum, Blütenregen,
Drop am Baumfuß, TITLE *"Der Hain erinnert sich."*, danach dauerhaft wärmerer Hain.

## Risiken

1. **Shader ungetestet zur Laufzeit** — `echo_grade.fsh` folgt der world_grade/
   xbox_era-Vorlage (Uniform-Feeding via `VeilPostController`), aber GLSL kompiliert
   erst im Client-Lauf. Fallback: Pipeline registriert sich mit Idle-Skip bei
   Amount=0 — Fehler wären auf den Hain begrenzt.
2. **Overlay-Budget** — 620 Displays + 4 Wellen à ≤160 Pushes/t liegen im Rahmen der
   Credits-/Chrono-Präzedenz, aber das Wellen-Timing (20-t-Fenster) braucht den
   Sichttest; Stellschrauben sind Konstanten in `EchoOverlayBuilder`.
3. **Szenen-Feintuning** — Keyframes sind nach Plan-Koordinaten gesetzt; ob Bank-,
   Stollen- und Laternen-Props exakt unter den Actors liegen, zeigt erst der
   In-Game-Blick (Anpassung = nur JSON bzw. `EchoGroveTerraformer.placeSceneProps`).
4. **Parallel-Welle** — `WoahFeatures`-Anker war zum Schreibzeitpunkt konfliktfrei;
   sollte ein anderer Agent denselben Anker angefasst haben, ist der Merge trivial
   (zwei Zeilen).
