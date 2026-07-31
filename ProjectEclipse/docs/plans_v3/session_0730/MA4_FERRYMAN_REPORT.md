# MA4 — Ferryman-GeckoLib-Konversion (F-098, Welle M-A)

**Team MA4** · Branch `cursor/project-eclipse` · NICHT committet (Integrator committet zentral).
Format nach B2-Muster: verifizierte Grundlagen zuerst, nichts aus dem Gedächtnis.

---

## §1 Verifizierte Grundlagen (alles per rg/Read geprüft, 30.07.)

1. **Ist-Zustand:** `entity/boss/FerrymanEntity` (1570 Z., `extends Monster`, komplett
   server-gescriptete Fight-Loop ohne Vanilla-Goals) + `client/entity/FerrymanModel`
   (370 Z., 24 Cubes, prozedurales `setupAnim` auf Client-Lerp-Hooks) +
   `client/entity/FerrymanRenderer` (MobRenderer + `EmissiveLayer` mit
   skipDraw-Muster). Textur `ferryman.png` 256×256 (128-UV bei 2×), **keine Glowmask**
   (Falle F-7).
2. **Boot-Frage (Auftrag §1):** Das alte Modell enthält **KEIN Boot**. Das „Boot" ist
   das **block-gebaute Geisterschiff** (`limbo/GhostShipBuilder`, 39×9-Block-Rumpf,
   Deck/ Masten/Bänke als `setBlock`-Stempel; der Boss schwebt über dem Deck,
   `deckY`-Hover in `tickMovement`). → Kein Boot-Bone-Set im Geo; der Wellengang
   wandert stattdessen als Molang-Roll (Liste + Konter-Roll) auf `body` in
   `idle_row`/`walk` (siehe §4). Dokumentiert in `docs/uv/ferryman.md`.
3. **Kampf-Cues (rg `CUE_FERRY`):**
   - `CUE_FERRY_KNEEL_CORONA` + `CUE_FERRY_LANTERN_SWARM`: feuern in
     `sendKneelEntranceFx()` — **exakt im selben Server-Tick, in dem
     `setKneeling(true)` synct** (`startCrewPhase`, beide Zweige Schiff+Arena).
     Corona = 100t-Sustain (Re-Fire alle 20t via `tickCrewPhase`, Photon-Dedup),
     Swarm = einmalig 80t aufsteigend (FxCues-Javadoc).
   - `CUE_FERRY_OAR_SWEEP`: feuert in `doSweep()` — Kontakt-Tick, exakt
     **26 Ticks nach Telegraph-Start** (`telegraphTimer = 25` in `tickSweep`,
     Dekrement-Zählung: Set-Tick + 25×`>=0` + 1 Underflow-Tick = 26t). Trägt
     `a = yaw` (Function-Shape-Halbkreis nach vorn).
   - `CUE_FERRY_HARVEST` (A3/B7): feuert in
     `FerrymanSpecialAttacks.startHarvest()` bei Telegraph-Start; Ring kontrahiert
     über `HARVEST_TELEGRAPH_TICKS = 40` (enraged 30), **Pull bei t=40t**, Strike
     bei **t=54t** (`HARVEST_STRIKE_DELAY = 14`). `ferry_harvest_ring` = 44t-One-Shot
     (FxCues-Javadoc). Nur-Lese-Quelle: `ferryman/finale/FerrymanSpecialAttacks.java`.
   - Death: `DEATH_DURATION_TICKS = 100`, Flamme guttert bis
     `DEATH_FLAME_OUT_TICKS = 30` (4t-Sputter via `isLanternFlameLit()`), letzte
     Glocke + `CUE_SIG_CROWN_VERDICT` + Schockwellen-Exhale bei
     `DEATH_BELL_TICK = 80` (`tickDeath`).
4. **FROZEN-Contract:** `EclipseGeoMonster` (zwei Controller `base`+`action`,
   `registerControllers` final), `EclipseGeoAnimations` (`animation.<geoId>.<name>`),
   `EclipseGeoRenderer` (DefaultedEntityGeoModel-Tripel, `withGlowmask()`/
   `withUprightDeath()`), `validate_geo.py`/`paint_lib.py` unangetastet.
