# PLAN-04 — RESONANZFELD (Kristall + Klang + Licht)

**Serie:** `docs/plans_v3/woah/` — Map-Features mit Woah-Faktor in der Klasse des volumetrischen
Sturms (`stormfx/` + `pinwheel/post/storm_volume.json`), aber jedes mit eigener Sinnesachse.
PLAN-04 ist die **Audio-Achse**: ein singendes Kristalltal mit Melodie-Rätsel.

**Alle Verweise in diesem Plan sind gegen den Code auf `cursor/project-eclipse` verifiziert**
(Datei:Zeile-genau, Stand dieses Plans). KEIN Java-Code hier — nur umsetzbare Spezifikation.

---

## 1. Konzept-Zusammenfassung + Fernwirkung

**Das Erlebnis.** Am äußersten Rand des Savannen-Sektors, in der Kristallsteppe
(`eclipse:crystal_steppe`), liegt ein terrageformtes Talbecken mit **9 riesigen
Kristall-Monolithen** (20–40 Blöcke, BlockDisplay-Kompositionen: Amethyst-/Tinted-Glass-Kern,
gedrehte Facetten-Schalen, vollhelle Glow-Nadel im Inneren, Photon-Aura). Am Boden echte,
begehbare Kristall-Cluster (`amethyst_cluster`, `budding_amethyst`, `WorldgenBlocks.LUSTER_CRYSTAL`,
`PRISM_SPROUTS`). **Jeder Monolith singt einen eigenen Pentatonik-Ton** — client-seitige
Distanz-Volume-Loops: wer auf einen Kristall zugeht, hört SEINEN Ton anschwellen; wer im
Talzentrum steht, hört den ganzen Akkord als schwebenden Chor. Zwischen benachbarten Kristallen
pulsieren **Lichtbahnen** (Photon-`beam_emitter` + wandernde Licht-Motes) im 2-Sekunden-Takt.

**Interaktion.** Schlägt ein Spieler einen Kristall an (Attack/Use auf dessen unsichtbare
`minecraft:interaction`-Hitbox), klingt er an: Note + Photon-Glitzer-Burst + Puls-Welle, die
über die Lichtbahnen zu den Nachbarn läuft, die nacheinander leiser mitklingen (**Kaskade**).
Nahe Spieler bekommen ein kurzes chromatisches Schimmern (Veil-Post, subtil, ≤ 12 Ticks).

**Rätsel.** In der Talmitte steht der **Stimmgabel-Altar** (Display-Komposition auf
Echtblock-Dais). Er spielt periodisch eine **Melodie aus 5 Tönen** vor — die zugehörigen
Kristalle leuchten dabei auf. Spielt die Gruppe die Sequenz durch Anschlagen der richtigen
Kristalle nach: **Finale** — alle 9 Kristalle fluten arpeggiert in den Grundakkord, alle
Bahnen leuchten voll, eine 120-Block-Lichtsäule schießt aus dem Altar, Photon-Glitzerregen
über dem ganzen Tal, Belohnung spawnt am Altar. Danach 10 Minuten Cooldown, neue
Zufallsmelodie. Fehlversuch: dissonanter Doppelton, rotes Flackern der Bahnen, Eingabe-Reset.

