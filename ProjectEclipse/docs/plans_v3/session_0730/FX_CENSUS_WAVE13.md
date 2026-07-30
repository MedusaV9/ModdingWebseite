# FX-ZENSUS WELLE 13 — Vollständiger Bestand + priorisierter Polish-Wellen-Plan

**Auftrag (F-097/F-098, 30.07.):** Jeder Veil- und Photon-Effekt wird einzeln von
Subagent-Teams auf ein neues Level gehoben, dazu NEUE Effekte. Diese Welle baut auf
FX-Wellen 9–12 auf (Stacking-Law-Audit, BlockDisplay-Masse-Choreografie 350/500,
Veil×Photon-Pairing) — nichts davon wiederholen, sondern die nächste Stufe zünden.

**Methode (alles verifiziert, nichts aus dem Gedächtnis):** `fxlib.py`-Parse über den
kompletten FX-Baum (Einmal-Skript `/tmp/fx_census13.py`, nicht committet), Grep über
alle Java-Trigger (`VeilPostController.register`, `PhotonFxRegistry.registerRow`,
`PhotonBridge.spawn*`, `QuasarSpawner`, Display-Spawner), Shader-Header-Review,
git log Wellen 9–12, `PHOTON_EDITOR_CAPABILITIES.md` (Gap-Analyse §5/§6).

## Gesamtzahlen

| Kategorie | Bestand |
|---|---|
| Veil-Post-Pipelines | **25** Pipelines (`pinwheel/post/*.json`) + **26** Fragment-Shader (inkl. `storm_volume_upsample`-Hilfspass) |
| Photon-`.fx` | **227** Dateien (206 Root + 16 `boss/` + 5 `sig/`) mit **718 FX-Objekten** (particle 563 · empty 95 · beam 46 · ara_trail 14), davon **76 Loop-Dateien** |
| Photon-Registry | **~130 Rows** in **31 Registrar-Klassen** + ~25 Klassen mit direkten `PhotonBridge.spawn*`-Seams |
| Photon-Generatoren | **38 Generator-Skripte** unter `tools/photon/` + `fxlib.py` (2134 Zeilen Haus-Standard) |
| Quasar-Emitter | **99** JSONs unter `quasar/emitters/` (Fallback-Lane + 10 Quasar-only-Lanes) |
| BlockDisplay-Choreografien | **~42 Java-Klassen** spawnen Displays; **~24 echte Set-Piece-Choreografien** |
| Cutscenes/Sequenzen | **8 große Sequenzen** (Intro 7 Phasen, Expansion 5, Nether-Öffnung 4, Herald, End-Ankunft 4, Ferryman-Finale 4, Credits 10, Tyrant-Awaken) |

Perf-Hotspots aus dem Scan (größte Partikelbudgets, alle Loops): `echo_spores` (1400),
`end_void_wisps` (1200), `storm_cloud_belt` (1200), `nether_eruption` (750, Burst),
`black_hole_maw` (610). GPU-Instancing weiterhin nur auf 5 Emittern in 3 Dateien.

---

## §1 Veil-Post-Pipelines (25)

Alle Pipelines laufen über `VeilPostController` (max. 3 gleichzeitig, GRADE < FEATURE <
TRANSITION, Iris-Gate, 3-Strikes-Fuse). Trigger = registrierende Klasse + Prädikat.

