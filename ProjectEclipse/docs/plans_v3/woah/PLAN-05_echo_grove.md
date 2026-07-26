# PLAN-05 — ECHO-HAIN (Geister & Erinnerungen)

**Feature-Familie:** WOAH-Map-Features (Schwester des volumetrischen Sturms — gleicher
Produktionsstandard, entgegengesetzte Emotion).
**Ziel-Version:** NeoForge 1.21.1, Mojang-Mappings, Mod-ID `eclipse`.
**Basis-Recherche (alles im Code verifiziert, Stand branch `cursor/project-eclipse`):**
`ghosts/` (LogoutGhostEntity + GhostPlayerRenderer), `scare/` + `client/scare/`
(NUR Whisper-Asset wiederverwendet, kein Scare-Framework!), `veilfx/` (PhotonFxRegistry,
PhotonBridge, VeilPostController), `stormfx/StormVolumeFx` (Volumetrik-Referenz),
`worldgen/fog/FogStormSites` (Site-Materialisierung), `ritual/CreditsFormationAct` +
`worldgen/stage/DisplayBrightnessFx` (BlockDisplay-Handwerk), `registry/PaleGardenBlocks`
(back-portierte Pale-Oak-Blöcke!), `analytics/` (KEINE Pfad-Aufzeichnung vorhanden —
siehe §3.2), `music/MusicCues`, `network/fx/FxCues` + `S2CCaptionPayload`
(STYLE_WHISPER existiert bereits).

---

## 1. Konzept-Zusammenfassung + Fernwirkung

### 1.1 Das Erlebnis

Am Außenrand des Wald-Keils, in der **Moonlit-Grove-Zone** (r > 280), liegt eine flache
Nebelmulde: ein **toter, bleicher Hain**. Knochenweiße, blattlose Bäume (die
back-portierte Pale-Oak-Palette + Bone Blocks) stehen in einem See aus Bodennebel;
tausende winzige **Glimmer-Sporen** treiben in der Luft; das Licht ist kalt-blau
graduiert. Zwischen den Bäumen spielen **Echos** — durchscheinende Geister-Silhouetten
im Stil der vorhandenen Logout-Ghosts — endlos kurze Erinnerungs-Szenen nach: zwei
Kinder jagen sich um einen Baum, ein Bergmann schwingt die Spitzhacke, ein Paar sitzt
schweigend auf einer Bank, ein Hund springt nach einem Stock, eine Laternenträgerin
geht ihre Runde. Jede Szene loopt 10–20 s mit sanftem Auf- und Abblenden.

Alle ~90 Sekunden kommt die **Erinnerungs-Flut**: Für ~8 Sekunden blendet der GANZE
Hain in seine lebendige Vergangenheit — sattgrüne Baumkronen, Blumen, warmes
Laternenlicht (alles als vorgeparkte BlockDisplay-Overlays, die per Interpolation von
Scale 0 aufwachsen), goldener Farb-Grade, alle Echos hell, ein verlangsamtes
Spieluhr-Motiv — dann zerfällt alles wieder zu Grau, während Asche-Partikel rieseln.
**Die Landschaft wechselt vor deinen Augen die Zeit — das ist der Woah-Moment.**

Im Zentrum steht der **Erinnerungs-Baum**: ein großer bleicher Baum mit hängenden
Glimmer-Lichtern. An ihm schweben **Erinnerungs-Lichter** (Orbs). Rechtsklick auf einen
Orb: ein geflüstertes Erinnerungs-Fragment (Whisper-Caption + leiser Sound), und die
zugehörige Echo-Szene spielt einmal direkt neben dem Spieler verstärkt ab.

**Sammel-Quest:** 5 verstreute "verlorene Erinnerungen" (Orbs an den Szenen-Orten)
einsammeln und am Baum abgeben → **Finale**: alle Echos versammeln sich um den Baum,
die Vergangenheits-Flut hält 30 Sekunden, der Baum blüht golden auf
(BlockDisplay-Blüten + Photon-Blütenregen), Belohnung. Danach bleibt der Hain dauerhaft
in einem sanfteren, wärmeren Zustand (persistiert via SavedData).

Tonalität: melancholisch-schön. KEIN Jumpscare, KEIN Scare-Framework-Aufruf, kein
Damage, keine Mobs. Der Hain ist ein sicherer Ort.

### 1.2 Fernwirkung (der "Blick von weitem")

- **Bleiche Baumkronen im Nebelsee**: die Terraforming-Palette selbst (Pale-Oak-Stämme +
  Bone-Block-Wurzeln auf Calcit-Grund) liest sich ab Sichtweite als heller Fleck im
  dunklen Birken-Außenring; der Photon-Bodennebel (`echo_ground_fog.fx`) hat eine
  CullBox über die volle Mulde und ist ab ~120 Blöcken als flacher weißer Teich sichtbar.
- **Goldenes Aufleuchten bei der Flut**: `CUE_ECHO_FLOOD` wird mit Range 256 gesendet;
  die Row spielt für ferne Kameras (> 96 Blöcke) nur das distanz-skalierte
  `echo_flood_bloom.fx` (eine weiche HDR-Lichtsäule + Kronen-Glints über der Mulde) —
  das gleiche Prinzip wie `CUE_SUMMON_BEACON`s distanz-skalierte Säule. Wer auf dem
  Berg steht, sieht alle 90 s ein kurzes goldenes Atmen am Horizont und weiß: da ist
  etwas.
- Nachts verstärken die `lights`-Module der Sporen/Baumlichter (Lightmap-Forcing,
  FX_FORMAT.md §7) den Glimmer-Teppich.

---

## 2. Platzierung + Terraforming

### 2.1 Standort

- **Landmark:** neuer Eintrag `eclipse:echo_grove` in
  `worldgen/DiscMapDefaults.overworldDefaults()`:
  `new DiscMapData.Landmark("eclipse:echo_grove", 0, 310, 30, 4)`.
  - Winkel = atan2(z, x) = **90.0°** → exakte Mitte des Wald-Keils (67.5–112.5°),
    maximaler Abstand zum ±5°-Seam-Wobble.
  - r = 310 → im **Moonlit-Grove-Ring** (> 280, "twisted birch") und innerhalb der
    Stage-4-Disc (D8-Radien {96, 150, 210, 280, 360, 440}).
  - Kollisionscheck gegen die authored Karte (verifiziert): Fluss 3
    ((62,215)→(65,320)) hält ≥ 63 Blöcke Abstand (Regel: > 18 + Radius 30 = 48 ✓);
    Mansion (219,−219), Village (254,−22), r=170-Spielerdisc-Ring — alles frei.
  - **WICHTIG (Frozen-Map-Falle):** `disc_map.json` ist per Save eingefroren.
    Bestehende Saves bekommen den neuen Default-Landmark NICHT. Deshalb liest
    `EchoGroveSites` die Koordinaten primär aus
    `DiscMapData.get().landmarks(DiscProfile.OVERWORLD)` und fällt bei Abwesenheit
    auf die Code-Konstante (0, 310, 30) zurück (nur Kollisionswarnung loggen).
- **Materialisierung:** exakt das `worldgen/fog/FogStormSites`-Muster:
  - `EchoGroveSites` registriert sich in `ServerAboutToStartEvent` als
    `WorldStageService`-Listener; bei **Overworld-Stage-4-Terrain-Complete** wird eine
    Pending-Row in `StructurePendingRegistry` eingereiht
    (`registerAsyncPlacer("eclipse:echo_grove", …)`).
  - Placer: `SitePrep.preparePlateau(…)` über die 61×61-Footprint →
    `EchoGroveTerraformer` (unten) → `SitePrep.finish` → Persist-Flag
    `placed=true` in `EchoGroveState` → `LandmarkDiscoveryService`-kompatible
    Entdeckung läuft über den bestehenden Sweep (Cue `CUE_LANDMARK_DISCOVERED`
    feuert gratis, wenn der Landmark in der Karte steht).