5. **G2 (SHARED):** `EclipseEntityRenderers` registriert heute Layer + Renderer für
   den Ferryman — wird NICHT editiert; Lösch-Snippet in §7. Neue Registrierung in
   eigener `@EventBusSubscriber(Dist.CLIENT)`-Klasse mit `isBound()`-Guard und
   **`EventPriority.LOW`**, damit sie deterministisch NACH der Alt-Registrierung
   läuft und die Renderer-Map-Eintragung gewinnt, solange das Snippet noch nicht
   gemergt ist (Muster-Kombination aus `AmbientRenderers` + `DeckhandRenderer.Registration`).
6. **Alt-Klassen-Referenzcheck (rg):** `FerrymanModel`/`FerrymanRenderer`/
   `FERRYMAN_LAYER` werden ausschließlich von `EclipseEntityRenderers` (shared) und
   untereinander referenziert; die Client-Anim-Hooks der Entity (`animAge`,
   `raiseAmount`, `kneelAmount`, `plantAmount`, `sweepSwing`, `swayBoost`,
   `deathProgress`, `tickClientAnim`) nur vom alten `FerrymanModel`. → Alt-Klassen
   `@Deprecated` (löschen erst mit Integrator-Patch §7, sonst Build-Bruch);
   `isLanternFlameLit()` bleibt aktiv (neuer Renderer konsumiert es).
7. **Vorbild komplett gelesen:** `fog_tyrant.geo.json` (25 Bones) +
   `fog_tyrant.animation.json` (Molang-/catmullrom-Idiome) + `FogTyrantEntity`
   (Trigger-Verkabelung, `die()`→`triggerAction(death)`, `tickDeath`-Keyframe-Beats)
   + `FogTyrantRenderer` (EclipseGeoRenderer-Subklasse mit Custom-Layern) +
   `scripts/geckolib_gen/mobs/fog_tyrant.py` (Painter-Idiome).
8. **Canvas:** 128×128 (Boss-Ausnahme wie fog_tyrant/rift_warden — der alte
   Ferryman-Sheet war bereits 128-UV; **Integrator bitte die 128²-Boss-Liste in
   §6.1 des Zensus um `ferryman` ergänzen**). Painter schreibt Albedo+Glowmask in
   einem Lauf auf identischem Canvas (F-7-sicher).

## §2 Neue/geänderte/deprecatete Dateien

| Datei | Status |
|---|---|
| `src/main/resources/assets/eclipse/geo/entity/ferryman.geo.json` | **NEU** — 32 Bones / 30 Cubes (Baum in §3) |
| `src/main/resources/assets/eclipse/animations/entity/ferryman.animation.json` | **NEU** — 8 Anims (§4) |
| `scripts/geckolib_gen/mobs/ferryman.py` | **NEU** — deterministischer Painter (Seed `0x0FE44174`), schreibt `ferryman.png` + `ferryman_glowmask.png` (128²) in einem Lauf; Rerun byte-identisch (verifiziert) |
| `src/main/resources/assets/eclipse/textures/entity/ferryman.png` | **REGENERIERT** (256²→128², jetzt Painter-Besitz; UV-Space war schon 128 — das nie-zeichnende Alt-Modell normalisiert weiter korrekt) |
| `src/main/resources/assets/eclipse/textures/entity/ferryman_glowmask.png` | **NEU** (gleicher Canvas — F-7-sicher) |
| `src/main/java/.../entity/boss/FerrymanEntity.java` | **UMBAU** — `extends EclipseGeoMonster`, `geoId`/`idleAnim`/`handleBaseState`/`registerActionTriggers`, Trigger in `tickSweep`/`startCrewPhase`/`die()`; Alt-Client-Hooks `@Deprecated` |
| `src/main/java/.../client/entity/FerrymanGeoRenderer.java` | **NEU** — EclipseGeoRenderer-Basis: Glowmask + UprightDeath + Translucency, Bone-Visibility (`glow_flame`+`glow_robe` ↔ `isLanternFlameLit`, `glow_gaze` ↔ `isGazing`) |
| `src/main/java/.../client/entity/FerrymanRenderers.java` | **NEU** — eigener Registrar (isBound-Guard, `EventPriority.LOW`) |
| `src/main/java/.../client/entity/FerrymanModel.java` | **@Deprecated** (Löschung via Snippet §7) |
| `src/main/java/.../client/entity/FerrymanRenderer.java` | **@Deprecated** (Löschung via Snippet §7) |
| `docs/uv/ferryman.md` | **NEU GESCHRIEBEN** (GeckoLib-Sheet, Layout + Art-Brief + Glowmask-Inventar) |
| `scripts/skin_gen/ferryman_v2.py` | unangetastet — obsolet mit dem Alt-Modell, Löschung im selben Integrator-Patch (§7) |