| Pipeline | Prio | Trigger/Feeder (Java) | Ist-Stand (1 Satz) | Potenzial | Konkrete Upgrade-Idee |
|---|---|---|---|---|---|
| `world_grade` | GRADE | `VeilPostController` builtin; aktiv bei Nacht/Eclipse/ArrivalDim/EndTintPulse/NetherHeat | v5: Nacht-Crush + PhaseTint-Farbskript + Grain/Breath + Horizontband + FX-12-Glutgrad (HeatTint/HeatShimmer) — sehr ausgebaut | mittel | **Blood-Dusk-Lean ab Tag 10+** (Timeline-getriebener Rotstich am Horizontband) + Boss-Nähe-Puls (Uniform `DreadPulse`, von Bossbar-Sync gespeist) |
| `sun_halo` | FEATURE | builtin; `SunTracker`-projizierter Sonnenpunkt, `AltarWarmth`-Leiter | v2 volumetrisch, Occlusion-Ease, Altar-Farbtemperatur | niedrig–mittel | Totality-Momente: **Shadow-Bands** (wandernde Schattenschlangen kurz vor/nach Totalität) + Diamantring-Snap-Frame gekoppelt an `totality_diamond_ring.fx` |
| `limbo` | GRADE | `LimboAmbience` static init | v4.1 nach LIMBOFIX/VEIL-REPASS-2 — ausgereift, Wasser-Maske frozen | niedrig | Ein Sub-Beat: **Undertow-Warp** nur während des Kenter-Moments (Intro-Keel-Over), Uniform von `LimboAmbience` |
| `border_glitch` | FEATURE | `BorderFxRenderer` static init; Border-Nähe | v3 "reality tearing toward the ring" | niedrig–mittel | Erst-Berührung: 1-Frame-**Static-Shock** + chromatisches Nachbild (koppelt an `border_first_contact.fx`) |
| `storm_volume` (+`_upsample`) | FEATURE | `StormVolumeFx`; SPHERE-Stürme | Echter Beer–Lambert-Raymarcher, Half-Res + adaptive Steps | — | **RESERVIERT für F-096-Team** (Sturm-Masse-Upgrade läuft) — Welle 13 fasst das nicht an |
| `storm_interior` | GRADE | `StormInteriorFx`; Kamera im Sturm | STORM2-Quartett (EyeDim/BandFlow/InnerFlash/WallProx) + Regen-Streaks | mittel | Regen-Streaks als **Flipbook-Schichten** + Blitz-Silhouetten (fernes Debris flackert als Schattenriss im Flash) — mit F-096 koordinieren |
| `rift_volume` | FEATURE | `RiftVolumeFx`; max. 2 Tears | Echter Vortex-fBm-Raymarch mit Glutkehle | mittel | **Throat-Pulse** beim Mob-Austritt (Uniform-Spike wenn Riss spawnt) + Sog-Streamer in Kamerarichtung bei <8 Blöcken |
| `rift_glitch` | TRANSITION | `TransitionFx` | v2: Transition + Ambient-Riss-Korruption | niedrig | Feintuning der Ambient-Korruption mit `random_curve`-artiger Variation (kein struktureller Umbau nötig) |
| `shockwave` | TRANSITION | `WaveOverlay`; `FxPayloads.FX_SHOCKWAVE` | v3 crisp (eased expansion + Luma-Crest) | niedrig | Nur Parameter-Feinschliff pro Aufrufer (Intro vs. Altar vs. Wand dürfen unterschiedliche Crest-Breiten haben — a/b-Cue-Params) |
| `black_hole` | FEATURE | `CreditsBlackHolePostFx`; `CreditsSkyFx.holeAmount` | V3 + fxwave9: Photon-Ring-Beads, gelenstes Sternfeld, Jets, Masse-Pulse | niedrig–mittel | Finaler Freeze: **Rotverschiebungs-Ausblutung** — im letzten Gulp friert das Sternfeld ein und blutet nach Rot aus, bevor Ergrauen kommt |
| `altar_aberration` | FEATURE | `client.AltarAberration`; Altar-Nähe | Chromatische Aberration + Ghosting am Altar | mittel | **Level-abhängige Runen-Geister**: ab L4 spiegeln sich schwache Glyphen-Echos im Ghosting (Textur-LUT statt mehr Taps) |
| `altar_aura_grade` | GRADE | `drama.AltarAuraGrade`; Insel-Rand d≈24 | Edge-Ripple + Violett→Gold-Leiter (F-075 V2) | niedrig–mittel | L5-Krone: sanfter **God-Ray-Fächer** vom Altar-Screenpoint (SunTracker-Muster wiederverwenden) |
| `ghost_grade` | GRADE | `client.GhostGradeFx`; 0-Leben-Geister | v2 "hauntingly beautiful" (violette Memory-Colors, Edge-Shimmer, 32-bpm-Puls) | niedrig | fertig — nur QA-Repass |
| `glitch_outline` | TRANSITION | `client.GlitchZoneFx` (Zonen + `/dev glitch`) | Ältester der 5 Zone-Shader | mittel | Kanten-Trace mit **Tiefen-Versatz** (SceneDepth-gewichtete Outline wandert, statt statisch zu kleben) |
| `glitch_datamosh` | TRANSITION | `client.GlitchZoneFx` | Stark: Macroblock-Hold, Tear-Lines, Accent-Wash | niedrig | fertig — Referenzqualität für die anderen vier |
| `glitch_scanlines` | TRANSITION | `client.GlitchZoneFx` | CRT-Scanlines | mittel | **Phosphor-Persistenz** (bewegte Objekte ziehen grüne Nachleucht-Schlieren) |
| `glitch_invert` | TRANSITION | `client.GlitchZoneFx` | Invert-Pops | mittel | Invert nur in **organischen Flecken** (fBm-Maske) statt Vollbild-Pop |
| `glitch_void` | TRANSITION | `client.GlitchZoneFx` (F-048 lila) | Violetter Void | mittel | **Tiefen-Parallaxe**: Void-Flecken driften mit Kamerabewegung wie Löcher IN der Welt (InverseView-Uniform vorhanden) |
| `gravity_lens` | FEATURE | `woah.gravityrift.client.GravityRiftLensFx` | Aufwärts-Refraktion + 45-s-Puls + Inversions-Ripple | niedrig–mittel | Debris-**Silhouetten im Shimmer** (die orbitenden Displays bekommen Hitzefahnen im Warp) |
| `dome_shell` | FEATURE | `woah.mansiondome.client.MansionDomeClient` | Analytischer Hex-Shimmer + Rim-Aberration (bewusst kein Raymarch) | mittel | **Touch-Intersection-Puls**: Spieler/Projektil-Berührung zündet lokalen Fresnel-Ring (Photon-Tutorial-Rezept, Uniform-Puls von Java) |
| `chrono_grade` | GRADE | `woah.chronostasis.client.ChronoGradeFx` | Unter-Glas-Grade + Zeitstaub | niedrig | fertig — ggf. Release-Beat verstärken (Puls beim Auftauen) |
| `echo_grade` | GRADE | `client.echo.EchoGroveFx` | Kalt-Slate ↔ Gold-Flut + Afterglow-Floor | niedrig | fertig |
| `resonance_shimmer` | FEATURE | `woah.resonance.client.ResonanceFieldFx` | Billigster Pass (3 Taps, 6.5-Hz-Tremble) | niedrig | fertig |
| `xbox_era` | GRADE | `client.xbox.XboxEraFx` | v2 "comfy 720p-Ära" | niedrig | fertig (bewusst nicht gimmicky) |

**Merksatz für alle Shader-Teams:** `VeilRenderTime` existiert in pinwheel-Posts NICHT
(Time-Uniform aus Java füttern), Raymarcher werden von depth-schreibender Geometrie
abgeschnitten (AGENTS.md-Falle), additive Uniforms müssen bei 0 bit-identisch sein.

---

## §2 Photon-FX — Zensus + Top-30

**Bestand:** 227 `.fx` / 718 FX-Objekte / 76 Loops. Seit dem 145er-Zensus
(`PHOTON_EDITOR_CAPABILITIES.md`) sind +82 Dateien dazugekommen (Wellen 9–12:
credits3/4, end_arrival2, wandfx2, tyrant_step, sig/, storm-nearfield, echo-grove,
chrono, gravity, dome, resonance). Die Capability-Gaps von damals gelten UNVERÄNDERT:
**custom_shader 0 · sprite 0 · distanceRate 0 · sizeBySpeed/rotationBySpeed 0 ·
Birth-SubEmitter 0 · GPU-Instancing 5 Emitter · Noise-Remap 1**. Genau diese Hebel
sind die Welle-13-Substanz — die Stacking-Law-Basics (dunkle Birth-Tints, breite
Shells, getrimmte Counts, HDR ~1.45) sind seit W10/W11 Gesetz und in den 14
Audit-Assets bereits umgesetzt.

### Top-30 nach Sichtbarkeit (Boss/Altar/Tagesriss/Nether/Finale/Zauberstab)

Spalten: Generator = Owner-Skript in `tools/photon/` (Konflikt-Einheit!), Registrar =
Client-Klasse mit der Cue-Row (`veilfx/` sofern nicht anders).