### 2.2 Terraforming: die Nebelmulde (`echo/EchoGroveTerraformer`)

Alle Schreibvorgänge über `worldgen/stage/BudgetedBlockWriter.enqueue` (das
FogStormSites-`carveGrove`-Vorbild), deterministisch aus dem Site-Seed:

1. **Mulde:** flache Schale, Radius 30, Tiefe als Kosinus-Profil — Rand 0, Zentrum
   −5 Blöcke unter Plateau-Y. Kein Wasser im Kern (Nebel ist der See); 2–3 kleine
   Rest-Pfützen (`water` 1 tief, Rand `calcite`) an gehashten Stellen.
2. **Boden-Palette** (per Distanz + Hash gemischt):
   - Kern (r < 18): 55 % `calcite`, 20 % `diorite`, 15 %
     `eclipse:pale_moss_block` (aus `registry/PaleGardenBlocks`), 10 % `gravel`.
   - Rand (18 ≤ r ≤ 30): Blend zurück zum Biom-Grund; `eclipse:pale_moss_carpet`
     als Streu (~8 % der Oberflächen).
   - Akzente: `bone_block` als "versteinerte Wurzeln" (2–4-Block-Läufe flach am
     Boden, ~14 Stück), vereinzelt `cobweb`-FREI (kein Horror), stattdessen
     `dead_bush` auf Coarse-Dirt-Inseln (~10 Stück).
3. **Bleiche Bäume** (~26 Stück, Poisson-artig gehasht, Mindestabstand 6):
   - Stamm: `eclipse:stripped_pale_oak_log` 4–7 hoch; dicke Alt-Bäume (jeder 5.):
     2×2 aus `eclipse:stripped_pale_oak_wood`, 8–10 hoch.
   - Äste: 2–4 horizontale Stummel aus `stripped_pale_oak_wood` (axis x/z) auf den
     oberen zwei Dritteln. **Keine Blätter** — tot. An ~30 % der Ast-Enden ein
     einzelnes `eclipse:pale_hanging_moss` (1–2 lang).
   - Wurzel-Flare: 3–5 `bone_block`/`stripped_pale_oak_wood` diagonal am Fuß.
