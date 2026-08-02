# WAVE6 (F-106) — Team B „Drachen-Tag & Wettkampf-Bühne" — Abschlussreport

Charter: `WAVE6_PLAN.md` §4 (Team B) + §6. Branch `cursor/project-eclipse`, kein
git add/commit/push (Hauptagent). Alle Deliverables B1–B7 (inkl. Stretch) gebaut.

---

## 0. Status je Deliverable

| # | Deliverable | Status |
|---|---|---|
| B1 | Drachen-Theme + Intro-Karte (`EclipseDragonFight`) | FERTIG |
| B2 | Kristall-Zerstör-Beat (`wave6_crystal_burst` + Sting) | FERTIG |
| B3 | Perch-/Landing-Beat (Phasen-Flanke, Schockring, Shake) | FERTIG |
| B4 | Sub-10%-Crescendo + Sieg-Requiem (`wave6_dragon_wisp`) | FERTIG |
| B5 | Race-Checkpoint-Cue + Podium-Beat (`LegacyRace` + `ArenaGame`) | FERTIG |
| B6 | Boot-Order-Härtung `FogStormSites.recoverColumn` + Audit | FERTIG |
| B7 | (Stretch) MusicMemory + `repeatVolume` + `/dev music forget` | FERTIG |

---

## 1. Erst-Verifikationstabelle (rg-Beweise VOR jeder Codezeile)

§6-Gesetz 1: nach der SACHE greppen, nicht nach Plan-Vokabular. Zwei Plan-Vokabeln
waren tatsächlich falsch/verschoben (Zeilen 9 und 10 der Tabelle).

