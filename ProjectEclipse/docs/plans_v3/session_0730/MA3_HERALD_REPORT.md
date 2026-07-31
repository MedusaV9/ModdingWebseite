# MA3 — Herald-GeckoLib-Konversion (Flaggschiff-Paket, F-098 Welle M-A)

**Status:** FERTIG — validate_geo 2/2 PASS (0 Errors/0 Warnings), `./gradlew compileJava`
UND `./gradlew build` grün, Painter deterministisch (Rerun byte-identisch, md5-geprüft).
Ergebnisse §6, Integrator-Snippets §7, A4-Koordination §8, Test-Rezept §9.
**Datei-Besitz (Zensus §5, Zeile MA3):** `entity/boss/HeraldEntity`,
`client/entity/Herald{Model,Renderer}` (Löschung via Snippet), NEU:
`geo/animations/textures herald*`, `scripts/geckolib_gen/mobs/herald.py`, eigene
Renderer-Registrar-Klasse, `docs/uv/herald.md`.

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

- **Ist-Zustand:** `HeraldEntity` (Monster, scripted fight, KEINE goals), `HeraldModel`
  (324 Z. Code-Modell: Core 12³ @ y40, inneres Auge 6³, 4 Kronen-Spikes 1×5×1, Korona-Ring
  r=14px mit 8 Shards 2×6×2, Halo r=9px mit 3 Shards 1×3×1, 4 Tentakel-Ketten × 4 Segmente
  2×6×2 ab y34 abwärts), `HeraldRenderer` (MobRenderer + `RenderType.eyes`-EmissiveLayer).
  Kein Glowmask, kein Keyframe-Sheet. Textur `herald.png` war 256² (2×-Paint auf 128-UV).
- **Hitbox:** `EclipseEntities.HERALD` = 2.2×3.2, eyeHeight 2.5 (Core-Zentrum = 40px) —
  bleibt unverändert, das neue Geo ist darauf gebaut.
- **Vorbild komplett gelesen:** Rift Warden (Geo 21/21, Anim-Sheet 9, `mobs/rift_warden.py`,
  `RiftWardenEntity` als `EclipseGeoMonster`-Nutzer, `RiftWardenRenderer` +
  `RiftRenderers`-Registrar mit `isBound()`-Guard) + `AmbientRenderers`-Muster +
  `DriftLanternEntity.handleBaseState` (Falle F-9: Positions-Delta statt `isMoving()`).
- **Summon-Sequenz (`sequence/HeraldSummonSequence`, 9.5 s = 190t):** t=0 Announcement
  (Veil+Horn), t=15 `CUE_HERALD_SUMMON_PILLAR`+`CUE_HERALD_GLYPH_SWIRL`, t=30 Ground-Break
  + Kamera-Pull, t=55–130 Partikel-Silhouette, t=130 Materialize (2. Glyph-Swirl+Tint),
  **t=150 Spawn** (`HeraldEntity.summon` → Blitz/Schockwelle/`CUE_BOSS_ROAR`), t=190 Ende.
  → `summon_rise` = **2.0 s** und deckt exakt t=150→190 ab.
- **FROZEN:** `EclipseGeoMob/Monster/Animations/Renderer`, `validate_geo.py`, `paint_lib.py`;
  Controller-Contract `base`+`action` final; `EclipseEntityRenderers.java` SHARED (G2).

## 1. Bone-Hierarchie (Ziel ~24 → geworden 31; Begründung unten)