4. **Der Erinnerungs-Baum** (Zentrum, deterministisch): 3×3-Stamm
   (`stripped_pale_oak_wood`, Kern `bone_block`) 12 hoch, ab Höhe 7 vier
   Hauptäste (3–5 Blöcke, leicht steigend) + Kronen-Kranz aus `stripped_pale_oak_wood`.
   - **Hängende Glimmer-Lichter:** 10 statische BlockDisplays
     (`pearlescent_froglight`, Scale 0.25, Brightness-Override 12/8 via
     `DisplayBrightnessFx.apply…`, viewRange 2.0) an den Ast-Enden, 1–3 Blöcke
     "hängend"; dazu 4 `chain`-Blöcke als reale Aufhänger. Spawn EINMALIG bei
     Materialisierung (persistente Displays, Tag `eclipse_echo_static`), keine
     Tick-Kosten. Photon-Motes (`echo_tree_lights.fx`) liefern das Funkeln.
   - **Build-Probe für den Client** (ObservatoryAmbience-Gesetz "physischer Proben-
     Block"): der oberste Zentrum-Block des Baums ist ein `waxed_oxidized_copper_bulb`
     (leuchtet nicht ohne Redstone, unverwechselbar, kommt natürlich nie vor) —
     Client-Fenster prüfen "geladen UND Probe-Block da" statt Server-Flags.
5. **Szenen-Requisiten** (reale Blöcke, Teil des Terraformings, an den 5 Szenen-Ankern,
   §3.3): Bank (2× `dark_oak_stairs` gegenüber + `dark_oak_slab`), Fels des Bergmanns
   (4×3×3 `cobbled_deepslate`/`deepslate` mit 2 `calcite`-Adern), Karren
   (`dark_oak_planks`/`dark_oak_trapdoor`-Rumpf + 2 `dark_oak_button`-"Räder" als
   BlockDisplays Scale 0.6), 3 Laternenpfähle (`stripped_pale_oak_log` 3 hoch +
   `lantern` hängend), Stock-Wurfplatz des Hundes (nur `pale_moss_carpet`-Kreis).

**Kein ChunkRegen / kein Block-Swap zur Laufzeit:** die Vergangenheits-Version ist
NIE echtes Terrain (§5) — das Terraforming hier ist einmalig und endgültig; damit
bleibt der `RingGrowthService`-Vertrag "Terrain = Funktion(Seed, Stage)" unangetastet
(der Hain ist eine Site wie FogStorm/Mansion, kein Terrainzustand).

---

## 3. Server-Systeme

Neues Package: `dev.projecteclipse.eclipse.echo` (Feature-Ordner-Konvention wie
`worldgen/fog`, `ferryman/finale`).

### 3.1 Entities (`echo/EchoEntities.java` — eigenes DeferredRegister, GhostEntities-Muster)

| Id | Klasse | Chassis | Zweck |
|---|---|---|---|
| `eclipse:echo_ghost` | `EchoGhostEntity` | wie `ghosts/LogoutGhostEntity`: `Mob`, `setNoAi(true)`, `noPhysics`, `setNoGravity`, `setInvulnerable`, MobCategory.MISC, sized 0.6×1.8, clientTrackingRange 10 | Szenen-Darsteller (Erwachsene + Kinder via Scale) |
| `eclipse:echo_ghost_wolf` | `EchoGhostWolfEntity` | gleiches Chassis, sized 0.6×0.85 | der Hund |
| `eclipse:memory_orb` | `MemoryOrbEntity` | `Entity` direkt (kein Mob — kein Attribut-Boilerplate), sized 0.5×0.5, `noPhysics`, unverwundbar, `setPersistenceRequired`-Äquivalent via `shouldBeSaved()=true` | interagierbare Orbs |

**Was das ghosts/-System hergibt und was wir erweitern (geprüft):**
`LogoutGhostEntity` ist ein reiner Marker (kein Pfad, keine Pose); die ganze
Geister-Optik lebt im Client-Renderer (`client/entity/ghost/GhostPlayerRenderer`):
PlayerModel + `RenderType.entityTranslucent` bei ~40 % Alpha, Hover-Bob, Drift,
Shimmer, Glow-Layer. **Wiederverwendung = Renderer-Familie, nicht Entity:** Echos
brauchen zusätzlich (a) server-getriebene Bewegung, (b) synced Aktion/Fade. Deshalb:

- `EchoGhostEntity` synced Data: `DATA_ACTION` (Byte: 0 IDLE, 1 WALK, 2 RUN, 3 SWING,
  4 SIT, 5 JUMP, 6 WAVE, 7 THROW), `DATA_FADE` (Int-Ticks, zählt hoch beim Einblenden /
  runter beim Ausblenden — Renderer mappt auf Alpha 0→0.35), `DATA_CHILD` (Boolean →
  Renderer skaliert 0.72), `DATA_GLOW` (Float 0..1 — Flut-/Finale-Boost, server-gesetzt).
- Bewegung: der Szenen-Player setzt pro Tick `setPos`/`setYRot` (Interpolation
  server-seitig); `LivingEntityRenderer` erzeugt Geh-Animation automatisch aus dem
  Positions-Delta (limbSwing) — genau wie bei echten Spielern. `SWING` triggert
  `swing(MAIN_HAND)` (vanilla broadcastet). `SIT` löst der Renderer über Pose-Offsets
  (Beine falten kann das PlayerModel nicht — der Renderer senkt den Körper um 0.45
  und rotiert die Beinteile; das besitzen wir, §4.3).
- `shouldBeSaved() = false` (SoulWispEntity-Gesetz): Darsteller leaken nie auf die
  Platte; der Szenen-Player respawnt sie deterministisch.

### 3.2 Analytics/Replay-Befund (verifiziert)

`analytics/AnalyticsSampler` sampelt 1 Hz NUR Aggregatzähler (Distanz-Deltas, Chunks,
Biome — `AnalyticsKeys`), **keine Positionspfade**; `/dev replay` (DevReplayCommands)
ist Cutscene-Replay über `SequenceReplayable`, keine Spieler-Aufzeichnung. **Es gibt
also nichts, was man als Echo-Wiedergabe abspielen könnte** → Szenen sind **authored
Keyframes** (unten). Bewusst offen gelassener Hook: das Keyframe-Format ist generisch
genug, dass ein späteres Feature ("Echo deiner ersten Stunde") aufgezeichnete Pfade
als Szene einspeisen könnte — dafür genügt ein zweiter Loader, kein Formatwechsel.

### 3.3 Szenen-Definitionen (Datenformat) + `echo/EchoScenes.java`

**Format:** JSON pro Szene unter `data/eclipse/echo_scenes/<id>.json`, geladen über
einen `SimpleJsonResourceReloadListener` (Server-Datapack-Lane, `AddReloadListenerEvent`)
mit **eingebauten Code-Defaults** für alle 5 Szenen (Datapack kann überschreiben,
Abwesenheit bricht nichts — das GhostConfig-"reload + defaults"-Muster).

```json
{
  "id": "children_chase",
  "loop_ticks": 320,
  "fade_ticks": 30,
  "anchor": { "dx": -14, "dy": 0, "dz": 6 },
  "actors": [
    { "role": "child_a", "variant": "player_child",
      "keyframes": [
        { "t": 0,   "x": 0.0, "y": 0.0, "z": 3.0, "yaw": 90, "action": "run" },
        { "t": 80,  "x": 3.0, "y": 0.0, "z": 0.0, "yaw": 180, "action": "run" },
        { "t": 160, "x": 0.0, "y": 0.0, "z": -3.0, "yaw": 270, "action": "run" },
        { "t": 240, "x": -3.0, "y": 0.0, "z": 0.0, "yaw": 0, "action": "run" },
        { "t": 320, "x": 0.0, "y": 0.0, "z": 3.0, "yaw": 90, "action": "run" }
      ] },
    { "role": "child_b", "variant": "player_child", "keyframes": [ "… 40t versetzt …" ] }
  ],
  "props": [
    { "block": "minecraft:dark_oak_fence", "dx": 0.0, "dy": 0.0, "dz": 0.0,
      "scale": 1.0, "static": true }
  ]
}
```

- Positionen szenen-lokal (Anker relativ zum Hain-Zentrum, `dy` relativ zur
  terraformten Oberfläche); `t` in Ticks; Interpolation **Catmull-Rom** über die
  Nachbar-Keyframes (weiche Kurven statt Polygonzug), Yaw linear kürzester Weg.
  Loop-Naht: letzter Keyframe == erster (Validator-Warnung sonst).
- `variant`: `player` | `player_child` | `wolf`. `action` gilt ab dem Keyframe.
- **Die 5 Szenen** (Loop-Längen 200–400t = 10–20 s):
  1. `children_chase` (320t) — zwei Kinder umrunden gegenläufig-versetzt einen
     Alt-Baum bei (−14, 6); Anker-Requisite: keiner (der Baum ist echt).
  2. `miner` (240t) — 1 Geist vor dem Deepslate-Fels bei (18, −10): 3 Schritte ran,
     4× `swing` im 30t-Takt, Schulterblick (Yaw-Keyframe), zurück.
  3. `bench_couple` (400t) — 2 Geister `sit` auf der Bank bei (10, 16); bei t=200
     dreht einer den Kopf zum anderen (Yaw ±25°), bei t=340 `wave` klein.
  4. `dog_fetch` (280t) — Geist bei (−6, −18) macht `throw` (t=20), der Wolf
     (`wolf`-Variante) sprintet 8 Blöcke, `jump` am Ende (t=120), trabt zurück (t=260).
  5. `lantern_walk` (360t) — Geist geht die drei Laternenpfähle ab (WALK, Pausen mit
     IDLE + `wave` an Pfahl 2); Requisite: warmes Photon-Glühen folgt via
     szenen-lokalem `echo_lantern_glow`-Anker (§4.2 Nr. 8).
- **Fade-Regel:** Der Szenen-Player setzt `DATA_FADE` in den letzten/ersten
  `fade_ticks` des Loops NICHT auf 0 (die Szene loopt nahtlos); Fades laufen nur bei
  (a) Actor-Spawn/-Despawn (LOD, §8), (b) Einmal-Wiedergaben (§7.2), (c) Finale.

### 3.4 Szenen-Player (`echo/EchoSceneService`)

- Ein `ServerTickEvent.Post`-Subscriber (Muster `LogoutGhostService`/`FogStormSites`).
  Pro Tick: billiger Gate — ist `EchoGroveState.placed()` und ein Spieler in 96
  Blöcken um das Zentrum? (eine Distanzprüfung über `level.players()`).
- **Pro Szene** ein `SceneInstance` (Anker-Vec3, tick-Cursor, Actor-Liste):
  - Spieler < 64 Blöcke vom Szenen-Anker → Actors sicherstellen (spawnen mit
    `DATA_FADE`-Einblendung 30t), Cursor läuft, pro Tick Keyframe-Sample →
    `setPos`/`setYRot`/`DATA_ACTION`.
  - Kein Spieler < 72 Blöcke (Hysterese) → Fade-out 30t, dann `discard()`; Cursor
    läuft NICHT weiter (Szene "friert" — beim Wiederkommen setzt sie am
    Loop-Anfang auf; niemand kann den Unterschied sehen, spart Buchhaltung).
- Requisiten (`props`): `static=true`-Props sind Teil des Terraformings (§2.2 Nr. 5);
  dynamische Props (Karren-Räder, Stock des Hundes) sind BlockDisplays, die mit der
  SceneInstance leben (Tag `eclipse_echo_scene`, Spawn beim Materialisieren der
  Instance, discard beim Release; Stray-Sweep über den Tag beim Server-Start —
  CreditsFormationAct-Despawn-Garantie-Gesetz).
- **Einmal-Wiedergabe** (`playOnce(sceneId, worldAnchor, glow)`) für §7.2: klont die
  Szene an einen freien Anker ~4 Blöcke neben dem Spieler, ein Durchlauf, `DATA_GLOW`
  = 0.6 (heller), Fade-in/out, dann discard. Max. 1 gleichzeitig pro Spieler
  (Zweitklick bricht die alte ab).

### 3.5 Flut-Timer (`echo/MemoryFloodService`)

- Zustand in-memory (statics, Reset in `ServerStoppedEvent`): `nextFloodInTicks`
  (1800 ± 200 gehasht), läuft NUR runter, solange ein Spieler < 96 Blöcke ist
  (sonst pausiert — kein Leerlauf-Spam, keine verpassten Fluten "nachholen").
- **Flut-Ablauf (Ticks, t0 = Auslösung), Gesamtdauer 160t (~8 s):**

| Tick | Server | Client (über Cue) |
|---|---|---|
| t0 | `FxPayloads.sendFxEvent(level, FxCues.CUE_ECHO_FLOOD, treeCenter, range 256, a=holdTicks(160), b=0)`; Overlay-Pushes Welle 1 (§5) | Grade-Warmth-Ease 0→1 über 20t; `echo_flood_bloom.fx`; Spieluhr-Motiv startet |
| t0–t3 | Overlay-Pushes Wellen 2–4 (je ~160 Displays, Interpolation 20t auf Scale 1) | — |
| t2 | Brightness-Step 1 auf Overlay-Kronen (DisplayBrightnessFx, versteckt in der Wachs-Bewegung) | — |
| t0–t160 | alle geladenen Echo-Actors: `DATA_GLOW` = 1.0 | Echos rendern heller (Alpha 0.35→0.55) |
| t140 | Overlay-Pushes zurück auf Scale 0 (20t-Fenster, 4 Wellen) | `echo_ash_fall.fx` (Asche rieselt), Grade-Warmth 1→0 über 30t |
| t158 | Brightness-Override CLEAR (letzter erlaubter Step ≤ 3) | — |
| t160 | `DATA_GLOW` = 0; Timer neu würfeln | Motiv klingt aus (Asset endet) |

- Nach dem Finale (§7.3): `EchoGroveState.finaleDone` → Timer-Basis 1200t, Flut-Grade
  wärmer (Cue-Parameter `b=1` = "Afterglow-Variante").

### 3.6 Orb-Interaktion (`echo/MemoryOrbEntity` + `echo/EchoQuest`)

- Synced Data am Orb: `DATA_KIND` (0–4 = verlorene Erinnerung an Szene N;
  10–14 = Baum-Orb für Fragment N), `DATA_LIT` (Boolean — Baum-Orbs leuchten stärker,
  wenn ihr Fragment abgegeben wurde).
- **Baum-Orb Rechtsklick** (`interact`-Override, Server-Seite):
  1. `S2CCaptionPayload(langKey="echo.eclipse.memory.<n>", 120t, STYLE_WHISPER)` NUR an
     den Klicker (`PacketDistributor.sendToPlayer`) — der Caption-Renderer existiert
     (`cutscene/client/CaptionRenderer`, Payload-Hub `EclipsePayloads` unangetastet:
     Versand-Helfer gibt es schon).
  2. Whisper-Sound: `EclipseSounds.AMBIENT_GAZER_WHISPER` positioniert am Orb,
     Volume 0.35, Pitch 0.7 (tief = warm statt gruselig) + `CUE_ECHO_WHISPER`
     (kleiner Photon-Wisp zum Ohr, §4.2 Nr. 7). Cooldown 3 s pro Orb (die
     `LogoutGhostService.lastRevealByEntityId`-Rate-Limit-Technik).
  3. `EchoSceneService.playOnce(sceneFor(kind), nebenSpieler, glow=0.6)`.
- **Verlorene-Erinnerung-Orb Rechtsklick:** Orb spielt eine 15t-Einsaug-Animation
  (Photon `echo_orb_collect`-Leg über `CUE_ECHO_ORB_COLLECT` am Orb-Pos), `discard()`,
  Spieler bekommt 1× Item `eclipse:memory_mote` (neu, `registry/EclipseItems`,
  max. Stack 5, Glint, Rarity UNCOMMON), Caption-Whisper "…du trägst jetzt eine
  Erinnerung." `EchoGroveState.collectedOrb(kind)` persistiert (Orb respawnt NIE —
  bei `reset` schon).