| # | .fx | Generator | Registrar/Cue | Ist-Stand | Potenzial | Upgrade-Idee (Gesetzeskonform) |
|---|---|---|---|---|---|---|
| 1 | `boss/tyrant_fog_arms` | `backlog_fx.py` | `BossPhotonFxRows` / `CUE_TYRANT_FOG_ARMS` | Loop-Nebelarme des Fog Tyrant, Einzeltextur-ALPHA | **hoch** | Soft-Particles (`custom_shader`+SceneDepth) + Noise-**Remap-Billowing** — der Boss-Körper hört auf, in Blöcke zu schneiden |
| 2 | `boss/tyrant_step_out`/`_in` | `tyrant_step_fx.py` | `BossPhotonFxRows` / `CUE_TYRANT_STEP_*` | W10-Beats, frisch nach V2.1-Law | niedrig–mittel | `inheritVelocity` auf Tendrils; sonst nicht anfassen |
| 3 | `boss/tyrant_blind_burst` | `backlog_fx.py` | `BossPhotonFxRows` / `CUE_TYRANT_SQUALL` | W11.1-verifiziert (Slate-Schalen) | niedrig | — |
| 4 | `boss/tyrant_death_implosion` | `boss_b_fx.py` | `BossPhotonFxRows` / `CUE_TYRANT_DEATH_IMPLOSION` | Einstufige Implosion | mittel–hoch | **Birth-SubEmitter-Kette**: Implosions-Partikel gebären Micro-Glints, Kollaps endet in Fresnel-Dome-Snap (nach A0-Shader) |
| 5 | `boss/tyrant_statue_idle` | `statue_fx.py` | `BossPhotonFxRows` / `CUE_TYRANT_STATUE_IDLE` | Statue-Ambient-Loop | mittel | `mesh`-Shape-Emission von der Statuen-Silhouette statt generischer Kugel |
| 6 | `boss/roar_shockwave` | `fx_boss_herald_ferryman.py` | `HeraldFerrymanFxRows` / `CUE_BOSS_ROAR` | Schockring + Funken | mittel | **`colorBySpeed`** auf Funken (weißglühend→Ember) + Multi-Material-Doppelpass-Ring (Vorbild `shadow_bolt_impact`) |
| 7 | `boss/herald_summon_pillar` | `fx_herald_summon.py` | `HeraldFerrymanFxRows` / `CUE_HERALD_SUMMON_PILLAR` | 9.5-s-Säule, W12-Omen-Grade gepaart | mittel | Pillar-Peak: Birth-Kette Glyphen→Funken, `random_gradient` gegen Wiederholungs-Müdigkeit |
| 8 | `boss/herald_glyph_swirl` | `fx_herald_summon.py` | `HeraldFerrymanFxRows` / `CUE_HERALD_GLYPH_SWIRL` | Glyphen-Wirbel | mittel | `uvAnimation`-Flipbook auf Glyphen (Zeichen morphen) + LOOKAT_XYZ-Facing |
| 9 | `boss/herald_shard_trail` | `fx_boss_herald_ferryman.py` | (Entity-Lane) | Ara-Trail flach, ohne Querschnitt/Physik | **hoch** (S!) | **Ara-Vollausbau**: `section`-Sternpolygon + inertia/damping + highQualityCorners — 5 Zeilen, größter Ribbon-Sprung |
| 10 | `boss/warden_eye_laser` | `boss_b_fx.py` | `BossPhotonFxRows` / `CUE_WARDEN_VOLLEY_TELEGRAPH` | Beam mit Raycast NONE — clippt durch Wände | **hoch** (S) | Raycast `BLOCKS` + Impact-Puff-Child am Endpunkt |
| 11 | `boss/warden_glitch_orbit` | `boss_b_fx.py` | `BossPhotonFxRows` / `CUE_WARDEN_STAGGER` | W11-fixiert, bereits Multi-Material | mittel | Erster **RGB-Split-custom_shader**-Abnehmer (GLITCH-Palette, nach A0) |
| 12 | `boss/ferry_lantern_swarm` | `fx_boss_herald_ferryman.py` | `HeraldFerrymanFxRows` / `CUE_FERRY_LANTERN_SWARM` | Laternenschwarm der Seelenernte | **hoch** | `lights`-Modul (Lightmap-Glow) + `random_curve`-Flackern pro Laterne + Ara-Fäden zwischen Laternen |
| 13 | `boss/ferry_oar_tear` | `fx_boss_herald_ferryman.py` | `HeraldFerrymanFxRows` / `CUE_FERRY_OAR_SWEEP` | Ruder-Riss-Sweep | mittel | `distanceRate`-Emission entlang des Sweeps (Dichte folgt der Ruderspitze) |
| 14 | `boss/ferry_kneel_corona` | `fx_boss_herald_ferryman.py` | `HeraldFerrymanFxRows` / `CUE_FERRY_KNEEL_CORONA` | fxwave9 V2 (Skirt+Halo+Heartbeat) | niedrig | — |
| 15 | `ferry_harvest_ring` | `ferryman2_fx.py` | `FerrymanFinaleFxRows` / `CUE_FERRY_HARVEST` | Bodenglow-Ring (renderMode-Crash gefixt) | mittel | Boden-**Intersection-Glow** via custom_shader (Ring leuchtet, wo er Geometrie küsst) |
| 16 | `ferry_wave_crest` | `ferryman2_fx.py` | `FerrymanFinaleFxRows` / `CUE_FERRY_WAVE` | Wellenkamm-Angriff | mittel | Ara-Ribbon-Kamm mit Segment-Physik (Welle schwappt nach) + Gischt-Birth-Kinder |
| 17 | `arena_mist_wall` | `ferryman2_fx.py` | `FerrymanFinaleFxRows` / `CUE_ARENA_MIST` | Arena-Nebelwand, schneidet hart in Geometrie | **hoch** | **Soft-Particles-Abnehmer Nr. 1** (SceneDepth-Fade) + Noise-Remap-Böen |
| 18 | `portal_soul_veil` | `ferryman2_fx.py` | `FerrymanFinaleFxRows` / `CUE_PORTAL_VEIL` | Seelen-Schleier am Tag-14-Portal | mittel | `SamplerSceneColor`-Distortion (Blick DURCH den Schleier wabert) |
| 19 | `day_rift_maw` | `ferryman2_fx.py` | `FerrymanFinaleFxRows` / `CUE_DAY_RIFT_MAW` | W11-Glockenvorhang, Drips mit physics | **hoch** | **Collision-SubEmitter-Splash** für Drips (physics ist schon da!) + Soft-Smoke + custom_shader-Verzerrung am Maul |
| 20 | `altar_corona_idle` | `fx_altar.py` | `AltarPhotonFxRows` / `CUE_ALTAR_CORONA_IDLE` | Idle-Corona als generische Kugel | **hoch** | **Mesh-Emission vom GeckoLib-Altar-Monument** (Edge-Modus) — "das Objekt selbst glüht" |
| 21 | `altar_aura_*` (10 Dateien rim/spiral/motes/bands/glyphs/pillar) | `altar_aura_fx.py` + `altar_aura2_fx.py` | `AltarAuraFxRows`/`AltarAura2FxRows` (WINDOWED) | V2.1-Lesbarkeits-Pass, CPU-Billboards | mittel | **GPU-Instancing** auf motes/rim (Dauer-Loops!) + `additionalGPUData`-Wobble im Vertex-Shader |
| 22 | `altar_levelup` + `altar_aura_powerup` | `fx_altar.py`/`altar_aura2_fx.py` | `CUE_ALTAR_LEVELUP` etc. | W11.1-verifiziert | niedrig | — |
| 23 | `nether_eruption` | `nether_open_fx.py` | `NetherOpenPhotonFxRows` (Sequenz-Cue) | W11-Masse (Apex 51, Debris-Rain), 750 maxP | mittel | Rauch auf **UV-Flipbook** (8×8) umstellen; Ember-Funken bekommen `trails` |
| 24 | `nether_pit_plume` | `nether_open_fx.py` | Loop über `NetherOpenClientFx` | Permanente Rauch-Feuer-Wolke, Einzeltextur, ~230 maxP CPU | **hoch** | Flipbook-Rauch + **GPU-Instancing** + Funken-Trails — der sichtbarste Dauer-Loop der Map |
| 25 | `breach_ash_geyser`/`breach_ember_updraft`/`breach_drift_cocoon` | `nether_open_fx.py` | `NetherOpenPhotonFxRows`/Loops | Breach-Umfeld-Set | mittel | `sizeBySpeed` auf Geysir-Asche, Flipbook teilen mit #24 |
| 26 | `storm_burst_shockwave` | `storm_nearfield_fx.py` | `StormNearfieldFxRows` / `CUE_STORM_BURST_SHOCKWAVE` | W11: HDR-Doppelring + Staubwand + Updraft-Jet | mittel | Multi-Material-Ring + `colorBySpeed`-Funken — **nur in Absprache mit F-096** |
| 27 | `wandfx2_*` (13 Dateien: 3 Muzzles + GLUT comet/burst/aschesturm + RISS well/maelstrom/echo_blade + STERN seal/guardian/bless) | `wandfx2_fx.py` | `client.wand.WandFx2PhotonRows` / `CUE_WANDFX2_*` | Pfad-Identitäten stehen (F-070), aber jede Wiederholung identisch, Muzzles kleben statisch | **hoch** | Das **Bewegungs-Paket**: `distanceRate` + `inheritVelocity` auf Muzzles/Trails, `colorBySpeed` auf Funken, **`random_gradient`** überall (kein Cast sieht zweimal gleich aus) |
| 28 | `wand_inferno_pillar`/`wand_judgment_finale`/`wand_event_horizon` | `wand2_fx.py` | `client.wand.WandPhotonFxRows` / `CUE_WAND_*` | Top-Tier-Zauber-Setpieces | mittel–hoch | Judgment: Birth-Ketten-Finale; Event-Horizon: `SamplerSceneColor`-Sog-Distortion (Mini-Schwarzloch im Cast) |
| 29 | `stern_komet_fall`/`_impact`/`_sparkle` | `gen_player_fx.py` | `PlayerFxPhotonRows` / `CUE_STERN_KOMET` | Komet einstufig | **hoch** (M) | **Erste Birth-SubEmitter-Kette des Bestands**: Komet→Birth-Glints→FirstCollision-Impact (Blaupause fürs ganze Repo) |
| 30 | `end_arrival2_*` (4) + `black_hole_maw` + `credits4_*` (3) | `end_arrival2_fx.py`/`credits2_fx.py`/`credits4_fx.py` | `EndArrivalFxRows`/`CreditsFinale*FxRows` | V2-Gigantismus bzw. V3 verifiziert | niedrig–mittel | Nur `credits4_jetburst`: Jet-Knoten mit `lifetimeByEmitterSpeed` (erster Nutzer überhaupt) |