**Fernwirkung (der „von weitem"-Beweis).** Wichtige verifizierte Physik: BlockDisplays werden
nur innerhalb des **160-Block-Entity-Tracking-Horizonts** an Clients gesendet (dokumentiert in
`worldgen/stage/ExpansionBorderFx.java`, Klassen-Javadoc „Why the arm has to happen at FLYOVER
time"), egal wie groß `view_range` ist. Die Fern-Silhouette kann also NICHT von den Displays
kommen. Lösung wie beim Sturm: **client-getriebene Photon-Loops** auf Basis der einmal
gesyncten Feld-Geometrie (`S2CResonanceFieldPayload`, §3.6) — Photon-Partikel sind
client-verankert und tracken keine Entities. Im Band 160–400 Blöcke rendert der Client
3–4 haarfeine HDR-Lichtschäfte über den höchsten Kristallen (das
`CUE_SUMMON_BEACON`-Prinzip aus `network/fx/FxCues.java`: „mile-high hair-thin light column,
readable disc-wide") plus einen langsamen 8-Sekunden-Himmelspuls über dem Tal. Nachts ist das
Tal damit ein leuchtender violett-cyaner Fixpunkt am Horizont; wer näher kommt, sieht die
Schäfte in die echten Glow-Monolithen übergehen (LOD-Handover, §8).

**Warum das ein anderer Woah als der Sturm ist:** Der Sturm ist bedrohlich-volumetrisch
(Fog, Siege, Interior-Post). Das Resonanzfeld ist **kontemplativ und instrumentell** — der
Spieler SPIELT das Feature wie ein Instrument; das Woah kommt aus Klang-Raum-Kopplung
(Distanz-Chor), nicht aus Wetter.

---

## 2. Platzierung auf der Disc + Tal-Terraforming

### 2.1 Ort (gegen die authored Map verifiziert)

Quelle: `worldgen/DiscMapDefaults.java` (Landmark-Tabelle + Ring-Bänder) und
`worldgen/StageRadii.java` / `FrozenParams.DEFAULT_OVERWORLD_RADII` (D8-Radien
`{96, 150, 210, 280, 360, 440}`).

- **Anker: `(-395, -30)`**, r ≈ 396, Winkel ≈ 184° — mitten im Savannen-Sektor
  (157.5°–202.5°, `DiscMapDefaults.overworldDefaults()`), im Ring-Band
  `eclipse:crystal_steppe` (Savanna-Wedge, r > 380 — WG3-Band, siehe `OVERWORLD_RINGS`).
  Thematisch exakt passend: das Band shipped bereits `LUSTER_CRYSTAL` + `PRISM_SPROUTS`
  (`registry/WorldgenBlocks.java`).
- **Stage 5** (Disc-Radius 440): Anker + Tal-Radius 44 → 396 + 44 = 440 ≤ 440. Seam-Abstand
  ≥ 18° trotz ±5° Sektor-Wobble (`DiscMapData.SECTOR_WOBBLE_DEG`).
- Kollisionscheck gegen die D8-Landmarks: nächster Nachbar ist `eclipse:stronghold_emergence`
  (0, −400, r 24) mit ≈ 540 Blöcken Abstand; Fluss 2 endet bei (−425, −295), ≥ 260 Blöcke
  entfernt; die r=170-Playerdisc-Ringe liegen weit innen. Frei.

### 2.2 Anlieferung: Self-Enqueue statt Landmark-Tabelle

**NICHT** in `DiscMapDefaults.overworldDefaults()` eintragen: die Map wird pro Save eingefroren
(`FrozenParams`), Bestands-Saves bekämen das Feature nie. Stattdessen das
**`SkyLauncher`-Muster** (`worldgen/structure/SkyLauncher.java`, `maybeEnqueue` +
`enqueueIfNeeded`): `ResonanceFieldService` pollt alle 20 Ticks; sobald
`WorldStageService.stage(server, DiscProfile.OVERWORLD) >= 5`, wird eine
`StructurePendingRegistry.PendingSite` enqueued (`siteId = structureId =
"eclipse:resonance_field"`, dimension `OVERWORLD`, anchor aus §2.1 mit
`DiscTerrainFunction.surfaceY`, stage 5, footprint 88). Dedup über
`StructurePendingRegistry.wasPlaced` + pending-Scan — Restart-sicher, gratis Rift-Reveal +
`StructureFlightFx`-Delivery, exakt wie beim SkyLauncher. Placer-Registrierung:
`StructurePendingRegistry.registerAsyncPlacer("eclipse:resonance_field",
ResonanceFieldBuilder::placeSite)` in `ServerAboutToStartEvent`.

### 2.3 Tal-Terraforming (SitePrep + eigene Schale)

`ResonanceFieldBuilder.placeSite` (AsyncSitePlacer-Contract, `onComplete`/`onFailure`):

1. **Plateau**: `SitePrep.preparePlateau(level, profile, minX, minZ, maxX, maxZ, plateauY)`
   über 88×88 (Anker ± 44), `plateauY` = niedrigstes `DiscTerrainFunction.surfaceY` des
   Footprints (SkyLauncher-Schule „terraced shelf"). Vegetation/Schnee räumt SitePrep.
2. **Talschale** in `prepared.whenReady(...)`: radiale Absenkung — Mitte −7 Blöcke,
   Smoothstep auf 0 bei r = 36, dann flacher Randwall +2 bei r = 36..44 (liest als Kessel).
   Boden-Mix pro Säule (index²-gewichtete Palette, das `ExpansionBorderFx.BOULDER_BLOCKS`-
   Prinzip): `calcite` 45 %, `smooth_basalt` 25 %, `amethyst_block` 12 %, `tuff` 10 %,
   `WorldgenBlocks.LUSTER_CRYSTAL` 8 %.
3. **Begehbare Cluster** (Echtblöcke): 12–16 Boden-Cluster à 3–7 Blöcke — `budding_amethyst`
   als Kern, `amethyst_cluster` (facing up/side) obendrauf, `PRISM_SPROUTS`-Tufts drumherum;
   2–4 kniehohe `amethyst_block`+`LUSTER_CRYSTAL`-Zacken (2–4 Blöcke, echte Blöcke, damit man
   draufklettern kann). Deterministisch aus dem Site-Seed (`RandomSource.create(mapSeed ^
   0x5E50)`).
4. **Altar-Dais** in der Mitte: 5×5 `polished_basalt`-Kreis, Rand `calcite`-Slabs-Ersatz
   (volle Blöcke, keine Slabs nötig), Zentrum 1 `amethyst_block`; darüber die
   Stimmgabel-Displays (§5.4).
5. `SitePrep.touchBounds(...)` über die Schale, `SitePrep.finish(level, prepared)` —
   Relight/Resend läuft über `BudgetedBlockWriter` (kein Tick-Spike, verifiziert in
   `SitePrep`-Javadoc).
6. Monolith-Spawn (§3.1), Interaction-Spawn (§3.3), `ResonanceFieldData`-Write (§3.5),
   `FxAnchors.set(RESONANCE_CENTER, level, altarPos)` (neue frozen Anchor-Id im
   `veilfx/FxAnchors`-Stil), initiales `S2CResonanceFieldPayload`-Broadcast, `onComplete`.

**Schutz:** neue Zone in `protection/LandmarkProtection` — Zylinder r = 52 um den Anker,
`minY = plateauY − 12` bis Sky (die Monolithe + Bahnen dürfen nicht unterhöhlt werden;
Ausnahme devmode wie gehabt). Die Echtblock-Cluster am Boden bleiben absichtlich INNERHALB
der Zone — Amethyst-Farming ist hier nicht die Belohnung, das Finale ist es.

---

## 3. Server-Systeme

Neues Feature-Package: `src/main/java/dev/projecteclipse/eclipse/resonance/`.

### 3.1 Kristall-Bauer (`ResonanceFieldBuilder`)

**Layout:** 9 Monolithe auf einem unregelmäßigen Doppelring um den Altar — 5 auf r ≈ 26
(Winkel-Jitter ±12°), 4 auf r ≈ 15, Mindestabstand 9 Blöcke zueinander und 7 zum Altar.
Größenklassen: 2×L (36–40 Blöcke), 3×M (26–32), 4×S (20–24) — die L-Monolithe gegenüberliegend
(Silhouetten-Anker). Jeder Monolith global geneigt: 2–10° um eine zufällige XZ-Achse
(Quaternion aufs gesamte Schichten-Set, Details §5).

**Display-Spawn-Regeln** (alle aus verifizierten Vorbildern):

- Entity-Anker am Boden-Mittelpunkt, ALLE Geometrie in der Transformation
  (Translation/Rotation/Scale) — das „DisplayPlacerService law" aus
  `ExpansionBorderFx.poseOf`-Javadoc; Slab-Box auf den Offset zentrieren, damit Neigung um
  die eigene Achse rotiert.
- `DisplayBrightnessFx.set(display, block, sky, viewRange)`
  (`worldgen/stage/DisplayBrightnessFx.java`): Kern/Schalen 10/15, Glow-Nadeln 15/15,
  `viewRange = 4.0F` (4×64 = 256 Blöcke > 160er-Tracking-Horizont; das vanilla-Default 1.0
  wäre der „never drawn past 64 blocks"-Bug aus dem ExpansionBorderFx-Postmortem).
- Tag `eclipse_resonance_crystal` auf jedem Display + Stray-Sweep-Doktrin: Boot-Sweep in
  `ServerStartedEvent` + `EntityJoinLevelEvent`-Sweep gegen nicht in der Session gespawnte
  UUIDs — 1:1 das `ExpansionBorderFx.onServerStarted`/`onEntityJoin`-Paar, ABER: da das Feld
  permanent ist, gilt hier die Variante „discard + sofort deterministisch neu bauen aus
  SavedData" statt bloßem Discard (Selbstheilung, §3.5).
- Spawn-Budget: 4 Displays/Tick (Warteschlange im Builder) — bei ~110 Displays ist das Feld
  in < 2 s voll; kein `addFreshEntity`-Burst in einem Tick.
- Chunk-Residenz: Das Tal umfasst ~6×6 Chunks. KEIN Dauerticket — Displays persistieren
  (anders als die flüchtigen Border-Boulders werden sie NICHT discarded); vanilla speichert
  sie im Chunk. Nur der Builder nimmt während des Baus ein `TicketType`-Ticket
  (`eclipse_resonance_build`, TTL 600, das `ExpansionBorderFx.BOULDER_TICKET`-Muster).

### 3.2 Melodie-Statemachine (`ResonanceMelodyMachine`, eigene Klasse, vom Service getickt)

Zustände: `IDLE → TEACH → LISTEN → (FINALE | FAIL) → COOLDOWN → IDLE`.

- **IDLE**: Bahnen pulsieren im Grundtakt (rein client-seitig, §4.3). Alle 1200 Ticks UND
  wenn ≥ 1 Spieler < 40 Blöcke vom Altar: automatischer Übergang zu TEACH. Zusätzlich
  manuell: Use auf die Altar-Interaction startet TEACH sofort (Cooldown 100 Ticks gegen
  Spam-Klicks).
- **TEACH** (Vorspielen): Melodie = 5 Töne, gezogen aus den 9 Tonstufen ohne Direktwiederholung,
  `RandomSource`-Seed aus `ResonanceFieldData.melodySeed` (persistiert → Restart-stabil).
  Beat-Raster 14 Ticks pro Note (0,7 s). Pro Beat: Server-`level.playSound` der Note AN DER
  KRISTALLPOSITION (Positionsortung! §6) + `FxPayloads.sendFxEvent(level,
  CUE_RESONANCE_STRIKE, kristallTopMid, toneIndex, 1.0F, 96.0D)` (b = 1 → Teach-Glow ohne
  Glitzer-Burst) + Brightness-Puls (§5.5). Nach der Sequenz 20 Ticks Pause → LISTEN.
- **LISTEN** (Input-Fenster): 600 Ticks (30 s). Jeder Kristall-Strike von IRGENDEINEM Spieler
  zählt (Koop bewusst erlaubt — Reihum-Spielen ist der soziale Woah). Richtige Note →
  Fortschritts-Index +1, Strike-FX normal + der getroffene Kristall hält 20 Ticks Glow.
  Falsche Note → FAIL. Timeout → zurück zu IDLE (kein FAIL-Sting, nur Ausklingen).
  Nicht-Melodie-Strikes VOR dem ersten TEACH (Zustand IDLE) sind frei: Note + Kaskade
  spielen immer — das Tal ist auch ohne Rätsel ein Instrument.
- **FAIL**: Dissonanz-Sting (§6.4) + `CUE_RESONANCE_FAIL` (rotes Bahnen-Flackern, 20 Ticks)
  + Eingabe-Reset. `failCount++`; die Melodie bleibt DIESELBE für 3 Fehlversuche (Lernbarkeit),
  ab dem 4. wird neu gewürfelt. Danach zurück zu TEACH (auto, nach 40 Ticks).
- **FINALE**: §7.2-Sequenz (Arpeggio-Flut → Akkord → Lichtsäule → Belohnung), Dauer 160 Ticks,
  dann COOLDOWN.
- **COOLDOWN**: 12000 Ticks (10 min), persistiert als absolute `gameTime` in
  `ResonanceFieldData.cooldownUntil`. Währenddessen: kein TEACH, Bahnen pulsieren gedimmt,
  freies Anschlagen bleibt. Ablauf → `melodySeed` neu würfeln → IDLE.

**Kaskade** (immer, in jedem Zustand): Beim Strike von Kristall K wird eine Hop-Queue gefüllt:
Nachbarn von K (Adjazenz §3.6) mit Delay 3 Ticks/Hop, Volume-Faktor 0,55 pro Hop, max. Tiefe 2
(K → Nachbarn → deren Nachbarn), Besuchs-Set gegen Zyklen, Queue-Cap 32 Einträge. Pro Hop:
leisere Note am Zielkristall + `CUE_RESONANCE_PULSE` (Bahnen-Wanderpuls, §4.4) + Mini-Glowpuls.
Strike-Cooldown pro Kristall 8 Ticks (Doppelklick-Schutz, verhindert Kaskaden-Spam).

### 3.3 Hit-Erkennung — Entscheidung: `minecraft:interaction` pro Kristall

**Problem:** `Display.BlockDisplay` hat server-seitig KEINE Hitbox — weder Attack- noch
Pick-Erkennung ist möglich (im ganzen Repo wird nie ein Display angeklickt; alle klickbaren
Set-Pieces nutzen Interactions).

**Entscheidung: 1 `minecraft:interaction`-Entity pro Monolith + 1 für den Altar.**
Begründung mit Code-Referenz: exakt das shipped Muster des SkyLaunchers —
`SkyLauncher.spawnPadInteraction` (NBT-Spawn über `EntityType.loadEntityRecursive`, weil
vanilla keine public width/height-Setter hat, `response=false`), Empfang über
`PlayerInteractEvent.EntityInteract` mit Tag-Check (`SkyLauncher.onEntityInteract`), plus
200-Tick-Self-Heal gegen `/kill` (`SkyLauncher.ambientAt`, „A /kill'ed interaction would
silently brick the pad"). Verworfen: unsichtbare Hitbox-Mobs (ArmorStand/Slime) — brauchen
AI-/Kollisions-Unterdrückung, triggern Anticheat-/Contract-Pfade (`ContractService.
onAttackEntity` hört auf `AttackEntityEvent` gegen Lebewesen) und haben Schadens-Semantik;
Interaction ist die von Mojang für genau diesen Zweck gebaute, kollisionsfreie Klick-Falle.

Spezifikation:

- Maße: width = Basis-Girth + 1,5 (3,5–6,5), height = min(Monolith-Höhe × 0,55, 14) — man
  schlägt den unteren/mittleren Schaft an; eine 40 Block hohe Hitbox würde Blickwinkel weit
  über dem Tal abfangen. Position: Boden-Mittelpunkt des Monolithen.
- Tags: `eclipse_resonance_hitbox` + `eclipse_resonance_idx_<n>` (n = Kristallindex 0–8;
  Index-Auflösung ohne UUID-Persistenz). Altar: `eclipse_resonance_altar`.
- **Anschlagen (links)**: `AttackEntityEvent` (Precedent: `ContractService.onAttackEntity`,
  `progression/ModGate.onAttackEntity`) — Target-Tag prüfen, Event canceln (kein Schaden,
  kein Arm-Swing-Exploit), `ResonanceFieldService.strike(player, idx)`.
- **Use (rechts)** auf Kristall = derselbe Strike (Accessibility / Konsolen-Bindings), auf
  Altar = TEACH-Replay; via `PlayerInteractEvent.EntityInteract`, MAIN_HAND-Guard wie
  `SkyLauncher.onEntityInteract`.
- Self-Heal alle 200 Ticks (nur wenn Feld gebaut & Chunk geladen): fehlende Interactions aus
  `ResonanceFieldData` neu spawnen — SkyLauncher-Muster inkl. Log-Zeile.

### 3.4 Service (`ResonanceFieldService`)

`@EventBusSubscriber`, Server-Events: `ServerAboutToStartEvent` (Placer + Listener
registrieren), `ServerStartedEvent` (Boot-Catch-up-Enqueue + Display-Selbstheilung),
`ServerTickEvent.Post` (siehe Budget), `ServerStoppedEvent` (statics leeren),
`EntityJoinLevelEvent` (Stray-Sweep), `AttackEntityEvent` + `PlayerInteractEvent.EntityInteract`
(§3.3), `PlayerEvent.PlayerLoggedInEvent` (Payload-Resync an den Joiner — das
`FxAnchors.onPlayerLoggedIn`-Muster).

### 3.5 SavedData (`ResonanceFieldData extends SavedData`)

Muster: `SkyLauncher.LauncherData` (eigene kleine Datei `data/eclipse_resonance_field.dat`
im Overworld-Storage; plans_v3 §2.5 verbietet neue Felder auf Shared State). Inhalt:

- `built` (boolean) + `anchor` (BlockPos) + `plateauY`;
- 9 Monolith-Records: Basis-BlockPos, Höhenklasse, Höhe, Girth, Neigungs-Quaternion-Seed,
  Schichten-Seed, `toneIndex` (0–8), Nachbarliste (2–3 Indizes);
- Statemachine: `melodySeed` (long), `melody` (int[5], redundant zur Ableitung — Debugbarkeit),
  `progressIndex`, `failCount`, `state` (enum ordinal), `stateSince` (gameTime),
  `cooldownUntil` (gameTime), `solveCount` (für Erst-Bonus §7.3);
- KEINE Entity-UUIDs: Displays und Interactions werden über Tags + Radius-Query aufgelöst
  und bei Fehlbestand deterministisch aus den Seeds neu gebaut (Selbstheilung schlägt
  UUID-Buchhaltung; ein `/kill @e[tag=eclipse_resonance_crystal]` heilt in ≤ 200 Ticks).

### 3.6 Wire: `S2CResonanceFieldPayload` + Cues

- **`S2CResonanceFieldPayload`** (neu in `network/fx/`, registriert in
  `FxPayloads.register` neben `S2CAnchorPayload`): Feld-Geometrie + Zustand — anchor,
  Liste (basePos, höhe, toneIndex), Kanten-Liste (Indexpaare, = Nachbargraph: pro Kristall
  die 2 nächsten + Ring-Schluss, einmalig im Builder berechnet, ~12 Kanten), state-Enum,
  cooldown-Rest. Gesendet: bei Build, bei Statewechsel, bei Login. Kein Melodie-Inhalt im
  Payload (der Client braucht ihn nicht; Teach-Glows kommen als Einzel-Cues — leak-frei).
- **Neue `FxCues`-Konstanten** (Namespace-Gesetz `eclipse:fx/cue/…`, Rows im neuen
  Client-Registrar `veilfx/ResonancePhotonFxRows`):
  - `CUE_RESONANCE_STRIKE` — Position-Lane am Kristall-Top-Mid; `a` = toneIndex,
    `b` = 0 Spieler-Strike / 1 Teach-Puls (nur Glow-Flare, kein Glitzer). Range 96.
    Row-Leg erzwingt `allowMulti` (schnelle Strike-Folgen, das `CUE_GLITCH_POP`-Gesetz).
  - `CUE_RESONANCE_PULSE` — Kaskaden-Hop; pos = Quellkristall-Top, `a` = Yaw zum Ziel (Grad,
    das `CUE_WARDEN_VOLLEY_TELEGRAPH`-Rotations-Muster), `b` = Hop-Länge in Blöcken
    (Executor-Scale). Range 96, `allowMulti`.
  - `CUE_RESONANCE_FAIL` — pos = Altar; rotes Bahnen-Flackern + Dissonanz-Staub. Range 96.
  - `CUE_RESONANCE_FINALE` — pos = Altar; `a` = 0. Range 256 (das Tal + Umfeld). Lichtsäule,
    Glitzerregen, Bahnen-Flut in EINEM Asset (Start-Delays im Asset gestaffelt, das
    `CUE_DAWN_TOLL`-Prinzip „pacing staged INSIDE the asset").

### 3.7 Tick-Budget (Server)

- Gate ganz vorn: Feld nicht gebaut ODER kein Spieler < 128 Blöcke vom Anker (Check alle
  20 Ticks, gecacht) → früher Return. Nur `cooldownUntil`-Vergleich läuft immer (1 long).
- Aktiver Betrieb: Statemachine = O(1)/Tick; Kaskaden-Queue ≤ 32, 1 Hop = 1 playSound +
  1 sendFxEvent + ≤ 2 Brightness-Roundtrips.
- Brightness-Pulse: ≤ 3 `DisplayBrightnessFx`-Roundtrips pro Beat (das „≤ 3 pro
  piece life"-Craft-Law aus `DisplayBrightnessFx`-Javadoc wird pro EVENT interpretiert:
  auf/hell/ab), nie per-Tick-Rampen.
- Idle-Atmung der Schalen (optional, §5.3): Round-Robin 2 Displays/Tick mit 60-Tick-
  Interpolationsfenstern, NUR wenn Spieler < 96 Blöcke — Keyframe-Lead-Regel („push the pose
  this interpolation window ENDS on", `ExpansionBorderFx.animate`).
- SavedData `setDirty` nur bei Statewechsel/Strike-Fortschritt, nicht pro Tick.

---

## 4. Client-Systeme

Neues Client-Package: `client/resonance/` (+ Registrar in `veilfx/`).

### 4.1 Layout-Cache (`client/resonance/ResonanceFieldClient`)

Empfängt `S2CResonanceFieldPayload` (Handler-Branch in `FxPayloads`), hält Geometrie +
Zustand als Client-Mirror (das `FxAnchors.CLIENT_ANCHORS`-Muster), cleart bei
`ClientPlayerNetworkEvent.LoggingOut`. Alle folgenden Controller lesen NUR hieraus.

### 4.2 Distanz-Volume-Singen (`client/resonance/ResonanceChoir`)

Referenz-Pattern verifiziert: `client/sound/SanctumHum.java` — `AbstractTickableSoundInstance`
mit per-Tick Volume-Envelope, `ClientTickEvent.Post`-Treiber, `soundStartedThisVisit`-Guard,
`SILENT_STOP_TICKS`-Selbststopp, `LoggingOut`-Teardown. Davon abgeleitet, mit drei Deltas:

- **Ein Voice-Instance pro Kristall**, positional am Kristall-Mittelpunkt (Top-Drittel,
  dort „sitzt" die Stimme), Pitch = Pentatonik-Tabelle §6.1, `SoundSource.AMBIENT`
  (kollidiert nicht mit `music/MusicManager`s MUSIC-Kanal).
- **Attenuation NONE + manuelle Distanzkurve**: vanilla-Rolloff würde bei volume ≤ 1 schon
  bei ~16 Blöcken enden; deshalb Attenuation auf NONE setzen (Feld existiert auf
  `AbstractSoundInstance`) und die Lautstärke rein im `tick()` fahren:
  `vol = 0.65 × clamp(1 − (dist − 4)/44, 0, 1)^1.5`, per-Tick-Lerp 0.05 (SanctumHum-
  `VOLUME_STEP`). 3D-Panning bleibt erhalten (relative=false).
- **Voice-Budget + Hysterese**: engage < 44 Blöcke, release > 52; max. **4 gleichzeitige
  Voices** (die 4 nächsten Kristalle; beim Überschreiten wird die leiseste gefadet und
  gestoppt). Im Talzentrum: 4 Stimmen = Akkordbett, gewollt.
- **Sound-Event**: neu `eclipse:ambient.crystal_voice` in `registry/EclipseSounds` +
  `sounds.json`-Eintrag (weicher Glas-Bogen-Dronetone, loopbar, ~6 s). Bis das .ogg
  geliefert ist: Fallback `EclipseSounds.AMBIENT_LIMBO_LOOP` pitched — exakt das
  dokumentierte selbstheilende Fallback aus `SanctumHum.resolveHum()`.
- Sing-LOD hart: **nur < 48 Blöcke** (siehe §8) — jenseits singt nichts, dort trägt die
  Fern-Silhouette.

### 4.3 Photon-FX-Controller (`client/resonance/ResonanceFieldFx`)

Per-Anchor-Loops laufen NICHT über Registry-Loop-Rows (das „STORM_CROWN_HALO not a registry
row"-Gesetz, dokumentiert am NEWFX-D3-Kommentar in `FxCues`): der Controller hält eigene
`PhotonBridge.LoopHandle`s (`spawnLoop`/`stopLoop`, `veilfx/PhotonBridge`) mit
Hysterese-Fenstern, released bei reducedFx/Dimensionswechsel/Logout (WINDOWED-Loop-Gesetz,
`PhotonFxRegistry`-Javadoc). Executor-Gesamtbudget beachten:
`PhotonBridge.MAX_LIVE_EXECUTORS = 24` — Feld-Kontingent ≤ 12 (Tabelle §8).

**Asset-Liste** (Generator `tools/photon/resonance_fx.py` mit `fxlib.py`; jede Datei mit
`.fxproj`-Sibling via `write_fxproj`, CullBox PFLICHT — 45 Dateien ohne CullBox sind laut
`PHOTON_EDITOR_CAPABILITIES.md` §5.12 der „billigste Perf-Fix", wir starten sauber):

| Asset (`assets/eclipse/fx/`) | Typ | Emitter-Spec (Kurzform) |
|---|---|---|
| `resonance_crystal_aura.fx` | Loop, per-Kristall | `empty`-Root + (a) particle: cylinder-Shell r≈1.6 (Executor-Scale je Klasse), Rate 5/s, Billboard violett HDR 1.4, `lights` block 12, velocityOverLifetime +0.12y, sizeOverLifetime fade; (b) particle: dot, Burst 3 alle 2 s, Facetten-Glints HDR 2.2, DISTANCE-Sort. maxParticles ≤ 60, prewarm, CullBox 6×h×6 |
| `resonance_bahn.fx` | Loop, per-Kante | (a) `beam_emitter`: `end` lokal [0,0,−1] (Executor rotiert per Yaw, skaliert auf Kantenlänge — `FX_FORMAT.md` §4.1 „end: Vector3f local-space endpoint"), width-Curve 0.22→0.42 pulsierend auf 40 t-Loop, Gradient violett→cyan HDR 1.8, raycast NONE (Bahn spannt Top zu Top); (b) particle `function`-Shape (z = −t·L): 8/s wandernde Licht-Motes Richtung Ziel, `lights` block 13. maxParticles ≤ 40, CullBox L×4×4 |
| `resonance_strike_burst.fx` | One-Shot 30 t | Burst 22 Glitzer (StretchedBillboard, HDR 2.4, leichte Gravity), 1 Horizontal-Ring am Fuß, 1 kurzer vertikaler Flash-Beam (8 Blöcke, 6 t). `allowMulti` via Row-Leg |
| `resonance_pulse_hop.fx` | One-Shot 12 t | 1 heller Bead: `function`-Shape gleitet lokal −Z (StretchedBillboard, HDR 2.6) + 4 Trail-Glints; Executor: Yaw aus `a`, Scale aus `b` |
| `resonance_fail_flicker.fx` | One-Shot 20 t | REVERSE_SUB-Dunkel-Pass + rotes Ring-Flackern (2 Pulse) + fallende Funken — GLITCH-Palette (FX-STYLE-GUIDE §1.3) |
| `resonance_finale_column.fx` | One-Shot 160 t | (a) beam vertikal 120 Blöcke, width 3→0, HDR 3.0; (b) Glitzerregen: circle r=26, 100/s für 6 s, physics collide + removedWhenCollided, `lights` 14; (c) Boden-Schockring; (d) Kronen-Sternburst. Delays im Asset gestaffelt (0/10/10/20 t). maxParticles ~700, CullBox 60×130×60 |
| `resonance_far_shaft.fx` | Loop, Fern-LOD | 1 hauchdünner vertikaler HDR-Schaft (h ≈ Kristallhöhe × 2), Breite distanz-skaliert vom Row-Leg (das `CUE_SUMMON_BEACON`-Rezept) + 2 träge Orbit-Glints. maxParticles ≤ 10 |
| `resonance_far_pulse.fx` | Loop, Fern-LOD | 8-s-Periode: ein schwacher Himmels-Dome-Puls über dem Tal (Horizontal-Ring r 40, HDR 1.3, langsame Expansion + Fade). maxParticles ≤ 12 |

**Registry-Rows** (`veilfx/ResonancePhotonFxRows`, `FMLClientSetupEvent`): 4 One-Shot-Rows
(STRIKE/PULSE/FAIL/FINALE), alle `Mode.LAYER` mit Quasar-Fallback-Emittern
(`assets/eclipse/quasar/emitters/resonance_*` — einfache END_ROD-/Glow-Kompositionen als
photon-lose Baseline, Degradations-Gesetz aus `PhotonFxRegistry`-Javadoc). STRIKE/PULSE mit
Custom-`PhotonLeg` (Rotation/Scale/allowMulti); Kanal `FxBudget.Channel.BURST`.

### 4.4 Bahnen-Fenster + Takt

Bahn-Loops nur für Kanten, deren BEIDE Enden < 64 Blöcke vom Spieler liegen (engage 64 /
release 72), Budget max. 6 Bahn-Handles (nächste zuerst). Der Puls-Takt steckt im Asset
(40-t-Loop); Kaskaden-/Finale-Beats kommen als zusätzliche One-Shot-Cues obendrauf — kein
Uhr-Sync über die Wire nötig.

### 4.5 Veil-Licht (verifiziert: Veil 4.3.0 kann Punktlichter)

`foundry.veil.api.client.render.light.data.PointLightData` +
`VeilRenderSystem.renderer().getLightRenderer().addLight(...)` — shipped Precedents:
`stormfx/StormFxClient` (Zeile ~1083), `veilfx/SupplyBeamClient` (pulsierendes violettes
Licht, Radius-Konstante + Handle-Lifecycle), `client/ShipDoorGlow`. Für das Feld:

- ≤ **2 Kristall-Lichter** (die 2 nächsten Monolithe < 40 Blöcke, nachts bzw. skyDarken ≥ 9;
  violett, Radius 18, Brightness atmend mit dem Bahn-Takt) — Handle-Verwaltung nach dem
  `SupplyBeamClient`-Muster (add/remove bei Fensterwechsel, LoggingOut-Teardown).
- **1 Finale-Licht** (Altar, Radius 40, 160 t Envelope) während `CUE_RESONANCE_FINALE`.
- Fallback ohne Veil-Renderer/Iris: nichts — die Glow-Displays (15/15) + `lights`-Module der
  Photon-Partikel tragen die Nacht-Lesbarkeit allein (das ist das dokumentierte
  „Fake-Glow"-Verhalten, `PHOTON_EDITOR_CAPABILITIES.md` §2.2/§2.6).

### 4.6 Veil-Post-Shimmer (optional, subtil)

Neue Pipeline `eclipse:resonance_shimmer`: `assets/eclipse/pinwheel/post/resonance_shimmer.json`
+ `pinwheel/shaders/program/resonance_shimmer.fsh` — chromatischer Offset ≤ 2 px, radial vom
Bildzentrum, Uniform `ShimmerAmount`. Vorlage: `altar_aberration.json`/`.fsh` (exakt dieser
Effekt-Typ shipped bereits). Registrierung als `VeilPostController.PipelineSpec` mit
`PipelinePriority.FEATURE`; Activation-Predicate: Envelope > 0, gesetzt von
`ResonanceFieldFx` bei Strike < 16 Blöcke (Peak 0.35, 12 t Abkling) und Finale < 48 Blöcke
(Peak 0.6, 40 t). Iris-Gate + `veilPostFx`-Toggle erledigt der Controller
(`EclipseIrisState.postFxAllowed`, `VeilPostController`-Javadoc). reducedFx: Predicate false.

---

## 5. BlockDisplay-Layout je Kristallgröße

Deterministisch aus dem Schichten-Seed; Bau-Mathematik nach dem verifizierten
`ExpansionBorderFx.buildBoulder`-Vorbild (per-Achse-Größen, Index²-Palette, zentrierte
Rotation), aber vertikal gestreckt und geneigt.

### 5.1 Paletten

- **Kern** (index²-gewichtet): `amethyst_block` 55 %, `tinted_glass` 30 %,
  `purple_stained_glass` 10 %, `WorldgenBlocks.LUSTER_CRYSTAL` 5 % (Cyan-Akzent, Licht 10).
- **Schalen**: `tinted_glass` 60 %, `purple_stained_glass` 25 %, `amethyst_block` 15 %.
- **Glow-Nadel**: `amethyst_block` mit Brightness-Override 15/15 (liest als leuchtender
  violetter Kern; kein TextDisplay-Trick nötig — Option bleibt als Fallback im Code-Kommentar,
  falls der Look zu flächig gerät).
- **Sockel**: `smooth_basalt`/`calcite`-Skirt-Display, halb im Boden (verkauft die Verwurzelung
  — die Anti-„sky box"-Lektion aus dem ExpansionBorderFx-v1-Postmortem).

### 5.2 Schichten-Spec pro Klasse

| Klasse | Höhe | Basis-Girth | Kern-Segmente | Facetten-Schalen | Glow | Sockel | Displays gesamt |
|---|---|---|---|---|---|---|---|
| S (×4) | 20–24 | 3.0–3.8 | 3 (je ~40 % Höhe, 25 % Überlappung, Taper auf 0.35) | 4 | 1 | 1 | 9 |
| M (×3) | 26–32 | 3.8–4.8 | 4 | 5 | 1 | 1 | 11 |
| L (×2) | 36–40 | 4.8–6.0 | 5 | 7 | 2 (unten/oben) | 1 | 15 |

Summe Monolithe: 4×9 + 3×11 + 2×15 = **99 Displays**; + Altar (§5.4) 6 + Sockel-Deko ≈
**≤ 110 Displays** gesamt (Vergleich: `CreditsFormationAct.TOTAL` = 1800+ — wir liegen bei 6 %).

- **Kern-Segmente**: per-Achse-Boxen (x/z = Girth × Taper(t) × Jitter 0.8–1.2, y = Segment-
  Höhe), jedes Segment 4–10° um Y gegeneinander verdreht, XZ-Jitter ≤ Girth × 0.15,
  Spitzen-Segment pyramidal schmal (Taper 0.25) und +6° zusätzlich geneigt — die Silhouette
  darf nie als skalierter Würfel lesen (Boulder-Lektion).
- **Facetten-Schalen**: schmale lange Boxen (0.5–0.9 × 55–75 % Höhe × 0.5–0.9), auf
  Golden-Angle-Offsets (2.39996 rad, die `SkyLauncher.GOLDEN_ANGLE`-Konstante als Vorbild)
  um den Kern verteilt, Radius Girth × 0.55, je 3–8° nach außen gekippt, `tinted_glass`
  überwiegend → Tiefen-Layering (man sieht den hellen Kern DURCH die dunklen Glasfacetten).
- **Globale Neigung**: ein Quaternion (2–10°, zufällige XZ-Achse) multipliziert auf alle
  Segment-Rotationen + Offsets — der ganze Kristall lehnt, nicht nur die Spitze.

### 5.3 Idle-Atmung (optional, LOD-gebunden)

Nur Schalen-Displays, nur < 96 Blöcke Spielernähe: 60-Tick-Interpolationsfenster, Scale-Puls
±1.5 %, Round-Robin 2 Displays/Tick (§3.7). Kern/Glow/Sockel statisch — Ruhe ist Teil des Looks.

### 5.4 Stimmgabel-Altar (Display-Komposition)

Auf dem 5×5-Dais (§2.3): 2 vertikale Zinken (je 1 Display `polished_deepslate`,
0.6×4.5×0.6, ±0.9 versetzt, 3° V-Spreizung) + 1 Quersteg (`amethyst_block` 2.2×0.5×0.7) +
1 schwebender Resonanzkern (Glow-`amethyst_block` 0.5³, 15/15, zwischen den Zinken) +
2 `tinted_glass`-Manschetten. 6 Displays, Tag `eclipse_resonance_altar_deco`. Beim TEACH
pulst der Resonanzkern (Brightness-Puls-Regel §3.7); beim Finale ersetzt die Photon-Säule
jede Display-Animation.

### 5.5 Glow-Puls-Mechanik (Teach/Strike/Kaskade)

Puls = Brightness-Roundtrip-Paar auf der Glow-Nadel des Zielkristalls: 15/15 → (Puls) alle
Schalen kurz 12/15 → zurück. Max. 3 Roundtrips pro Event (Craft-Law), Puls-Sichtbarkeit
übernimmt primär der Photon-Flare aus `CUE_RESONANCE_STRIKE` (b=1) — Brightness ist nur der
Basis-Layer, damit auch reducedFx-/photonlose Clients das Vorspielen LESEN können
(Anti-Frust §7.4, Degradations-Gesetz).

---

## 6. Sounds — konkrete Ton-Zuordnung

### 6.1 Pentatonik-Tabelle (A-Dur-Pentatonik über 1,5 Oktaven, 9 Stufen)

Ein-Ort-Wahrheit in neuer gemeinsamer Klasse `resonance/ResonanceTones` (Server spielt,
Client pitcht die Choir-Loops): Halbton-Offsets relativ Pitch 1.0:
`{−12, −10, −8, −5, −3, 0, +2, +4, +7}` → Pitches
`{0.500, 0.561, 0.630, 0.749, 0.841, 1.000, 1.122, 1.260, 1.498}` (= A3 B3 C#4 E4 F#4 A4 B4
C#5 E5 auf dem Bell-Timbre). Alles im validen Pitch-Fenster 0.5–2.0. Zuordnung: tiefste Töne
auf die L-Monolithe, höchste auf die S-Klasse (Masse = Tiefe, intuitiv lesbar).

### 6.2 Anschlag-Klang (Strike, Teach-Beat, Kaskaden-Hop)

Layering pro Note, alle positional am Kristall (Server `level.playSound`):

- `SoundEvents.NOTE_BLOCK_BELL`, `SoundSource.RECORDS`→ nein: **`SoundSource.BLOCKS`**,
  vol 1.4 (Strike) / 0.9 (Teach) / 0.55 × 0.55^hop (Kaskade), pitch aus §6.1.
  **Mapping-Gotcha (1.21.1 Mojang-Mappings): die `NOTE_BLOCK_*`-Konstanten sind
  `Holder<SoundEvent>`, nicht `SoundEvent`** — die `Level.playSound`-Überladung mit
  `Holder<SoundEvent>` verwenden (im Repo bislang ungenutzt; `ScareScripts` nutzt
  `BELL_BLOCK` als plain Event — nicht verwechseln).
- `SoundEvents.AMETHYST_BLOCK_CHIME` (plain `SoundEvent`, Precedents überall in
  `wand/WandPowers`), gleicher Pitch, vol × 0.6 — gibt dem Bell den Kristall-Schimmer.
- Nur Spieler-Strike zusätzlich: `SoundEvents.AMETHYST_CLUSTER_HIT` vol 0.8 (taktiles Klick).

### 6.3 Finale-Akkord

1. **Arpeggio-Flut**: alle 9 Kristalle spielen ihren Ton in 2-Tick-Staffel (tief → hoch),
   vol 1.2 — 18 Ticks Klangwelle durchs Tal.
2. **Akkord** bei t+24: Kristalle mit Offsets {−12, −5, 0, +7} (A-E-A-E-Quintstapel)
   gleichzeitig, vol 1.6, + `SoundEvents.AMETHYST_BLOCK_RESONATE` pitch 1.0 vol 1.2 am Altar
   + `SoundEvents.BELL_RESONATE` pitch 0.5 vol 0.9 (Sub-Fundament).
3. t+60: `EclipseSounds.EVENT_EMERGE` vol 0.7 pitch 0.9 am Altar (der shipped
   „Release"-Swell) unter dem Photon-Glitzerregen.

### 6.4 Fehlversuch (Dissonanz)

`NOTE_BLOCK_DIDGERIDOO` (Holder!) Doppelton pitch 0.53 + 0.56 gleichzeitig (kleine Sekunde im
Bass, vol 1.2) + `SoundEvents.AMETHYST_BLOCK_BREAK` pitch 0.7 vol 0.8 + 2 Ticks später
`AMETHYST_BLOCK_CHIME` pitch 0.51 vol 0.5 — kurz, hässlich, eindeutig, nicht bestrafend laut.

### 6.5 Singen (Loop)

§4.2: neues Event `eclipse:ambient.crystal_voice` (Registrierung in `EclipseSounds` nach dem
`AMBIENT_LIMBO_LOOP`-Muster, `sounds.json`-Eintrag mit `"stream": false`, Asset-Ask im
Asset-Ledger); pro Kristall gepitcht nach §6.1. Fallback bis Asset-Lieferung:
`AMBIENT_LIMBO_LOOP` × Pitch — dokumentiertes `SanctumHum`-Selbstheilungs-Muster.

---

## 7. Gameplay

### 7.1 Melodie-Rätsel-Ablauf (Spielersicht)

1. Ankommen → Kristalle singen distanzbasiert, Bahnen pulsieren; freies Anschlagen macht
   sofort Musik + Kaskade (das Tal belohnt Neugier VOR dem Rätsel).
2. Altar erreicht / 60-s-Timer → Stimmgabel klingt an, 5 Kristalle leuchten nacheinander auf
   und spielen die Melodie (14 Ticks/Note). Actionbar-Caption
   `eclipse.resonance.caption.teach` („Die Stimmgabel singt vor …" — Lang-Keys §10).
3. Spieler schlagen die Kristalle in Reihenfolge an — jeder Treffer bestätigt hörbar/sichtbar;
   der Fortschritt ist team-geteilt (Koop by design).
4. Richtig komplett → Finale (§7.2). Falsch → §6.4 + rotes Flackern + Reset der Eingabe;
   Melodie bleibt 3 Versuche stabil, Altar-Use spielt sie jederzeit erneut vor.

### 7.2 Finale

160-Tick-Sequenz (Server-Regie in `ResonanceMelodyMachine`): t0 Arpeggio + `CUE_RESONANCE_FINALE`
(Photon-Säule/Regen/Ring, Bahnen-Flut client-seitig via State-Payload FINALE) + Veil-Finale-
Punktlicht + Shimmer-Envelope; t24 Akkord; t40 Belohnungs-Drop; t160 → COOLDOWN-State-Broadcast.
Kein Screenshake-Overkill: einmal `S2CShakePayload.shake(0.18F, 14)` an Spieler < 64
(Precedent `ExpansionBorderFx.raiseFx`).

### 7.3 Belohnung (konkret)

- **Jeder Solve**: 6 × `EclipseItems.UMBRAL_SHARD` als ItemEntity am Altar (Team-Ökonomie —
  Shards fließen in den Altar-Pool, `economy/ShardEconomy`-Bank-Loop) + 300 XP als Orbs,
  gesplittet über die Spawn-Punkte der 9 Kristallfüße (Einsammeln = nochmal durchs Tal laufen).
- **Erst-Solve pro Welt** (`solveCount == 0`): zusätzlich 1 × `EclipseItems.VITAE_SHARD`
  (Epic-Drop, shipped Item) + Server-weite Caption `eclipse.resonance.caption.first_solve`.
- Statistik-Hook: `analytics`-Zähler `resonance_solved` (bestehendes Zähler-Muster, vgl.
  `shards_banked` in `ShardEconomy`-Javadoc) — Award-Anbindung später möglich, hier nur zählen.

### 7.4 Anti-Frust

- Vorspielen wiederholbar (Altar-Use, kostenlos, 100-Tick-Anti-Spam).
- Beim TEACH leuchtet der Zielkristall deutlich (Photon-Flare + Brightness-Basis-Layer §5.5 —
  funktioniert auch reducedFx/photonlos).
- Während LISTEN zeigt der NÄCHSTE erwartete Kristall einen dezenten Dauer-Glow (nur
  Brightness 15/15→Schalen 12, kein Photon — Hinweis, kein Lösungsautomat); abschaltbar via
  Config-Flag `resonance.hint_glow` in `core/config/EclipseConfig` (default true).
- Fortschritts-Anzeige: Actionbar `♪ 2/5` bei jedem korrekten Treffer
  (`eclipse.resonance.caption.progress`).
- Melodie bleibt 3 Fehlversuche stabil; erst dann neu (kein „Slot-Machine"-Gefühl).
- Kaskade ist vom Rätsel-Input entkoppelt: nur der DIREKT angeschlagene Kristall zählt als
  Eingabe (Kaskaden-Mitklingen kann nie versehentlich falsch eingeben).

### 7.5 Cooldown

12000 Ticks; COOLDOWN-State im Payload → Client dimmt Bahnen-Loops (Asset-Alpha via zweitem
gedimmtem Loop-Spawn-Scale, kein neues Asset). Freies Spielen bleibt immer an.

---

## 8. Performance-Budget + LOD

| System | Budget | LOD-Fenster (engage/release, Hysterese) |
|---|---|---|
| BlockDisplays | ≤ 110, statisch; Pulse ≤ 3 Brightness-Roundtrips/Event; Atmung 2 Displays/Tick | Atmung nur < 96 Blöcke; view_range 4.0 (256 Blöcke); Tracking-Horizont 160 ist die harte Sichtgrenze |
| Interactions | 10 Stück, passiv (Event-getrieben) | immer (persistent) |
| Singen (Choir) | ≤ 4 `AbstractTickableSoundInstance` gleichzeitig | **< 48 Blöcke** (44/52), leiseste Voice wird verdrängt |
| Photon-Auren | ≤ 4 Handles (nächste Monolithe) | 56/64 |
| Photon-Bahnen | ≤ 6 Handles | beide Enden 64/72; nur nah ANIMIERT — genau die Anforderung |
| Photon-Fern-LOD | ≤ 4 `resonance_far_shaft` + 1 `resonance_far_pulse` | 160–400 Blöcke (Handover: Schäfte aus, sobald < 150 — dann tragen Displays + Auren) |
| Photon gesamt | Feld-Kontingent ≤ 12 von `PhotonBridge.MAX_LIVE_EXECUTORS` = 24 | Controller zählt eigene Handles, verweigert darüber |
| Veil-Punktlichter | ≤ 2 idle (nachts) + 1 Finale | < 40 Blöcke |
| Veil-Post | 1 FEATURE-Pipeline, Envelope-aktiv ≤ 40 t | Strike < 16, Finale < 48 |
| Server-Tick | Early-Out ohne Spieler < 128; Kaskaden-Queue ≤ 32; playSound ≤ 12/Beat | Spieler-Nähe-Check 1×/20 t, gecacht |
| Wire | Payload nur bei Build/State/Login; Cues nur Event-getrieben (kein Loop über die Wire — WINDOWED-Gesetz) | — |

reducedFx (Client-Config, vgl. `PhotonBridge`-Guards): keine Photon-Loops, keine Post-Pipeline,
Punktlichter aus; es bleiben Displays (inkl. Glow), Sounds, Brightness-Pulse, Quasar-One-Shot-
Fallbacks — Feature bleibt voll spielbar.

---

## 9. Dev-Commands

Neue Datei `devtools/dev/DevResonanceCommands.java` — eigener
`RegisterCommandsEvent`-Subscriber, der sich in den geteilten `/dev`-Literal mergt
(Brigadier-Merge-Regel dokumentiert in `devtools/dev/DevRoot`), Docs via
`DevCommandRegistry.register(new DevCommandDoc(...))`, Kategorie `DevCategory.EVENT`:

- `/dev woah resonance spawn [here]` — enqueued/erzwingt den Bau am authored Anker; mit
  `here` am Executor-Standpunkt (Dev-Welten, Stage-unabhängig; nutzt denselben
  AsyncSitePlacer). Perm 2.
- `/dev woah resonance melody [print|new]` — `print`: aktuelle Melodie als Ton-Indizes +
  Kristall-Koordinaten in den Chat; `new`: neu würfeln + sofort TEACH. Perm 2.
- `/dev woah resonance solve` — erzwingt das Finale (FX-/Belohnungs-Abnahme). Perm 2.
- `/dev woah resonance reset` — State auf IDLE, Cooldown löschen, Displays + Interactions
  discarden und aus SavedData neu bauen (Selbstheilungs-Test). Perm 2.
- `/dev woah resonance status` — State, Fortschritt, Cooldown-Rest, Display-/Interaction-
  Zählung, live Photon-Handle-Zahl ist client-seitig (nicht hier) — nur Server-Sicht. Perm 2.

(`woah` als neuer Zwischenliteral unter `/dev` — weitere PLAN-0x-Features der Serie hängen
sich dort ein.)

---

## 10. Datei-für-Datei-Checkliste

**Server (neu), Package `dev/projecteclipse/eclipse/resonance/`:**

1. `ResonanceFieldService.java` — Lifecycle/Events/Enqueue-Poll/Strike-Routing/Self-Heal
   (§3.3, §3.4), Kaskaden-Queue, Payload-Broadcasts.
2. `ResonanceFieldBuilder.java` — AsyncSitePlacer: SitePrep-Plateau + Talschale +
   Echtblock-Dressing + Altar-Dais + Monolith-/Altar-Displays + Interactions (§2.3, §3.1, §5).
3. `ResonanceMelodyMachine.java` — Statemachine inkl. Timings, Finale-Regie, Belohnung (§3.2, §7).
4. `ResonanceFieldData.java` — SavedData `eclipse_resonance_field` (§3.5).
5. `ResonanceTones.java` — Pentatonik-/Pitch-Tabelle, Melodie-Würfeln (gemeinsame Wahrheit §6.1).

**Server (Änderungen):**

6. `network/fx/FxCues.java` — 4 neue `CUE_RESONANCE_*`-Konstanten (§3.6).
7. `network/fx/S2CResonanceFieldPayload.java` (neu) + `network/fx/FxPayloads.java` —
   Registrierung + Client-Handler-Branch (neben `S2CAnchorPayload`, §3.6, §4.1).
8. `veilfx/FxAnchors.java` — frozen Anchor-Id `RESONANCE_CENTER` (§2.3 Schritt 6).
9. `protection/LandmarkProtection.java` — Resonanzfeld-Zone r 52 (§2.3).
10. `registry/EclipseSounds.java` + `src/main/resources/assets/eclipse/sounds.json` —
    `ambient.crystal_voice` (§6.5; .ogg-Asset-Ask im Asset-Ledger vermerken).
11. `core/config/EclipseConfig.java` — `resonance.hint_glow` (§7.4).
12. `devtools/dev/DevResonanceCommands.java` (neu, §9).
13. `src/main/resources/assets/eclipse/lang/en_us.json` + `de_de.json` — Captions/Actionbar:
    `eclipse.resonance.caption.teach|progress|fail|first_solve|cooldown`,
    `dev.eclipse.*`-Doc-Strings (Lang-Pipeline: `lang/ServerLang`-Nutzung wie SkyLauncher).

**Client (neu), Package `dev/projecteclipse/eclipse/client/resonance/`:**

14. `ResonanceFieldClient.java` — Payload-Mirror (§4.1).
15. `ResonanceChoir.java` — Distanz-Volume-Singen (§4.2; `SanctumHum`-Pattern).
16. `ResonanceFieldFx.java` — Loop-Fenster (Auren/Bahnen/Fern-LOD), Punktlicht-Handles,
    Shimmer-Envelope (§4.3–§4.6).

**Client (Änderungen):**

17. `veilfx/ResonancePhotonFxRows.java` (neu) — 4 One-Shot-Rows + Custom-Legs (§4.3);
    Registrar-Aufruf am selben Ort wie die übrigen `*PhotonFxRows` (FMLClientSetup).

**Assets/Tools:**

18. `tools/photon/resonance_fx.py` — Generator für die 8 `.fx` + `.fxproj` aus §4.3
    (fxlib-Konventionen, `validate --lint` clean, CullBox überall).
19. `src/main/resources/assets/eclipse/fx/resonance_*.fx|.fxproj` — 8 Paare (Generator-Output).
20. `src/main/resources/assets/eclipse/quasar/emitters/resonance_strike|pulse|fail|finale.json`
    — Quasar-Fallback-Emitter (§4.3).
21. `src/main/resources/assets/eclipse/pinwheel/post/resonance_shimmer.json` +
    `pinwheel/shaders/program/resonance_shimmer.fsh` (§4.6; `altar_aberration`-Vorlage).

**Abnahme (Dev-Loop):** `/dev woah resonance spawn here` in einer Dev-Welt → Choir-Test
(auf Kristall zulaufen), Strike/Kaskade, `melody print` → nachspielen, `solve`, `reset`;
`/photon_client clear_client_fx_cache` nach jeder `.fx`-Iteration
(`PHOTON_EDITOR_CAPABILITIES.md` §1).

---

## 11. Risiken

1. **Display-Tracking-Horizont (160 Blöcke) vs. „Fernwirkung"** — die Monolithe sind
   physikalisch nur nah sichtbar; die Fern-Silhouette hängt KOMPLETT am Photon-Fern-LOD
   (§4.3/§8). Wenn `resonance_far_shaft.fx` visuell nicht trägt, wirkt das Tal aus der Ferne
   tot. Mitigation: Distanz-Skalierung im Row-Leg (SUMMON_BEACON-Rezept), früh in-game auf
   300+ Blöcken abnehmen.
2. **Sound-Layering-Kollisionen** — 4 Choir-Loops + Strike-Layer + Kaskade können mit
   `MusicManager`-Crossfades und dem vanilla Sound-Engine-Limit (247 Kanäle) kollidieren;
   Attenuation-NONE-Instanzen, die nicht sauber gestoppt werden, leaken unhörbar weiter.
   Mitigation: hartes 4-Voice-Budget, `SILENT_STOP_TICKS`-Selbststopp, `LoggingOut`-Teardown
   (alles §4.2), `SoundSource.AMBIENT`/`BLOCKS` statt MUSIC.
3. **Interaction-Hitbox-UX** — zu große Hitboxen fangen Klicks, die dem Nachbarn/Boden galten
   (frustriert das Rätsel), zu kleine machen 40-Block-Kristalle „unantastbar"; außerdem können
   `/kill`-Strays oder Crash-Reste das Feld stumm schalten. Mitigation: height-Cap 14 +
   Girth-basierte Breite (§3.3), Self-Heal 200 t, Boot-/Join-Sweeps, `reset`-Command.
4. **Stage-5-Gating** — das Feature liegt am Rand des finalen Rings; auf Servern, die Stage 5
   nie erreichen (oder erst nach Wochen), existiert es nicht. Mitigation ist bewusst
   akzeptiert (Endgame-Woah), aber: der Self-Enqueue-Poll MUSS `wasPlaced`-idempotent sein,
   sonst doppelt ein Stage-Revert (`/eclipse stage set`) das Feld. Dev-Zugriff über
   `spawn here` deckt Tests ab.
5. **Photon-/Display-Budget-Erosion** — 8 neue Loop-Assets + Finale (~700 Partikel) neben
   Sturm/Boss-FX können `MAX_LIVE_EXECUTORS` = 24 aufbrauchen (Refusals degradieren still —
   dann pulst nichts mehr); 110 persistente Displays in 6×6 Chunks sind neu für dieses Repo
   (bisher waren große Display-Zahlen flüchtig). Mitigation: eigenes Feld-Kontingent ≤ 12 im
   Controller, CullBoxen überall, Displays statisch ohne Tick-Pushes, Abnahme mit
   `/dev photon`-Telemetrie (bestehende `DevPhotonCommands`).
