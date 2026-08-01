# WAVE6_PLAN — Polish-Welle 6 (F-106): „Die Nacht bekommt Zähne, der Drache eine Bühne, der Morgen ein Gedächtnis"

Planner-Dokument für Polish-Welle 6, Branch `cursor/project-eclipse`. Drei dateidisjunkte
Team-Charters (A/B/C) für parallele Fable-5-Max-Thinking-Teams auf DEMSELBEN Worktree.
Dateidisjunktheit ist HART: die Ownership-Matrix in §6 ist Vertragsbestandteil jedes Charters.

Quellenlage: `AGENTS.md` (Hausregeln), `UserFeedback.md` (F-001…F-105),
`WAVE5_PLAN.md` + die drei Welle-5-Reports (`WAVE5_A_DEVHOLDS_BOSS_REPORT.md` inkl.
A6-Re-Kill-Dedup-Nachtrag, `WAVE5_B_STORM_REPORT.md` inkl. `/dev fogsite`- und
pollFogSites-Boot-Fix-Nachträgen, `WAVE5_C_ALTAR_RITUAL_REPORT.md`), Ideensammlungen
`ideas_wave4/IDEA-01…20`. **Jede Ist-Zustands-Behauptung unten wurde gegen den Live-Tree
verifiziert** (rg/Read, Stand HEAD `34078ad`) — die Reports allein waren nachweislich nicht
verlässlich: `WAVE5_PLAN.md` §1.3 führte IDEA-16 #1–3 als konsumiert, mein erster Grep nach
den PLAN-Tokens (`BossIntroCard`, `STYLE_BOSS_INTRO`) fand 0 Treffer — gebaut wurde es unter
ANDEREN Namen (`client/hud/BossIntroOverlay` + `BossPayloads.S2CBossIntroPayload`). Merke:
immer nach der SACHE greppen, nicht nach dem Plan-Vokabular.

---

## 1. Bestandsaufnahme — offene / deferred Punkte (alles Live-Tree-verifiziert)

### 1.1 Explizit übergeben / weiterhin offen