```
root
└─ body (0,40,0)                       Hover-Chassis; summon_rise/death fahren hierüber
   ├─ head (0,40,0)                    Core 12³ + Brauen-Sims + 2 hintere Kronen-Spikes (Cubes);
   │  │                                heißt exakt `head` → GeckoLib-Head-Tracking (turnsHead=true)
   │  ├─ glow_eye (0,40,-4)            Auge 6³, Frontfläche 1px proud — Glowmask auto (glow_-Präfix)
   │  ├─ glow_veins (0,40,0)           3 transparente Aden-Platten (N-Platte 10×10×1 proud 0.75 +
   │  │                                2 Seiten-Säulen 1×10×1) — NUR die Vein-Pixel sind opak+emissiv
   │  ├─ horn_left (-4,45,-3)          Horn 2 Cubes (Basis 2×6×2 + Spitze 1×5×1, Lean via Cube-Rotation)
   │  └─ horn_right (4,45,-3)
   ├─ shield_left (-11,40,0)           Schulter-Schild: Platte 2×10×7 + Grat-Finne 1×7×3 (schwebend)
   ├─ shield_right (11,40,0)
   ├─ ring (0,40,0)                    Korona-Träger (kein Cube; Molang-Spin)
   │  └─ shard1..shard8                r=14px, alle 45°, Bone-yRot=-Winkel (lokales zRot = radialer
   │                                   Tilt-out — 8 EIGENE Bones, weil der Renderer sie pro synced
   │                                   `getShardsLeft()` einzeln versteckt: P3-Detach + Death-Ablösung)
   ├─ halo (0,40,0)                    3 Ammo-Shards 1×3×1 als CUBES auf EINEM Bone; das Volley-
   │                                   Gathering läuft über halo-x/z-SCALE (zieht radial rein)
   ├─ glyph_ring (0,40,0)              FX-Träger (kein Cube; eigener, ruhiger Molang-Spin)
   │  ├─ glyph_orbit_1 (10,42,0)       ┐ A4-FX-Anker (Locator, keine Cubes),
   │  ├─ glyph_orbit_2 (-5,40,8.66)    │ 120°-versetzt, r=10px, leicht höhen-gestaffelt
   │  └─ glyph_orbit_3 (-5,38,-8.66)   ┘
   ├─ tentacle_fl_1 → tentacle_fl_2    4 Ketten × 2 Segmente (2×10×2 + 1×9×1, kelp-ragged Saum)
   ├─ tentacle_fr_1 → tentacle_fr_2    an den Core-Unterkanten (±3.5, 34, ±3.5)
   ├─ tentacle_bl_1 → tentacle_bl_2
   └─ tentacle_br_1 → tentacle_br_2
```

**31 Bones / 35 Cubes** (Tyrant-Parität 25/35). Über den ~24-Richtwert hinaus gehen genau:
(a) die 8 Einzel-Shard-Bones — erzwungen durch den Erhalt der P3-Detach-Mechanik
(Renderer-`setHidden` pro Bone, synced `DATA_SHARDS_LEFT`), (b) `glyph_ring` + 3 Locators
(cube-los, reine FX-Anker für A4). Silhouette = altes Modell (Proportionen aus den
Cube-Definitionen übernommen), verfeinert um Hörner statt 4 gleicher Spikes,
Schulter-Schilde und Glow-Adern.

**Basis-Rotationen:** Nur die Shard-Bones tragen Base-Rotation (yRot=-Winkel, nötig für
radiales Tilt-out); alle Anim-Keys auf Shards wiederholen den y-Basiswert
(Haus-Konvention, vgl. `rift_warden` horn/pauldron). Hörner/Schilde/Kronen tragen ihre
Ruhe-Neigung in CUBE-Rotationen → deren Anim-Keys bleiben saubere Null-basierte Deltas.

## 2. Animation-Sheet (`animation.herald.*`, format 1.8.0)