**Rest-Bestand (~140 weitere .fx)** in Welle B/C: Mob-Set (`mobs_fx.py`: hound, gazer,
revenant, wanderer, sentinel, scare_*), Progression (`gen_player_fx.py`/`ceremony_fx.py`:
rebirth, revive, skill, collection, award, dawn_toll), Welt-Events (`worldevents_fx.py`,
`events_fx.py`: supply, landmark, quest, contract, minigame, race), Woah-Sets
(`woah_*/chrono/echo/resonance`), Portale, Glide/Sky-Launch, Credits 1–3, Sig-Familie.

---

## §3 Quasar-Emitter (99)

Rolle laut Haus-Gesetz: **Fallback-Lane** unter jeder Photon-Row (REPLACE/LAYER) —
Quasar wird NIE gelöscht (Baseline-Gesetz), nur ergänzt. Familien:

| Familie | Anzahl | Beispiele | Empfehlung |
|---|---|---|---|
| Altar | 12 | `altar_beam`, `altar_corona_ignite`, `altar_levelup_ring`, `altar_glyph_rain` | Fallbacks OK; `altar_beam` ist **Quasar-only** (s. u.) |
| Zauberstab-Pfade | 16 | `glut_*` (7), `riss_*` (6), `stern_*` (5, inkl. `stern_konstellation`) | Fallbacks OK, nicht anfassen (wandfx2-Photon ist die Hero-Lane) |
| Limbo | 5 | `limbo_fog`, `limbo_godray`, `limbo_motes(_near)` | bleiben Quasar (Ambient, kein Photon nötig) |
| Sturm | 5 | `storm_arc`, `storm_godfinger`, `storm_rain_sheet` | F-096-Territorium |
| Sig-Kompositionen | 6 | `sig_crown_verdict_*`, `sig_sanctum_*` | Fallbacks OK |
| Bosse/Ferryman | 6 | `boss_slam`, `ferry_kneel_corona`, `ferry_lantern_swarm` | Fallbacks OK |
| Resonance/Woah | 6 | `resonance_pulse`, `resonance_finale` | Fallbacks OK |
| Progression/Zeremonie | 14 | `heart_burst`, `rebirth_ring`, `revive_thunderbloom_ring`, `unlock_burst` | s. Quasar-only-Lanes |
| Welt/Events/Sonstiges | 29 | `map_expand_materialize`, `cutscene_veil`, `glyph_*`, `supply_*`, Portale | s. Quasar-only-Lanes |

**Die 10 Quasar-only-Lanes** (Konstanten in `S2CQuasarPayload`, KEINE Photon-Hero-Leg):
`altar_beam`, `arm_wisps`, `map_expand_materialize`, `border_glitch`, `boss_slam`,
`heart_burst`, `limbo_motes`, `cutscene_veil`, `altar_levelup_ring`, `offering_swallow`.
Davon verdienen ein Photon-Upgrade (neue Row, Quasar bleibt als Fallback drunter):

- **`heart_burst`** (Herz-Verlust — DER emotionale Beat des Hardcore-Events) → Photon-Herzsplitter mit Ara-Fäden, hoch.
- **`boss_slam`** (jeder Boss-Bodenschlag) → Photon-Bodenwelle + Chips, hoch.
- **`map_expand_materialize`** (jede Ring-Erweiterung, alle sehen es) → Photon-Materialise-Front, mittel.
- `altar_beam`, `offering_swallow` → mittel; Rest niedrig/bewusst Quasar.

---

## §4 BlockDisplay-Choreografien

Legende Ist-Stand: W12 = frisch aus Welle 12 (Masse-Choreografie), nicht anfassen.