- **Abgabe:** Rechtsklick mit `memory_mote` in der Hand auf einen BELIEBIGEN Baum-Orb
  → Mote verbraucht, `deposited++` (SavedData), Baum-Orb `DATA_LIT`; Chime
  (`NOTE_BLOCK_CHIME`-Sequenz, 3 Töne aufsteigend). Bei `deposited == 5` →
  `EchoFinaleSequence.start`.

### 3.7 Sammel-Quest-State (`echo/EchoGroveState`)

`SavedData` nach dem `ghosts/GhostsState`-Vorbild (`EclipseSavedData.getOverworld`,
Datei `eclipse_echo_grove.dat`): `placed` (bool), `treeCenter` (BlockPos),
`collectedOrbs` (Bitmaske 0–4), `deposited` (0–5), `finaleDone` (bool),
`staticDisplayUuids` + `orbUuids` (Listen — Reparatur/Reset findet alles wieder).
Client-Sync: kleines `network/fx/S2CEchoGrovePayload` (flags + deposited), gesendet
bei Login + Änderung (Mailbox-Feld in `client/ClientStateCache`, das
`S2CGhostRevealPayload`-Muster).

### 3.8 Tick-Budget (Server, Worst Case: Spieler mitten im Hain)

| Posten | Kosten |
|---|---|
| Gate (kein Spieler in 96) | 1 Distanzcheck/Spieler/Tick — ~0 |
| 5 SceneInstances aktiv | ≤ 8 Ghost-Entities: je 1 Catmull-Rom-Sample + setPos (No-AI-Mob-Tick ist trivial) |
| Orbs | 10 Entities, `tick()` leer bis auf 100t-Selfcheck (LogoutGhost-Muster) |
| Flut | 2×4 Push-Wellen à ~160 `setTransformation` pro Flut (alle 90 s) + 2 Brightness-Roundtrips — CreditsFormationAct lief mit 130 Pushes/Tick DAUERHAFT, wir haben 160 Pushes in 4 Einzel-Ticks alle 1800t |
| Overlay-Pool idle | ~640 geparkte Displays: kein Push, kein Interp-Fenster; Entity-Tick von Displays ist annähernd frei |
| Terraforming | einmalig, `BudgetedBlockWriter` |

---

## 4. Client-Systeme

Neues Client-Package `dev.projecteclipse.eclipse.client.echo` + Renderer unter
`client/entity/echo/`.

### 4.1 Zonen-Grade (`eclipse:echo_grade`)

- Neue Veil-Post-Pipeline: `assets/eclipse/pinwheel/post/echo_grade.json` +
  `assets/eclipse/pinwheel/shaders/program/echo_grade.{json,fsh}`.
- Registrierung als `VeilPostController.PipelineSpec` mit Priority **GRADE** aus dem
  static-init von `client/echo/EchoGroveFx` (das `LimboAmbience`/`StormVolumeFx`-Seam).
- Aktivierung: Kamera < 90 Blöcke vom client-abgeleiteten Hain-Zentrum
  (`DiscMapData.get()`-Landmark bzw. Code-Fallback — die ObservatoryAmbience-
  "Anker ohne Sync"-Schule) UND Build-Probe (§2.2 Nr. 4) ok.
- Uniforms (Feeder allokationsfrei, VeilPostController-Vertrag):
  `Amount` (Distanz-Hysterese 70→90, pro Tick geslewt — nie poppen),
  `Warmth` (0..1 — Flut/Finale, vom Cue-Latch geeased),
  `AfterglowFloor` (0 oder 0.18 wenn `finaleDone` — dauerhaft wärmer),
  `Time`, `Detail` (reducedFx-Gate — die world_grade-Konvention).
- Shader-Look: leichte Kälte-Grade (Lift der Schatten Richtung #6C7A8F, Desat 15 %,
  sanfte Vignette), bei `Warmth`→1 Überblendung zu goldener Wärme (#E8C878-Lean,
  +10 % Exposure). Budget-Regel beachtet: GRADE wird bei > 3 Pipelines zuerst
  evicted — akzeptiert (Sturm/Übergänge gewinnen, der Hain-Kern bleibt lesbar).

### 4.2 Photon-FX-Liste (Generator `tools/photon/echo_grove_fx.py`, fxlib-Standard; alle Assets + `.fxproj`-Siblings; CullBox + maxParticles PFLICHT)