| Anim | Länge | Loop | Inhalt / Timing-Anker |
|---|---|---|---|
| idle | 4.0 s | true | Molang: body-Schwebe-Sinus, head-Atmungs-Scale, ring +90°/s (=360°/Loop, nahtlos), halo −180°/s, glyph_ring +90°/s, 8 Shard-Bobs 45°-phasenversetzt, Tentakel-Peitschen-Lag, Schild-Hover, Vein-Puls-Scale |
| walk | 3.0 s | true | Drift-Gleiten: body-Vorlage 6°, Tentakel trailen nach hinten, ring +120°/s, halo −240°/s, Schilde schwingen zurück |
| attack | 0.8 s | false | Gaze-Peitsche: head-Snap nach vorn/unten, Vein-Flare, Tentakel-Schnapp, Recoil (catmullrom) — Trigger im Gaze-FIRE-Moment |
| shard_volley | 1.5 s | false | 0→1.0 s Gathering (halo-Scale 0.55 rein, Shards −10° einwärts, ring-Spin-Up, Tentakel-Klaue), **1.0 s = Release-Beat** (Server-Telegraph Basis 20t), 1.0→1.2 Snap (+160° ring, Shards +18° raus, Recoil), →1.5 Settle. Trigger bei Telegraph-START |
| roar | 1.4 s | false | Auf `CUE_BOSS_ROAR`/`roar_shockwave`: 0→0.35 Rear-up (altes Envelope: scharfe Attack im ersten Viertel), Hörner/Schilde/Tentakel-Splay, 0.35→1.4 eased Release. Trigger: Phasen-Break AUFwärts + Stalker-Summon |
| summon_rise | 2.0 s | false | **Auf die 9.5s-Sequenz getimt:** Boss spawnt bei Sequenz-t=150; Anim deckt t=150→190. 0 s: Spindel-Pose (body-Scale [0.45,1.55,0.45] = die Partikel-Spindel der Sequenz, ring/halo/Schilde eingefaltet, Shards flach an den Ring gelegt, Tentakel eingerollt) → 1.2 s Entfaltung (catmullrom, ring 540°-Spin-up) → 1.6 Overshoot → 2.0 Ruhe. Trigger 3t nach Spawn (Tracking-Sicherheit) |
| death | 3.5 s | hold_on_last_frame | = `DEATH_DURATION_TICKS` 70t. Gestaffelt: Tentakel sterben Kette für Kette (0.3/0.6/0.9/1.2), Schilde reißen ab (1.0–2.0), Hörner knicken (1.4/1.7), Halo stürzt, Ring sackt unter den Core + Shards kippen aus, Core sinkt in 3 Lurches + keelt vor; Server-`shatter()` bei t=69 (3.45 s) trifft den letzten Frame |

Anim-Ids: `animation.herald.<name>` (`geoId()` = `"herald"`). Mindest-Set idle/walk/attack/
Special/death erfüllt; Molang-Sinus für Atmung/Schweben, catmullrom für Organik (§6.1).

## 3. Textur-Konzept (128², Albedo + ERSTMALS Glowmask)

Canvas **128×128** — Boss-Linie-Präzedenz (`fog_tyrant`/`rift_warden` 128², Zensus §6.1);
formell eine neue 128er-Ausnahme → **Integrator-Flag** in §7 dieses Reports. Beide PNGs
aus EINEM deterministischen Lauf (`mobs/herald.py`, Seed fixiert), `AutoGlowingTexture`
verlangt identische Canvases.

- **Palette (aus dem alten Art-Brief `docs/uv/herald.md` übernommen):** Schwarzviolett-Glas
  `#181224` facettiert, Gold-Riss-Adern `#E8A83A`→`#FFD86A`, Auge `#FFD86A` + Void-Pupille
  `#100A18`, Korona `#C88AFF`, Halo hot-lavender, Tentakel `#241C36` mit Gelenk-Banding,
  Hörner Obsidian mit Gold-Spitze, Schilde dunkles Glas mit Gold-Grat.
- **Glowmask (NEU — der Herald hatte keinen):** `glow_eye` + `glow_veins` auto (Präfix);
  dazu Custom-Glow-Painter (Warden-Muster, same-salt-Zwilling Albedo↔Mask): Gold-Fissuren
  auf dem Core (head), Shard-SPITZEN (obere Reihen, gedimmt ~α180 — der Telegraph-Puls im
  Renderer moduliert den Layer), Halo voll, Horn-Spitzen, Schild-Grat.