| # | Punkt | Quelle | Befund (verifiziert) |
|---|---|---|---|
| D-1 | **Fotoschuld Ghost-Wake-Splash** (W4-C2): Sub-2-s-SPLASH/SOUL/GLOW auf llvmpipe nicht bildfähig; W5-A1 lieferte das Werkzeug `/eclipsefx limbo wakehold on\|off` | WAVE4_LIMBO / WAVE5_A §3 | Werkzeug IST im Tree (`FxDevPayloads.ACTION_LIMBO_WAKEHOLD = 12`, Hold-Branch in `DeckhandRenderer`). **Reine ABNAHME-Aufgabe des Hauptagenten — KEIN Team-Scope.** Drehbuch: §8 Schritt 0 |
| D-2 | **Fotoschuld Tyrant-Desperation-Flicker** (W4-A1): 1–2-t-Blackouts unfangbar; W5-A2 lieferte `/eclipsefx tyrant flickerhold on\|off\|blackout` | WAVE4_COMBAT / WAVE5_A §3 | Werkzeug IST im Tree (`ACTION_TYRANT_FLICKERHOLD = 13`, Tristate in `FogTyrantRenderer`). **Reine ABNAHME-Aufgabe** — §8 Schritt 0. Hold-Hygiene danach via `/eclipsefx holds` (`ACTION_HOLDS_STATUS = 14`) |
| D-3 | **Woah-Audio G-2** (3 Audio-Beds) + alle weiteren Treblo-Wünsche (z. B. `_alt`-Boss-Track-Varianten aus IDEA-08 #10) | AUDIT_REVERIFY / F-095 | **BLOCKIERT — NICHT einplanen** (`TREBLO_API_KEY` fehlt weiterhin in der Umgebung; Specs+Prompts liegen fertig). Konsequenz für W6: B7-Stretch (MusicMemory) arbeitet NUR mit `repeatVolume`-Dämpfung, keine neuen OGGs |
| D-4 | **W5-B2-Outside-Schrei-Lane** vollständig nur mit 2. Client abnehmbar | WAVE5_B §6 | Bleibt Beobachtungsposten: Plausibilitäts-Abnahme über die corpse-Sonde ist erfolgt; ein 2-Client-Test ist optional, kein Charter |
| D-5 | **IDEA-16 #4 (Boss-Sky-Reaktionen)** — in W5 wegen „neues Protokoll + Sky-Stack-Risiko" zurückgestellt | WAVE5_PLAN §1.3 | Bleibt AUCH in W6 gestrichen, jetzt mit hartem Grund: Team A besitzt in dieser Welle den Sky-Stack (`OverworldPurpleEffects`, `StarField`) für die Umbral-Nacht — ein Boss-Sky-Puls bräuchte dieselben Dateien. Gesetz: gleiche Datei ⇒ selbes Team oder eines fliegt. Es fliegt. |
| D-6 | **IDEA-16 #9 (Summon-Fly-by)** — Letterbox-Contention | WAVE5_PLAN §1.3 | Bleibt Backlog. Die Intro-Karte (#1) existiert inzwischen (`BossIntroOverlay`, HOLD_TICKS = 70, wartet selbst auf die freie Center-Stage) — ein zusätzlicher Kamera-Orbit konkurriert mit genau dieser Bühne UND mit `CameraDirector`-Bestand. Kein W6-Scope. |

### 1.2 Boot-Order-Bug-Klasse (`getHeight` auf ungeladenen Chunks) — Audit-Ergebnis

Auftrag war: prüfen, ob es nach dem `pollFogSites`-Fix (Loaded-Chunk-Gate, Commit `1c56087`)
WEITERE Aufrufer derselben Klasse gibt. Vollständiger Grep
(`rg -n "getHeight\(Heightmap|getHeightmapPos" src/main/java` → 40+ Stellen), jede Stelle
gelesen. **Ergebnis: die Klasse ist im Haus weitgehend geschlossen** — die Codebase kennt
drei etablierte Schutzmuster, und fast jede Stelle trägt eines davon:

| Muster | Belegstellen (verifiziert) |
|---|---|
| `level.isLoaded(...)`-Gate vor dem Lookup | `EclipseSpawner.surfaceAt` (Z. 385), `EventSpawnRules.surfaceAt` (Z. 476), `StormSiege.sampleRingGround` (Z. 885), `NetherUpheavalFx.surfacePoint` (Z. 599) |
| Force-Load (`level.getChunk(...)` / Region-Ticket) vor dem Lookup | `StrongholdEmergence.Sequence` (Z. 202), `CreditsMapRipAct.sampleBatch` (Z. 682 „force-load (GhostShipBuilder pattern)"), `ExpansionBorderFx.resolveBoulder` (Ticket + getChunk, Z. 748–750), `ExpansionSequence.edgeAnchorFor` (Z. 1317), `StructureFlightFx` (Z. 993/1053 „terrain phase already wrote these chunks") |
| Min-Build-Height-Sentinel-Guard (`y <= getMinBuildHeight()` ⇒ Fallback/Skip) | `XboxPortal.surfaceAt` (Z. 117), `ExpansionSequence` (Z. 1690), `LimboAmbience.pickSpawnPos` (Client, Kamera-Nähe, Z. 300), `StructureFlightFx` (Z. 995) |
| Kontext macht Laden garantiert (Entity-Tick / Spieler anwesend) | `HeraldEntity.ensureFightInitialized`, `GazerEntity`, `WandPowers`, `StormApproachFx` (reiner Client), `FogBankMarker` (aktiver Sturm) |

**Echte Restfunde (klein, kein eigenes Team):**

1. `FogStormSites.recoverColumn` (Z. 306): der budgetierte Snow-Recovery-Sweep ruft
   `getHeightmapPos` OHNE Load-Gate — auf ungeladenen Chunks landet `top` am
   Dimensions-Boden, der Biome-Lookup dort ist ein Cave-Biom und die Column wird STILL
   übersprungen (kein Crash, aber die Recovery „vergisst" Spalten dauerhaft, der Sweep
   meldet trotzdem „finished"). → **Team-B-Deliverable B6 „Boot-Order-Härtung"** (1
   Gate + Sonde + Audit-Tabelle im Report).
2. Grenzfälle, NUR dokumentieren (kein Fix): `NetherOpeningSequence.fireEmberTear`
   (Z. 437 — Krater-Rim, Show läuft nur mit anwesenden Spielern),
   `EndArrivalSequence` (Z. 350 — Fresh-Dev-World-Fallback am Disc-Center). B6-Report
   führt beide in der Audit-Tabelle mit Begründung „Kontext-geschützt".

### 1.3 UMBRAL-NIGHT-Census — FX-arm, Charter-reif (→ Team A)

Verifiziert in `entity/EclipseSpawner.java` (Z. 40–199) + Greps über `client/`:

- Es EXISTIERT ein echtes Nacht-Event-System: Pale Nights (ab Tag 4, 25 %, erste
  garantiert, Tag 12 fix), Umbral Nights fix Tag 6 + 10, persistiert in
  `EclipseWorldState.getActiveNightEvent()`, live überschreibbar via
  `/eclipse event set <pale|umbral|none>` (verifiziert in `admin/EclipseCommands.java`
  Z. 91/133–159 — **das ist bereits das perfekte Abnahme-Werkzeug, kein neuer Hold nötig;
  der Nacht-Zustand ist von Natur aus statisch fotografierbar**).
- Vorhandene Politur: W8-Announcement (`STYLE_UNLOCK`) + der W3-Personal-Omen-One-Shot
  (`wave3_night_omen`, a = 1 umbral / 0 pale, `EclipseSpawner.announceNightEvent`
  Z. 191–197) + verdoppelte Stalker-Packs + Landungs-Howl (`HOWL_RANGE = 64`).
- **Was FEHLT (alles rg-verifiziert 0 Treffer):** (a) der Nacht-Zustand wird NIRGENDS zum
  Client gesynct (`ClientStateCache` hat kein Feld, kein Payload existiert) — kein
  Renderer kann heute wissen, dass Umbral-Nacht ist; (b) `client/sky/**` kennt
  `umbral|pale` nicht (Grep 0) — der in F-105 fotografierte „Doppelmond" ist EMERGENT
  (Vanilla-Mond + die im Zenit gepinnte Eclipse-Scheibe aus `OverworldPurpleEffects`),
  kein gestaltetes Umbral-Visual; (c) während der Nacht passiert FX-seitig NICHTS mehr
  (kein Dread-Bett, kein Mob-Tell, keine Morgen-Erlösung); (d) `TheOtherEntity` hat
  keinerlei Nähe-Tell (Grep `whisper|proximity|heartbeat` → 0), er mimt nur
  (`MimicWalkGoal`); (e) `UmbralStalkerRenderers` hat keinen Glow-/Emissive-Pass-Hook
  auf das Event (Grep `glow|emissive` → 0 relevante Treffer).

### 1.4 System-Census (Kandidatenliste des Auftrags, per rg gegen den Live-Tree)

| Kandidat | Befund | Verdict |
|---|---|---|
| **Nether-Himmel/Pit** | `client/nether/NetherPitPlume` + `NetherOpenClientFx` vorhanden; NETHER_MASS2-Masse-Pass abgenommen (F-104-Umfeld) | poliert — kein Charter |
| **End-Content: Drachen-Kampf** | `worldgen/end/EclipseDragonFight.java` (eigener Overworld-Controller für den Vanilla-`EnderDragon` auf der End-Disc, Kristall-Scan/Watchdog/Bossbar/Rewards) hat GENAU EINEN FX-Beat: `END_PORTAL_SPAWN`-Sound + Shake beim Sieg (Z. 512–515). Kein Bossbar-Theme (`S2CBossbarStylePayload`-Grep in der Datei: 0), keine Intro-Karte, kein Kristall-Beat (obwohl `lastCrystalCount` bereits getrackt wird, Z. 76/126), kein Crescendo. Der Tag-13-Höhepunkt ist der FX-ärmste Boss des Mods | **Charter → Team B** |
| **End-Content Rest** | `EndShatterSequence`/`EndArrivalSequence`/`EndVoidWisps` poliert (F-077/F-089/W3) | kein Charter |
| **Minigames** | `LegacyRace` hat Countdown/Positions-HUD/Podium + genau EINEN Cue (`CUE_RACE_FINISH`, NEWFX-C3b, Z. 472). Checkpoint-Durchflug ist stumm; `ArenaGame` hat 2 Sound-/Partikel-Stellen. `/dev minigame start (arena\|race)` als Abnahme-Werkzeug vorhanden | **Team B (B5)** |
| **Radio / Musik-Übergänge** | Es gibt KEIN Radio-System (Grep `radio` in src → 0; „Radio" gehört zur unverwandten Website im Repo-Root). Musik: IDEA-08 #1–#7 sind KONSUMIERT (verifiziert: `fog_storm`-Hysterese-Rung + Totality-Rung + `day_final`-Rung in `MusicManager.naturalCue` Z. 283–328, `lingerTicks`+Un-Fade, `MusicManager.release()`, Duck-Verweise in `MusicCues`) | fast poliert; Rest = IDEA-08 #10 (MusicMemory) → **B7-Stretch, ohne neue Tracks (D-3)** |
| **Skilltree/Bestiary-UI** | `LevelUpOverlay`, `SkillProcToast`, `SkillXpBarLayer` vorhanden; Bestiary-Tier-up hat Sting + Actionbar-Caption (`S2CBestiaryPayload` mit `tierUpId/tierUpTier`, `BestiaryService` Z. 239–243) | ausreichend; nur IDEA-05 #8 (XP-„+n"-Chip) als **C7-Stretch** |
| **Backrooms** | `BackroomsDread`/`BackroomsBuzz`/`BackroomsFlickerOverlay` (F-042/043) | poliert — kein Charter |
| **Echo-Grove** | `EchoGroveFx`/`EchoPhotonFxRows`/`MemoryFloodService` (F-062 Woah-C3-Flut-Beat) | poliert — kein Charter |
| **Aeronautics-Ballons** | Externer Mod, nur `ModGate`-Namespace-Gating im Haus (Grep: keine eigenen FX-Hooks). Assets All-Rights-Reserved | außerhalb unseres FX-Bodens — kein Charter |
| **Collections/Contracts/Awards** | Collections: Tier-Toast + Sting (`S2CCollectionTierPayload`). Contracts: Announce + Shake + `ContractRevealOverlay` + `HunterMarkFxClient` + `kill_contract`-Musik. Awards: Roulette-Overlay komplett | Systeme poliert; die LÜCKEN liegen im Morgen-SEAM drumherum (IDEA-09 #5/#6/#9/#10, alle 4 offen-verifiziert: kein `isIdle` in `AnnouncementOverlay`/`AwardsOverlay`, kein `digest|skippedDays` in `AnnouncementService`, kein `recap` in `AwardService`) → **Team C** |

### 1.5 Ideensammlungs-Census (Marker-Grep gegen den Live-Tree)

- **Konsumiert, NICHT erneut einplanen** (Beweise): IDEA-16 komplett bis auf #4/#9 —
  #1 = `BossIntroOverlay` + `BossPayloads.sendIntro` (generisch: `nameKey`/`subtitleKey`),
  #2 = `RiftAnchor.particleWall(level, player, phase)` / `FogTyrantArena.particleWall(…,
  severity)`, #3 = „W4 IDEA-16 #3 death slow-mo"-Kommentar in `FerrymanEntity.tickClientAnim`
  (Z. 1556) + „W4 loot ceremony"-Payout-Keyframes in `HeraldEntity` (Z. 169), #7 =
  `FogTyrantRenderer.getEnrageStacks()` (Z. 116/216) + `RiftWardenRenderer`-DATA_STAGGERED-
  Flourish, #5/#6/#8/#10 = W5-A6/C6/A4/A5. IDEA-08 #1–#7 (§1.4). IDEA-09 #1–#4/#7,
  IDEA-12 #2/#4–#6/#8–#10 (W5-C; #2-Beleg: `offeringTellPitch/-Tier` in `AltarBlockEntity`
  Z. 431–446), IDEA-05 #4/#7, IDEA-13/14/15/17/18-Kernbestand.
- **Offen und in DIESER Welle chartered**: IDEA-09 #5/#6/#8/#9/#10 (Team C);
  IDEA-12 #7 (Team C — verifiziert offen: kein SMOKE-Zweig in `handleOffering`, die
  `FIRE_EXTINGUISH`-Treffer in der Datei sind Reject-Pfade); IDEA-08 #10 (Team B,
  Stretch, nur Dämpfung); IDEA-05 #8 (Team C, Stretch).
- **Offen, Backlog Welle 7+**: IDEA-16 #4/#9 (§1.1 D-5/D-6); IDEA-01 #4–#10;
  IDEA-05 #1–#3/#5/#6/#9/#10 (Sidebar-Dateien sind W4-FEEL-Bestand, s. §6);
  IDEA-04/06/07/10/11/19/20-Reste.

---

## 2. Ideation-Census — 20 Ideen mit Datei-Ankern

Suchraster: Systeme mit Zustand aber ohne Client-Echo (Nacht-Event), Höhepunkte ohne
Punktuation (Drache), Seams mit Beweis-Lücke (Morgen-Rollover), verifiziert stumme Beats
(Race-Checkpoints, Junk-Offering). Impact = spielersichtbar? Risiko = Datei-Kollision /
llvmpipe / reducedFx-Pfad.

| # | Idee (1–2 Sätze) | Datei-Anker (Hook) | Impact | Risiko | Team |
|---|---|---|---|---|---|
| 1 | **Nacht-Event-Client-Sync**: `S2CNightEventPayload(event, day)` bei Nightfall/Dawn/Login — die enabling infra, ohne die KEIN Renderer die Umbral-Nacht kennen kann. | NEU `network/night/NightPayloads.java`; Send-Hooks in `EclipseSpawner.announceNightEvent`/`clearNightEvent` + eigener Login-Subscriber | hoch (Enabler) | niedrig — dezentrale Payload-Registrierung ist Haus-Muster (28 eigene `*Payloads`-Registrare) | A |
| 2 | **Umbral-Mond-Grade**: der Vanilla-Mond-Pass färbt auf Umbral-Nächten tief violett + größerer Halo; Pale Nights entsättigen ihn fahl. Ganze Nacht = statisch fotografierbar, kein Hold nötig. | `client/sky/OverworldPurpleEffects` Mond-Pass Z. 291–312 | hoch (2 fixe Nächte + jede Pale Night) | mittel — Sky-Stack; Gegenmittel §7 R2 | A |
| 3 | **Umbral-Sternfeld-Dimmen**: Sterne auf Umbral-Nächten dunkler/rötlicher — „der Himmel hält den Atem an". | `client/sky/StarField.java` | mittel | niedrig (reine Farb-Arithmetik) | A |
| 4 | **Rudel-Landungs-Bühne**: der bestehende Howl bekommt ein Bild — Photon-Bodennebel-Burst + 3–4 Augen-Glints am Pack-Center beim gelandeten Stalker-Pack. | `EclipseSpawner.spawnStalkerPack` (Howl-Block); NEU `veilfx/Wave6NightFxRows` + `tools/photon/wave6_night_fx.py` | hoch | niedrig (One-Shot, Cue-Lane `FxCues.cue("wave6_pack_land")`) | A |
| 5 | **The-Other-Nähe-Flüstern** (Pale Night): innerhalb ~12 Blöcke hört NUR der nächste Spieler ein gedämpftes, throttled Flüstern/Herzschlag-Paar — der Doppelgänger wird körperlich unheimlich. | `entity/TheOtherEntity.java` Server-Tick (privates `ClientboundSoundPacket`-Idiom wie W5-A5) | hoch | niedrig | A |
| 6 | **Morgen-Erlösungs-Beat**: endet ein Nacht-Event im Dawn-Clear, bekommt jeder Online-Spieler einen leisen Exhale + Personal-Omen-INVERS-Cue (Gegenstück zu `wave3_night_omen`). | `EclipseSpawner.clearNightEvent`; Cue `wave6_dawn_release` (Personal-Lane `sendFxEventTo`) | mittel | niedrig | A |
| 7 | **Stalker-Umbral-Glow**: auf Umbral-Nächten leuchten Stalker-Augen/Kristallrücken heller (Emissive-Multiplikator liest den A1-Client-State). | `client/entity/stalker/UmbralStalkerRenderers.java` | mittel | niedrig (Client-only, reducedFx-gated) | A |
| 8 | **Drachen-Bossbar-Theme + Intro-Karte**: `THEME_BOSS`-Skin-Payload je Bar-Viewer + `BossPayloads.sendIntro(...)` beim Fight-Start — der Tag-13-Boss zieht mit den vier Haus-Bossen gleich, OHNE dass `BossIntroOverlay`/`BossbarSkin` angefasst werden (beides public API). | `worldgen/end/EclipseDragonFight.begin/attach` (Bar-Management Z. 107–128) | hoch | niedrig | B |
| 9 | **Kristall-Zerstör-Beat**: der bereits getrackte `lastCrystalCount`-Diff feuert am zerstörten Kristall einen Photon-Bloom + fernen Sting — jede Spire-Eroberung wird ein Ereignis. | `EclipseDragonFight` Kristall-Scan (Z. 76/126/269-Umfeld); NEU `veilfx/Wave6DragonFxRows` | hoch | niedrig (Position bekannt, Beat ≥ 3 s haltbar via prewarm) | B |
| 10 | **Perch-/Landing-Schockring**: der Phase-Watchdog kennt Landing/Perch — beim Aufsetzen Bodenring + `S2CShakePayload` + END_ROD-Staub am Perch. | `EclipseDragonFight`-Watchdog (`WATCHDOG_TICKS`/`LANDING_RETRY_TICKS`) | mittel | niedrig | B |
| 11 | **Drachen-Crescendo + Sieg-Requiem**: Sub-10 %-Herzschlag-Leiter (W5-A5-Idiom 30→20→12 t) + Sieg: Beam-Salve + `wave6_dragon_wisp`-WINDOWED-Loop über dem Ei/Portal via `FxAnchors.set`. | `EclipseDragonFight.tick`/Victory-Pfad (Z. 512 ff.) | hoch | mittel (Loop-Hygiene → Gesetze §6) | B |
| 12 | **Race-Checkpoint-Cue + Podium-Beat**: jeder korrekt durchflogene Checkpoint-Bogen gibt dem Racer einen privaten Tick-Chime + Bogen-Glint; das Podium bekommt einen 3-Stufen-Feuerwerks-Beat statt nur Titel + Finish-Cue. | `minigames/LegacyRace.java` (Checkpoint-Segment-Test, Podium-Block), `minigames/ArenaGame.java` | mittel | niedrig (`/dev minigame start race` als Werkzeug verifiziert) | B |
| 13 | **Boot-Order-Härtung**: `FogStormSites.recoverColumn` bekommt das `isLoaded`-Gate (+ Defer-Verhalten im budgetierten Sweep) + Repo-Audit-Tabelle der Bug-Klasse im Report (§1.2). | `worldgen/fog/FogStormSites.java` Z. 306 | niedrig (unsichtbar, aber Korrektheit) | niedrig | B |
| 14 | **MusicMemory** (IDEA-08 #10, NUR Dämpfung): Client-„heard"-Ledger, Wiederholungen von `eclipse_totality`/`wand_awakening` leiser/aus — KEINE neuen Tracks (D-3). | `music/MusicCues.java` + `music/MusicManager.java` + NEU `music/MusicMemory.java` | mittel | niedrig | B (Stretch) |
| 15 | **„Today's Decrees"-Reveal** (IDEA-09 #5): die schwächste Morgen-Zeile (`quest.eclipse.assigned`-Actionbar, verifiziert in `QuestEngine`) wird eine sequenzierte Karten-Enthüllung der Tages-Goals nach dem Day-Announcement. | NEU `client/awards/DecreesCard.java` (AwardsOverlay-Queue-Muster, self-subscribed); `progression/goals/QuestEngine.java` (Zeile ersetzen/fallback) | hoch | mittel (Bühnen-Kollision → §7 R1) | C |
| 16 | **Awards-Pre-Beat + Kollisions-Gate** (IDEA-09 #6): `AnnouncementOverlay.isIdle()` (verifiziert: existiert nicht) + AwardsOverlay wartet darauf + 40-t-„take your seats"-Dim + Sting client-seitig zur INTRO-Phase. | `client/hud/AnnouncementOverlay.java`, `client/awards/AwardsOverlay.java`, `awards/AwardService.sendRevealNow` (Sting-Note) | hoch | niedrig | C |
| 17 | **Sundial-Schatten-Wanderung** (IDEA-09 #8): Erase/Place der Basalt-Schattenlinie über ~30 t animiert statt Ein-Tick-Rewrite, Puffs + gilded Flash am Ring-Marker; Fallback instant ohne Spieler ≤ 64 Blöcke / Chunk nicht geladen. | `worldgen/structure/SundialPlaza.onDayChanged` (Z. 44) | mittel | niedrig (~40 Block-Writes, budget-trivial) | C |
| 18 | **Catch-up-Digest** (IDEA-09 #9): ≥ 2 übersprungene Tage ⇒ EIN „Days 4–6 passed…"-Digest statt Sweep-Flut (Queue-Cap 8 verliert heute Unlocks). | `progression/realtime/RealtimeDayService.runCatchUpNow` (Count-Handoff) + `timeline/AnnouncementService.onDayChanged/announceNewUnlocks` (Digest-Branch; verifiziert: kein `skippedDays` im Tree) | mittel | niedrig | C |
| 19 | **Morning Paper** (IDEA-09 #10): Login nach Rollover ⇒ kompakte Recap-Karte (Tag + Titel + Award-Gewinner + Mains) statt nichts; APIs `AwardsState.resolved()/latestResolvedDay()` verifiziert vorhanden. | `awards/AwardService.onPlayerLoggedIn` (Z. 76) + Recap-Renderer neben `AwardsOverlay` | hoch | mittel (neues Payload ODER `S2CAwardRevealPayload`-Flag) | C |
| 20 | **Junk-Sniff-and-Swallow** (IDEA-12 #7): `exactValue == 0` ⇒ Beam skippen, SMOKE + `FIRE_EXTINGUISH` 0.6 F — der Altar seufzt hörbar über Dreck; verrät nur die Junk-Grenze, nie den Tier. | `ritual/AltarBlockEntity.handleOffering` post-accept (Z. 385–420, `offeringTellTier`-Nachbarschaft) | mittel | niedrig | C |

(Stretch-Reserve: **IDEA-05 #8 XP-„+n"-Chip** in `client/skills/SkillXpBarLayer.java` → C7.)

Nicht eingeplant mit Begründung: Woah-Audio/Track-Varianten (D-3 blockiert), IDEA-16 #4
(D-5 Datei-Kollision mit Team A), IDEA-16 #9 (D-6 Bühnen-Contention), Sidebar-Mikro-Ideen
IDEA-05 #1–#3/#5/#6/#9/#10 (`SidebarPanel`/`SidebarExpanded` bleiben W4-FEEL-Frozen, §6).

---

## 3. Team-Charter A — „Umbral-Uhr & Nacht-Dread" (Sonden-Präfix `[w6a-*]`)

**Mission**: Das einzige große Zustands-System OHNE Client-Echo bekommt Augen, Haut und
einen Morgen: Nacht-Event-Sync, Umbral-Mond, Rudel-Bühne, Doppelgänger-Nähe, Erlösung.

### Scope / Deliverables

1. **A1 Nacht-Event-Client-Sync** — NEU `network/night/NightPayloads.java` (eigener
   `RegisterPayloadHandlersEvent`-Registrar, Haus-Muster `BestiaryPayloads`) mit
   `S2CNightEventPayload(String event, int day)`. Sends: in
   `EclipseSpawner.announceNightEvent` (nach dem Omen-Loop), in `clearNightEvent`
   (event = none) und in einem NEUEN Login-Subscriber (eigene Datei oder im Registrar,
   `PlayerLoggedInEvent`, liest `EclipseWorldState.getActiveNightEvent()` READ-only —
   `EclipseWorldState.java` wird NICHT editiert). Client-Senke ist ein statisches Feld in
   NEU `client/drama/NightDreadFx.java` (NICHT `ClientStateCache` — die Datei ist W6-frozen,
   §6). Sonde `[w6a-nightsync] event=<e> day=<d> (login|nightfall|dawn)`.
2. **A2 Umbral-Mond & Pale-Blässe** — im Mond-Pass von
   `client/sky/OverworldPurpleEffects` (Z. 291–312): Umbral ⇒ Mond-Quad-Tint tief violett
   (#6A1FB0-Familie) + zweites, leicht versetztes Ghost-Quad bei ~0.25 Alpha (der
   „Doppelmond" wird KANON statt Zufall); Pale ⇒ Entsättigung Richtung Knochenweiß.
   NUR Farb-/Alpha-Arithmetik + ein Zusatz-Quad im bestehenden Pass, KEINE neue
   Render-Stage, Iris-Gate + `creditsDark`-Fade des Bestands bleiben unangetastet
   (der Tint multipliziert NACH deren Faktoren). `reducedFx`: Tint bleibt (kostenlos),
   Ghost-Quad entfällt. Sonde `[w6a-moon] mode=<umbral|pale|none>` (1× pro Wechsel).
3. **A3 Umbral-Sternfeld** — `client/sky/StarField.java`: Umbral ⇒ Sternhelligkeit ×0.55
   + warmer Rotstich; Pale ⇒ ±0 (die Pale Night gehört dem Mond). Reine Konstanten-Mathe
   im bestehenden Vertex-Farbpfad.
4. **A4 Rudel-Landungs-Bühne** — `EclipseSpawner.spawnStalkerPack`: nach erfolgreicher
   Pack-Platzierung (der Howl-Block) ein `FxPayloads.sendFxEvent(level,
   FxCues.cue("wave6_pack_land"), packCenter, packSize, umbral ? 1 : 0)` — Cue-Lane-API,
   `FxPayloads.java` wird NICHT editiert. Asset `wave6_pack_land` (Bodennebel-Ring +
   3–4 Augen-Glints, One-Shot ≤ 60 t) via NEU `tools/photon/wave6_night_fx.py` →
   `assets/eclipse/fx/wave6_pack_land.{fx,fxproj}`, Row in NEU
   `veilfx/Wave6NightFxRows.java` (`PhotonFxRegistry.registerRow`-API — die
   Registry-Datei selbst ist frozen). Quasar-Leg `null` legal (neuer Cue), Vanilla-Leg
   CAMPFIRE_COSY_SMOKE-Ring. Sonde `[w6a-packland] size=<n> umbral=<b> at=<pos>`.
5. **A5 The-Other-Nähe-Flüstern** — `entity/TheOtherEntity.java` Server-Tick: ist der
   NÄCHSTE Spieler ≤ 12 Blöcke, alle 60–80 t (gejittert) ein privates
   `ClientboundSoundPacket`-Paar (AMBIENT_CAVE-artig gedämpft 0.35 F + WARDEN_HEARTBEAT
   0.25 F, Pitch 0.6) NUR an diesen Spieler. Throttle-Marke transient im Entity.
   Sonde `[w6a-otherdread] target=<name> dist=<f>` (max 1 Zeile / 3 s).
6. **A6 Morgen-Erlösung** — `EclipseSpawner.clearNightEvent`: war das Event aktiv,
   pro Online-Spieler `sendFxEventTo(p, FxCues.cue("wave6_dawn_release"), p.position(),
   umbralWar ? 1 : 0, 0)` (Personal-Lane, `wave3_night_omen`-Idiom) + leiser
   Exhale-Sound. Asset `wave6_dawn_release` (aufsteigender, sich auflösender heller
   Mote-Ring — die Umkehrung des Omens) im selben Generator. Sonde
   `[w6a-dawnrelease] players=<n> event=<e>`.
7. **A7 (Stretch) Stalker-Umbral-Glow** — `client/entity/stalker/UmbralStalkerRenderers`:
   Emissive-/Eye-Pass-Alpha ×(1 + 0.6) wenn `NightDreadFx.isUmbral()`; `reducedFx` lässt
   den Basis-Look unangetastet (nur der Boost entfällt). W5-B4-Präzedenz (Zweitpass nur
   wo Farb-Ints clampen).

### Akzeptanzkriterien (llvmpipe-real)

- **A1**: Server + Client laufen → `/eclipse event set umbral` → Client-Log
  `[w6a-nightsync] event=umbral`; Relog → Login-Zeile; `event set none` → dawn-Zeile.
- **A2/A3**: `event set umbral` + `time set midnight` → Screenshot Mond violett +
  Ghost-Quad + gedimmte Sterne; `event set pale` → Screenshot fahler Mond;
  `event set none` → Screenshot byte-gleiche Vanilla-Nacht-Optik (Referenz: die
  F-105-Midnight-Fotos). Gegenprobe Shaderpack aktiv (Iris): Custom-Pass deaktiviert
  sich wie im Bestand. Der Nacht-Zustand hält beliebig lange — KEIN Hold nötig.
- **A4**: `/eclipse day set 6` + Nacht abwarten (oder `event set umbral` + Difficulty
  ≥ easy) → `rg "\[w6a-packland\]" run/logs/debug.log` ≥ 1; Foto des Nebel-Rings binnen
  der 60-t-Lebenszeit bei `tick rate 2` ODER Sonde als Beweis + `prewarm`-Standbild.
- **A5**: `event set pale`, `summon eclipse:the_other ~5 ~ ~` → Sonde throttled;
  zweiter Spieler weiter weg hört nichts (Log zeigt nur den nächsten).
- **A6**: aktives Event + `time set day` → `[w6a-dawnrelease]`-Zeile, 1× pro Dawn;
  Folge-Dawn ohne Event still.
- **A7**: Stalker außerhalb/innerhalb Umbral-Nacht fotografieren (Glow-Differenz);
  `reducedFx on`-Gegenprobe.
- **Gates**: `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain`
  grün; fxlib `validate --lint` 0 NEUE Findings + Generator-Doppellauf byte-identisch +
  `.fxproj`-Siblings; `processResources` grün; Lang-Keys NUR
  `docs/plans_v3/langdrop/WAVE6A.json` (en+de paritätisch).

### Datei-Ownership (exklusiv Team A)

`entity/EclipseSpawner.java`, `entity/TheOtherEntity.java`, `entity/UmbralStalkerEntity.java`,
`client/entity/stalker/**`, `client/sky/OverworldPurpleEffects.java`,
`client/sky/StarField.java`; NEU: `network/night/**`, `client/drama/NightDreadFx.java`,
`veilfx/Wave6NightFxRows.java`, `tools/photon/wave6_night_fx.py`,
`assets/eclipse/fx/wave6_pack_land.*` + `wave6_dawn_release.*`,
`docs/plans_v3/langdrop/WAVE6A.json`, Report
`docs/plans_v3/session_0730/WAVE6_A_NIGHT_REPORT.md`.

**Verbotszonen**: ALLE Team-B-Dateien (insb. `worldgen/end/**`, `minigames/**`,
`network/boss/**`, `worldgen/fog/**`, `music/**`), ALLE Team-C-Dateien (insb.
`client/hud/AnnouncementOverlay`, `client/awards/**`, `awards/**`, `ritual/**`,
`progression/**`, `timeline/**`), `client/ClientStateCache.java`,
`core/state/EclipseWorldState.java` (READ-only), übrige `client/sky/**`-Dateien
(`EclipseSkyState`, `DaySkyEscalation`, `OverworldFogTint`, `RimMountainSilhouette` —
NICHT anfassen), `client/drama/LastMinuteHush.java`, globale Frozen-Zonen (§6).

---

## 4. Team-Charter B — „Drachen-Tag & Wettkampf-Bühne" (Sonden-Präfix `[w6b-*]`)

**Mission**: Der FX-ärmste Boss des Mods (Tag-13-Drache) zieht mit den vier Haus-Bossen
gleich — Theme, Ouvertüre, Kristall-Beats, Crescendo, Requiem; dazu die stummen
Race-Checkpoints und die letzte offene Boot-Order-Lücke.

### Scope / Deliverables

1. **B1 Drachen-Theme + Intro-Karte** — `EclipseDragonFight`: beim Fight-Start/Re-Attach
   pro Bar-Viewer `S2CBossbarStylePayload(THEME_BOSS)` (Idiom der vier Bosse; die
   Viewer-Verwaltung der `ServerBossEvent` liegt bereits in der Datei, Z. 107–128) und
   EINMAL `BossPayloads.sendIntro(level, discCenter, "entity.eclipse.dragon.card",
   "entity.eclipse.dragon.card.sub")` — beides public API, `BossIntroOverlay.java` und
   `BossbarSkin.java` bleiben byte-unangetastet. 2 Lang-Keys via Langdrop. Re-Attach
   nach Restart sendet KEINE zweite Karte (transienter Latch). Sonde
   `[w6b-dragoncard] sent (begin|skip-reattach)`.
2. **B2 Kristall-Zerstör-Beat** — der Kristall-Scan diff't `lastCrystalCount` bereits:
   bei Count-Drop den zerstörten Kristall lokalisieren (Scan-Snapshot vorher/nachher)
   und dort `wave6_crystal_burst` feuern (Photon: kalter End-Bloom + aufsteigende
   Splitter, One-Shot, prewarm-Standbild ≥ 3 s) + ferner Sting an alle Bar-Viewer
   (`GLASS_BREAK`-Familie tief gepitcht). Row in NEU `veilfx/Wave6DragonFxRows.java`.
   Sonde `[w6b-crystal] remaining=<n> at=<pos>`.
3. **B3 Perch-/Landing-Beat** — im Phase-Watchdog: Übergang in
   Landing/Perch-Phasen (`EnderDragonPhase`) ⇒ Boden-Schockring am Perch
   (END_ROD + Staub, serverseitige Partikel) + `S2CShakePayload.shake(0.8F, 20)` an
   Spieler ≤ 48 Blöcke. Throttle: 1× pro Landung (Phase-Flanke, nicht pro Tick).
   Sonde `[w6b-perch] phase=<p>`.
4. **B4 Crescendo + Sieg-Requiem** — Sub-10 %-HP: `WARDEN_HEARTBEAT`-Leiter 30→20→12 t
   an alle Spieler ≤ `BOSS_BAR_RANGE` (W5-A5-Idiom, transiente `lastCrescendoTick`-Marke).
   Sieg (bestehender Victory-Pfad Z. 512 ff.): 3 gestaffelte Licht-Säulen über dem
   Portal-Center + `wave6_dragon_wisp`-Loop (WINDOWED, Hysterese 28/36, Retry 40 t,
   `reducedFx` skippt, Anker via `FxAnchors.set` — FROZEN-API nur benutzt) über dem
   Ei/Portal. Sonden `[w6b-crescendo] hp=<f> cadence=<t>` / `[w6b-requiem] anchored=<pos>`.
5. **B5 Race-Checkpoint-Cue + Podium-Beat** — `minigames/LegacyRace.java`: im
   Checkpoint-Segment-Test bei Pass ein PRIVATER Chime (Pitch steigt mit
   Checkpoint-Index 1→7, `playNotifySound`) + Glint-Partikel am Bogen (server-seitig,
   nur Umkreis); Podium: 3 gestaffelte Feuerwerks-/Funken-Beats (Gold/Silber/Bronze
   nacheinander) am bestehenden Podium-Block. `ArenaGame.java` erbt den Sieg-Beat
   (1 Aufruf). KEINE neuen Assets nötig (Vanilla-Partikel + Bestands-Cue-Familie
   `CUE_RACE_FINISH` bleibt unangetastet). Sonde `[w6b-checkpoint] racer=<n> cp=<i>/7`.
6. **B6 Boot-Order-Härtung** — `worldgen/fog/FogStormSites.recoverColumn` (Z. 306):
   `if (!level.isLoaded(new BlockPos(x, level.getSeaLevel(), z))) return;` VOR dem
   `getHeightmapPos` — der budgetierte Sweep überspringt die Column dann EHRLICH
   (Skip-Zähler statt Fehl-Lookup am Dimensions-Boden); einmal pro Sweep-Abschluss
   Sonde `[w6b-recover] site=<id> skipped=<n> columns` (INFO, nur wenn skipped > 0).
   PLUS: die §1.2-Audit-Tabelle (alle `getHeight`-Stellen + Schutzmuster) wandert
   vollständig in den Team-Report — das ist der Abschluss-Beleg der Bug-Klasse.
7. **B7 (Stretch) MusicMemory** — NEU `music/MusicMemory.java` (Client-Ledger,
   `config/eclipse-music-memory.json`, per-Server-Key) + `repeatVolume`-Feld in
   `MusicCues` (Wiederholung: `eclipse_totality` 0.7, `wand_awakening` 0.0) +
   Auflösung im `CueSound`-Konstruktor + `/dev music forget`. KEINE neuen Tracks,
   keine `_alt`-Varianten (D-3 blockiert). Sonde `[w6b-musicmem] cue=<id> heard=<b>`.

### Akzeptanzkriterien

- **B1**: End-Disc-Save (`/eclipse day set 13` triggert den `EndDiscService`-Pfad;
  auf dem Langzeit-Dev-Save existiert die Disc ab Tag 12) → Bossbar violett-themed
  (Screenshot), Intro-Karte einmalig (HOLD-Fenster 70 t ⇒ bei `tick rate 2`
  fotografierbar; Sonde als Primärbeweis); Server-Restart mitten im Kampf → Re-Attach
  OHNE zweite Karte (`skip-reattach`-Sonde).
- **B2**: Kristall per Bogen/`/kill` zerstören → Sonde mit plausibler Spire-Position;
  Foto des Blooms (prewarm-Standbild). Alle Kristalle weg → keine weiteren Sonden.
- **B3**: Landing abwarten (oder Dragon per Watchdog zwingen) → genau 1 Sonde pro
  Landung; Shake nur nah (2. Position gegenprüfen, falls 2. Client verfügbar — sonst
  Log-Radius-Beleg).
- **B4**: `damage` unter 10 % → Kadenz-Deltas 30→20→12 t im debug.log; Kill → Requiem-
  Sonde + Foto der Säulen; `reducedFx on` → Wisp-Loop weg (Fenster-Release-Log).
- **B5**: `/dev minigame start race` → 7 Checkpoint-Sonden strikt aufsteigend pro Runde,
  Re-Pass desselben Bogens ohne Fortschritt still; Podium-Foto nach Zieleinlauf.
- **B6**: frischer Server-Boot mit retirter/entfernter Site-Region → `[w6b-recover]`
  nur bei echten Skips; Sweep-„finished"-Log unverändert; Audit-Tabelle im Report.
- **B7**: Cue 2× erzwingen (`/dev music play eclipse_totality`, stop, erneut) →
  zweite Instanz bei 0.7-Gain (Sonde); `forget` → wieder voll.
- **Gates**: wie Team A (compile offline, fxlib 0 NEW + Doppellauf byte-identisch für
  `wave6_crystal_burst`/`wave6_dragon_wisp`, Langdrop NUR `WAVE6B.json`).

### Datei-Ownership (exklusiv Team B)

`worldgen/end/EclipseDragonFight.java`, `client/end/EndVoidWisps.java` (nur falls das
Requiem dort einen Reg-Anker braucht — sonst unangetastet), `network/boss/BossPayloads.java`
(nur falls `sendIntro` einen optionalen Parameter braucht — Ziel: 0 Edits),
`minigames/LegacyRace.java`, `minigames/ArenaGame.java`, `worldgen/fog/FogStormSites.java`,
`music/MusicManager.java` + `music/MusicCues.java` (NUR Stretch B7); NEU:
`veilfx/Wave6DragonFxRows.java`, `tools/photon/wave6_dragon_fx.py`,
`assets/eclipse/fx/wave6_crystal_burst.*` + `wave6_dragon_wisp.*`,
`music/MusicMemory.java` (Stretch), `docs/plans_v3/langdrop/WAVE6B.json`, Report
`docs/plans_v3/session_0730/WAVE6_B_DRAGON_REPORT.md`.

**Verbotszonen**: ALLE Team-A-Dateien (insb. `entity/EclipseSpawner.java`,
`client/sky/**`), ALLE Team-C-Dateien (insb. `client/hud/AnnouncementOverlay`,
`awards/**`, `client/awards/**`, `timeline/AnnouncementService`), `client/hud/
BossIntroOverlay.java` + `client/hud/BossbarSkin.java` (NUR deren public API benutzen),
`entity/boss/**` (die vier Haus-Bosse sind in W6 fertig — kein Anlass), `worldgen/end/`
-Sequenzen (`EndShatterSequence`, `EndDiscService` — nur lesen), `stormfx/**`, globale
Frozen-Zonen (§6).

---

## 5. Team-Charter C — „Morgen-Meta & späte Aufsteher" (Sonden-Präfix `[w6c-*]`)

**Mission**: Die letzten stummen Beats des Morgen-Rituals (IDEA-09 #5/#6/#8/#9/#10)
plus der fehlende Altar-Design-Tell (IDEA-12 #7): Goals bekommen eine Enthüllung, die
Awards einen Vorhang, die Sonnenuhr einen Gang, Abwesende ein Gedächtnis, Dreck einen Seufzer.

### Scope / Deliverables

1. **C1 „Today's Decrees"-Reveal (IDEA-09 #5)** — NEU `client/awards/DecreesCard.java`
   (self-subscribed `@EventBusSubscriber(Dist.CLIENT)` im `AwardsOverlay`-Queue-Muster —
   `EclipseGuiLayers.java` bleibt frozen): getriggert client-seitig vom
   `dayClockDay`-Wechsel + nächstem Quest-State-Sync; Mains typewriten einzeln
   (`TypewriterLine`-Craft READ-only), persönliche Draws flippen mit `UI_PAGE_TURN`.
   Sneak skippt, `reducedFx` zeigt die fertige Liste, Letterbox unterdrückt (Read-only-
   Check wie AwardsOverlay). Server: die `quest.eclipse.assigned`-Actionbar-Zeile in
   `QuestEngine.ensurePlayer` wird zum reducedFx-/Fallback-Pfad degradiert. Sonde
   `[w6c-decrees] day=<d> mains=<n> personal=<n>`.
2. **C2 Awards-Pre-Beat + Kollisions-Gate (IDEA-09 #6)** — `AnnouncementOverlay` bekommt
   `public static boolean isIdle()` (Queue leer && kein aktiver Sweep); `AwardsOverlay`
   wartet darauf (zusätzlich zum bestehenden Letterbox-Gate) und öffnet mit 40-t-Dim +
   langsamem `UI_ROULETTE_TICK`-Count-in; `AWARD_STING` wandert client-seitig an den
   INTRO-Beat (Server-Sting bleibt als Arrival-Cue für versteckte Overlays —
   1-Kommentar-Note in `AwardService.sendRevealNow`). Sonde `[w6c-curtain] waited=<t>t`.
3. **C3 Sundial-Schatten-Wanderung (IDEA-09 #8)** — `SundialPlaza.onDayChanged`:
   Erase alt-Linie block-weise auswärts, Place neu-Linie einwärts über ~30 t
   (Task-Schedule-Muster; ~40 Writes), pro Placement Basalt-Puff (`S2CQuasarPayload`
   Bestands-Emitter) + `UI_CAPTION_TICK` ≤ 24 Blöcke; Finale: gilded Flash am
   Ring-Marker + 5-s-`BeamEmitter`-Säule. Fallback INSTANT (Bestandspfad) wenn kein
   Spieler ≤ 64 Blöcke ODER Chunk nicht geladen (Boot-Order-Gesetz!). Sonde
   `[w6c-sundial] animated=<b> steps=<n>`.
4. **C4 Catch-up-Digest (IDEA-09 #9)** — `RealtimeDayService.runCatchUpNow` übergibt
   `skippedDays` (statisches Handoff im `rollingOver`-Muster);
   `AnnouncementService.onDayChanged/announceNewUnlocks` emittiert bei ≥ 2 EINEN
   Digest-Sweep („Days X–Y passed… N seals opened") + volle Key-Liste 1× in den Chat.
   Lang-Keys en+de via Langdrop. Sonde `[w6c-digest] days=<x>..<y> unlocks=<n>`.
5. **C5 Morning Paper (IDEA-09 #10)** — `AwardService.onPlayerLoggedIn`: Login NACH
   Rollover (gesehen-aber-neue-Session) ⇒ kompakte Recap-Karte statt Show —
   Tag + `TimelineService.dayTitleKey` (READ-only) + Gewinner aus
   `AwardsState.resolved(latestResolvedDay())` + Mains. Transport: `S2CAwardRevealPayload`
   + `recap`-Flag (additiv im Payload-Record) ODER kompaktes neues Payload im
   C-eigenen Registrar-Stil — Entscheidung im Report begründen. Client-Karte im
   Summary-Craft von `AwardsOverlay` (oder in `DecreesCard`-Datei mitrenderend).
   Sonde `[w6c-paper] player=<n> day=<d>`.
6. **C6 Junk-Sniff (IDEA-12 #7)** — `AltarBlockEntity.handleOffering`: `exactValue == 0`
   ⇒ ALTAR_BEAM-Payload skippen, stattdessen SMOKE-Puffs + `FIRE_EXTINGUISH` 0.6 F
   Pitch — verrät ausschließlich die Junk-Grenze (aus `offering_values.json` ohnehin
   ratbar), nie den Tier (`offeringTellPitch`-Pfad unangetastet). Sonde
   `[w6c-sniff] item=<id>`.
7. **C7 (Stretch) XP-„+n"-Chip (IDEA-05 #8)** — `client/skills/SkillXpBarLayer.java`:
   beim XP-Delta ein kleiner aufsteigender „+n"-Chip neben der Leiste (12 t, gameTime-
   Envelope ⇒ tick-rate-dehnbar, W5-C6-Learning), `reducedFx` skippt.

### Akzeptanzkriterien

- **C1**: `/eclipse schedule next +1m` + Boundary abwarten → Decrees-Karte NACH dem
  Day-Sweep (Screenshot bei `tick rate 2`), Sonde 1× pro Tag; Sneak-Skip verifiziert;
  Relog danach ⇒ keine zweite Karte.
- **C2**: Boundary auf Nicht-Expansions-Tag → `[w6c-curtain]` zeigt Wartezeit > 0 wenn
  der Day-Sweep noch lief; Screenshot des Dim-Pre-Beats; Sting hörbar erst zur INTRO
  (Log-Reihenfolge).
- **C3**: Spieler an der Plaza + Boundary → Foto-Serie der wandernden Linie bei
  `tick rate 2` (30 t ⇒ ~15 s Echtzeit) + Flash-Foto; Gegenprobe ohne Spieler ≤ 64:
  `animated=false`-Sonde, Instant-Rewrite wie Bestand.
- **C4**: `/dev phase`-Werkzeuge 3 Tage überspringen lassen (Katch-up-Pfad) → EIN
  Digest-Sweep statt Parade, Chat enthält die Key-Liste 1×, Queue-Cap-Verlust = 0
  (Sonde nennt unlocks-Count = tatsächliche Key-Zahl).
- **C5**: Rollover ohne Spieler B online → B loggt ein → Recap-Karte (Screenshot),
  Sonde; zweiter Login derselben Session still.
- **C6**: Dirt opfern → Sniff-Sonde + KEIN Beam (Foto-Negativ: Altar dunkel + Rauch);
  Diamant opfern → Bestands-Beam unverändert (`[w5c-abpulse]`-Bestand feuert weiter).
- **C7**: Mining-XP → Chip-Foto bei `tick rate 2`.
- **Gates**: wie Team A; Payload-Diff (falls `recap`-Flag) strikt additiv; Lang-Keys
  NUR `docs/plans_v3/langdrop/WAVE6C.json` (en+de paritätisch).

### Datei-Ownership (exklusiv Team C)

`progression/goals/QuestEngine.java`, `progression/realtime/RealtimeDayService.java`,
`timeline/AnnouncementService.java`, `awards/**` (Service/State/Config),
`client/awards/**` (inkl. NEU `DecreesCard.java`, ggf. `MorningPaper`-Renderer),
`client/hud/AnnouncementOverlay.java`, `network/S2CAwardRevealPayload.java` (nur
additives `recap`-Flag), `worldgen/structure/SundialPlaza.java`,
`ritual/AltarBlockEntity.java`, `client/skills/SkillXpBarLayer.java` (Stretch); NEU:
`docs/plans_v3/langdrop/WAVE6C.json`, Report
`docs/plans_v3/session_0730/WAVE6_C_MORNING_REPORT.md`.

**Verbotszonen**: ALLE Team-A-Dateien (insb. `entity/EclipseSpawner.java` — C4/C5
arbeiten NICHT über Nacht-Events), ALLE Team-B-Dateien (insb. `network/boss/**`,
`worldgen/end/**`, `minigames/**`), `progression/DayScheduler.java` +
`drama/DawnCeremony.java` (Bestands-Sequenzer NICHT umbauen — C2 löst die Kollision
client-seitig), `client/hud/BossIntroOverlay.java`, `client/hud/BossbarSkin.java`,
`client/hud/DayTimerLayer.java`, `client/hud/SidebarPanel.java`/`SidebarExpanded.java`
(W4-FEEL-Bestand), `offering/OfferingService.java` (W5-C-Bestand, nur lesen),
`ritual/BeamEmitter.java` (nur API-Aufrufe), globale Frozen-Zonen (§6).

---

## 6. Gesetze für ALLE Charters + globale Frozen-Zonen

Jedes Team MUSS (aus AGENTS.md + Wave-Historie, unverändert gültig):

1. **Erst-Verifikation vor jeder Codezeile**: Tabelle im Report mit rg-Beweisen, dass
   jedes Item wirklich offen ist. §1-Lehre dieser Welle: nach der SACHE greppen, nicht
   nach Plan-Vokabular (BossIntroCard-Falle). Bereits Konsumiertes wird mit Beweis
   gestrichen, nicht doppelt gebaut.
2. **`.fx`-Assets NUR via `tools/photon/fxlib.py`-Generatoren** (uuid5-deterministisch,
   eigener Generator pro Team, `.fxproj`-Sibling committen, `fxlib.py validate --lint`
   0 neue Findings, Doppellauf byte-identisch). Quasar-Emitter-JSONs handschreibbar.
3. **V2.1-Stacking-Law**: Birth-Tints dunkel, HDR ≤ 1.45, Schalen breit, Counts
   getrimmt; CullBox auf JEDEM Photon-Emitter; Loops nur WINDOWED mit Hysterese;
   `reducedFx`-Gates (Operator-Holds dürfen als expliziter Override zeichnen);
   Quasar-/Vanilla-Fallbacks je neuer Row (Quasar-Leg `null` nur für NEUE Cues legal).
4. **Keine neuen GLSL-Dateien und keine GLSL-Edits ohne glslangValidator-Beleg** — in
   dieser Welle braucht KEIN Deliverable GLSL; wer doch eines „braucht", hat den Scope
   verlassen.
5. **Lang-Keys NUR als `docs/plans_v3/langdrop/WAVE6<X>.json`** (en+de paritätisch).
   NIEMAND ruft während der Parallel-Phase `merge_langdrops.py` auf — der Hauptagent
   merged zentral in der Abnahme. Die beiden Mod-lang-JSONs sind Schreibverbotszone.
6. **Keine `data/minecraft/tags`-Duplikate** (generated-Root prüfen).
7. **Gradle immer `flock /tmp/gradle.lock ./gradlew … --offline`**; laufende Server-/
   Client-JVMs NIE killen oder starten (Live-Abnahme macht der Hauptagent; F-103:
   frische JVM nach Kompilieren gilt für IHN).
8. **DEBUG-Sonden im `[c2-splash]`-Muster** (`EclipseMod.LOGGER.debug` →
   `run/logs/debug.log`): Präfixe `[w6a-*]`, `[w6b-*]`, `[w6c-*]`. llvmpipe-Gesetz:
   jede visuelle Behauptung braucht einen statisch fotografierbaren Zustand (Nacht-
   Zustand, prewarm-Standbild, `tick rate 2` + Dauer ≥ ~3 s, gameTime-Envelope) ODER
   eine Sonde ODER einen Bestands-Hold (`/eclipsefx holds` listet sie).
9. **Additive Diffs, kein Reformat fremder Zeilen**; jede Fremd-Datei-Änderung als
   klar kommentierter `WAVE6 (F-106 <TEAM>)`-Hook.
10. **Reports** nach W5-Muster: Erst-Verifikationstabelle, Umsetzung + Design-
    Entscheidungen je Item, Gate-Belege, RCON-Abnahme-Drehbuch (llvmpipe-tauglich).
11. **Neue Client-Overlays subscriben sich SELBST** (`@EventBusSubscriber(Dist.CLIENT)`,
    AwardsOverlay-Präzedenz) — `client/EclipseGuiLayers.java` ist für alle drei Teams
    frozen (das ist der W6-Kollisionsbrecher für die geteilte HUD-Bühne).

**Globale Frozen-Zonen (kein Team fasst sie an):** `UserFeedback.md` (Hauptagent),
`FxCues.java` (Cue-Ids beidseitig via `FxCues.cue("…")` re-derivieren),
`PhotonBridge.java`, `PhotonFxRegistry.java` (nur `registerRow`-API),
`network/fx/FxPayloads.java` + `veilfx/EclipseFxState.java` (W6 braucht keine neuen
FX-Sonderpfade — die Cue-Lane reicht allen dreien), `tools/photon/fxlib.py`, die beiden
lang-JSONs, `client/EclipseGuiLayers.java`, `client/ClientStateCache.java`,
`cutscene/**` inkl. `cutscene/dev/**` (die Bestands-Holds sind Abnahme-Werkzeuge, keine
Baustelle), `stormfx/**`, `entity/boss/**` + `client/entity/fogboss/**` (W5-Bestand),
`limbo.fsh`, `limbo/GhostShipBuilder`/`LimboSeascape`, `veilfx/LimboAmbience.java`/
`LimboRowChant.java`, `drama/CombatFeedbackFx.java`, `drama/WitnessedLossService.java`,
`hearts/**`, `lives/**`, `network/hearts/**`, `credits*`-Klassen und -Generatoren,
`offering/OfferingService.java`, `progression/DayScheduler.java`, `drama/DawnCeremony.java`.

### Ownership-Matrix (Kurzform, HART — KEINE Datei in zwei Teams)

| Zone | A | B | C |
|---|---|---|---|
| `entity/EclipseSpawner` + `TheOtherEntity` + `UmbralStalkerEntity` + `client/entity/stalker/**` | ✅ | ❌ | ❌ |
| `client/sky/OverworldPurpleEffects` + `client/sky/StarField` | ✅ | ❌ | ❌ |
| NEU `network/night/**`, `client/drama/NightDreadFx`, `veilfx/Wave6NightFxRows`, `tools/photon/wave6_night_fx.py` | ✅ | ❌ | ❌ |
| `worldgen/end/EclipseDragonFight` (+ `client/end/EndVoidWisps` bei Bedarf), `network/boss/BossPayloads` (Ziel: 0 Edits) | ❌ | ✅ | ❌ |
| `minigames/**`, `worldgen/fog/FogStormSites`, `music/**` (nur Stretch B7), NEU `veilfx/Wave6DragonFxRows`, `tools/photon/wave6_dragon_fx.py` | ❌ | ✅ | ❌ |
| `progression/goals/QuestEngine`, `progression/realtime/RealtimeDayService`, `timeline/AnnouncementService`, `awards/**`, `client/awards/**`, `client/hud/AnnouncementOverlay`, `network/S2CAwardRevealPayload`, `worldgen/structure/SundialPlaza`, `ritual/AltarBlockEntity`, `client/skills/SkillXpBarLayer` (Stretch) | ❌ | ❌ | ✅ |
| Eigene NEUE Dateien (Generator, Rows, Assets, Langdrop, Report) | Namensraum `wave6_night…`/`WAVE6A` | `wave6_dragon…`/`wave6_crystal…`/`WAVE6B` | `WAVE6C` |

Kollisionscheck (explizit durchgerechnet): `client/hud/` wird von B (nur READ auf
`BossIntroOverlay`-API — 0 Edits) und C (`AnnouncementOverlay` exklusiv) berührt —
disjunkt auf Dateiebene. `client/drama/` bekommt EINE neue A-Datei, `LastMinuteHush`
frozen. `worldgen/` teilt sich in `end`+`fog` (B) vs. `structure/SundialPlaza` (C) —
disjunkt. Boss-Karten-Bühne: B sendet über die BossPayloads-Lane, C gated NUR
AwardsOverlay auf das C-eigene `AnnouncementOverlay.isIdle()` — kein Team referenziert
ungemergten Code des anderen.

---

## 7. Risiken (Top 3) + Gegenmittel

1. **Geteilte Center-Stage des HUD** (B-Drachen-Karte, C-Decrees-Karte, C-Awards-Show,
   Bestands-Announcements könnten am selben Abend kollidieren). *Gegenmittel*:
   Datei-Matrix trennt hart (B editiert keine Overlay-Datei, nur die Send-Seite);
   `BossIntroOverlay` wartet BEREITS selbst auf die freie Bühne (Queue-Hold verifiziert,
   Z. 98); C2 führt `isIdle()` als einziges neues Gate ein und NUR C konsumiert es;
   Abnahme fährt die drei Bühnen in getrennten Sessions (§8). Falls in der Abnahme doch
   eine Überlappung auffällt: Reihenfolge-Fix gehört dem Hauptagenten, nicht den Teams.
2. **Sky-Stack-Regression durch A2/A3** (der violette Sonnen-/Zenit-Stack ist
   F-096/F-104-abgenommen; Iris-Selbstabschaltung und `creditsDark`-Fade dürfen nicht
   kippen). *Gegenmittel*: NUR Farb-/Alpha-Arithmetik + ein Zusatz-Quad im bestehenden
   Mond-Pass, multiplikativ NACH allen Bestands-Faktoren; `event set none`-Gegenprobe
   gegen die F-105-Midnight-Referenzfotos ist PFLICHT-Akzeptanzkriterium; IDEA-16 #4
   bleibt exakt deshalb gestrichen (D-5) — niemand sonst zieht am Sky in dieser Welle.
3. **Drachen-Testbarkeit** (Tag-13-Gate F-023, End-Disc-Abhängigkeit, vanilla
   `EnderDragonPhase`-Timing auf llvmpipe). *Gegenmittel*: Abnahme auf dem Langzeit-Save
   via `/eclipse day set 13` (Gate-Log `WARNED_EARLY_DRAGON` beachten); alle flüchtigen
   Beats haben Sonden als Primärbeweis; die zwei Foto-Beats (Kristall-Bloom, Requiem-
   Säulen/Wisp) sind bewusst als Standbilder ≥ 3 s bzw. WINDOWED-Loop (beliebig lange
   fotografierbar) designt; Karten-/Crescendo-Envelopes laufen auf gameTime
   (W5-C6-Präzedenz) und dehnen sich mit `tick rate 2`.

---

## 8. Abnahme-Reihenfolge (Hauptagent)

**Schritt 0 — Fotoschulden-Abnahme (VOR dem W6-Merge, Werkzeuge sind auf HEAD):**
Die Holds liegen komplett im aktuellen Stand (`ACTION 12/13/14` verifiziert). Restart-
Frage: laufen Server UND Client bereits auf einem Build ≥ Commit `2789676` (W5-Merge),
ist KEIN Restart nötig — sonst beide JVMs einmal frisch von HEAD booten (die Command-
Leaves sind serverseitig registriert, die Hold-Logik ist clientseitig: BEIDE Seiten
brauchen den Stand).

```
# D-1 Ghost-Wake (wakehold):
eclipse tp_limbo Dev                                  # Kamera auf die Ruderbank
execute as Dev run eclipsefx limbo wakehold on
tick rate 2                                           # FOTO: Soul-Driftlinie + Splash am Ruderblatt
rg -c "\[w5a-wakehold\]" run/logs/debug.log           # wächst
execute as Dev run eclipsefx limbo wakehold off       # Gegenprobe: friert ein, [c2-splash] läuft weiter
# D-2 Tyrant-Flicker (flickerhold):
summon eclipse:fog_tyrant ~10 ~ ~
execute as Dev run eclipsefx tyrant flickerhold blackout   # FOTO: Krone/Auge/Core DUNKEL
execute as Dev run eclipsefx tyrant flickerhold on         # tick rate 2: 20t-Kadenz fangbar
execute as Dev run eclipsefx tyrant flickerhold off        # FOTO: Glow zurück
# Hygiene:
execute as Dev run eclipsefx holds                    # alle vier Holds = off
tick rate 20 ; Tyrant entfernen
```
Ergebnisse als W4-Fotoschulden-Closeout in `UserFeedback.md` (F-104-Zeile) nachtragen.

**Schritt 1 — Merge-Gates**: Langdrops zentral mergen (`python3
tools/langmerge/merge_langdrops.py WAVE6A/B/C.json`), `flock … compileJava/
processResources --offline`, `fxlib validate --lint` (0 NEW), Doppellauf-Hashes prüfen.
Danach **frische Server- UND Client-JVM** (F-103) + einmal
`/photon_client clear_client_fx_cache` + F3+T (neue `.fx`-Assets beider Teams).

**Schritt 2 — Team A (Nacht-Session)**: `/eclipse event set umbral` + `time set
midnight` → Mond/Sterne-Fotos; Relog → nightsync-Login-Sonde; Pack-/Other-/Dawn-Sonden
nach §3; `event set pale` → Blässe-Foto; `event set none` + Referenz-Gegenprobe.
Der Nacht-Zustand hält — hier ist KEIN Hold nötig.

**Schritt 3 — Team B (Drachen/Race-Session)**: `/eclipse day set 13` → Theme +
Intro-Karte (tick rate 2), Kristall-Kills, Landing, Crescendo, Kill → Requiem-Fotos;
`reducedFx`-Gegenprobe Wisp; Restart-Re-Attach-Gegenprobe (skip-reattach); danach
`/dev minigame start race` → Checkpoint-Leiter + Podium; B6-Boot-Sonde beim
Session-Server-Boot mitlesen.

**Schritt 4 — Team C (Morgen-Session)**: `/eclipse schedule next +2m` → Decrees +
Curtain + Sundial-Fotos; Katch-up-Tage via `/dev phase` → Digest; Zweit-Login →
Morning Paper; Dirt- vs. Diamant-Offering → Sniff-Negativ + Bestands-Beam.

**Schritt 5 — Hygiene**: `tick rate 20`, Mobs/Events aufräumen (`/eclipse event set
none`), `/eclipsefx holds` (alles off), `run/logs/debug.log`-Sonden-Sammelgreps
(`rg "\[w6[abc]-"`) archivieren, `UserFeedback.md` F-106-Zeile schreiben (Hauptagent).