| # | Behauptung (Plan) | rg/Read-Beweis | Befund |
|---|---|---|---|
| 1 | `EclipseDragonFight` trackt `lastCrystalCount` bereits | `rg -n 'lastCrystalCount' worldgen/end/EclipseDragonFight.java` → Feld + Scan-Diff im `CRYSTAL_SCAN_TICKS`-Block (vor Edit Z. 76/126) | STIMMT — B2 hängt sich an den bestehenden Diff, kein zweiter Scan |
| 2 | Victory-Pfad existiert, Name? | `rg -n 'victory' EclipseDragonFight.java` → `completeVictory(ServerLevel, EndFightState)` (jetzt Z. 726), Bestand: END_PORTAL_SPAWN-Sound + Dimension-Shake (Z. 746–749) | STIMMT — B4-Requiem wird dort geARMt, Bestand unangetastet |
| 3 | Kein Bossbar-Theme im Drachenkampf | `rg -c 'S2CBossbarStylePayload' EclipseDragonFight.java` → 0 (vor Edit) | STIMMT — B1 ist echte Lücke |
| 4 | Keine Intro-Karte im Drachenkampf | `rg -c 'sendIntro' EclipseDragonFight.java` → 0 (vor Edit) | STIMMT |
| 5 | `BossPayloads.sendIntro(level, center, nameKey, subtitleKey)` public API | `network/boss/BossPayloads.java` Z. 100–114; `bossKindOrdinal` default → 0 (Herald-Tint) für unbekannte Keys | STIMMT — Drachen-Karte nutzt die API 1:1; Summon-Beacon tintet Herald-violett (dokumentierter Default für neue Bosse, Z. 117–121) |
| 6 | `S2CBossbarStylePayload(THEME_BOSS)` — wo liegt das Payload? | `rg -ln 'THEME_BOSS' src/main/java` → `network/S2CBossbarStylePayload.java` (NICHT `network/boss/`), `THEME_BOSS = "boss"`; Konstruktor `(UUID barId, String theme)` | STIMMT (Pfad-Detail beachten) — Send-Idiom der vier Haus-Bosse (`HeraldEntity` `startSeenByPlayer`-Muster) übernommen |
| 7 | `recoverColumn` sitzt bei Z. 306, `getHeightmapPos` OHNE Gate | Read `worldgen/fog/FogStormSites.java` Z. 300–320 (vor Edit): `private static void recoverColumn(...)` mit ungeschütztem `level.getHeightmapPos(MOTION_BLOCKING, new BlockPos(x, 0, z))` | STIMMT — der §1.2-Restfund existierte unverändert |
| 8 | `LegacyRace` hat Checkpoint-Segment-Test + genau EINEN Cue | `rg -n 'CUE_RACE_FINISH\|checkpoint' minigames/LegacyRace.java` → Segment-Test in `tickRunning` (Bogen-Durchflug), einziger FX-Cue `CUE_RACE_FINISH` (NEWFX-C3b); 7 Bögen: `RaceTrackBuilder.CHECKPOINT_T.length == 7` („Seven colored wool checkpoint arches", Index 0 = Start/Ziel) | STIMMT — B5-Chime/Glint sind echte Lücken |
| 9 | „CueSound-Konstruktor" (B7) | `rg -ln 'CueSound' src/main/java` → **0 Treffer**; die Voice-Klasse heißt `music/MusicFadeSound.java` (AbstractTickableSoundInstance, Konstruktor nimmt `MusicCues`) | PLAN-VOKABEL FALSCH — `repeatVolume`-Auflösung sitzt im `MusicFadeSound`-Konstruktor (die BossIntroCard-Falle aus §0, erneut bestätigt) |
| 10 | Kristall-Scan-„Snapshot vorher/nachher" vorhanden? | `rg -n 'snapshot\|positions' EclipseDragonFight.java` (vor Edit) → 0: nur der Count wurde gemerkt, KEINE Positionen | LÜCKE — B2 braucht einen NEUEN transienten Positions-Snapshot (`lastCrystalPositions`), sonst ist der zerstörte Kristall nicht lokalisierbar |
| 11 | Drachen-Start: `/eclipse day set 13`? | `admin/EclipseCommands.java` Z. 150–153: `/eclipse day set <1..14>` (Perm 3). Tages-Gate: `EclipseDragonFight.dragonDayReached` → `EndConfig.current().dragonDay()` = 13 (`FrozenParams` Z. 533). `begin()` feuert via `ServerStartedEvent` (Z. 196), `EndDiscService.complete` (Z. 313) und `tickFight`-Selbstheilung (Z. 326) | STIMMT — Drehbuch in §5 nutzt exakt diese Kette |
| 12 | Race-Start: `/dev minigame ...`? | `devtools/dev/DevMinigameCommands.java` Z. 46/72–78: `/dev minigame start (arena\|race) [<minutes>]` (Perm 2) + `stop [now]`, `status`, `time <duration>` | STIMMT |
| 13 | Musik-Werkzeug | `devtools/dev/DevMusicCommands.java` Z. 53–65: `/dev music play <id>`, `stop`, `list` (+ NEU `forget`); Cue-Ids `eclipse_totality`, `wand_awakening` in `MusicCues` Z. 59/85 | STIMMT |
| 14 | WINDOWED-Muster: Hysterese 28/36, Retry 40t, reducedFx-Skip | `veilfx/Wave5BossFxRows.java` `TrophyWisp`: MATERIALIZE 28 / RELEASE 36, `RETRY_TICKS = 40`, `EclipseClientConfig.reducedFx()`-Gate, `FxAnchors.get` + Overworld-Gate | STIMMT — 1:1 als `Wave6DragonFxRows.DragonWisp` übernommen |
| 15 | `FxCues.java` frozen — wie kommen neue Cue-Ids? | `rg -n 'FxCues.cue\(' veilfx/` → `SmallCueFxRows`/`Wave5BossFxRows` deriven Ids zweiseitig via `FxCues.cue("...")` (public helper) | STIMMT — beide `wave6_*`-Ids zweiseitig abgeleitet, `FxCues.java` 0 Edits |
| 16 | `S2CShakePayload.shake(0.8F,20)` API | `rg -n 'shake\(' network/` → statische Factory vorhanden; Versand-Idiom `PacketDistributor.sendToPlayersNear` | STIMMT |

---

## 2. Design-Entscheidungen

1. **B1 — `freshFight` VOR dem Spawn entschieden**: `state.dragonId() == null &&
   state.deathStartedGameTime() < 0L` wird gelesen, BEVOR resolve/spawn den
   `dragonId` in den persistierten `EndFightState` schreibt. Restart-Re-Attach hat
   einen persistierten `dragonId` ⇒ `freshFight == false` ⇒ nur die
   `skip-reattach`-Sonde. Der transiente Latch `introCardSent` schützt zusätzlich
   gegen wiederholte `begin()`-Aufrufe in derselben Session (Selbstheilungspfad
   `tickFight` → `begin`). Kein neues persistiertes Feld nötig.
2. **B1 — Theme pro NEU hinzugefügtem Bar-Viewer** (nicht pro Tick): `syncBossBar`
   diff't `bossBar.getPlayers().contains(player)` vor `addPlayer` — deckt
   Fight-Start, Walk-Ins, Relogs und Restart-Re-Attach mit genau einem
   Style-Payload pro Viewer ab (das `startSeenByPlayer`-Idiom der vier Haus-Bosse,
   ohne `ServerBossEvent` zu subclassen).
3. **B2 — Positions-Snapshot statt Count-Only**: der bestehende Scan diff't nur
   `lastCrystalCount`; für die Lokalisierung hält B2 zusätzlich `lastCrystalPositions`
   (transient, `List<Vec3>`). Jede ALTE Position ohne Überlebenden im 4-Block-Radius
   ist ein Todesort → dort Burst + Sting. Nach Restart startet der Snapshot LEER ⇒
   Kristalle, die während des Downtimes starben, können nie nachträglich einen Beat
   feuern (kein Replay-Artefakt).
4. **B2 — Quasar-Leg `null`**: die Vanilla-Kristall-Explosion ist die photonlose
   Baseline, `wave6_crystal_burst` ist reine Photon-Garnitur (BURST-Channel,
   Mode LAYER, legal für NEUE Cues — `Wave5BossFxRows`-Präzedenz).
5. **B3 — Per-Tick-Phasen-Flanke statt 40t-Watchdog**: der Watchdog-Takt würde kurze
   Sitting-Fenster aliasen (Landung+Abflug innerhalb 40t = verpasster Beat).
   `tickPerchBeat` sampelt `isSitting()` jeden Tick; `perchLatched` hält 1 Beat pro
   Landung und löst beim Abheben.
6. **B4 — Requiem-Drain VOR dem killed-Early-Return**: `tickRequiemPillars` läuft in
   `onServerTick` VOR `state.dragonKilled()`-Return, sonst würden die 3 gestaffelten
   Säulen (30t-Stagger, 120°-Dreieck um das Ei) nach dem Sieg nie abgespult.
   `FxAnchors` sind in-memory ⇒ der Wisp-Anker wird bei JEDEM Boot eines gewonnenen
   Saves re-publiziert (`begin()`-Killed-Zweig). Fenster/Hysterese/Retry/reducedFx
   liegen komplett client-seitig in `Wave6DragonFxRows.DragonWisp` (28/36, 40t).
7. **B4 — Crescendo-Leiter HP-gestaffelt**: unter 10 % HP dritteln die Bänder die
   Kadenz 30t → 20t → 12t (W5-A5 `HeraldEntity`-Idiom); `ClientboundSoundPacket`
   AN DER SPIELERPOSITION (kein Positional-Falloff — der Herzschlag sitzt „im Ohr").
8. **B5 — Podium über Millis-Stagger im COOLDOWN-Tick**: `finishHeat` armiert
   `podiumBeatsTotal/Fired` + `nextPodiumBeatMillis` (700 ms); `tick(COOLDOWN)`
   drainiert. `victoryBeat(level, pos, place)` ist package-private static — der EINE
   erlaubte `ArenaGame`-Aufruf (Rundensieger, place=1, Arena-SPAWN) ist damit 1 Zeile.
   Checkpoint-Chime privat via `playNotifySound` (EXPERIENCE_ORB_PICKUP +
   NOTE_BLOCK_BELL, Pitch 0.7F + 0.15F·(cp−1) steigend 1→7), KEINE neuen Assets.
9. **B6 — ehrlicher Skip statt stiller Fehlleser**: `recoverColumn` → `boolean`;
   das Gate nutzt das Haus-Muster `level.isLoaded(new BlockPos(x, seaLevel, z))`
   (identisch zu `EclipseSpawner.surfaceAt`/`EventSpawnRules.surfaceAt`). Zähler im
   `int[]`-Closure des budgetierten Sweeps; `[w6b-recover]`-INFO nur bei `skipped > 0`.
10. **B7 — `markHeard` erst bei tatsächlich erreichtem Voll-Level**: die Voice
    markiert den Cue erst als „gehört", wenn der Fade-In 1.0 erreicht hat — ein
    sofort gestoppter/geduckter Anspieler verbraucht das „erste Mal" nicht.
    Ledger per-Server-Key (`config/eclipse-music-memory.json`), Auflösung EINMAL im
    `MusicFadeSound`-Konstruktor (Faktor bleibt für die Lebenszeit der Voice stabil).
    `/dev music forget` reist als `FORGET_TOKEN "!"` im BESTEHENDEN Cue-Payload
    (server-verifizierter Befehl, 0 neue Payload-Typen, 0 Edits an frozen Registraren).

---

## 3. Gate-Belege

### 3.1 fxlib-Doppellauf (byte-identisch, sha256)

`python3 tools/photon/wave6_dragon_fx.py` zweimal hintereinander, Hashes unverändert:

```
d847524048c64b6bb2ee0a23ccfb205109e3970f6bef7c4e88120f2b9817c544  wave6_crystal_burst.fx
9346e13c40b6f070a1c1e9b78ad5a61168615d64df4e7836cf849a550b86ecc6  wave6_dragon_wisp.fx
```

Generator-Ausgabe: `wave6_crystal_burst.fx` raw 12747 B / gzip 1934 B,
`wave6_dragon_wisp.fx` raw 6865 B / gzip 1532 B — beide „valid, + .fxproj"
(uuid5-deterministisch, V2.1-Birth-Tints, HDR ≤ 1.45, CullBox, Prewarm-Standbild
≥ 3 s für den Burst).

### 3.2 fxlib validate --lint

```
lint: 293 file(s), 0 NEW error/warn, 27 grandfathered, 149 advisory info
```

Gezielter Grep über die Lint-Ausgabe nach `wave6_crystal_burst|wave6_dragon_wisp`:
**0 Findings** (auch keine Advisories).

### 3.3 processResources (offline)

```
> Task :processResources UP-TO-DATE
BUILD SUCCESSFUL
```

`build/resources/main/assets/eclipse/fx/` enthält `wave6_crystal_burst.fx(.fxproj)`
und `wave6_dragon_wisp.fx(.fxproj)`.

### 3.4 compileJava (offline)

```
flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain --rerun-tasks
BUILD SUCCESSFUL in 7s   (2 actionable tasks: 2 executed — echter Voll-Recompile)
```

Chronologie-Hinweis für die Abnahme: ein Zwischenlauf während der Parallel-Phase
war rot AUSSCHLIESSLICH durch Team-C-in-flight-Code (`AwardsOverlay.java:279:
cannot find symbol DecreesCard` — Team-C-Datei, Verbotszone für B). Team B wurde
in dem Fenster zusätzlich isoliert bewiesen: alle 11 Team-B-Dateien via
`javac -proc:none` gegen den Frozen-API-Klassenpfad
(`build/moddev/artifacts/neoforge-21.1.238-merged.jar` +
`clientLegacyClasspath.txt` + GeckoLib + `build/classes/java/main`) →
`W6B ISOLATED COMPILE: OK` (0 Fehler). Nach Team-Cs Landung von
`DecreesCard.java` ist der Voll-Tree-Gate wie oben grün (forcierter Recompile,
nicht up-to-date-Cache).

### 3.5 Langdrop

`docs/plans_v3/langdrop/WAVE6B.json` — 4 Keys, en+de paritätisch:
`entity.eclipse.dragon.card`, `entity.eclipse.dragon.card.sub` (B1, exakt die
Plan-§4-Key-Namen), `dev.eclipse.doc.music.forget`, `dev.eclipse.music.forgot`
(B7). Die beiden Mod-lang-JSONs sind unangetastet (Schreibverbotszone);
`boss.eclipse.ender_dragon` existierte bereits (Z. 511 beider lang-Dateien) und
wird unverändert weitergenutzt.

---

## 4. `getHeight`-Audit-Tabelle (B6 — Abschluss der Boot-Order-Bug-Klasse)

Selbst re-verifiziert gegen den Live-Tree
(`rg -n "getHeightmapPos|getHeight\(Heightmap" src/main/java` → 63 Treffer,
jede Stelle gelesen). Muster-Terminologie wie Plan §1.2.

| Stelle (Datei:Zeile) | Schutzmuster | Beleg |
|---|---|---|
| `worldgen/fog/FogStormSites.recoverColumn:326` | **NEU B6: `isLoaded`-Gate + ehrlicher Skip-Zähler** | Gate Z. 324 (`new BlockPos(x, seaLevel, z)`, Haus-Muster), `boolean`-Return, `[w6b-recover]`-Sonde — der letzte §1.2-Restfund ist geschlossen |
| `entity/EclipseSpawner.surfaceAt:426` | `isLoaded`-Gate + Min-Build-Sentinel | Z. 423 Gate, Z. 427 `y <= getMinBuildHeight() → null` (re-verifiziert per Read) |
| `entity/spawn/EventSpawnRules.surfaceAt:479` | `isLoaded`-Gate + Min-Build-Sentinel | Z. 476/480 (re-verifiziert per Read) |
| `stormfx/StormSiege.sampleRingGround:888` | `isLoaded`-Gate | Z. 885 (re-verifiziert per Read) |
| `stormfx/StormRegistry:286` | `isLoaded`-Klasse: Defer-Loop | „deferring fog site — center chunk not loaded yet" + `continue`, Retry per Poll (das ist der `pollFogSites`-Fix `1c56087` selbst) |
| `stormfx/StormApproachFx:154/206` | Client-only (Kamera-Nähe) | reine Client-FX, Chunks um die Kamera sind geladen |
| `economy/SupplyBeacon:143` | Force-Load (Ticket) | `BudgetedBlockWriter.loadWithTicket` direkt davor + Code-Kommentar benennt exakt diese Bug-Klasse |
| `limbo/GhostShipBuilder:164` | Chunk in Hand | `chunk.getHeight(...)` auf bereits beschafftem `LevelChunk` |
| `limbo/StartEventCutscene:448` | Force-Load + Min-Build-Sentinel | Z. 447 `overworld.getChunk(...)` („force-load before the height lookup") + Z. 449 Sentinel |
| `ritual/CreditsBlackHoleAct:279` | Force-Load | Z. 278 `overworld.getChunk(...)` „(GhostShipBuilder pattern)" |
| `ritual/CreditsMapRipAct:683` | Force-Load | Z. 682 gleiche Zeile/Muster |
| `cutscene/CutsceneService:643` (gatherSpot) | Kontext (Spieler werden AN den Spot geholt, Show-Area geladen) | Gather-Ring um die Show-Area; Cutscene läuft nur mit anwesenden Spielern |
| `cutscene/CutsceneService:720` | Force-Load + Min-Build-Klemme | Z. 714 `level.getChunk(...)` („block + heightmap reads need it"), `Math.max(..., minY + 1)` |
| `veilfx/LimboAmbience:299` | Client-only (Kamera-Nähe) | Spawn-Kandidaten ≤ Ambience-Radius um die Kamera |
| `client/drama/HorizonLightning:115` | Client-only | Blitz-Einschlagspunkte im Render-Umkreis |
| `entity/boss/HeraldEntity:351` | Kontext (Entity-Tick) | Boss tickt ⇒ sein Chunk ist geladen; Lookup auf `blockPosition()` |
| `entity/GazerEntity:329/475` | Kontext (Entity-Tick, Nahbereich) | dito |
| `woah/mansiondome/MansionDomeService:256` | Chunk in Hand | `chunk.getHeight(...)` |
| `woah/echogrove/EchoSceneService:146` | Kontext (Spieler-Gate) | Szenen aktivieren erst bei Spieler ≤ `GATE_DIST` (Z. 84–85) ⇒ Anker-Chunk geladen |
| `wand/WandTickService:357`, `wand/WandPowers:884/1018`, `wand/WandSpellEffects:684/816/1095` | Kontext (Spieler-Cast, Wirkradius) | Zauber wirken im geladenen Umkreis des Casters |
| `ferryman/finale/PortalFormation.choosePortalPos:689` | Kontext (Finale am Altar, Spieler anwesend) | Golden-Angle-Suche im `PORTAL_MIN/MAX_DIST`-Band um den aktiven Altar; nachgelagerter `getBlockState`-Read lädt die Säule ohnehin synchron |
| `xboxevent/XboxPortal:116/131` | Min-Build-Sentinel | Sentinel-Fallback (Plan §1.2 re-verifiziert) |
| `worldgen/stage/ExpansionBorderFx:750` | Force-Load (Ticket + getChunk) | Plan §1.2 Z. 748–750, re-verifiziert |
| `worldgen/stage/StructureFlightFx:677/994/1054/1166` | Force-Load-Kontext + Sentinel | „terrain phase already wrote these chunks" + Z. 995-Sentinel |
| `worldgen/stage/NewRingRegistry:115`, `RingGrowthService:1335`, `ChunkRegen:461` | Chunk in Hand | `chunk.getHeight(...)` |
| `worldgen/structure/StrongholdEmergence:203/279` | Force-Load (Sequenz-Tickets) | Plan §1.2, re-verifiziert: Sequenz lädt ihre Spalten |
| `worldgen/structure/SitePrep:278` | Force-Load | Z. 276 `ensureChunk(...)` unmittelbar davor |
| `worldgen/structure/WizardObservatory.surfaceProbe:413` | Kontext (Dev-Tooling) | `/dev wizard tp` — aufrufender Spieler lädt das Ziel |
| `worldgen/DiscRepairService:116` | Chunk in Hand + Sentinel | `chunk.getHeight(...) >= chunk.getMinBuildHeight()` |
| `worldgen/end/EndShatterSequence:1555/1674/1823/1969/2000` | Kontext (Show-Sequenz auf der Disc, Chunks von der Sequenz geladen/beschrieben) | Nur-Lese-Zone für Team B; Sequenz betickt ausschließlich ihr eigenes, ticketiertes Show-Areal |
| `worldgen/vanilla/FixedSeedGenRegion:212/352` | Kontext (Worldgen-Region) | Delegate innerhalb einer `WorldGenRegion` — per Definition geladen |
| `sequence/NetherOpeningSequence.fireEmberTear:437` | **Grenzfall, NUR dokumentiert (Plan §1.2 Punkt 2)** | Krater-Rim-Lookup; Show läuft nur mit anwesenden Spielern — Kontext-geschützt, kein Fix |
| `sequence/endarrival/EndArrivalSequence:350` | **Grenzfall, NUR dokumentiert (Plan §1.2 Punkt 2)** | Fresh-Dev-World-Fallback am Disc-Center — Kontext-geschützt, kein Fix |
| `sequence/NetherUpheavalFx.surfacePoint:601` | `isLoaded`-Gate | Plan §1.2 Z. 599, re-verifiziert |
| `sequence/ExpansionSequence:1318/1349` | Force-Load/Sentinel (Sequenz-Muster) | Plan §1.2 (edgeAnchorFor Z. 1317 + Sentinel Z. 1690-Klasse), re-verifiziert |

**Fazit**: mit dem B6-Gate ist die einzige zum Plan-Zeitpunkt UNGESCHÜTZTE Stelle
geschlossen. Verbleibende ungegatete Aufrufe sind entweder Client-only,
Chunk-in-Hand, force-geladen oder kontext-geschützt; die zwei dokumentierten
Grenzfälle bleiben wie vom Plan §1.2 verlangt Doku-only.

---

## 5. RCON-Abnahme-Drehbuch (Hauptagent)

Voraussetzung: Debug-Log für `dev.projecteclipse` aktiv (die `[w6b-*]`-Sonden sind
DEBUG; `[w6b-recover]` ist INFO). Befehle Perm 3 (`/eclipse*`) bzw. Perm 2 (`/dev*`).

### 5.1 B1 — Theme + Intro-Karte (+ Restart-Re-Attach-Test)

```
/eclipse-worldgen end status              # Disc materialisiert? dragonDay=13 bestätigen
/eclipse-worldgen end materialize         # NUR falls status "not materialized" meldet
/eclipse day set 13                       # Tages-Gate öffnen; begin() feuert selbstheilend
```

- Erwartete Sonden: `[w6b-dragoncard] sent begin`, danach „Eclipse dragon fight
  active: dragon …".
- FOTO 1: Intro-Karte (BossIntroOverlay-Decode) + violette THEME_BOSS-Bar,
  Spieler ≤ 128 Blöcke vom Disc-Center.
- **Re-Attach-Test**: Server stoppen, neu starten, Spieler wieder auf die Disc →
  Sonde `[w6b-dragoncard] sent skip-reattach`, KEINE zweite Karte, Bar-Theme
  kommt trotzdem (Theme ist pro NEU hinzugefügtem Viewer, nicht pro Karte).

### 5.2 B2 — Kristall-Zerstör-Beat

Einen Spire-Kristall zerstören (Bogen/Snowball von der Disc aus).

- Sonde: `[w6b-crystal] remaining=<n> at=<x, y, z>`.
- FOTO 2: kalter End-Bloom + aufsteigende Splitter am Todesort (One-Shot,
  Prewarm-Standbild ≥ 3 s — Foto darf „spät" sein); hörbar: tiefer GLASS_BREAK
  (Pitch 0.55) für alle Bar-Viewer.
- Gegenprobe reducedFx: `wave6_crystal_burst` ist Payload-One-Shot mit Photon-Row —
  unter `reducedFx on` bleibt die Vanilla-Kristall-Explosion die Baseline.

### 5.3 B3 — Perch-Beat

Alle Kristalle zerstören → der Controller zwingt LANDING_APPROACH; Landung abwarten.

- Sonde: `[w6b-perch] phase=SITTING_*` (genau 1× pro Landung; Abheben re-armt).
- FOTO 3: END_ROD-Schockring (r=4) + violetter Staubring (r=2.5) am Perch;
  Shake 0.8F/20t für Spieler ≤ 48.

### 5.4 B4 — Crescendo + Requiem

Drachen auf < 10 % HP prügeln (Kristalle müssen weg sein, sonst klemmt der
1-HP-Floor), dann töten.

- Sonden: `[w6b-crescendo] hp=0.0xx cadence=30|20|12` (Leiter wird schneller),
  nach dem Tod `[w6b-requiem] anchored=<x, y, z>` + 3× Säulen (BEACON_ACTIVATE,
  steigender Pitch, 30t-Stagger).
- FOTO 4: die drei END_ROD-Lichtsäulen im Dreieck über dem Portal.
- FOTO 5: `wave6_dragon_wisp` über dem Drachenei — NÄHER als 28 Blöcke herantreten
  (Fenster öffnet), > 36 Blöcke zurück (Loop released graceful).
- Gegenproben: `reducedFx on` → kein Wisp (Ei/Portal = Baseline);
  Server-Restart des gewonnenen Saves → `[w6b-requiem] anchored=…` kommt erneut
  (Anker-Re-Publish), Wisp-Fenster funktioniert wieder.

### 5.5 B5 — Race + Podium (+ Arena-Sieger)

```
/dev minigame start race 5
```

- Pro durchflogenem Bogen: Sonde `[w6b-checkpoint] racer=<name> cp=<i>/7`,
  privater Doppel-Chime (Pitch steigt 1→7), ELECTRIC_SPARK+END_ROD-Glint am Bogen.
- Heat zu Ende fahren (oder Zeit ablaufen lassen): im COOLDOWN 3 gestaffelte
  Feuerwerks-Beats Gold/Silber/Bronze (700 ms Stagger), Sonden
  `[w6b-podium] place=1|2|3 at=…`.
- FOTO 6: Podium-Moment mit Feuerwerk + Dust-Farbstufen.
- Arena-Gegenprobe: `/dev minigame start arena 3` → Rundensieger bekommt EINEN
  `[w6b-podium] place=1`-Beat am Arena-Spawn (der eine erlaubte ArenaGame-Aufruf).

### 5.6 B6 — Recovery-Skip

Fog-Storm-Site recovern lassen (Storm-Zyklus oder Dev-Weg), idealerweise mit
NICHT geladenen Randspalten (Spieler weit weg teleportieren).

- Sonde (INFO, nur wenn > 0): `[w6b-recover] site=<id> skipped=<n> columns`
  direkt nach „FogStormSites: snow recovery finished for <id>".

### 5.7 B7 — MusicMemory

```
/dev music play eclipse_totality      # 1. Lauf: volle Lautstärke; Sonde [w6b-musicmem] cue=eclipse_totality heard=false
                                      # nach Erreichen des Voll-Levels: heard=now-marked
/dev music stop
/dev music play eclipse_totality      # 2. Lauf: Sonde heard=true → Voice startet bei 0.7-Gain
/dev music forget                     # Sonde [w6b-musicmem] forget key=<server> removed=<n> + Chat "…geleert"
/dev music play eclipse_totality      # wieder volle Lautstärke (heard=false)
```

`wand_awakening` analog: zweiter Lauf ist stumm (repeatVolume 0.0).

---

## 6. Angefasste/neue Dateien (Team-B-Ownership, Plan §4)

**Geändert:**
- `src/main/java/dev/projecteclipse/eclipse/worldgen/end/EclipseDragonFight.java` (B1–B4)
- `src/main/java/dev/projecteclipse/eclipse/minigames/LegacyRace.java` (B5)
- `src/main/java/dev/projecteclipse/eclipse/minigames/ArenaGame.java` (B5, 1 Aufruf)
- `src/main/java/dev/projecteclipse/eclipse/worldgen/fog/FogStormSites.java` (B6)
- `src/main/java/dev/projecteclipse/eclipse/music/MusicCues.java` (B7, `repeatVolume`)
- `src/main/java/dev/projecteclipse/eclipse/music/MusicFadeSound.java` (B7, Auflösung + markHeard)
- `src/main/java/dev/projecteclipse/eclipse/music/MusicClientHooks.java` (B7, Trampolin)
- `src/main/java/dev/projecteclipse/eclipse/music/MusicPayloads.java` (B7, FORGET_TOKEN)
- `src/main/java/dev/projecteclipse/eclipse/devtools/dev/DevMusicCommands.java` (B7, `/dev music forget`)

**Neu:**
- `src/main/java/dev/projecteclipse/eclipse/veilfx/Wave6DragonFxRows.java` (B2/B4 Rows + DragonWisp-Fenster)
- `src/main/java/dev/projecteclipse/eclipse/music/MusicMemory.java` (B7 Client-Ledger)
- `tools/photon/wave6_dragon_fx.py` (fxlib-Generator)
- `src/main/resources/assets/eclipse/fx/wave6_crystal_burst.fx` + `.fxproj`
- `src/main/resources/assets/eclipse/fx/wave6_dragon_wisp.fx` + `.fxproj`
- `docs/plans_v3/langdrop/WAVE6B.json`
- `docs/plans_v3/session_0730/WAVE6_B_DRAGON_REPORT.md` (dieser Report)

**0 Edits (API-only / Verbotszonen respektiert):** `BossIntroOverlay.java`,
`BossbarSkin.java`, `network/boss/BossPayloads.java`, `veilfx/FxPayloads.java`,
`PhotonFxRegistry.java`, `FxCues.java`, `FxAnchors.java`, `entity/boss/**`,
`EndShatterSequence.java`, `EndDiscService.java`, `stormfx/**`, beide
Mod-lang-JSONs, sämtliche Team-A-/Team-C-Dateien.