| Klasse (Java) | Trigger/Ort | Ist-Stand | Potenzial | Upgrade-Idee |
|---|---|---|---|---|
| `stormfx.StormSiege` | Sturm-Bosskampf-Whirl | W12: 350/500, Sediment-Gesetz, 3 Radius-Bänder, MSPT-Guard | — | **F-096-reserviert** |
| `sequence.StormDebrisFx` | Intro-Sturm-Orbit | W12: 450/600 + Fern-Silhouetten-Band | — | F-096-reserviert |
| `sequence.NetherUpheavalFx` | Nether-Öffnung Tag 2 | W12: 380/480 + JET-Klasse + Masse-Kopplung | niedrig | — |
| `ferryman.finale.PortalFormation` | Tag-14-Portalbau | W12: 3 Sync-Tiers, Kometen-Braid, Keystone-Krone | niedrig | — |
| `ferryman.finale.DayRiftOrbits` | Tagesriss-Fallout-Orbit | W11: Masse-Stratifikation (corr −0.876) | niedrig–mittel | Keystone-Platten werfen Photon-`rift_piece_flash` beim Tier-Wechsel |
| `worldgen.end.EndShatterSequence` | End-Disc-Insel-Shatter | Vor-W12-Stand — NICHT im Masse-Audit gewesen | **hoch** | Masse-Gesetz nachziehen: 3-Klassen-Shatter, schwere Platten tief+langsam, Keystones ×2.4, Sub-Volleys |
| `worldgen.end.EndIslandCrashFx` | Insel-Crash nach Drachenkampf (F-023/047) | Displays krachen zu Boden | mittel | Einschlags-Staffelung nach Masse + Boden-Schockring-Cue pro Keystone |
| `sequence.endarrival.EndArrivalDebrisFx` | End-Ankunft Tag 12 | V2: 600-Teile-3-Strang-Helix, Cap 700 | niedrig | — |
| `ritual.CreditsShatterAct`/`MapRipAct`/`BlackHoleAct`/`FormationAct` | Credits-Finale | V3: 1250-Zellen-Effigy, 40 Platten, Peak ~2890 | niedrig | — (fxwave9 hat Gulp/Jets schon) |
| `worldgen.stage.StructureFlightFx` | Struktur-Spawn-Anflug (bis 640 Displays, F-007) | Hover-Wirbel, EINE Uhr für alle Teile | **hoch** | Per-Piece-Stagger (golden-hash wie P3-Ribs) + Masse-Stratifikation + Landing-Slam-Staub pro schwerem Teil |
| `worldgen.stage.ExpansionBorderFx` | Ring-Erweiterung/Monolithen | F-008/009-Stand | mittel | Monolith-Reveal mit Fern-Silhouetten-Band (W12-StormDebris-Muster kopieren) |
| `sequence.FloatingDecor` | Intro-Debris-Orbit | F-017-Stand (Orbit, Blitz-Kicks, Spiral-Kollaps) | mittel | Masse-Gesetz: schwere Brocken tief+langsam ins Orbit-Feld, Keystone-Akzente |
| `worldgen.structure.SanctumOrbitals` | Sanctum-Umlauf-Displays | funktional | mittel | Höhen-/Tempo-Stratifikation nach SCALE (DayRift-Orbit-Muster) |
| `worldgen.structure.SkyLauncher` | Windaltar-Wurf (F-024) | funktional | niedrig | — |
| `woah.gravityrift.GravityRiftOrbitals` | Gravitationsbruch-Orbit | Basis (F-062 offen) | mittel | Inversions-Beat: Orbit kehrt Drehrichtung sichtbar träge um (Trägheit nach Masse) |
| `woah.mansiondome.DomeShatterFx` | Dome-Kollaps | Basis | mittel | 3-Klassen-Shatter + Dome-Touch-Puls-Kopplung (§1 dome_shell) |
| `woah.chronostasis.ChronoSceneBuilder` | eingefrorene Szene | Basis | niedrig | — |
| `woah.echogrove.*` (Terraformer/SceneService/OverlayBuilder) | Echo-Hain-Vergangenheits-Overlay | Basis | niedrig–mittel | Flut-Beat: Overlay-Displays materialisieren als Welle vom Zentrum (statt gleichzeitig) |
| `ferryman.ArenaBuilder`/`ArenaMorphLayer` | Arena-Bau/Morph | funktional | mittel | Morph-Übergänge mit Stagger statt Flächen-Swap |
| `ferryman.AltarDoor` | Tag-14-Tür bricht auf | funktional | mittel | Tür-Splitter als ballistische Chips (P3-Rib-Debris-Muster) + lila Geister-Timing |
| `entity.boss.fog.TyrantStatue` | Statue-Awaken (60 t) | funktional; bekanntes Minor-Issue: Scythe-Display wirkt bei Storm-Step-Vanish kurz detached (F-081..087-Beobachtung) | mittel | Scythe-Handoff fixen + Awaken: Stein-Schalen platzen als Display-Chips ab (statt nur FX) |
| `limbo.OarAnimator` | Deckhand-Ruder | F-003-gefixt | niedrig | — |
| `minigames.MinigamePortal` | Minigame-Tore | funktional | niedrig | — |

---

## §5 Cutscenes — schwächster Beat pro Sequenz

Alle FX-replaybar via `/eclipsefx sequence <id> <PHASE>` bzw. `/dev`-Kommandos
(AGENTS.md); Bewertung = Planner-Hypothese, vor dem Polish per Replay verifizieren.