- **Adern:** `glow_veins`-Platten sind fast vollständig transparent (Material gibt `None`);
  nur die wandernden Vein-Pfade sind opak + emissiv → schwebende Gold-Adern 0.75px proud
  über dem Glas (Cutout-Renderpfad, kein `withTranslucency()` nötig).

## 4. Java-Umbau

- **`HeraldEntity extends EclipseGeoMonster`** (statt Monster): `geoId()="herald"`,
  `registerActionTriggers` = super(death-hold) + attack/roar/shard_volley/summon_rise —
  `registerControllers` bleibt final in der frozen Basis (genau `base`+`action`, F-3).
  `handleBaseState`-Override mit eigenem xOld/zOld-Positions-Delta (Drift-Lantern-Muster,
  F-9 — der Herald bewegt sich per `setDeltaMovement`-Skript).
  Trigger-Verdrahtung: Telegraph-Start→`shard_volley`, Gaze-Fire→`attack`,
  Phasen-Break-aufwärts + Stalker-Summon→`roar`, `summon()`→`summon_rise` (3t verzögert),
  `die()`→`death`. Der alte ~110-Zeilen-Client-Anim-Clock-Block (animAge/telegraphLerp/
  volleyKick/ringSpinExtra/roarTicks/deathProgress) entfällt ersatzlos.
- **Neuer Renderer** `client/entity/herald/HeraldGeoRenderer` auf `EclipseGeoRenderer`-Basis:
  turnsHead=true, `withUprightDeath()`, Shadow 1.1; `preRender` versteckt `shard1..8` nach
  `getShardsLeft()` (P3-Detach + Death-Ablösung); `TelegraphGlowLayer` (AutoGlowingGeoLayer-
  Sub nach `RiftWardenRenderer.StaggerGlowLayer`-Muster) pulst die Glowmask während
  `isTelegraphing()` (reducedFx → statisch).
- **Registrar** `client/entity/herald/HeraldRenderers`: `@EventBusSubscriber(Dist.CLIENT)`
  + `isBound()`-Guard (AmbientRenderers-Muster; `EclipseEntities.HERALD` ist als plain
  `Supplier` typisiert → `instanceof DeferredHolder`-Cast). Die ALTE Zeile in
  `EclipseEntityRenderers` wird NICHT angefasst → Lösch-Snippet §7 (Integrator). Bis dahin
  doppelt registriert — DETERMINISTISCH aufgelöst via
  `@SubscribeEvent(priority = EventPriority.LOWEST)`: `registerEntityRenderer` ist
  last-write-wins, LOWEST feuert nach der Default-Priority der Shared-Klasse, der
  Geo-Renderer gewinnt also immer (nach dem Löschen redundant, aber harmlos).
- **Alte Klassen:** `rg` bestätigt — `HeraldModel`/`HeraldRenderer` werden NUR von
  `EclipseEntityRenderers` referenziert (shared, G2) → **nicht löschbar ohne die Shared-
  Datei**. Beide `@Deprecated` + von den entfernten Entity-Hooks entkoppelt (kompilieren
  standalone weiter); Löschung zusammen mit dem Snippet in §7.

## 5. Validierung

1. `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` nach JEDER Änderung (0 Errors).
2. `python3 scripts/geckolib_gen/mobs/herald.py` + Eyeball beider PNGs (Nearest-Upscale).
3. `./gradlew compileJava`.
4. Client-Sichtprüfung ist auf dieser VM llvmpipe-langsam — Test-Rezept in §9.

## 6. Ergebnisse

### 6.1 Dateien

**NEU:**