(Kein `ferryboss/`-Subpackage wie ursprünglich geplant — die beiden Client-Klassen
liegen flach in `client/entity/` neben dem Deckhand-Präzedenzfall.)

Kein langdrop/sounddrop nötig (keine neuen Lang-Keys/Sound-Events).

## §3 Bone-Baum (32 Bones, 30 Cubes, Canvas 128²)

```
root
└─ body                          (Robe 10×26×8, Saum 14px überm Deck; Wellengang-Molang)
   ├─ hem_front_left/right       (2×6×1 — Saum-Segmente vorn)
   ├─ hem_back_left/right        (2×6×1 — Saum-Segmente hinten)
   ├─ tatter_left → tatter_left_tip     (2-Segment-Kette 2×5×1 + 2×4×1)
   ├─ tatter_right → tatter_right_tip   (2-Segment-Kette)
   ├─ tatter_back → tatter_back_tip     (2-Segment-Kette)
   ├─ glow_robe                  (emissive Runen-Trim, +x-Flanke = Laternenseite)
   ├─ head                       (Schädel 7³; GeckoLib-Head-Tracking, turnsHead=true)
   │  ├─ hood                    (9³, Nordseite transparent — offene Kapuze)
   │  └─ glow_eyes               (Augenschlitz 5×2×1, emissiv)
   ├─ arm_right / arm_left       (3×20×3)
   ├─ chain_1 → chain_2 → chain_3       (Pendel-Kette 1×4×1, link_1..3 Kreuzglieder)
   │  └─ lantern_hook            (LEER — **FX-Locator**, Aufhängepunkt der Laterne)
   │     └─ lantern              (Gehäuse 4×5×4, Fensterausschnitte im Skin)
   │        ├─ glow_flame        (Seelenflamme 2³, emissiv; Renderer blendet beim Death-Gutter aus)
   │        ├─ cap               (Eisenkrone 3×1×3)
   │        └─ glow_gaze         (Runen-Shell, inflate 0.35 — NUR sichtbar während Lantern Gaze)
   └─ oar_grip (LEER — Griffanker)
      └─ oar_shaft               (2×36×2)
         └─ oar_blade            (Blatt 1×7×5 + Spitze 1×2×3 — Peitschen-Lag im Sweep)
```

Ruder-Bone-Kette = `oar_grip → oar_shaft → oar_blade` (Auftrag §1). Laternen-Locator =
`lantern_hook` (leerer Bone am Aufhängepunkt, Kettenende). Render-Reihenfolge:
`glow_flame` VOR `cap`/`glow_gaze` gelistet (Kern innen zuerst, §6.1-Gesetz).

## §4 Anim-Sheet ↔ Kampf-Cue-Timing

Alle Ids `animation.ferryman.<name>`. `base`-Controller (Blend 6t):
kneel-Kette > idle_plant (P3) > walk (eigenes Positions-Delta, Falle F-9 — der Boss
ist ein setDeltaMovement-Drifter) > idle_row. `action`-Controller: oar_sweep,
harvest, death (Trigger-Verkabelung §5).