| # | Asset | Typ | Emitter-Spec (Kurzform) |
|---|---|---|---|
| 1 | `echo_ground_fog.fx` | **Loop** (WINDOWED) | 2× particle: Horizontal-Billboards, box-Shape 56×2×56 flach über dem Muldenboden, weiche Fog-Textur (vorh. Storm-Fog-Textur wiederverwendbar), startLifetime 12–18 s, Rate ~6/s + prewarm, noise 1D schwach (Remap-Kurve für "Schwaden"), colorOverLifetime Alpha-Rampe, maxParticles 110, lights sky=6; CullBox 64³ |
| 2 | `echo_spores.fx` | **Loop** (WINDOWED) | 1× particle mit **useGPUInstance** (end_void_wisps-Präzedenz): box 64×14×64, 1400 maxParticles (Tier-2; Asset-Variante `_lite` 400 für Tier 0/1 wählt die Row), winzige HDR-Motes (Boost ~1.6), velocity orbital + noise langsam, sizeOverLifetime Puls, lights block=10 |
| 3 | `echo_tree_lights.fx` | **Loop** (WINDOWED) | 2× particle am Baum: (a) cylinder-Shape r=3 h=10 aufsteigende Gold-Motes Rate 4/s, (b) dot-Bursts an 10 gehashten Licht-Offsets (function-Shape), Glint-Sprite, HDR 2.0 |
| 4 | `echo_flood_bloom.fx` | One-Shot 160t | empty-Root + (a) HDR-Lichtsäule (cylinder, StretchedBillboard, 30 hoch, Alpha-Kurve rise/hold/decay passend zur Flut-Timeline), (b) Kronen-Glints (box über Baumkronenhöhe, Burst alle 20t), (c) Distanz-Leg skaliert X/Z (CUE_SUMMON_BEACON-Technik) |
| 5 | `echo_ash_fall.fx` | One-Shot 80t | box 44×1×44 auf Kronenhöhe, graue Flocken, forceOverLifetime −Y sanft, rotationOverLifetime, physics AUS (durch Displays fallen ok), 300 Partikel gesamt |
| 6 | `echo_bloom_rain.fx` | One-Shot 600t (Finale) | Modell-Partikel (RenderMode Model, `block_atlas`, cherry_leaves-Optik via rosa/weiße Sprites), box 20×1×20 über dem Baum, Rate 25/s, physics AN mit removedWhenCollided, colorBySpeed Gold→Weiß |
| 7 | `echo_whisper_wisp.fx` | One-Shot 40t | dot am Orb, 6 Soul-Wisps, velocityOverLifetime radial→orbital klein, Alpha-Fade; Entity-Lane (reitet den Orb) |
| 8 | `echo_orb_glow.fx` | **Attach-Loop** | kleiner Halo + 2 Funken-Orbits, maxParticles 20 — via `PhotonMobFx`-Tabellenzeile (`MemoryOrbEntity` → attach < 48 Blöcke, nearest-8-Cap); `DATA_LIT`-Orbs bekommen die `_lit`-Variante (2. Zeile, Prädikat) |
| 9 | `echo_orb_collect.fx` | One-Shot 20t | Einsaug-Implosion: sphere-Shell invertiert (velocity radial negativ), 40 Glints, HDR 1.8 |

**Cues (neue Konstanten in `network/fx/FxCues`, Rows im neuen Registrar
`client/echo/EchoPhotonFxRows` per `PhotonFxRegistry.registerRow`):**
`CUE_ECHO_FLOOD` (One-Shot-Row mit Custom-Leg: a=holdTicks, b=Afterglow-Flag; Leg
startet #4, plant #5 mit `setDelay(140)`, latcht Grade-Warmth + Musik in
`EchoGroveFx`), `CUE_ECHO_BLOOM_RAIN` (Finale), `CUE_ECHO_WHISPER` (Entity-Lane),
`CUE_ECHO_ORB_COLLECT`. Die Loops #1–#3 sind **WINDOWED-only** (niemals
payload-gefeuert — INTEGRATION.md-§4-Gesetz) und werden von `EchoGroveFx` über
`PhotonFxRegistry.ensureLoop/releaseLoop` gefahren: Fenster 80/100-Hysterese ums
Zentrum, Retry-Kadenz 20t, Release bei reducedFx/Dimensionswechsel/Logout — das
`ObservatoryAmbience`-Schema wortwörtlich. Quasar-Fallback-Legs: #1 bekommt einen
dünnen Quasar-Nebel-Emitter (REPLACE-Modus), #2/#3 sind Photon-only-Garnish (legal,
Baseline war nichts).

### 4.3 Geister-Rendering (`client/entity/echo/`)

- `EchoGhostRenderer` — Ableger der `GhostPlayerRenderer`-Bauart (NICHT Subclass —
  die Klasse ist final-artig auf Reveal-Logik zugeschnitten; Copy-and-strip):
  - PlayerModel WIDE, `RenderType.entityTranslucent`, **neue Textur**
    `textures/entity/echo_ghost.png` (entfärbte, blau-weiße Ableitung der
    `eclipsed_player.png` — Generator-Zeile in `tools/skins`-Familie oder einmalig
    authored; KEIN lila Herz-Glow: statt `HeartGlowLayer` ein schwacher
    Ganzkörper-`RenderType.eyes`-Pass mit `echo_ghost_glow.png` bei Alpha 0.10 —
    Mondschein-Silhouette).
  - Alpha = 0.35 × fade(DATA_FADE) + 0.20 × DATA_GLOW, Shimmer/Drift-Sinus aus dem
    Original übernehmen (Hash-per-Entity-Phasen — Geister nie im Gleichtakt);
    reducedFx: konstantes Alpha (das GhostPlayerRenderer-Gesetz).
  - `DATA_CHILD` → poseStack-Scale 0.72; `DATA_ACTION==SIT` → Körper −0.45,
    Beinteile 90° gefaltet (wir besitzen das Model — die `GhostModel`-Technik mit
    renderergesteuertem Alpha wird um Pose-Zugriff erweitert).
  - Kein Schatten, kein Nameplate (Original-Regeln).
- `EchoGhostWolfRenderer` — `WolfModel` über `ModelLayers.WOLF` gebacken, gleiche
  Translucent-Alpha-Technik, Textur `textures/entity/echo_ghost_wolf.png`
  (bleiche Wolf-Textur-Ableitung).