| Sequenz (Klasse) | Phasen | Schwächster Beat | Fix-Idee |
|---|---|---|---|
| Intro (`sequence.IntroSequence`) | ECLIPSE_ON→FLIGHT→APPROACH→LIGHTNING→BURST→REVEAL→SUNRISE | **FLIGHT/APPROACH-Mittelteil**: lange Gleitstrecke ohne Eskalationskurve zwischen Kenterung und Blitz | Wind-Shear-Photon-Streamer die sich zum Vortex hin verdichten (`distanceRate` am Kamera-Rig) + Limbo-Undertow-Beat (§1) |
| Expansion (`sequence.ExpansionSequence`) | SKYWARD→FLYOVER→GROWTH→STRUCTURES→END | **FLYOVER**: Kamera-Überflug liest statisch (GROWTH hat Ribbon, STRUCTURES Slams) | Fern-Monolith-Silhouetten pulsen im Vorbeiflug + Boden-Schatten-Lauf der wachsenden Front |
| Nether-Öffnung (`sequence.NetherOpeningSequence`, 47 s) | OMEN→TREMOR→RUPTURE→AFTERMATH | **AFTERMATH**: Decay in Dauer-Plume ohne eigenen Abschluss-Beat (OMEN/TREMor/RUPTURE haben W12-Grades) | "Erste Glut-Träne": ein einzelner Lava-Riss kriecht sichtbar vom Krater weg + Heat-Grade-Ausklang mit Nachbeben-Puls |
| Herald-Spawn (`sequence.HeraldSummonSequence`, 9.5 s) | Offering→Pillar→Spawn (+Watchdog) | **Pillar-Peak→Materialisierung**: kein Silhouetten-Reveal — der Boss ist plötzlich da | Schatten-Silhouette kondensiert IM Pillar (Photon-Model-Renderer mit Herald-Modell, 0→1 Alpha) bevor der echte Spawn swappt |
| End-Ankunft (`sequence.endarrival.EndArrivalSequence`) | OMEN→CHARGE→SPILL→FINALE | **CHARGE**: Mittelaufbau zwischen OMEN-Dim und Spill-Kaskade trägt am wenigsten | Himmel-Riss-Vorzeichen: `end_crack_bleed`-Instanzen zünden im Raster mit ansteigender Frequenz (Countdown-Gefühl) |
| Ferryman-Finale (`ferryman.finale.FinaleSequence`) | IDLE→FLIGHT→UNLOCK→FADE | **UNLOCK**: die Schlüsseldrehung selbst hat wenig FX (Tür-Aufbruch danach ist stark) | Key-Photon: Bart-Glyphen rasten hörbar/sichtbar ein (3 Klick-Beats mit Ring-Snap), Portal-Veil saugt ein |
| Credits (`ritual.CreditsSequence`) | SHATTER→HELM→WHITEOUT→BEACH→LIGHTNING→ECLIPSE→BURST→OUTRO→BLACKHOLE→HOLD | **WHITEOUT→BEACH-Übergang**: harter Tonartwechsel vom Chaos in die Stille | Nachglühen: weiße Asche-Motes rieseln in die Beach-Stille hinein (Brücken-Loop, 10 s Crossfade) |
| Tyrant-Awaken (`entity.boss.fog.TyrantStatue`, 60 t) | Statue→Boss | **Statue→Boss-Handoff** (dokumentiertes Scythe-Detach-Flackern) | Handoff hinter Step-Out-Fog-Fold verstecken (Cue 2 t früher) + Stein-Chip-Abplatzer (§4) |

---

## §6 NEUE Effekte — 15 Vorschläge (Horror/Eclipse/Umbral, Hardcore-Psychothriller)

Aufwand: S = Generator/Uniform-Arbeit · M = neues Asset/Child-fx/Textur · L = neue
GLSL-Pipeline. Impact = erwartete Sichtbarkeit im Event.

| # | Effekt (Lane) | Was man sieht | Trigger-Ort im Code | Aufwand | Impact |
|---|---|---|---|---|---|
| N1 | **Umbral-Adern** (Veil, neue Pipeline `eclipse:umbral_veins`) | Schwarze Adern wachsen vom Bildschirmrand, pulsieren mit Boss-HP <20 % | Bossbar-Sync-State (`hud`-Bossbar-Payloads) → neue Feeder-Klasse, Registrierung wie `GhostGradeFx` | L | **hoch** — jeder Bosskampf-Endspurt |
| N2 | **Shadow-Bands der Totalität** (Photon `totality_shadow_bands` + sun_halo-Uniform) | Wandernde Schattenschlangen auf dem Boden 30 s vor/nach Totalität (real-physikalisches Finsternis-Phänomen = perfekt fürs Thema) | `veilfx.TotalityPeakFx` (existiert, spawnt schon den Diamantring) | M | **hoch** — jeder Spieler, jeden Eclipse-Peak |
| N3 | **Herzschlag-Dread** (Veil-Uniform-Erweiterung `world_grade.DreadPulse`) | Vignette+Desat pulsieren im Herzschlag wenn HP <3 Herzen ODER in Dread-Zonen | `backrooms`-Dread-System (Client-State existiert) + HP aus `ClientStateCache` | S–M | **hoch** — Hardcore-Kernemotion |
| N4 | **Seelenlaterne am Grab** (Photon `grave_soul_lantern`, WINDOWED-Loop) | Über jedem Spielergrab schwebt eine flackernde Seelenlaterne mit Ara-Faden nach unten; erlischt bei Wiederbelebung | Grab-Schutz-System (F-085 Grave-Blöcke) — neue Row + Hysterese-Fenster wie `SanctumLightfall` | M | **hoch** — Gräber sind die emotionalen Marker der Map |
| N5 | **Wand-Overcharge-Bögen** (Photon `wand_overcharge_arc`, Entity-Loop) | Bei voller Veil-Ladung zucken Mini-Blitzbögen um die Stabhand, `inheritVelocity` reißt sie beim Laufen mit | `wand.WandTickService` Ladungs-State → Entity-attached Loop-Row in `WandFx2PhotonRows` | M | **hoch** — dauerpräsentes Belohnungs-Signal |
| N6 | **Flüster-Hände** (Photon `whisper_hands`) | Nebelhände greifen aus Glitch-Zonen-Rändern nach dem Spieler (2–3 s, dann Zerfall) | `client.scare.ScareDirector` (Jumpscare-Registry F-065, neue Variante) + Glitch-Zonen-Rand aus `GlitchZoneFx` | M | mittel–hoch |
| N7 | **Blood-Dusk** (Veil, `world_grade`-Uniform ab Tag 10) | Dämmerungen ab Tag 10 kippen ins Blutrote — die Welt weiß, dass das Ende naht | Timeline-Tag über bestehenden Day-Sync (`timeline`-Paket) → `VeilPostController.feedWorldGrade` | S | **hoch** — jeden Abend, ganze Map |
| N8 | **Contract-Brandmal** (Photon `contract_seal_brand`) | Beim Contract-Abschluss brennt sich die Siegel-Glyphe in den Boden und glimmt 60 s nach | `contracts`-Paket, neben `CUE_CONTRACT_OMEN` neue Cue + Row in `WorldEventPhotonFxRows` | M | mittel |
| N9 | **Seelenfaden der Wiederbelebung** (Photon `revive_soul_thread`, Ara) | Während des Revive-Rituals spannt sich ein leuchtender Ara-Faden vom Grab zum Sigil und wird straffer | `ritual.ReviveRitual` Fortschritts-Ticks → Entity/Pos-Cue-Paar | M | mittel–hoch |
| N10 | **End-Statik** (Veil, neue FEATURE-Pipeline `eclipse:end_static`) | Nahe End-Rissen knistert das Bild: feine Aberration + Sternfeld-Bleed in Schattenpartien | `worldgen/end`-Rift-Ambient (`CUE_RIFT_AMBIENT`-Fenster) → Proximity-Feeder | L | mittel |
| N11 | **Asche-Schnee** (Photon `ash_snow_ambient`, WINDOWED) | Sanfter grauer Asche-Schneefall im 60-Block-Umfeld des Nether-Breach — Dauerstimmung statt nur Plume | `client.nether.NetherOpenClientFx` (Fenster-Controller existiert) | S–M | mittel–hoch |
| N12 | **Gaze-Tether** (Photon `mob_gaze_tether`, Ara + Physik) | Der Gazer-Blick wird ein zäher Faden, der beim Blickbrechen sichtbar nachschwingt und reißt | `MobPhotonFxRows` (Gazer-Row existiert: `gazer_gaze_beam`) — Upgrade + neues Child | M | mittel |
| N13 | **Schwarze-Sonne-Snap** (Veil `TransitionFx`-Erweiterung + Photon) | Am Totalitäts-ENDE friert 1 Frame als Negativ ein und "reißt" dann weg (Diamantring-Gegenstück) | `TotalityPeakFx` Ende-Flanke → `TransitionFx`-Cue | S | mittel–hoch |
| N14 | **Sanctum-Konfession** (Photon `sanctum_confession`) | Beim Betreten des L5-Sanctums steigen Schrift-Glyphen wie Gebete in die Lightfall-Säule | `veilfx.SignatureCompositions` (Sanctum-Fenster existiert) | M | mittel |
| N15 | **Hitze-Leichentuch** (Photon, `custom_shader` über SceneColor) | Über Lava/Breach flimmert ein Leichentuch-Shimmer, der Silhouetten dahinter verzerrt (nutzt A0-Distortion-Shader) | Loop-Fenster in `NetherOpenClientFx`, Reuse des A0-RGB/Distortion-Shaders | M (nach A0) | mittel |