| Datei | Inhalt |
|---|---|
| `src/main/resources/assets/eclipse/geo/entity/herald.geo.json` | 31 Bones / 35 Cubes, `texture 128×128`, Hierarchie exakt wie §1 |
| `src/main/resources/assets/eclipse/animations/entity/herald.animation.json` | 7 Anims (§2), Molang-Sinus + catmullrom, null-basierte Deltas |
| `src/main/resources/assets/eclipse/textures/entity/herald_glowmask.png` | ERSTER Herald-Glowmask, 128², 574 Mask-Pixel |
| `scripts/geckolib_gen/mobs/herald.py` | deterministischer Painter (Seed `0x0E8A83A5`), Albedo+Glowmask in EINEM Lauf |
| `src/main/java/.../client/entity/herald/HeraldGeoRenderer.java` | `EclipseGeoRenderer`-Sub: turnsHead, UprightDeath, Shard-Hide, `TelegraphGlowLayer` (Telegraph-Puls + Death-Gutter-out; reducedFx-ruhig) |
| `src/main/java/.../client/entity/herald/HeraldRenderers.java` | Registrar, `EventPriority.LOWEST` + `isBound()`-Guard |

**GEÄNDERT:**

| Datei | Änderung |
|---|---|
| `src/main/java/.../entity/boss/HeraldEntity.java` | `extends EclipseGeoMonster`; `geoId()`; 4 Action-Trigger registriert; Trigger-Verdrahtung (Telegraph→`shard_volley`, Gaze-Fire→`attack`, Phasen-Break-aufwärts+Stalker-Summon→`roar`, `summon()`→`summon_rise` 3t-verzögert, `die()`→`death`); `handleBaseState` Positions-Delta + P3-forced-walk; ~110 Zeilen Client-Anim-Clock (animAge/shardTilt/telegraphLerp/volleyKick/ringSpinExtra/roarTicks/deathProgress) ersatzlos raus. Fight-Logik/NBT/Bossbar UNBERÜHRT |
| `src/main/resources/assets/eclipse/textures/entity/herald.png` | war 256² (2×-Paint fürs Vanilla-Modell) → jetzt 128²-GeckoLib-Sheet, 2887 Albedo-Pixel |
| `src/main/java/.../client/entity/HeraldModel.java` | `@Deprecated`; `setupAnim` auf entkoppelten Fallback-Idle reduziert (kompiliert ohne die entfernten Entity-Hooks); `createBodyLayer`/`renderEmissive` unverändert (Shared-Referenz) |
| `src/main/java/.../client/entity/HeraldRenderer.java` | `@Deprecated`; Roar-Hook-Aufruf entfernt |
| `docs/uv/herald.md` | komplett neu auf das 31-Bone-Geo (Warden-Muster) |

**GELÖSCHT:**

- `scripts/skin_gen/herald_v2.py` — der alte 256²-Painter; ein Rerun hätte das neue
  128²-Canvas überschrieben und `AutoGlowingTexture` (Canvas-Mismatch zur Glowmask) hart
  gefailt. Nur von Doku referenziert (rg-geprüft: `docs/uv/herald.md` — neu geschrieben —
  und der historische Plan `MOB-BOSS1.md`).
- `HeraldModel`/`HeraldRenderer` NICHT gelöscht (rg: von der SHARED
  `EclipseEntityRenderers` referenziert, G2) → `@Deprecated`; Löschung gehört dem
  Integrator zusammen mit dem §7-Snippet.

### 6.2 Zahlen + Validierungs-Status

- **31 Bones / 35 Cubes** (validate_geo-Baum identisch §1); Hitbox 2.2×3.2 unverändert.
- **Anims:** idle 4.0s loop · walk 3.0s loop · attack 0.8s · shard_volley 1.5s ·
  roar 1.4s · summon_rise 2.0s · death 3.5s hold_on_last_frame (=70t Kollaps).
- `validate_geo.py herald.geo.json herald.animation.json` → **2/2 PASS, 0 Errors,
  0 Warnings** (Bone-Crosscheck aktiv).
