# AUDIT_REVERIFY — Re-Verifikations-Audit (F-095), Session 30.07.

Unabhängiges Code-Audit über ALLE Feedback-Punkte aus `/workspace/UserFeedback.md`
(F-001..F-094 inkl. Subpunkte a/b, FX-W10/W11 sowie die Stichpunkte unter „Fertig
(frühere Sessions, Auszug)"). Geprüft wurde ausschließlich im Quellcode
(`src/main/java`) und in den Assets (`src/main/resources`): Existenz der Klassen /
Methoden / Assets, Wiring (Event-Bus-Subscription, Command-Tree-Registrierung,
Registry-Einträge, Payload-Registrierung) und Lang-Key-Parität. Kein Produktionscode
wurde verändert.

**Hinweise zur Nummerierung:** F-029 und F-072 sind in der Feedback-Datei nicht
vergeben (Sprünge F-028→F-030 und F-071→F-073). F-071/078/079 sowie F-095..F-099
sind Prozess-/Dauerbetriebs-Punkte ohne code-auditierbaren Inhalt. F-062 ist offen
und wird im eigenen Abschnitt unten behandelt.

**Globale Regressionschecks (alle sauber):**

- Lang-Parität: `en_us.json` = `de_de.json` = **2834 Keys**, 0 Abweichungen in beide Richtungen (inkl. aller 5 Woah-Langdrops aus `docs/plans_v3/langdrop/woah_*.json` — vollständig gemerged).
- **Keine** `TODO`/`FIXME`/`XXX`-Kommentare in 1245 Java-Dateien.
- **Keine** auskommentierten Registrierungen gefunden; 66 Klassen registrieren Commands via `RegisterCommandsEvent`, Stichproben (Scare/Skin/Stage/Preload/Ferryman/Inspect) alle verdrahtet.
- Photon-FX-Kreuzcheck: 126 Row-/Direct-Spawn-Referenzen gegen 227 `.fx`-Assets — **eine** echte Fehlstelle (`rim_recede`, siehe G-1). `slam_dust_puff`/`storm_dust_puff` sind KEINE Waisen (Collision-Sub-Emitter-Kinder innerhalb anderer `.fx`-Binaries, s. `tools/photon/events_fx.py` §3, `build_storm_fx.py`); `boss_summon_beacon_<kind>` wird dynamisch suffigiert (Assets `_0.._3` vorhanden); `fx/cue/...`-Ids sind Wire-Ids, keine Asset-Pfade.
- Sounds: alle 87 `sounds.json`-Events zeigen auf existierende Oggs (42 eclipse-Oggs); alle 55 in `EclipseSounds`/`EclipseMusicSounds` registrierten Ids haben `sounds.json`-Rows; `music.*`/`ui.*` werden bewusst per RL/Alias abgespielt (`MusicFadeSound`, `UiSounds`, `BackroomsBuzz`).
- Quasar-Kreuzcheck: 39 Row-Fallback-Emitter, alle unter `assets/eclipse/quasar/emitters/` vorhanden (99 Assets).
- Glitch-Pipelines: alle 6 Effekt-Ids (`outline`, `datamosh`, `scanlines`, `invert`, `void`, `dome`) besitzen das Paar Post-JSON + `.fsh`.

---

## Verifiziert OK

| F-Nr | Kurzname | Beweis: Datei/Klasse/Asset |
|---|---|---|
| F-001 | custom_payload-Kick (32K-Limit) | `network/NetCodecs.LARGE_UTF8`; Chunked-Sync in `S2CCutsceneLibraryPayload`, `S2CSkillTreePayload` |
| F-002 | Limbo-Portal/Disc feste Himmelsrichtung | `client/sky/LimboSpecialEffects` (LIMBOFIX2, `celestialDirection`, feste Elevation/Azimut) |
| F-003 | Deckhands: Ruck/Culling/Spiegel | `client/entity/DeckhandRenderer` (60t-Controller-Reset-Fix), `limbo/OarAnimator` (Port-Mirror aus Sitz statt yBodyRot) |
| F-004 | Bossbars prozedural, 4 Themes | `client/hud/BossbarSkin` („Everything is drawn procedurally", Theme-Tabelle), `network/S2CBossbarStylePayload` |
| F-005 | Outpost-Plateau-Sitz | `worldgen/structure/StructureStamper.footprintOf` (`pillager_outpost` → 48, Plateau-Mode über Footprint gesampelt) |
| F-006 | Blackscreen-Guard + Client-Reißleine | `network/fx/S2CScreenFadePayload.sustained` + `cutscene/client/CaptionRenderer.MAX_HOLD_TICKS = 60` (3 s Client-Clamp) |
| F-007 | Struktur-Anim (Riss, Blitz, Displays, Hover) | `worldgen/stage/StructureFlightFx` (LIGHTNING_INTERVAL_TICKS, MIN/MAX_HOVER_TICKS, `flight_fx.max_displays`-Budget) |
| F-008 | Riesen-Monolithen am Map-Rand | `worldgen/stage/ExpansionBorderFx` (RING_BOULDERS-Monolithe, MOTION_BLOCKING_NO_LEAVES-Anker, view_range-Fix) |
| F-009 | Map-Erweiterung 2,3× schneller | `worldgen/stage/ExpansionTiming` (Messtabelle 141,6 s → 60,7 s, ×2.33 im Klassen-Doc) |
| F-010 | GUI-Scale: Akzent-Zeile pro Frame | `bootstrap/BootstrapScreen` (`drawCenteredString(width/2, …)` im Render-Pfad) |
| F-011 | EMI-/Mod-Versionscheck | `admin/ModVersionCheck` (Build-Metadata-Toleranz), `gametest/admin/ModVersionCheckTests`, `client/emi/EclipseEmiPlugin` |
| F-012/069 | Classic-Textur-Audit (13 Rebuilds) | `docs/plans_v3/CLASSIC_BLOCK_AUDIT.md`, `classicblocks/`-Paket, Generator `tools/classicblocks/` |
| F-013 | Limbo-Bausperre (nur /devmode) | `protection/LimboProtection` (Break+Place cancelled, `DevMode.isExempt` als einziger Ausweg) |
| F-014 | Limbo-PvP-Sperre + Toggle | `LimboProtection.isPvpAllowed` (+ Bosskampf-Ausnahme), `devtools/dev/DevLimboCommands` (`/dev limbo pvp on|off`, persistiert) |
| F-015 | Kein fröhlicher Track beim Kentern | `limbo/StartEventCutscene` (MUSICFADE: Fade erreicht 0 exakt am Dimension-Hop, kein intro_storm-Start) |
| F-016 | Sturm vor der Blende gespawnt | `sequence/IntroSequence` (STORMFIRST: Vortex wird hinter dem Schwarz adoptiert; „FIRST frame … has the storm in it") |
| F-017 | Debris-Choreografie | `sequence/StormDebrisFx` (Orbit, Blitz-Kicks, Spiral-Kollaps; Sweep-Doktrin) |
| F-018 | Echte Musik-Fades | `music/MusicManager` (Dimension-Hop-Root-Cause dokumentiert + behandelt), `music/MusicFadeSound`, `StartEventCutscene` t=80 |
| F-019 | Altar-Quest Touch-Trigger + 2-min-Karenz | `ritual/AltarBlock.touched → EclipseSignals.fireAltarTouched`; `progression/goals/QuestEngine.ARRIVAL_GRACE_TICKS = 2400` |
| F-020 | Schutzzone 96→71, Fallschutz 112→87 | `protection/ProtectionConfig.DEFAULT_SPAWN_RADIUS = 96−25 = 71`; Fall-Safe = radius+16 = 87 (Migrations-Log inklusive) |
| F-021 | Shift = einzahlen, Rechtsklick = Menü | `ritual/AltarBlock.onSneakRightClick`; alte Herzfragment-Doppel-Sneak-Lane explizit entfernt (Klassen-Doc) |
| F-022 | Splitterladen-UI (Icon/Anzahl/Börse) | `client/altar/AltarScreen` (Preis-Chips count+currency, Balance-Footer, 6 Textkorrekturen via Lang) |
| F-023/047 | End-Timeline + Insel-Crash-Finale | `worldgen/end/EndDiscService` (FINAL_DAY=12, Tag-7-Herald-Fenster), `EclipseDragonFight.dragonDayReached` (Tag 13), `EndIslandCrashFx`, `EndShatterSequence` |
| F-024 | Windaltar wirft über höchste Plattform | `worldgen/structure/SkyLauncher` (Klettertarget = höchste Plattform + TARGET_MARGIN, Slow-Falling-Refresh, Descent-Steering, Stall-Watchdog) |
| F-025 | Mesa-Pyramide leere Chunks | `worldgen/DiscRepairService` (Report-Zitat „Mesa/Savannen-Biome wo die Pyramide entsteht") |
| F-026 | Schneeberg-Fluss friert | `worldgen/DiscBiomeSource.FROST_RIVER_ID = frozen_river`, `DiscTerrainFunction` PACKED_ICE/BLUE_ICE (nicht random-tickbar = kein Schmelzen) |
| F-027/053 | Herold Kampf-/Siegesmusik + Cutscene | `entity/boss/HeraldEntity.playVictoryScore` (F-027-Kommentar: „victory score belongs to the KILL"), `sequence/HeraldSummonSequence` |
| F-028 | 7 Xbox-Era-Maps | `xboxevent/XboxEraProfile` + `XboxDimensions` (era-korrekte Paletten, disjunkte Fenster), `assets/eclipse/xboxworlds/` |
| F-030–034 | Sturm-Paket (Perf/Kampf/Burst/LOD) | `pinwheel/shaders/program/storm_volume.fsh` (F-030-Header: HALF RESOLUTION + adaptive steps + `volume_half`-Upsample), `stormfx/StormSiege` (wächst, Kern, Debris-Orbits, echte Display-Würfe), `stormfx/StormNearfieldFx` + `veilfx/StormNearfieldFxRows` |
| F-035 | Nether-Öffnung Tag 2 (47 s + Dauerwolke) | `sequence/NetherOpeningSequence`, `sequence/NetherUpheavalFx` (Eruptionssäule), `client/nether/NetherOpenClientFx`, `veilfx/NetherOpenPhotonFxRows` |
| F-036–041 | Zauberstab-Rework komplett | `wand/WandTree` („48 nodes, 16 per path" + Rebirth), `wand/WandSpells` („30 spells, 10 per path"; `riss.umbra_lanze` ERSETZT Phasenwelle, F-038-Kommentar), `wand/WandPowers` („F-040: cooldowns are GONE", nur Veilladung), `client/wand/WandSelectInput` (nur mit `EclipseWandItem` in Hand), `devtools/dev/DevWandCommands` (xp/level) |
| F-042/043 | Backrooms Dread + 5 Ebenen | `backrooms/BackroomsDread` (Lichter-Aus, Far-Dread, Hollow-Exit-Beacon), `backrooms/BackroomsLayers` („FIVE classic backrooms levels", Level 4 Flooded Halls, Level 5 The Hollow) |
| F-044–046 | Tagesriss/Portal/Schlüssel/Ferryman | `ferryman/finale/DayRiftOrbits` (F-044-Kommentar, Fallout sammelt sich um Mittelinsel), `PortalFormation` + `PortalKeyEntity` (Riesenschlüssel), `FerrymanSpecialAttacks` (F-046b, 3 Specials), `DevFerrymanCommands` (`/dev start_ferryman`) |
| F-048/049 | Glitch Lila-Void + Altar-Ambient + Farb-Param | `glitchzone/GlitchColors` (Palette inkl. `purple`, `void_purple`-Syntax), `glitchzone/AltarGlitchAmbience`, Farb-Id im `/dev glitch`-Command orthogonal zum Effekt |
| F-050–052 | Skins + /msg-Policy | `devtools/dev/DevSkinCommands` (URL/NameMC/Name; `adminskin` = bundled purple skin), `skin/SkinUrlResolver`, `admin/WhisperPolicy` (`ALLOWED_TARGETS = ["Sonic0810"]`) |
| F-054 | /dev structure geerdet | `worldgen/structure/StructureGrounding` + `devtools/dev/DevStructureCommands` |
| F-055 | „Letzte Überfahrt"-Erklärung | 15 „Überfahrt"-Lang-Values in `de_de.json` (advancement/announce/dev-Keys), en-Pendants vorhanden (Parität) |
| F-056–058 | Credits-Finale komplett | `ritual/CreditsSequence` (Shatter-Prolog, Spieler INVISIBLE, Auto-Run raus, SPACE-Skybox, Ortho-FOV), `CreditsShatterAct`, `CreditsFormationAct` (tausende Displays), `client/menu/CreditsScreen` |
| F-059 | 20 Biome + 15 Flora-/Kristallblöcke | 21 Biome-JSONs unter `data/eclipse/worldgen/biome/`, `registry/WorldgenBlocks` + `PaleGardenBlocks`, 37 Blockstates |
| F-060 | Photon-Editor-Bericht | `docs/plans_v3/PHOTON_EDITOR_CAPABILITIES.md` |
| F-061 | Legacy-Race Rundkurs | `minigames/LegacyRace` (7 Checkpoint-Bögen IN ORDER, Runden, Podium, Fluss-Reset), `minigames/CourseBlocks` |
| F-063 | /dev stage skipdark | `devtools/dev/DevStageCommands` + `sequence/ExpansionSequence` (Cutscene-Abbruch-Pfad) |
| F-064 | ghostscreen + backroomsscare | `devtools/dev/DevScareCommands`, `backrooms/BackroomsScare`, `client/backrooms/JumpscareOverlay` |
| F-065 | /dev jumpscare 30 Varianten | `scare/ScareIds` („The 30 /dev jumpscare <version> scripts", #30 `totality`), `client/scare/ScareScripts` (34 Script-Builder), `ScareDirector`/`ScareOverlay`/`ScareRampSound` |
| F-066 | /invsee + /enderchestsee | `devtools/inspect/InspectCommands` (beide Literale), `LiveEnderChestContainer` |
| F-067 | Mining-Multiplikator | `devtools/MiningSpeedService` (Attribut-Modifier + SavedData-Persistenz), verdrahtet in `devtools/dev/DevPlayerCommands` |
| F-068 | Schwarzes Loch V2 | `ritual/CreditsBlackHoleAct` (Doppler-Bänder, Spaghettisierung, Swallow-Pulse, Plane-Tilts), `client/credits/CreditsBlackHolePostFx` (Lensing/Aberration/Streaks), `pinwheel/post/black_hole.json` |
| F-070 | Zauberstab-FX Pfad-Identitäten | `client/wand/WandFx2PhotonRows` (RISS/GLUT/STERN-Muzzles, `tierScale` = F-070-Kontrakt), 18 `riss_*`/`glut_*`/`stern_*`-`.fx`-Assets, `WandCastAccentOverlay`, `WandPathScreen` |
| F-073 | Trailer (Erstfassung) | `/workspace/ECLIPSE-Trailer-4K.mp4` + Quellprojekt `/workspace/trailer/` (Remotion) |
| F-074 | Altar-UI + Kaufbestätigung + Zeremonie | `client/altar/AltarScreen` (Confirmation-Overlay, Flying-Icons BUYFX_*, Leistbarkeits-Kanten), `economy/AltarBuyCeremony` (kategoriebasiert) |
| F-075 | Altar-Aura V2 + Anchor-Republish | `sequence/IntroSequence.republishAltarAnchor` (Root-Cause im Doc: ALTAR_CENTER nach Restart nie re-publiziert; Float-Gate via `SanctumVersionData`), `veilfx/AltarAuraFxRows` + `AltarAura2FxRows` (Leiter-Stufen) |
| F-076 | Altar als GeckoLib-Monument | `client/altarmodel/AltarModelRenderer` (`AutoGlowingGeoLayer` + `altar_glowmask.png`, erupt/idle-Beschreibung), `ritual/AltarModelTriggers`, `assets/eclipse/geo/block/` + `animations/block/` |
| F-077 | End-Ankunft „Gigantismus" (DIM-Boost) | `sequence/endarrival/EndArrivalSequence`: `DIM_OMEN=0.55F`, `DIM_SPIKE=0.8F`, `DIM_SIMMER=0.2F`, Cues auf CUE_GRADE |
| F-080 | Stop hängt nicht mehr in SAVING | `core/EclipseShutdownSweep` (FX-Schwärme VOR dem Save geräumt), `veilfx/PhotonMobFx` (Bridge-Sweep-Doktrin) |
| F-081/082 | Statue-Trigger + Wipe-Reset | `entity/boss/fog/TyrantStatue` (ARMED→AWAKEN→COOLDOWN, `REARM_TICKS=600` = 30 s, `onFightReset`, Selbstheilung), `FogTyrantFightHooks` |
| F-083 | Stürme entkoppelt (reconcile) | `entity/boss/fog/FogBankMarker` (Reconcile-Pattern: clear-all → JEDE aktive Site re-marken) |
| F-084 | Display-Leak + Scope-Tags + Orphan-Sweeps | `stormfx/StormSiege` (`STORM_FX_TAG`-Umbrella, `FIGHT_SCOPE_TAG_PREFIX`, Stray-Discard bei Chunk-Load — deckt Crash-Strays UND Chunk-Unload-Orphans, F-084-Kommentare) |
| F-085/086/087 | Grab-Schutz komplett | `lives/GraveProtection` (F-085: `ExplosionEvent.Detonate`-Pruning + `LivingDestroyBlockEvent`-Cancel; F-086: `StormSiege.liftable`-Ausschluss; Zauber-Blacklist), `GraveBlock` (Scatter-Fallback; 1200.0F Blast-Resistance) |
| F-088 | Limbo-Pink-Objekt | `client/sky/LimboSpecialEffects` (F-088-Konstante: 45° Azimut-Schwenk weg vom Bug, Fan verkleinert/gedimmt), `veilfx/LimboAmbience` |
| F-089 | Evakuierung + End-Disc-Heightmap + SpawnReturns | `core/util/SpawnReturns` (Heimkehr-Teleports), F-089/F-089b-Annotationen in Sequenz-Code |
| F-090/093 | Credits + Schwarzes Loch V3 | `client/credits/TitleCardLayer` (dynamischer Z-Lift, Doc verweist auf gemessenes z=12400-Problem), `CreditsBlackHolePostFx.JetPulse`, `ritual/CreditsMapRipAct`, `CreditsSkyFx.jetPulse` |
| F-091 | /dev preload everything | `devtools/dev/DevPreloadCommands`, `worldgen/pregen/MapPregenService` + `PregenState` (Persistenz/Auto-Resume/Re-Run-Guard) |
| F-092 | Rand-Berge mehrschichtig | `client/sky/RimMountainSilhouette` (Layer A Fern-Silhouette, Fade-Bänder), `worldgen/DiscTerrainFunction` (Terrain-Wall-Band), Recede-Cue in `ExpansionBorderFx` (→ aber G-1) |
| F-094 | Trailer V2 FINAL | `/workspace/ECLIPSE-Trailer-4K.mp4` (78,6 MB ≈ 20,9 Mbps × 30 s), `trailer/`-Projekt |
| F-094a | Photon-Client-Crash (Enum-NPE) | `tools/photon/fxlib.py` `_RENDER_MODES`-Validierung („Photon deserializes enum strings with valueOf-or-null … Validate at authoring time") |
| F-094b | Fährmann-Re-Run-Fixes | `devtools/dev/DevFerrymanCommands.clearStaleVictoryLatch` (2 Aufrufer), `ferryman/finale/FinaleSequence` (Orphan-Boss-Sweep im Arrival-Beat, Boss-Identity-Guard) |
| FX-W10 | Tyrant Step-Beats + Stride-Wake | `fx/boss/tyrant_step_out.fx` + `tyrant_step_in.fx` (+ fxproj), `FogTyrantEntity.STRIDE_WAKE_BLOCKS = 8.0`, `tickStormStepVanish` |
| FX-W11 | Stacking-Law-Fix-Assets | `.fx` vorhanden: `boss_intro_shockwave`, `boss/tyrant_blind_burst`, `altar_levelup`, `altar_aura_powerup`, `nether_eruption`, `day_rift_maw`, `storm_burst_shockwave`; DayRift-Stratifikation in `DayRiftOrbits` (Keystone-Slabs tief+langsam) |
| (früher) | Volumetrischer Veil-Sturm + Occluder/EXO | `stormfx/StormVolumeFx`, `storm_volume.fsh`/`.json`, `StormWallRenderer.OCC_VOLUMETRIC_CORE` (30 %-Kern) |
| (früher) | Glitch-Zonen-System + /dev glitch | `glitchzone/GlitchZoneService`/`GlitchZoneEffects`/`GlitchZoneState` (`eclipse_glitch_zones.dat`), 6 Post/FSH-Paare (Effekt-Ids heute: outline/datamosh/scanlines/invert/void/dome — s. G-5) |
| (früher) | Altar-UI-Gating, versiegelte Angebote, Spawn-Protection, DEVMODE | `AltarScreen` (`sealedOffers`-Count), `protection/ProtectionConfig`, `DevMode` |
| (früher) | Skilltree-/Bestiary-Gates, Arm-Artefakt | `client/skills/SkillTreeScreen` (server-validiert), `network/bestiary/BestiaryPayloads`, `artifact/ArmArtifactItem` + `ArmArtifactRenderer` |
| (früher) | Übersetzungs-Audit | en/de je 2834 Keys, 0 Paritätsverletzungen; Umbral-/Orin-/Tür-/Zeitleiste-Keys vorhanden |
| (früher) | Journal crashsicher, Backpack-Rezepte raus, Doppel-XP | `wand/WandPhaseService` (Phasenwelle heute durch Umbra-Lanze ersetzt), `gameplay/BackpackCraftBan` |
| (früher) | Backrooms-Restriktionen + Exit | `backrooms/BackroomsRestrictions` (kein Break/Place, `blocksCast`-Wand-Guard an der Netzwerk-Grenze), `BackroomsPortal`, `BackroomsLeaveCommand` |
| (früher) | Nether-Eingang ohne Fallschaden, Himmel-Eskalation, Text-Dedupe | `worldgen/nether/BreachTransferService` (Funnel-Capture ohne Fallschaden), `client/sky/OverworldPurpleEffects` (SKYDAY-Eskalation Tag 1..14), `timeline/AnnouncementService` |

**Zwischenfazit:** 92 code-auditierbare F-(Sub-)Punkte + 8 Frühere-Sessions-Stichpunkte
geprüft — alle mit belastbarem Code-/Asset-Beweis vorhanden und verdrahtet. Die einzigen
Befunde stehen unten.

---

## Lücken / Verdacht

| Lfd-Nr | Problem | Beweis | Vorschlag | Schweregrad |
|---|---|---|---|---|
| G-1 | **`rim_recede`-Photon-Asset fehlt** (F-092): Row + Cue sind voll verdrahtet (`FxCues.CUE_RIM_RECEDE`, gefeuert von `ExpansionBorderFx` beim Release-Beat), aber `assets/eclipse/fx/rim_recede.fx` wurde nie authored — Clients bekommen dauerhaft nur das Quasar-Leg `growth_dust_wall`. Im Code selbst als Interim dokumentiert („until the Photon rim_recede asset is authored … LAYER law"). | `veilfx/WorldEventPhotonFxRows` (Zeile ~158 Row `fx("rim_recede")` + Klassen-Doc), `network/fx/FxCues.CUE_RIM_RECEDE`, kein Treffer in `assets/eclipse/fx/` | Asset mit `tools/photon/fxlib.py` authoren (Staubvorhang + Low-Rumble-Begleitung ist bereits im Cue-Doc spezifiziert), `fxlib.py validate`, Client-Test via `/dev photon test` + Expansion-Release | mittel |
| G-2 | **Drei geplante dedizierte Woah-Audio-Beds fehlen** (Teil des offenen F-062): `eclipse:ambient.gravity_hum`, `eclipse:ambient.crystal_voice`, `music/echo_music_box.ogg` (+ optional `echo_grove.ogg`/`echo_wind.ogg`). Die Code-Resolver schalten automatisch um, sobald die Rows existieren; bis dahin tragen re-gepitchte Fallbacks. | `woah/gravityrift/client/GravityRiftAmbience.resolveHum()`, `woah/resonance/client/ResonanceChoir.resolveVoice()`, `sounds.json` ohne die Ids, Spezifikationen in `docs/plans_v3/wiring/woah_{gravity,resonance,echo}_sounds.json` | TREBLO-Generierung nach AGENTS-Regeln (Vorbis, loudnorm, `validate_oggs.py`), `sounds.json`-Rows ergänzen — Code-Änderung: keine | niedrig |
| G-3 | **F-062-Konsolidierungsreste** (in den Wiring-Docs als „bewusst offen" geführt): (a) Woah-Cue-Ids leben in Feature-Paketen (`ResonanceCues`, `ChronoCues`, …) statt in `FxCues`; (b) `ChronoStasisItems`/`EchoGroveItems` statt `EclipseItems`; (c) **`echo_blossom` fehlt in der `ItemLexicon`-Allowlist** — das Item wird im Collections-Handbuch nie als entdeckt registriert (einziger spielersichtbarer Teil). | `network/fx/FxCues.java` ohne `CUE_RESONANCE_*`/`CUE_CHRONO_*`/`CUE_ECHO_*`; `collections/ItemLexicon.java` (19 Einträge, kein `echo_blossom`); `docs/plans_v3/wiring/woah_*_status.md` §Offen | (c) zuerst: eine Zeile in `ItemLexicon` + Lang-Key-Paar; (a)/(b) rein kosmetisch, bei Gelegenheit | niedrig |
| G-4 | **Scythe-Display-Detach beim Storm-Step** — die im Feedback (F-081..087) selbst notierte Minor-Beobachtung („Scythe-Display kann während Storm-Step-Vanish kurz detached wirken") hat keinen auffindbaren Fix: `tickStormStepVanish` behandelt Fog-Beats/Fairness-Cue, aber kein Verstecken/Re-Attach des Sensen-Displays während der Vanish-Ticks. | `entity/boss/fog/FogTyrantEntity.tickStormStepVanish` (kein Scythe-Handling), UserFeedback F-081..087-Zeile | Sense während STEP_OUT unsichtbar schalten (Alpha/Teleport unter Boden) und erst mit `tyrant_step_in` re-attachen | niedrig |
| G-5 | **Doku-Diskrepanzen (kein Funktionsloch):** (a) Frühere-Sessions-Notiz nennt Glitch-Effekte „matrix, static" — diese Ids existieren nicht (aktuelles Set: outline/datamosh/scanlines/invert/void [+dome]); (b) `AGENTS.md` nennt „68 `.fx`-Assets", real sind es 227 (+ .fxproj-Quellen); (c) UserFeedback nennt „174 .fx" (FX-W11-Zeile) — ebenfalls veraltet. | `glitchzone/GlitchZoneEffects` (kanonische Liste); `.fx`-Zählung unter `assets/eclipse/fx/` = 227 | Doku-Stellen bei nächster Gelegenheit aktualisieren (UserFeedback/AGENTS sind Doku, kein Produktionscode) | niedrig |

Ausdrücklich **nicht** als Lücke gewertet: `slam_dust_puff`/`storm_dust_puff` (Sub-Emitter-
Kinder in anderen `.fx`-Binaries), `boss_summon_beacon_` (dynamischer `_0.._3`-Suffix,
alle 4 Assets vorhanden), `my_moment`(_quasar) (Javadoc-Beispiel in `PhotonFxRegistry`),
`fx/cue/template_*` (Wire-Ids; `template_burst.fx`/`template_loop.fx` existieren).

---

## F-062 Feinschliff-Plan

**Ist-Zustand (Basis solide implementiert und verdrahtet):** Alle 5 Features leben unter
`woah/` mit eigenem Subpaket, sind über `WoahFeatures.register` (aufgerufen in
`EclipseMod`, Zeile 65) am Mod-Bus, haben Game-Event-Subscriber, Payloads, Dev-Commands
(`/dev dome|woah gravity|woah chrono|woah resonance|woah echo …`), Client-FX-Rows und
persistente States; alle 5 Langdrops sind gemerged (0 fehlende Keys).

| Feature | Kern-Klassen | Zustand |
|---|---|---|
| WOAH-01 Mansion-Glitch-Dome | `MansionDomeService/State/Protection`, `DomeShatterFx`, `client/Dome*Renderer`, Post `glitch_dome.json`+`dome_shell.json` | vollständig; 8-Hit-Emitter, 240-Shard-Shatter, Aftershocks |
| WOAH-02 Gravitationsbruch | `GravityRiftZone/State/Builder/Service/Orbitals`, `client/GravityRiftLensFx` (`gravity_lens`-Post) | vollständig; ~220 Orbitals, 45-s-Puls, Inversion |
| WOAH-03 Chrono-Stase | `ChronoStasisSite/SceneBuilder/Service`, `client/ChronoGradeFx/RainField/TickSound` (`chrono_grade`-Post) | vollständig; ~460-Display-Szene, JOLT×5→DISCHARGE→REWIND |
| WOAH-04 Resonanzfeld | `ResonanceFieldBuilder/Service/MelodyMachine/Tones`, `client/ResonanceChoir/FieldFx` (`resonance_shimmer`-Post) | vollständig; Melodie-Maschine + Choir |
| WOAH-05 Echo-Hain | `EchoGroveTerraformer/Sites/SceneService/Scenes/FinaleSequence`, Ghost/Wolf/MemoryOrb-Entities + Renderer (`echo_grade`-Post) | vollständig; Szenen + Finale |

**Konkrete Feinschliff-Schritte (priorisiert):**

1. **Client-Verifikationspass für alle 5 Features** (höchster Hebel): Die Wiring-Docs
   vermerken für Dome/Chrono/Echo explizit „Kein In-Game-Lauf" zur Abnahmezeit.
   Pro Feature die RCON-Anleitung aus `docs/plans_v3/wiring/woah_*_status.md` bzw.
   `*_wiring.md` abfahren (`/dev dome arm here`, `/dev woah gravity build/pulse/invert`,
   `/dev woah chrono spawn` + JOLT-Zyklus, `/dev woah resonance …`, `/dev woah echo spawn`
   + Finale) und je einen Screenshot-/Video-Beleg ablegen — erst danach F-062 als
   „client-verifiziert" führen.
2. **Audio-Beds nachziehen (G-2):** `ambient.gravity_hum`, `ambient.crystal_voice`,
   `music/echo_music_box.ogg` via TREBLO generieren, postprozessieren
   (`validate_oggs.py`), `sounds.json`-Rows gemäß `woah_*_sounds.json` anlegen. Kein
   Java-Diff nötig (Resolver-Pattern nimmt die Ids automatisch).
3. **`echo_blossom` in die `ItemLexicon`-Allowlist (G-3c)** + Lang-Paar, damit die
   Collections das Hain-Item registrieren.
4. **Mansion-eigener Dome-Accent** (aus `woah_dome_status.md` §Offen 3): der
   Interior-Pass nutzt den generischen GlitchZone-Accent-Uniform-Satz; ein per
   Disc-Profil gesetzter Mansion-Accent (z. B. giftgrün → tief-violett bei COLLAPSING)
   wäre der sichtbarste Einzel-Polish am Dome.
5. **Kosmetische Konsolidierung (G-3a/b, optional):** Woah-Cue-Konstanten nach
   `FxCues` (Delegation stehen lassen), `ChronoStasisItems`/`EchoGroveItems` nach
   `EclipseItems` — reine Ordnung, kein Funktionsgewinn; nur zusammen mit einem
   ohnehin fälligen Build anfassen.
6. **Danach Eval-Runde** (deckt sich mit F-099): die 5 Features durch das
   Eval-Schema aus `docs/plans_v3/eval/` laufen lassen; „zu simpel"-Befunde in
   Polish-Wellen nach dem FX-W10/W11-Muster (Photon-Beats pro Statuswechsel,
   z. B. Chrono-DISCHARGE-Hero-Burst, Resonanz-Ton-Sichtbarkeit bei Nacht).

---

*Audit-Methodik: Datei-/Klassenindex über 1245 Java-Dateien; skriptbasierte
Kreuzchecks (Lang-Parität, Photon-Rows↔`.fx`, Quasar-Rows↔Emitter-JSONs,
`sounds.json`↔Oggs↔Registrierungen, Glitch-Post↔FSH); gezielte Struktur-Greps pro
F-Punkt inkl. Wiring-Nachweis (Event-Bus, Command-Tree, Registry). Kein
`./gradlew`-Lauf im Rahmen dieses Audits (reines Code-Audit; Build-/Client-Verifikation
ist Schritt 1 des F-062-Plans).*