---

## §7 Priorisierte Polish-Wellen (parallelisierbar, konfliktfrei)

### Konflikt-Gesetz (VOR der Team-Aufteilung lesen)

1. **Ein `.fx` gehört genau EINEM Generator-Skript** — die Konflikt-Einheit ist immer
   `tools/photon/<gen>.py` + dessen `.fx`/`.fxproj`-Outputs + (falls Rows editiert
   werden) der zugehörige Registrar. Zwei Teams NIE im selben Generator.
2. **`fxlib.py` + `assets/eclipse/shaders/core/` (neu) + neue GLSL = NUR Team A0.**
   Alle custom_shader-Abnehmer warten, bis A0 gemergt ist (oder liefern shaderfreie
   Upgrades zuerst).
3. **Veil-Pipelines**: Einheit = `pinwheel/post/<id>.json` + `program/<id>.fsh` +
   Feeder-Klasse. Die 5 `glitch_*` teilen sich `GlitchZoneFx` → EIN Team für alle fünf.
4. **Neue Cues**: `FxCues.java`/`FxPayloads.java`/`EndArrivalFxCues.java` sind shared —
   Teams liefern Cue-Konstanten als Patch-Snippet, der **Integrator** merged sie (gleiches
   Muster wie langdrop). Neue Rows kommen in **eigene neue Registrar-Klassen**
   (PH-CORE-Contract: `PhotonFxRows` kopieren), nie in fremde.
5. **Sturm-Subsystem ist F-096-exklusiv**: `StormSiege`, `StormVolumeFx`,
   `storm_volume(.fsh)`, `storm_interior`, `StormDebrisFx`, `build_storm_fx.py`,
   `storm_nearfield_fx.py` — Welle 13 fasst NICHTS davon an (Ausnahme: Absprache).
6. **Lang**: nur `docs/plans_v3/langdrop/<PKG>.json`, nie die lang-JSONs direkt.
7. Nach jedem Asset-Regen: `python3 tools/photon/fxlib.py validate --lint` +
   `write_fxproj`, im Client `/photon_client clear_client_fx_cache` (Photon cached
   statisch!), Test via `/dev photon test <fxId>`.

### Welle A — höchster sichtbarer Impact (10 Pakete, alle parallel nach A0)

| Team | Paket | Effekte | Datei-Besitz (exklusiv) |
|---|---|---|---|
| **A0** | Shader-Grundstein (BLOCKIEREND, zuerst/allein) | 3 Core-Shader: soft-particle (SceneDepth), Fresnel-Force-Field, RGB-Split/Distortion (SceneColor) + fxlib-Nutzungsmuster + Doku | `assets/eclipse/shaders/core/*` (neu), `tools/photon/fxlib.py` (falls nötig), 1 Demo-Asset |
| **A1** | Zauberstab-Bewegungspaket | 13× `wandfx2_*` + Muzzles: `distanceRate`, `inheritVelocity`, `colorBySpeed`, `random_gradient` | `tools/photon/wandfx2_fx.py`, `fx/wandfx2_*`, `client/wand/WandFx2PhotonRows.java` |
| **A2** | Zauber-Setpieces | `wand_inferno_pillar`, `wand_judgment_finale`, `wand_event_horizon` (+Sog-Distortion nach A0), `wand_idle_*` | `tools/photon/wand2_fx.py`, `fx/wand_*`, `client/wand/WandPhotonFxRows.java` |
| **A3** | Ferryman/Arena/Tagesriss | `arena_mist_wall` (Soft-Particles!), `day_rift_maw` (Collision-Splash), `ferry_harvest_ring`, `ferry_wave_crest`, `portal_soul_veil` | `tools/photon/ferryman2_fx.py`, `fx/arena_*`,`fx/day_rift_*`,`fx/ferry_*`,`fx/portal_soul_*`, `veilfx/FerrymanFinaleFxRows.java` |
| **A4** | Herald + Warden + Ferry-Boss | `herald_shard_trail` (Ara-Vollausbau), `warden_eye_laser` (Raycast), `roar_shockwave` (colorBySpeed), `ferry_lantern_swarm`, `herald_summon_pillar`/`glyph_swirl` + Herold-Silhouetten-Reveal (§5) | `tools/photon/fx_boss_herald_ferryman.py`, `fx_herald_summon.py`, `boss_b_fx.py`, `fx/boss/{herald,warden,roar,ferry}_*`, `veilfx/HeraldFerrymanFxRows.java` |
| **A5** | Fog Tyrant | `tyrant_fog_arms` (Soft-Particles + Noise-Remap), `tyrant_death_implosion` (Birth-Kette + Fresnel-Snap), `tyrant_statue_idle` (mesh) + Scythe-Handoff-Beat | `tools/photon/backlog_fx.py` (tyrant-Teile), `statue_fx.py`, `fx/boss/tyrant_*` (außer step: frisch), `veilfx/BossPhotonFxRows.java` |
| **A6** | Nether-Öffnung + Dauerplume | `nether_pit_plume` (Flipbook+GPU), `nether_eruption` (Flipbook), `breach_*`-Set, N11 Asche-Schnee, N15 Hitze-Leichentuch | `tools/photon/nether_open_fx.py`, `fx/nether_*`,`fx/breach_*`, `veilfx/NetherOpenPhotonFxRows.java`, `client/nether/NetherOpenClientFx.java` + 1 Flipbook-Sheet-Textur |
| **A7** | Altar-Hub | `altar_corona_idle` (Mesh-Emission vom Monument), `altar_aura_*` GPU-Instancing, `altar_aberration.fsh` Runen-Geister | `tools/photon/fx_altar.py`, `altar_aura_fx.py`, `altar_aura2_fx.py`, `fx/altar_*`, `client/AltarAberration.*` (Shader+Feeder), Aura-Registrare |
| **A8** | Stern-Komet-Kette (Blaupause) | `stern_komet_fall`→Birth-Glints→Collision-Impact als erste 3-Stufen-Kette, dokumentiert als Repo-Muster | `tools/photon/gen_player_fx.py`, `fx/stern_komet_*` (+1 Child-fx), `veilfx/PlayerFxPhotonRows.java` |
| **A9** | Eclipse-Himmelsmomente (Veil) | N2 Shadow-Bands, N13 Schwarze-Sonne-Snap, N7 Blood-Dusk, `sun_halo`/`world_grade`-Uniform-Erweiterungen | `pinwheel/{post,shaders/program}/{sun_halo,world_grade}.*`, `veilfx/VeilPostController.java`, `veilfx/TotalityPeakFx.java`, `veilfx/TransitionFx.java` |