- `MemoryOrbRenderer` — kleine additive Billboard-Quad (die `SupplyBeamRenderer`-
  Schule für handgebaute RenderTypes) mit Puls-Sinus; `DATA_LIT` → wärmerer Ton +
  1.3× Größe. Photon-Glow (#8) liefert die Funken; der Renderer garantiert
  Photon-lose Sichtbarkeit (Baseline-Gesetz).
- `EchoRenderers` — Lookup-guarded Registrierung aller drei (das
  `GhostRenderers.onRegisterRenderers`-Muster mit `BuiltInRegistries.ENTITY_TYPE.containsKey`).

---

## 5. Vergangenheits-Overlay (die Flut-Optik)

### 5.1 Entscheidung: **vorgeparkter Scale-0-Display-Pool** (kein Block-Swap)

Displays können nicht alpha-faden — die zwei Kandidaten waren:

1. **Scale-0-Interpolation (GEWÄHLT):** ein persistenter Pool von BlockDisplays wird
   EINMAL gespawnt (beim ersten Spieler-Fenster, Batch 50/Tick — das
   `CreditsFormationAct.SPAWN_PER_TICK`-Gesetz), auf Scale ~0.02 geparkt
   (`SCALE_FLOOR`-Präzedenz: nie exakt 0, Interpolation bleibt gesund) und pro Flut
   mit EINEM interpolierten Transform-Push (20t-Fenster) auf Zielscale gefahren und
   zurück. Warum: (a) das Aufwachsen IST der Morph — Blätter "knospen" sichtbar,
   exakt der gewünschte Zeitwechsel-Effekt; (b) idle kostet der geparkte Pool nichts
   (keine Pushes, kein Interp-Fenster); (c) Terrain bleibt unberührt — kein Konflikt
   mit dem RingGrowthService-Vertrag (Terrain = byte-identische Funktion), kein
   Protection-/Anticheat-Rauschen, kein Crash-Risiko "Flut halb persistiert";
   (d) 2 Pushes/Display/Flut sind Größenordnungen unter dem CreditsFormationAct-
   Dauerbetrieb (130 Updates/Tick über Minuten).
2. **Block-Swap-Wellen (VERWORFEN):** ~4–6k `setBlock` pro Richtung pro Flut (alle
   90 s!) mit Licht-Neuberechnung, Chunk-Resends, Persistenz-Fenstern und der Pflicht,
   nach Crash mitten in der Flut aufzuräumen. Für die EINMALIGE Finale-Blüte wäre es
   vertretbar, für einen 90-s-Zyklus nicht.

### 5.2 Overlay-Set (deterministisch aus dem Site-Seed, `echo/EchoOverlayBuilder`)

| Gruppe | Displays | Blockstates | Ziel-Scale |
|---|---|---|---|
| Kronen der 26 bleichen Bäume | je 10–14 → ~330 | `eclipse:pale_oak_leaves` (60 %), `minecraft:birch_leaves` (25 %), `minecraft:flowering_azalea_leaves` (15 %), persistent=true | 1.6–2.4, golden-phasig rotiert (BD-SHIP-Gesetz: Nachbarn nie synchron) |
| Erinnerungs-Baum-Krone | 60 | wie oben + 8 `minecraft:ochre_froglight` "Lichtfrüchte" | 1.8–2.6 |
| Blumen/Gras-Teppich | ~160 | `peony`/`lilac`/`oxeye_daisy`/`short_grass`/`moss_carpet` gehasht auf den Kernboden gestreut | 0.9–1.2 |
| Warmes Licht | ~30 | `ochre_froglight` Scale 0.3 an Laternenpfählen/Bank/Karren + Brightness-Override 14/10 | 0.3 |
| Szenen-Garnitur | ~40 | Blumenkasten auf dem Karren, Efeu-Blätter am Fels, Kissen (`white_wool` 0.4) auf der Bank | 0.4–1.0 |
| **Summe** | **~620** | Tag `eclipse_echo_overlay`, viewRange 2.0, kein Schatten-Thema (Displays werfen keinen) | — |

- Pushes in 4 Wellen à ~155 Displays über t0–t3 (Radiuswellen von innen nach außen —
  die Vergangenheit "blüht vom Baum her auf"); Rück-Pushes identisch bei t140–t143.
- Brightness: max. 3 Steps pro Flut (Set bei t2, Clear bei t158 — Craft-Gesetz aus
  `DisplayBrightnessFx`: Steps in Bewegung verstecken, nie per-Tick-Rampen).
- Pool-Fenster: Spawn, wenn ein Spieler < 128 Blöcke (Batch), Discard bei > 160 für
  > 2 Minuten oder Dimensionswechsel des letzten Spielers (Ticket-frei; der Pool wird
  beim nächsten Fenster deterministisch identisch wiederaufgebaut). `finaleDone`-
  Afterglow: 15 % der Kronen-Displays parken dauerhaft auf Scale 0.8 (der Hain wirkt
  "halb erwacht"), die Froglight-Gruppe auf 0.2.

### 5.3 Finale-Blüte

Zusätzliches Set (~120 Displays, `cherry_leaves` + `pink_petals` + 12
`ochre_froglight`) NUR am Erinnerungs-Baum, gespawnt im Finale-Batch, Scale-in über
60t, bleibt für die 600t-Haltephase, geht danach auf das Afterglow-Sub-Set (30
Displays bleiben dauerhaft — der "golden erblühte" Baum).

---

## 6. Sounds

**Bestandsprüfung (verifiziert):** `assets/eclipse/sounds/music/` hat 15 Score-Tracks
(kein Spieluhr-Material); `assets/eclipse/sounds/ambient/` hat `gazer_whisper.ogg`
(als `EclipseSounds.AMBIENT_GAZER_WHISPER`, fixed range) — die Scare-Skripte
(`client/scare/ScareScripts`) nutzen es hart geramped; **das Asset ist neutral genug
für Wiederverwendung**, die Scare-Rampen übernehmen wir NICHT.

1. **Spieluhr-Motiv (Flut, ~8 s):** neuer Track `music/echo_music_box.ogg` über
   `tools/music/treblo_generate.py` (neuer Katalog-Eintrag: "slowed music box /
   celesta, minor key, nostalgic, gentle tape wow, 30s", Loudnorm-Pipeline inklusive)
   → `sounds.json`-Eintrag `music.echo_music_box` + Registrierung in
   `music/EclipseMusicSounds`. Abgespielt CLIENT-seitig von `EchoGroveFx` beim
   `CUE_ECHO_FLOOD`-Latch als positionierter One-Shot am Baum (SoundSource.RECORDS,
   Distanz-Falloff gratis). **Fallback ohne Treblo-Key:** `MemoryFloodService`
   sequenziert das Motiv server-seitig aus `NOTE_BLOCK_CHIME`/`NOTE_BLOCK_BELL`
   (12-Töne-Tabelle, 6t-Raster, Pitch aus der Notentabelle) — klingt nach Spieluhr,
   null neue Assets; die Wahl fällt zur Buildzeit (Asset vorhanden → Client-Weg).
2. **Ambience-Bett (im Hain):** neuer `MusicCues`-Situation-Rung `ECHO_GROVE`
   ("inside grove"-Hysterese 80/100 wie FOG_STORM mit 0.55/0.15-Analogie), Track
   `music/echo_grove.ogg` (Treblo: "sparse ambient, distant slowed music box,
   soft wind, warm sadness, 90s loop"). Bis das Asset da ist, bleibt der Rung
   unregistriert — der Hain funktioniert ohne Bett.
3. **Wind:** kein neues Asset nötig — der Bodennebel + Sporen tragen die Stille;
   optionaler Treblo-Foley `ambient/echo_wind.ogg` als leiser Client-Loop in
   `EchoGroveFx` (die `SanctumHum`-Bauart in `client/sound/`), Volume 0.25.
4. **Flüstern (Orbs):** `AMBIENT_GAZER_WHISPER` @ vol 0.35 / pitch 0.7 (§3.6) —
   bewusst NICHT scary: einmalig, kein Ramp, keine Layering-Eskalation.
5. **Finale:** Motiv voll — `music/echo_music_box.ogg` 2× hintereinander + die
   bestehende `NOTE_BLOCK_CHIME`-Abgabe-Sequenz als Auftakt; Belohnungsmoment
   `EclipseSounds.AWARD_STING` (existiert).
6. Subtitles/Lang: `subtitles.eclipse.echo.*` via Langdrop.

---

## 7. Gameplay

### 7.1 Orb-Fundorte (szenen-gebunden, alle im Hain-Radius)

| # | Orb (Kind) | Fundort (relativ zum Zentrum) | Szene |
|---|---|---|---|
| 0 | Kinderlachen | im Geäst des Alt-Baums der Jagd-Szene (−14, +8, 6) — man muss klettern | `children_chase` |
| 1 | Silberstaub | im Spalt des Deepslate-Felsens (18, +1, −10), halb verdeckt | `miner` |
| 2 | Abendrot | unter der Bank (10, 0, 16) | `bench_couple` |
| 3 | Stock | in der Rest-Pfütze beim Hunde-Platz (−6, 0, −18), knapp unter Wasser | `dog_fetch` |
| 4 | Laternenlicht | oben AUF Laternenpfahl 3 (22, +4, 4) | `lantern_walk` |

### 7.2 Lore-Fragmente (5 Baum-Orbs, Whisper-Captions; Lang-Keys `echo.eclipse.memory.0–4`, en+de via Langdrop — deutsche Vorschläge:)

1. *"Der Baum war schon alt, als wir klein waren. ‚Fang mich doch', hat sie gerufen — ich höre es noch."*
2. *"Jeden Morgen hab ich ihr vom Stollen aus gewinkt. Der Fels gab Silber. Die Stunden gab er nie zurück."*
3. *"Auf dieser Bank haben wir geschwiegen, bis die Sonne unterging. Es war das schönste Gespräch meines Lebens."*
4. *"Brav, Junge. Hol das Holz. Bring es her. … Ich glaube, er wartet noch immer."*
5. *"Als die Lichter kamen, haben wir gesungen. Wenn du das hörst: Wir waren glücklich hier."*

Jeder Baum-Orb spielt zusätzlich seine Szene EINMAL verstärkt neben dem Spieler ab
(§3.4 `playOnce`) — Lore und Bild verzahnt.

### 7.3 Finale (`echo/EchoFinaleSequence`, 600t + Nachlauf)

| Tick | Beat |
|---|---|
| 0 | Abgabe #5: Chime-Kadenz, 20t Stille (Spannungsatmer) |
| 20 | Flut wird erzwungen (holdTicks=600, b=1); alle Szenen wechseln auf generierte "Gather"-Keyframes: Actors gehen/laufen sternförmig zum Baum (Pfade radial, WALK, Kinder RUN), Wolf umkreist |
| 80–560 | Echos stehen/sitzen im Ring um den Baum (`DATA_GLOW`=1, IDLE mit vereinzelten `wave`), Finale-Blüten-Set wächst (60t), `CUE_ECHO_BLOOM_RAIN` läuft, Motiv voll |
| 560 | Belohnung materialisiert am Baumfuß (Item-Entity-Drop aus Loot-Table `data/eclipse/loot_table/event/echo_grove_finale.json`) + `AWARD_STING` + Caption (TITLE): *"Der Hain erinnert sich."* |
| 600 | Flut klingt aus — aber in den Afterglow-Zustand (§5.2): mehr Glimmer, warme Grade-Floor, 15 %-Kronen bleiben |
| — | `finaleDone=true` persistiert; Echos kehren zu ihren Loops zurück |

### 7.4 Belohnung (konkret)

- **`eclipse:echo_blossom`** ("Echo-Blüte") — neues Artefakt-Item
  (`registry/EclipseItems`, Rarity EPIC, Glint): passives Trinket nach dem
  `artifact/`-Bestandsmuster — solange im Inventar, gilt im Hain-Radius +
  überall nachts: sanfter Regeneration-I-Puls alle 30 s bis max. 6 Herzen
  ("Erinnerungen wärmen"). Zusätzlich in der Loot-Table: 2× `music_disc_otherside`-
  Ersatz? Nein — konkret: 16× `eclipse:memory_mote`-Dekostack ENTFÄLLT (Motes sind
  Questware); stattdessen 3× Diamant + 1× `eclipse:pale_oak_leaves`-Block-Bundle
  (16) als Bau-Souvenir + 500 XP (Orb-förmig verteilt).
- Collections-Anbindung: `echo_blossom` in die Collections-/Bestiary-Lexika
  (`collections/ItemLexiconService`-Allowlist) — Anzeige im Handbook gratis.

### 7.5 Wiederholbarkeit

- Finale einmal pro Welt (`finaleDone`). Danach: Fluten weiter (wärmer, 60-s-Basis),
  Baum-Orbs bleiben endlos anhörbar (Whisper + `playOnce` unbegrenzt — der Hain
  bleibt ein Ort, an den man Freunde mitbringt), Szenen loopen für immer.
- `/dev woah echo reset` (§9) setzt Quest + Finale zurück (Testbarkeit + Server-Events).

---

## 8. Performance + LOD

- **Echos ticken nur < 64 Blöcke** (pro Szenen-Anker, Hysterese 64/72, §3.4);
  eingefrorene Szenen kosten einen Distanzcheck. Actors `shouldBeSaved=false`.
- **Flut-Overlay Batch-Spawn:** Pool-Spawn 50/Tick (Credits-Gesetz), Pushes in 4
  Wellen à ~155; Interpolation macht die Bewegung client-seitig — keine per-Tick-
  Transformflut. Idle-Pool: 0 Pushes.
- **Flut-Timer pausiert ohne Spieler in 96** — keine Arbeit in leeren Regionen; der
  Hain liegt bei r=310 und ist ohne Spieler ohnehin entladen (Orbs/Static-Displays
  sind persistente Entities in entladenen Chunks = null Kosten).
- **Photon:** alle Loops WINDOWED (80/100-Fenster), CullBox überall, Sporen
  GPU-instanziert mit `_lite`-Variante für Quality-Tier ≤ 1; reducedFx: Loops
  released (Loop-Gesetz), Grade `Detail=0`, Flut behält Quasar-/Display-Anteil
  (die Zeitreise bleibt lesbar — nur der Glitter fehlt).
- **Veil:** 1 GRADE-Pipeline; Konkurrenz-Eviction akzeptiert (§4.1).
- **Wire:** 1 Cue pro Flut (Range 256), 1 State-Payload bei Änderung, Whisper/Collect
  einzeln pro Interaktion — weit unter der Frequency-Law-Schwelle.
- Introspektion: `PhotonBridge.liveExecutors()`/`PhotonFxRegistry.liveLoopWindows()`
  decken die FX-Seite; `/dev woah echo status` (§9) druckt Actor-/Display-/Pool-Zähler.

## 9. Dev-Commands (`devtools/dev/DevWoahEchoCommands.java`)

Eigener `RegisterCommandsEvent`-Subscriber, der `/dev woah` als Literal beisteuert
(Brigadier merged Literale über Registrare — `DevRoot` hält die Permission-Wurzel;
Geschwister-WOAH-Pläne hängen ihre Features unter dasselbe `woah`-Literal).
`DevCommandDoc`-Einträge (Kategorie `DevCategory.EVENT`) + Langdrop-Beschreibungen:

| Command | Wirkung | Danger |
|---|---|---|
| `/dev woah echo spawn` | materialisiert den Hain sofort (Terraform + Orbs + Static-Displays), stage-unabhängig | CAUTION |
| `/dev woah echo flood [ticks]` | löst sofort eine Erinnerungs-Flut aus (Default 160) | SAFE |
| `/dev woah echo finale` | setzt deposited=5 und startet `EchoFinaleSequence` | CAUTION |
| `/dev woah echo reset` | Quest-State zurück, Actors/Einmal-Szenen despawnen, Overlay-Pool re-parken, Orbs respawnen; Terrain bleibt | CAUTION |
| `/dev woah echo status` | placed/deposited/finaleDone, Actor-, Orb-, Pool-, Loop-Zähler | SAFE |
| `/dev woah echo scene <id>` | spielt Szene `<id>` einmal neben dem Ausführenden (playOnce-Test) | SAFE |

## 10. Datei-für-Datei-Checkliste

**Server (neu, Package `dev/projecteclipse/eclipse/echo/`):**
- [ ] `EchoEntities.java` — DeferredRegister (`echo_ghost`, `echo_ghost_wolf`, `memory_orb`) + Attribute; Wiring-Aufruf `EchoEntities.register(modEventBus)` in `EclipseMod` (GhostEntities-Zeile daneben)
- [ ] `EchoGhostEntity.java` / `EchoGhostWolfEntity.java` — No-AI-Chassis + synced ACTION/FADE/CHILD/GLOW
- [ ] `MemoryOrbEntity.java` — interact-Logik, KIND/LIT, Cooldown
- [ ] `EchoGroveSites.java` — Stage-Listener + PendingRegistry-Placer + Koordinaten-Fallback
- [ ] `EchoGroveTerraformer.java` — Mulde, Palette, Bäume, Erinnerungs-Baum, Requisiten, Probe-Block, Static-Displays, Orb-Spawns
- [ ] `EchoScenes.java` + `EchoSceneData.java` — Keyframe-Records, JSON-Loader (`AddReloadListenerEvent`), Code-Defaults der 5 Szenen, Validator (Loop-Naht)
- [ ] `EchoSceneService.java` — SceneInstances, LOD-Fenster, Catmull-Rom-Sampler, playOnce, Prop-Lifecycle, Tag-Sweep
- [ ] `MemoryFloodService.java` — Timer, Flut-Timeline, Overlay-Push-Wellen, Note-Block-Fallback-Motiv
- [ ] `EchoOverlayBuilder.java` — deterministischer Overlay-/Finale-Blüten-Pool (Spawn-Batch, Park-Scale, Wellen-Pushes, Brightness-Steps)
- [ ] `EchoFinaleSequence.java` — 600t-Timeline, Gather-Keyframes, Loot, Persist
- [ ] `EchoGroveState.java` — SavedData `eclipse_echo_grove.dat`
- [ ] `EchoQuest.java` — Sammel-/Abgabe-Regeln (dünn; kann in MemoryOrbEntity aufgehen — Entscheidung beim Bauen)

**Netzwerk/Cues (bestehende Dateien anfassen):**
- [ ] `network/fx/FxCues.java` — `CUE_ECHO_FLOOD`, `CUE_ECHO_BLOOM_RAIN`, `CUE_ECHO_WHISPER`, `CUE_ECHO_ORB_COLLECT` (+ Javadoc-Verträge wie üblich)
- [ ] `network/fx/S2CEchoGrovePayload.java` (neu) + Registrierung in `network/EclipsePayloads.java` + Mailbox-Felder in `client/ClientStateCache.java`

**Client (neu, `client/echo/` + `client/entity/echo/`):**
- [ ] `client/echo/EchoGroveFx.java` — Grade-Row (static init), Loop-Fenster (#1–#3), Flut-Latch (Warmth-Ease, Musik, Ash-Delay), Wind-Loop optional
- [ ] `client/echo/EchoPhotonFxRows.java` — Row-Registrar (FMLClientSetupEvent)
- [ ] `client/entity/echo/EchoGhostRenderer.java`, `EchoGhostWolfRenderer.java`, `MemoryOrbRenderer.java`, `EchoRenderers.java`
- [ ] `veilfx/PhotonMobFx.java` — 2 Tabellenzeilen für `echo_orb_glow`/`_lit` (bestehende Datei, additive Zeilen)

**Assets:**
- [ ] `tools/photon/echo_grove_fx.py` — Generator für die 9 Assets aus §4.2 (+ `.fxproj`; `fxlib.py validate --lint` grün)
- [ ] `assets/eclipse/fx/echo_*.fx(+.fxproj)` — generiert
- [ ] `assets/eclipse/pinwheel/post/echo_grade.json`, `assets/eclipse/pinwheel/shaders/program/echo_grade.{json,fsh}`
- [ ] `assets/eclipse/textures/entity/echo_ghost.png`, `echo_ghost_glow.png`, `echo_ghost_wolf.png`
- [ ] `tools/music/treblo_generate.py` — Katalog-Einträge `echo_music_box`, `echo_grove` (+ optional `echo_wind`); `sounds.json`-Einträge; `music/EclipseMusicSounds.java` + `music/MusicCues.java` (Rung ECHO_GROVE)
- [ ] `registry/EclipseItems.java` — `memory_mote`, `echo_blossom` (+ Modelle/Texturen `assets/eclipse/models/item/`, `textures/item/`)
- [ ] `data/eclipse/loot_table/event/echo_grove_finale.json`
- [ ] `data/eclipse/echo_scenes/*.json` — die 5 Default-Szenen (identisch zu den Code-Defaults, als Referenz/Override-Vorlage)
- [ ] Langdrop `docs/plans_v3/langdrop/woah_echo.json` — Captions (`echo.eclipse.memory.0–4`), Items, Subtitles, Dev-Command-Docs (en+de)

**Worldgen/Dev (bestehende Dateien anfassen):**
- [ ] `worldgen/DiscMapDefaults.java` — Landmark-Zeile `eclipse:echo_grove` (0, 310, 30, 4)
- [ ] `worldgen/structure/VanillaLandmarks.java` — KEINE Änderung (kein Vanilla-Struktur-Mapping nötig; nur zur Kenntnis: `/locate` bleibt außen vor, Discovery-Flare kommt vom Landmark-Sweep)
- [ ] `devtools/dev/DevWoahEchoCommands.java` (neu) + Doc-Registrierung

**Tests/Abnahme:**
- [ ] `gametest/`-Smoke: Terraformer idempotent (2× materialize = identisch), Szenen-Validator, SavedData-Roundtrip
- [ ] Manuell: `/dev woah echo spawn` → Szenen sichtbar < 64; `flood` → Morph ohne Pop; Orb-Kette bis `finale`; reducedFx-Durchlauf; Iris-aktiv-Durchlauf (Grade weg, Rest intakt)

## 11. Risiken

1. **Frozen `disc_map.json` auf Bestands-Saves** — der neue Landmark fehlt dort;
   Mitigation ist der Code-Koordinaten-Fallback in `EchoGroveSites` (§2.1). Restrisiko:
   auf alten Saves prüft niemand Kollisionen gegen eventuell verschobene authored
   Punkte → Kollisionswarnung + `spawn`-Command als manueller Ausweg.
2. **~620-Display-Pool + ~26 Actor/Orb-Entities in einem Chunk-Cluster** — Tracking-
   Pakete beim ersten Sichtkontakt (Pool-Spawn-Fenster) können spiken; Mitigation:
   50/Tick-Batch + viewRange 2.0 + Park-Scale (fast unsichtbar = kein Overdraw). Muss
   auf einem vollen Server profiliert werden (`/dev woah echo status` + Spark).
3. **Veil-Budget (≤ 3 Pipelines, GRADE zuerst evicted):** Sturm-Volumetrik + Übergang +
   Glitchzone gleichzeitig verdrängen `echo_grade` — der Hain verliert dann seinen
   Kälte-Look, während FX/Displays weiterlaufen (akzeptiertes Degradieren, aber im
   Review als "known" dokumentieren, sonst wird es als Bug gemeldet).
4. **Sitz-/Kind-Posen im PlayerModel** sind Handarbeit im Renderer (kein Vanilla-Sit
   für Mobs): Gefahr von "Uncanny"-Posen; Mitigation: Posen minimal halten (gefaltete
   Beine + Körper-Offset), früh in-game reviewen, notfalls SIT durch stehende
   "Lehnen"-Pose ersetzen (nur Keyframe-Daten ändern, kein Codeumbau).
5. **Audio-Abhängigkeit Treblo:** ohne API-Key keine Spieluhr-OGGs; der
   Note-Block-Fallback (§6.1) MUSS von Anfang an mitgebaut werden, sonst blockiert
   der Woah-Moment auf Asset-Beschaffung. Zusätzlich: `music.echo_music_box` als
   RECORDS-Kategorie testen (User mit Musik-Slider 0 hören sonst nichts — bewusste
   Entscheidung: Flut bleibt auch stumm lesbar).
6. *(Bonus)* **Cue-Dedup:** `CUE_ECHO_FLOOD` wird alle 1800t am SELBEN BlockPos
   gefeuert — weit außerhalb jeder Asset-Laufzeit, aber das Custom-Leg muss
   `allowMulti` NICHT setzen (Standard-Dedup reicht); beim Finale (holdTicks=600
   direkt nach einer normalen Flut) den Vorgänger-Runtime-Fall testen.