- `./gradlew compileJava` → **grün**; `./gradlew build` (strict, §8-Checkliste) → **grün**.
  (Deprecation-Note kommt planmäßig von den absichtlich `@Deprecated` Herald-Altklassen.)
- Painter-Rerun **byte-identisch** (md5 8c1a7aea… / 1cac065b…).
- **Loop-/Handback-Hygiene:** alle Molang-Perioden ganzzahlig pro Loop-Länge
  (idle ×90°/s über 4s = 360°, walk ×120°/s über 3s); alle One-Shot-Spins enden auf
  symmetrie-unsichtbaren Winkeln (ring 360≡0 bzw. 540≡45°-Vielfaches bei 8-fach-Ring,
  halo −360/−480≡120°-Vielfaches bei 3-fach-Ring) → kein Snap beim action→base-Handback.
- **Polish-Iteration:** (1) Seiten-Vein-Säulen von ~65 % Deckung auf gestrichelte
  2-Texel-Runs (~48 %) — vorher massiver Goldklotz, der das Auge überstrahlt hätte;
  (2) Tentakel-Gelenk-Banding (jede 4. Reihe heller violett) — die Ketten lasen sich
  sonst als schwarzer Schmier; (3) Anim-Review wie oben (Perioden/Handback/Timing).

## 7. Patch-Snippets für den Integrator (SHARED `EclipseEntityRenderers.java`, G2)

**Löschen (drei Zeilen), im SELBEN Commit `HeraldModel.java` + `HeraldRenderer.java`
entfernen** (Zeile 1 ist die letzte Referenz auf `HeraldModel`; `HeraldRenderer`
referenziert seinerseits `HERALD_LAYER` — einzeln gelöscht bricht der Build):

```java
// client/entity/EclipseEntityRenderers.java — Zeile 27:
    public static final ModelLayerLocation HERALD_LAYER = layer("herald");
// … onRegisterLayerDefinitions, Zeile 45:
        event.registerLayerDefinition(HERALD_LAYER, HeraldModel::createBodyLayer);
// … onRegisterRenderers, Zeile 56:
        event.registerEntityRenderer(EclipseEntities.HERALD.get(), HeraldRenderer::new);
```

Bis dahin ist NICHTS kaputt: `HeraldRenderers` registriert mit `EventPriority.LOWEST`
nach der Shared-Klasse (last-write-wins) — der Geo-Renderer gewinnt deterministisch,
die alte Layer-Definition wird nur ungenutzt gebacken.

**Canvas-Flag:** `herald` = 128×128 (Boss-Linie wie `fog_tyrant`/`rift_warden`) — bitte
in der §6.1-Ausnahmenliste des Zensus nachtragen.

**Lang/Sounds:** KEINE neuen Keys (Entity-Name + alle `BOSS_HERALD_*`-Sounds existieren);
kein langdrop nötig.

## 8. Koordinations-Snippet für A4 (FX — `fx/boss/herald_*`, HeraldFerrymanFxRows)