Hinweis Reihenfolge: A1, A4 (Ara/Raycast-Teile), A6 (Flipbook), A8 sind **A0-unabhängig**
und können sofort starten; A3/A5-Soft-Particle-Teile, A2-Distortion und N15 brauchen A0.

### Welle B — breite Sichtbarkeit / zweite Reihe

| Team | Paket | Dateien |
|---|---|---|
| B1 | Quasar→Photon-Hero-Legs: `heart_burst`, `boss_slam`, `map_expand_materialize` (+N4 Grab-Laterne) | neuer Generator `tools/photon/wave13b_fx.py` + neue Registrar-Klasse + Cue-Snippets an Integrator |
| B2 | Mob-Paket: `inheritVelocity`-Auren, `hound_dash_trail` distanceRate, N12 Gaze-Tether, scare_*-Politur + N6 Flüster-Hände | `tools/photon/mobs_fx.py`, `scare_fx.py`, `fx/hound_*`,`gazer_*`,`scare_*`,`revenant_*`,`wanderer_*`,`sentinel_*`, `veilfx/MobPhotonFxRows.java`, `client/scare/ScareDirector.java` |
| B3 | BlockDisplay-Nachzügler: `EndShatterSequence` + `EndIslandCrashFx` Masse-Gesetz, `StructureFlightFx` Stagger, `FloatingDecor`, `ExpansionBorderFx` | `worldgen/end/*`, `worldgen/stage/StructureFlightFx.java`, `sequence/FloatingDecor.java`, `worldgen/stage/ExpansionBorderFx.java` |
| B4 | Glitch-Familie (Veil): outline Tiefen-Trace, void Parallaxe, scanlines Phosphor, invert fBm-Flecken | `pinwheel/*/glitch_{outline,void,scanlines,invert}.*`, `client/GlitchZoneFx.java` |
| B5 | Boss-HP-Dread (N1 Umbral-Adern) + Herzschlag-Dread (N3) | neue Pipeline `umbral_veins.*`, `world_grade`-DreadPulse-Uniform (nach A9 mergen!), neue Feeder-Klasse |
| B6 | Progression/Zeremonien: rebirth/revive (+N9 Seelenfaden), dawn_toll, collection, awards, `random_gradient`-Variation | `tools/photon/ceremony_fx.py`, `gen_player_fx.py` (Rest), `fx/rebirth_*`,`revive_*`,`award_*`,`dawn_*`, `veilfx/{Ceremony,Progression}PhotonFxRows.java`, `ritual/ReviveRitual.java` (Cue-Hook) |
| B7 | Cutscene-Beats aus §5: Intro-FLIGHT-Streamer, Expansion-FLYOVER, Nether-AFTERMATH-Träne, EndArrival-CHARGE, Finale-UNLOCK, Credits-WHITEOUT-Brücke | jeweils Sequenz-Klasse + 1 neues Child-fx pro Beat (eigene Generatoren `wave13_cutscene_fx.py`) |

### Welle C — Politur / Perf / Rest

| Team | Paket |
|---|---|
| C1 | GPU-Instancing-Rollout auf alle großen Ambient-Loops (`echo_spores` 1400, `end_void_wisps`, `storm_cloud_belt` [F-096-Absprache], `era_dust_motes`, `arena_mist_wall`-Basis) + `parallelUpdate/Rendering`-Audit |
| C2 | CullBox-/Prewarm-Audit über alle 227 (Photon hat kein LOD — CullBox ist unser Ersatz) + neue Lint-Regel in `fxlib.py` (nach A0, mit A0-Team abstimmen) |
| C3 | Woah-Sets Feinschliff (F-062): chrono/echo/resonance/dome/gravity Photon-Politur + §4-Display-Ideen | 
| C4 | Kleine Cues: supply, landmark, quest, minigame, race, glide, sky_launch, portale, sig-Familie + N8/N10/N14 |
| C5 | Credits/End-Feinschliff: `credits4_jetburst` lifetimeByEmitterSpeed, black_hole Rotverschiebungs-Freeze, `end_arrival2`-Detail |

**Eval-Gate (F-099):** Nach jeder Welle Sol-Eval über die Ergebnisse; „zu simpel"-Befunde
erzeugen Nach-Polish-Runden im selben Datei-Besitz.

---

## §8 Arbeits-Checkliste pro Executor-Team

1. Generator ändern → `.fx` UND `.fxproj` regenerieren (`write_fxproj`), nie Binaries
   hand-editieren.
2. `python3 tools/photon/fxlib.py validate --lint` (neue Findings = Fail).
3. Client-Test: `/photon_client clear_client_fx_cache` (Pflicht!), dann
   `/dev photon test <fxId>` bzw. `/eclipsefx sequence <id> <phase>` — llvmpipe:
   20–40 s Wartezeiten, Screenshots statt Video.
4. Stacking-Law-Selbstcheck: Birth-Tints dunkel, Shells breit, Counts getrimmt,
   HDR ~1.45, LAYER-Rows dürfen den Photon-Body nicht in Vanilla-Weiß ersäufen;
   Masse-Gesetz: schwer = tief + langsam.
5. Veil-Teams: additive Uniforms bit-identisch bei 0, Time aus Java, kein Depth-Write
   in Volumen, `reducedFx`-Detail-Gate.
6. Neue Cues/Rows: eigene Registrar-Klasse, Cue-Snippet + Langdrop an den Integrator.