| Anim | Länge/Loop | Cue-Timing (Server ↔ Keyframes) |
|---|---|---|
| `idle_row` | 8.0s Loop | Rhythmisches Rudern (Molang 90°/s = 4s-Strich ×2) + Wellengang (45°/s-Liste + 90°/s-Konter-Roll); Personality-Beat: Laternen-Blick 5.4–7.4s (Ersatz des alten 27s-„peer") |
| `walk` | 2.0s Loop | Stalk-Drift: 180°/s-Strich, Säume/Tatters ziehen nach achtern, Kette trailt |
| `idle_plant` | 4.0s Loop | P3 „The Toll": Ruder gepflanzt (Gondoliere-Pose, Blatt beißt ins Deck), Kopf jagt, Flamme im Overdrive |
| `kneel` | 1.0s One-Shot (Chain in `kneel_loop`) | Startet im **selben Tick** wie `CUE_FERRY_KNEEL_CORONA`+`CUE_FERRY_LANTERN_SWARM` (`startCrewPhase`); Körper landet bei 0.55s (11t) — der 80t-Swarm steigt von der gesetzten Silhouette, die Corona (100t) blüht um den Landepunkt |
| `kneel_loop` | 4.0s Loop | Schwerer Atem, Kette lotrecht-still, Flamme niedrig |
| `oar_sweep` | 2.2s One-Shot | Trigger bei Telegraph-Start (`tickSweep`); Windup 0–1.1s, Quiver 1.1–1.3s, **STRIKE exakt bei 1.30s = 26t = Server-`doSweep()` + `CUE_FERRY_OAR_SWEEP` + Schaden**; Recovery bis 2.2s; Blade-Lag 1.25→1.6s |
| `harvest` | 2.7s One-Shot | Auf `ferry_harvest_ring`-Kontraktion: Einzug/Sog 0–2.0s (=40t-Telegraph, Säume/Tatters saugen sich nach innen, Laterne hochgehievt), **YANK bei 2.0s = 40t = Server-Pull**, Crouch-Hold, **Release-Flare bei 2.7s = 54t = AoE-Strike**. Enraged (30t-Telegraph): Pull kommt 10t früher als der Anim-Yank — bewusst hingenommen, Feindaten liegen bei B7 (§7-Snippet nötig, s.u.) |
| `death` | 5.0s hold_on_last_frame | = `DEATH_DURATION_TICKS` 100t; 0–0.4s Final-Blow-Stagger, 0.5s Ruder-Plant, 0.5–1.5s Flammen-Gutter (= `DEATH_FLAME_OUT_TICKS` 30t, Renderer sputtert `glow_flame` im 4t-Takt), 1.5–4.0s Falten zur Laterne (Kette stillt sich lotrecht), **4.0s = 80t = `DEATH_BELL_TICK`: letzter Toll-Shudder** (Crown-Verdict-Koda + Schockwelle), 4.0–5.0s Settle in den Halte-Frame |

## §5 Java-Verkabelung (Datei-Besitz MA4)

- `FerrymanEntity extends EclipseGeoMonster`: `geoId() = "ferryman"`,
  `idleAnim() → idle_row`, `handleBaseState` mit Prio kneel_loop > walk (eigenes
  Positions-Delta `xOld/zOld`, Falle F-9 — der Boss ist ein setDeltaMovement-Drifter,
  DriftLantern-Muster) > idle_plant > idle_row; bei `deathTime > 0` **STOP** (das
  gehaltene death-Sheet besitzt jeden Bone). `registerActionTriggers` = super(death,
  hold) + `kneel` (once) + `oar_sweep` (once) + `harvest` (once, Trigger liegt bei B7 —
  §7.2). `baseTransitionTicks() = 6`.
- `tickSweep()`: `triggerAction(ANIM_OAR_SWEEP)` im Telegraph-Set-Tick.
- `startCrewPhase()`: `triggerAction(ANIM_KNEEL)` im `setKneeling(true)`-Tick (beide
  Zweige Schiff+Arena laufen durch dieselbe Methode) — gleicher Tick wie
  `CUE_FERRY_KNEEL_CORONA`/`_LANTERN_SWARM` aus `sendKneelEntranceFx()`.
- `die()`: `triggerAction(EclipseGeoAnimations.ANIM_DEATH)` im Tableau-Block. Der alte
  W4-Death-Slow-Mo-Client-Clock lebt nur noch im deprecateten Legacy-Hook-Block
  (Tyrant-Präzedenz EVAL-V6-MOB D2: Slow-Mo frisst das Keyframe-Sheet; das 100t-Sheet
  ist auf 1× authored). Der 40t-Soft-Drift-Shake aus `die()` bleibt.
- **Anim-Naht-Regel** (Polish-Runde): der `action`-Controller hat 0t-Transition — alle
  One-Shot-Randkeys sitzen deshalb exakt auf der Basis-Pose (`oar_grip` Start-/End-Keys
  auf z=+8, die Ruder-Trage-Basis von idle_row/walk; Arm-Keys auf den Loop-Basiswerten).
- `FerrymanGeoRenderer`: `super(context, "ferryman", true)` + `withGlowmask()` +
  `withUprightDeath()` + `withTranslucency()` (die `glow_gaze`-Shell ist mit
  Alpha 96 gemalt — Cutout würde sie deckend zeigen); `preRender` toggelt
  `glow_flame`+`glow_robe` (`isLanternFlameLit()`, 4t-Gutter-Sputter; der Robe-Schein
  stirbt mit seiner Lichtquelle) und `glow_gaze` (`isGazing()`) via
  `GeoBone.setHidden` (Deckhand-Muster). `shadowRadius = 0.9F` (Alt-Renderer-Wert).
- `FerrymanRenderers`: eigener Registrar, `isBound()`-Guard (via
  `DeferredHolder`-instanceof — `EclipseEntities.FERRYMAN` ist als `Supplier` typisiert),
  `@SubscribeEvent(priority = EventPriority.LOW)` → gewinnt deterministisch gegen die
  Alt-Registrierung in `EclipseEntityRenderers`, bis Snippet §7 gemergt ist.

## §6 Validierung (durchgeführt 31.07.)

1. **validate_geo** (geo + anim im selben Aufruf, Bone-Cross-Check aktiv):
   ```
   === GEO  .../ferryman.geo.json
       identifier geometry.ferryman  canvas 128x128  32 bones  30 cubes
     -> PASS (0 error(s), 0 warning(s))
   === ANIM .../ferryman.animation.json
       idle_row 8.0s loop · walk 2.0s loop · idle_plant 4.0s loop · kneel 1.0s ·
       kneel_loop 4.0s loop · oar_sweep 2.2s · harvest 2.7s · death 5.0s hold
     -> PASS (0 error(s), 0 warning(s))
   validate_geo: 2/2 file(s) passed — all good
   ```
2. **Painter**: `python3 scripts/geckolib_gen/mobs/ferryman.py` → 3585 Albedo-px,
   310 Glowmask-px auf 128²; **zweiter Lauf byte-identisch** (git-Status unverändert),
   kein „no material"-Cube.
3. **`./gradlew compileJava`**: EXIT 0. Verbleibende Warnungen sind ausschließlich die
   beabsichtigten Deprecation-Notes der Alt-Klassen (plain `@Deprecated`, kein
   `forRemoval` — hält das Shared-Build-Log leise, weil Nutzung deprecateter API in
   `EclipseEntityRenderers` sonst als removal-Warnung feuern würde, die MA4 dort nicht
   unterdrücken darf).

## §7 Patch-Snippets an den Integrator (G2/G4 — NICHT von MA4 anzuwenden)

### 7.1 `EclipseEntityRenderers.java` (SHARED) — Alt-Registrierung entfernen

```diff
     public static final ModelLayerLocation HERALD_LAYER = layer("herald");
-    public static final ModelLayerLocation FERRYMAN_LAYER = layer("ferryman");
@@ onRegisterLayerDefinitions
         event.registerLayerDefinition(HERALD_LAYER, HeraldModel::createBodyLayer);
-        event.registerLayerDefinition(FERRYMAN_LAYER, FerrymanModel::createBodyLayer);
@@ onRegisterRenderers
         event.registerEntityRenderer(EclipseEntities.HERALD.get(), HeraldRenderer::new);
-        event.registerEntityRenderer(EclipseEntities.FERRYMAN.get(), FerrymanRenderer::new);
+        // Ferryman: GeckoLib renderer self-registers in client.entity.FerrymanRenderers (MA4).
```

Im selben Patch löschen: `client/entity/FerrymanModel.java`,
`client/entity/FerrymanRenderer.java`, `scripts/skin_gen/ferryman_v2.py`, sowie den
`@Deprecated`-Client-Hook-Block in `FerrymanEntity` (Abschnitt
`// --- legacy client animation hooks (MA4: superseded by the GeckoLib sheet) ---`:
Felder `animAge*`/`raiseLerp*`/`kneelLerp*`/`plantLerp*`/`swingTicks`/`wasTelegraphing`/
`swayBoost*`/`animSpeed` + `SWEEP_SWING_TICKS`, Methoden `tickClientAnim`/`animAge`/
`raiseAmount`/`kneelAmount`/`plantAmount`/`sweepSwing`/`swayBoost`/`deathProgress` und
den `tickClientAnim()`-Aufruf in `tick()`; `isLanternFlameLit()` BLEIBT — der neue
Renderer konsumiert es). Danach darf in `FerrymanRenderers` die
`EventPriority.LOW`-Annotation auf Default zurück (harmlos, kann auch bleiben).

### 7.2 `FerrymanSpecialAttacks.java` (B7/MA5-Besitz) — Harvest-Anim-Trigger

Eine Zeile in `startHarvest(ServerLevel level)`, direkt nach `this.timer = ...`:

```java
this.boss.triggerAction(FerrymanEntity.ANIM_HARVEST); // MA4: Seelenernte-Körperanim (54t, Yank@40t/Strike@54t)
```

Der Triggerable ist bereits registriert (`registerActionTriggers`) — ohne die Zeile
spielt die Seelenernte wie bisher nur FX ohne Körper-Anim (Status quo, kein Bruch).
Optional (B7-Judgement): in `startWave()` KEIN Trigger — die Welle liest über die
Yaw-Lock-Stance + Crest-FX; ein zweiter Ruder-Schlag würde mit dem Basis-Sweep-Read
kollidieren.

## §8 Koordinations-Snippet an A4/A3 (FX — Bone-/Locator-Namen + Timings)

| Anker | Bone/Locator | Welt-Offset (Bind-Pose, Blocks über Füßen) | Nutzung |
|---|---|---|---|
| Laternen-Aufhängung | `lantern_hook` (leerer Bone, Kettenende) | ~1.63 üF, +0.41 links (+x), +0.09 achtern | `ferry_lantern_swarm`-Aufstiegs-Anker (heute Welt-Anker `kneelAnchor()`; Bone-Anchor jetzt möglich). Im Kneel sinkt er ~0.69 Blocks mit (body −11px). |
| Laternen-Gehäuse | `lantern` / `glow_flame` | 1.31–1.63 üF | Gaze-Mark-Paarung: `glow_gaze`-Shell wird sichtbar solange `isGazing()` — Photon-Puls kann darauf synchen |
| Ruderblatt | `oar_blade` (Kette `oar_grip→oar_shaft→oar_blade`) | Blatt 0.75–1.31 üF, 0.28–0.59 vor dem Körper (−z) | `ferry_oar_tear`-Arc: Kontakt-Beat = Trigger+26t; Blatt-Tiefpunkt der Whip bei Trigger+27..29t |
| Robe-Säume | `hem_*` (4), `tatter_{left,right,back}` + `_tip` | Saum 0.88 üF | `ferry_harvest_ring`-Kontraktion: Säume saugen 0..40t nach innen, Release-Flare bei 54t |
| Kneel-Beats | — | — | Kneel-Down landet Trigger+11t (Corona blüht 20t — Körper sitzt vorher); Death-Toll-Shudder exakt bei deathTime 80t (Crown-Verdict-Fenster) |

## §9 Test-Rezept

(Statisch validiert — §6; In-Game-Läufe sind Integrator-/QA-Schritt.)

1. `./gradlew build`, `runServer` (RCON): `python3 tools/rcon/rcon.py "dev start_ferryman"`
   (ganzer Arc, 15s-Dev-Cut; Kommando verifiziert in `devtools/dev/DevFerrymanCommands`)
   bzw. direkt `"eclipse boss ferryman summon"` in Limbo.
2. Phasen erzwingen: `"eclipse boss ferryman phase 2"` (Kneel-One-Shot + kneel_loop +
   Corona-Sync), `"... phase 3"` (idle_plant/Gaze-Shell/Harvest-Rotation — Harvest-Anim
   erst nach §7.2-Snippet), `"kill @e[type=eclipse:ferryman]"` (100t-Death, Flamme
   guttert 30t, Toll-Shudder bei 80t).
3. Optik NUR im `runClient` (llvmpipe, 20–40s-Waits): `/summon eclipse:ferryman ~2 ~ ~`
   in Limbo, Screenshots front/side/¾ + je Anim; Checkpunkte: offene Kapuze (Nordface
   transparent, Schädel + Slit sichtbar), Glowmask bei Nacht (Augen/Flamme/Robe-Schein),
   Gaze-Shell nur während Mark, Sweep-Whip auf dem Kontakt-Tick.