```
ENTITY   eclipse:herald — GeckoLib geo "herald", Bone-Frame = Entity-Yaw (body),
         head folgt Head-Tracking. Core-Zentrum/Auge: eyePos() = +2.5 über Fuß.

FX-ANKER (cube-lose Locator-Bones, für BoneFrame-Anbindung):
  glyph_orbit_1  pivot ( 10, 42, 0)      ┐  r=10px um den Core, 120°-versetzt,
  glyph_orbit_2  pivot (-5, 40, 8.66)    │  höhen-gestaffelt 42/40/38; Parent glyph_ring
  glyph_orbit_3  pivot (-5, 38,-8.66)    ┘  spinnt idle +90°/s, walk +120°/s (Molang)
  Idle-Bob der Locators: ±1.5px, 120°-phasenversetzt.

WEITERE BONES (falls FX andocken will):
  head (Core+Krone), glow_eye (Auge, protrudiert vorn), ring→shard1..8 (Korona r=14px;
  Renderer versteckt Bones nach synced ShardsLeft!), halo (Ammo-Ring), shield_left/right,
  tentacle_{fl,fr,bl,br}_{1,2}.

SUMMON_RISE-TIMING (HeraldSummonSequence, 190t gesamt):
  t=150  Server spawnt den Boss (Blitz/Schockwelle/CUE_BOSS_ROAR wie gehabt)
  t=150–153  Boss steht 3t in Ruhe-Pose (GeckoLib-Trigger erreicht nur TRACKENDE
             Clients → 3t-Delay). BITTE: Pillar/Materialize-FX bis ~t=155 deckend
             halten, dann ist der Frame unsichtbar.
  t=153  Anim-Start: Spindel-Pose (body-Scale [0.45,1.55,0.45], alles eingefaltet)
         = die Silhouette IM Summon-Pillar (FX-Zensus §5 Reveal jetzt möglich)
  t=177  (~1.2s) Entfaltungs-Peak: ring 540°-Spin, Schilde/Hörner/Tentakel offen
  t=193  Anim-Ende (Settle-Tail ragt 3t über das Sequenz-Ende t=190 — unkritisch)

ROAR: Anim 1.4s; Trigger bei Phasen-Break AUFwärts (P1→P2, P2→P3; dort feuern
  CUE_BOSS_ROAR + Shake bereits) und beim Stalker-Summon. Rear-up-Peak bei 0.35s.
VOLLEY: shard_volley 1.5s ab Telegraph-START (Basis-Telegraph 20t → Release-Beat
  1.0s = Schuss-Moment; skaliert der Telegraph auf 12t, bleibt die Geste ehrlich).
GLOW: Glowmask pulst während isTelegraphing() (~3.5Hz, reducedFx statisch 0.75)
  und blendet über die 70t-Death-Collapse auf Glut (0.1) ab.
```

## 9. Test-Rezept (Client, llvmpipe: 20–40s Wartezeit einplanen)

```
./gradlew build            # strict, vor jedem Client-Start (AGENTS.md)
./gradlew runClient        # oder Server + RCON (AGENTS.md §RCON)

# 1) Arrival-Cutscene inkl. summon_rise + Silhouetten-Fenster (kanonischer Pfad):
/eclipse boss herald summon          # bzw. Herald's Lure nach Dusk am Altar deponieren
#    → 9.5s-Sequenz; ab t=153 Spindel→Entfaltung IM Pillar beobachten

# 2) Basis-Loops: idle (P3-los schwebend kaum Drift), walk (P1-Orbit) — spawnen via
/summon eclipse:herald               # Acceptance-Pfad, Arena pinnt sich selbst
#    → Ring/Halo/Glyph-Spin, Tentakel-Lag, Schild-Hover, Vein/Auge-Glow (Nacht!)

# 3) shard_volley + Telegraph-Puls: warten (~3s P1-Kadenz) — Mask-Throb + Gathering,
#    Release-Beat beim SHULKER_SHOOT; Projektile spawnen unverändert aus eyePos().
# 4) roar: Boss auf <2/3 HP prügeln (Phase-Break P1→P2) bzw. Stalker-Summon abwarten.
# 5) attack: in P2 die Gaze austehen lassen (Head-Snap im Fire-Moment).
# 6) P3-Shard-Detach: unter 1/3 HP — Korona-Bones verschwinden einzeln (synced).
# 7) death: /kill @e[type=eclipse:herald] ODER auskämpfen → 70t-Kollaps hold, Glow
#    guttert aus, Wrack sinkt zur Dais, shatter-FX bei t=69, Removal t=70.
# 8) reducedFx-Gegenprobe: eclipse-client.toml reducedFx=true → Puls statisch.
```

