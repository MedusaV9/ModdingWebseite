# UserFeedback — Project Eclipse

> **So funktioniert diese Datei:**
> Schreib neues Feedback / Wünsche einfach unten in den Abschnitt **„NEUES FEEDBACK“** (auf GitHub direkt editieren + committen auf `cursor/project-eclipse`).
> Der Agent zieht die Datei regelmäßig (alle ~30 min, sobald der aktuelle Stapel abgearbeitet ist), verschiebt neue Punkte in den Backlog und hält die Status hier aktuell.
>
> Status-Legende: 🔴 offen · 🟡 in Arbeit · 🟢 fertig (gepusht) · ⚪ braucht Design-Entscheidung von dir

---

## NEUES FEEDBACK (hier eintragen!)

_(leer — hier neue Punkte reinschreiben; zuletzt gezogen: 30.07. ~23:35 UTC — keine neuen Einträge, Mob/Item-Wellen M-B/M-D laufen)_

## Aktuell in Arbeit

| # | Punkt | Status |
|---|-------|--------|
| F-095 | **Re-Verifikations-Audit** ✅: Audit-Team hat F-001…F-094 im Code gegengeprüft (`docs/plans_v3/session_0730/AUDIT_REVERIFY.md`), 5 Lücken gefunden und ALLE gefixt (rim_recede.fx gebaut, Woah-Items ins ItemLexicon, Scythe-Detach beim Storm-Step, AGENTS.md-Doku, Woah-Audio dokumentiert) | 🟢 |
| F-096 | **Sturm-Masse-Upgrade**: Volumen-Shader auf 2 Dichte-Schalen + Höhenprofil v2 (Wallcloud-Basis, Konvektionstürme, Amboss-Fransen), Powder-Term + Dual-Lobe-Phase + radiale AO (B1/B5/B9/B2/B3/B7 fertig); Kampf-Uniforms (SiegeChurn/CoreFade) verdrahtet; Rest: B4 Wetter-Layer, B6 Nahfeld-Parallaxe, B8 Burst-Integration, B10 Perf-Pass | 🟡 |
| F-097 | **Per-Effekt-Polish-Wellen** KOMPLETT: Welle A (A0–A9) + Welle B (B1–B7) + Welle C fertig — C2 fxlib-Infrastruktur (UUID5-Determinismus: Generator-Läufe jetzt byte-identisch; Range-Codec a/b-Fix: Photon las min/max gar nicht; CullBox/Prewarm-Lint), C3 Woah-Feinschliff (=F-062 ✅), C4 kleine Cues + N8 Vertrags-Brandsiegel/N10 End-Static/N14 Sanctum-Gebet, C5 Credits/End-Feinschliff inkl. Reparatur der KOMPLETT TOTEN black_hole.fsh-Pipeline (glsl-processor-NPE) | 🟢 |
| F-098 | BlockDisplay-Effekte ✅ (B3) + Cutscenes ✅ (B7); Custom-Mobs/Items: **Welle M-A ✅** (MA1 Tyrant, MA2 Warden, MA3 Herald→GeckoLib, MA4 Ferryman→GeckoLib, MA5 Finale-Props, MA6 Fog-Eliten) + **MD3 Items-B ✅**; **jetzt in Arbeit: Welle M-B** (MB1 Deckhand, MB2 Orin, MB3 Cultist+Bolt, MB4 Glitch-Trio, MB5 Wanderer, MB6 Sentinel+Revenant) **+ MD1 Eclipse Wand + MD2 Items-A**; danach Welle M-C (5 Konversionen: Gazer, Stalker, Sunmote+Lantern, TheOther/Ghosts, Glitch Emitter) + MD4 | 🟡 |
| F-099 | **Eval-Runde** (Sol 5.6) über die gesamte Session-Arbeit, bei „zu simpel"-Befunden → Nach-Polish-Runden | 🔴 |
| F-080 | Server/Welt-Verlassen hängt für immer im SAVING-State statt sauber zu stoppen — Fix implementiert (Stop-Sweep räumt FX-Schwärme VOR dem Save, kein Sync-Chunkload im Stop mehr, Arena-Pit-Chunks werden freigegeben); dedizierter Server-Stop in ~10 s verifiziert ✅ | 🟢 |
| F-082 | Tod im Sturm-Bosskampf ⇒ Wipe-Reset (Boss heilt/despawnt, Statue re-armt nach 30 s, KEINE Blockschreibungen ⇒ Gräber sicher) — im Client-Test verifiziert (s. F-081..087 unten) ✅ | 🟢 |
| F-083 | Stürme entkoppelt: reconcile markiert jetzt JEDE aktive Site — im Server-Log verifiziert (2 Lairs gleichzeitig armed) ✅ | 🟢 |
| F-084 | Display-Leak gefixt (LIVE_DISPLAYS-Chunk-Unload-Leak) + Scope-Tags + Orphan-Sweeps bei Kampfende/Reset/Serverstart/Chunkload — im Client-Test keine verwaisten Displays nach Wipe-Reset ✅ | 🟢 |
| F-085/086/087 | Grab-Schutz implementiert: Explosions-Pruning + LivingDestroyBlock-Cancel, Grab-Ausschluss in Sturm-Liftlogik, Zauber-Blacklist, Blast-Resistance 6→1200 — Gräber/Kisten im Client-Test unversehrt ✅ | 🟢 |
| F-088 | Limbo-Pink-Objekt (Eclipse-Aura vorm Schiffsbug): 45° gedreht, verkleinert + gedimmt — Client-Sichttest vom Bug aus ok ✅ | 🟢 |
| F-089 | Blackscreen/Evakuierung + End-Disc-Heightmap-Familie: Evakuierungs-Band-Scan, ScatteredFeature-Pinning UND neu SpawnReturns (Heimkehr-Teleports der Credits/Finale/Arena landeten auf der End-Disc y≈361, Spieler starb dort hinterm Schwarz an Drachen-Magie — live reproduziert + gefixt) | 🟢 |
| F-091 | `/dev preload everything` VERIFIZIERT: Pregen lief komplett durch (overworld + nether je 2.928 Chunks bis r=480, `dev preload status` = DONE), Zustand persistiert über Server-Neustarts (Auto-Resume-Pfad), Re-Run wird sauber geguardet („already complete — cancel first to re-run") | 🟢 |
| F-092 | Rand-Berge: mehrschichtige Silhouetten-Kette umringt die Map, aus Bodennähe UND aus der Luft von überall sichtbar (Client-Sichttest ✅); Terrain-Wall-Band [R−56, R−6] regeneriert planmäßig mit jeder Ring-Erweiterung | 🟢 |
| F-090/093 | Credits + Schwarzes Loch V3 im Client verifiziert: Insel-Shatter-Prolog, Map-Zerreißen (Terrain-Brocken-Spiralen, Swallow-Pulse, polare Jet-Bursts), Ergrauen — dazu 2 Client-Bugs gefunden+gefixt: Titel-Karten wurden vom Fade-Schwarz depth-geclippt (GUI-Layer-Z 12400 > Post-Render-Z; dynamischer Z-Lift via getGuiFarPlane), Heimkehr auf die End-Disc (s. F-089) | 🟢 |
| F-075 | Altar-Insel-Aura V2 VERIFIZIERT: Leiter L1/L3/L5 im Client abgefahren (L1 Rand-Motes → ab L2 Fern-Säule → L5 volle Krone, „THE ALTAR ASCENDS"-Beat feuert, 0 Duplicate-Warnungen). Dabei Root-Cause-Fund+Fix: ALTAR_CENTER-FxAnchor wurde nach Server-Neustart NIE re-publiziert (nur der Mid-Intro-Abbruchpfad tat das) — die gesamte Altar-Ambience war nach jedem Restart tot; onServerStarted re-seatet den Anchor jetzt immer | 🟢 |
| F-077 | End-Ankunft V2 „Gigantismus" VERIFIZIERT (Re-Test nach DIM-Boost 0.55/0.8/0.2): OMEN-Creep dimmt die Szene jetzt klar lesbar ab, Erupt-Spike landet als dramatischer Fast-Schwarz-Beat exakt auf „The sky tears open", Simmer gibt in die Eruptionssäule frei, Captions + „THE END HAS COME" rendern über dem Grade — Frames + Video als Beleg | 🟢 |
| F-071/078/079 | Dauerbetrieb: alle ~30 min Feedback-Check; wenn leer → Photon/Veil-Effekte mit Planner-/Ideen-Teams immer weiter iterieren; nur Fable 5 Max Thinking als Subagent-Modell | 🟡 (läuft) |

## Backlog (offen, in Priorität)

| # | Punkt | Status |
|---|-------|--------|
| F-062 | 5 „Woah“-Map-Features Feinschliff — von C3 abgeschlossen: Gravitationsbruch träge Orbit-Umkehr + Tumble-Boost-Bugfix, Mansion-Dome 3-Klassen-Shatter + Touch-Puls, Chrono-Stase echte Zeitlupe + Stotterblitz, Resonanzfeld-Wellen-Choreograph, Echo-Hain-Flut-Beat | 🟢 |

---

## Fertig (diese Session)

| # | Punkt | Commit |
|---|-------|--------|
| FX-W11 | Stacking-Law-Audit über alle 174 .fx (557 Emitter) mit 10 Fix-Assets + 4 Masse-Upgrades, alles client-verifiziert (Video-Review PASS): boss_intro_shockwave (Funkenellipse + neuer Bodenblitz), tyrant_blind_burst (dunkle Slate-Schalen), altar_levelup (Funkenfontäne), altar_aura_powerup (5 getrennte Orbs statt Weiß-Ball), nether_eruption (Aschesäule + Ember-Kern + Pilzwolke), day_rift_maw (Glockenvorhang-Unterhang, hängt mit Tiefe), storm_burst_shockwave (HDR-Doppelring-Blitz → Staubring → saubere Auflösung), DayRift-Orbit-Stratifikation (schwere Platten tief+langsam). Wichtigstes Tooling-Learning: Photon cached .fx statisch — F3+T lädt sie NICHT neu, `/photon_client clear_client_fx_cache` ist Pflicht nach Asset-Regen | `feat(fxwave11)` + `fix(fxwave11.1)` |
| FX-W10 | Fog-Tyrant Storm-Step Photon-Beats: `tyrant_step_out` (Fog-Fold-Gulp — dunkle Slate-Tendrils stürzen einwärts, Indigo-Kern, Snap-Fleck-Burst + kleiner Blitz-Quad, Boden-Skirt) + `tyrant_step_in` (aufplatzende Fog-Schale, Boden-Schockring, Wisp-Säule, fallende Embers) — isoliert im Client verifiziert (dunkler Body liest klar, KEIN Weiß-Ball mehr); Stride-Wake alle 8 Blöcke (Staubring + Floor-Chips + Ravager-Thud + Mini-Shake). Learning „V2.1-Stacking-Law" dokumentiert: dutzende ALPHA-Sprites im selben Halbblock konvergieren zur Sprite-Eigenfarbe → Birth-Tints müssen DUNKEL starten, Shells breit, Counts getrimmt | `feat(fxwave10)` |
| F-081..087 | Sturm-Boss VERIFIZIERT (Client-Test): Statue-Trigger (Melee-Schlag in Reichweite <=3 Bloecke!) -> 60t-Awaken -> Fog Tyrant spawnt (Bossbar, Storm-Steps), Spielertod -> Wipe-Reset (Boss heilt/despawnt, 2 Adds discarded, Statue-Cooldown 600t -> Re-Arm), Graeber/Kisten unversehrt; Custom-Death-Screen 'YOU HAVE FALLEN' + Limbo-Respawn ok. Beobachtung (minor): Scythe-Display kann waehrend Storm-Step-Vanish kurz detached wirken | Logs + Screenshots |
| F-094 | Trailer V2 FINAL: `ECLIPSE-Trailer-4K.mp4` neu gerendert (3840x2160@60, 1800 Frames, 30s, 20.9 Mbps, Song 'Worst Enemy feat. goldN' auf -14 LUFS) — 11 echte Gameplay-Video-Szenen inkl. NPC-Szenen (Deckhands/Herold/Villager/Fährmann-Boss), alle 360p-Review-Blocker gefixt; Hinweis: nativer 4K-Remotion-Render wedgt auf dieser VM (SwiftShader), Pipeline = 1080p-Body + wedge-resistente Chunk-Frames + Lanczos-4K-Assembly | `feat(trailer)` |
| F-094a | Photon-Client-Crash gefixt: 'HorizontalBillboard' ist kein Photon-Enum → renderMode null → NPE beim ersten Render (Seelenernte-Ring + 4 Altar-Aura-Fogs betroffen); fxlib validiert Enum-Strings jetzt beim Authoring | `fix(photon)` |
| F-094b | Fährmann-Re-Run-Fixes: /dev-Kommandos räumen den persistierten Sieg-Latch (Fight-Watch beendete den Kampf sonst sofort 'victory'), Arrival-Beat sweept verwaiste Bosse statt abzubrechen, Boss-Identity-Guard gegen Doppel-Bossbars (async Entity-Streaming) | `fix(ferryman)` |
| F-073 | „ECLIPSE-Trailer-4K": 30 s Remotion-Trailer, 4K 60 fps, deutsch, eigener Score+SFX — liegt als `ECLIPSE-Trailer-4K.mp4` im Repo-Root, Quellprojekt unter `trailer/` | `feat(trailer)` |
| F-074 | Altar-UI-Lesbarkeit (Preis-Chips, Währungs-Icons, Leistbarkeits-Kanten, Tooltips) + modale Kaufbestätigung + Flying-Shard-Kaufanimation + kategoriebasierte Nach-Kauf-Zeremonie (Spirale/Item-Flug/Fontäne) — war bereits in `681f98e` gelandet, Backlog war veraltet; Plan-/Verifikationsdoc nachgereicht | `feat(altar)` |
| F-076 | Altar als GeckoLib-Monument (schwebender Eclipse-Kern, gegenläufige Runenringe, Debris-Satelliten; idle/heartbeat/gift/erupt/stage_up + Glowmask) — war bereits in `eae14f4` gelandet; Plan-/Verifikationsdoc nachgereicht | `feat(altar)` |
| F-063 | `/dev stage skipdark` — dunkle Phase zwischen Tageswechsel und Map-Erweiterung skippen (Cutscene-Abbruch, Himmel zurück, Ring wächst normal weiter) | `feat(devtools)` |
| F-064 | `/dev ghostscreen <Spieler>` + `/dev backroomsscare <Spieler>` (Blackscreen → 20–30 s Backrooms-Clip, unsterblich, Schaden ⇒ Glitch + Rückteleport) | `feat(scare)` |
| F-065 | `/dev jumpscare <version> <Spieler>` — 30 benannte Varianten (`/dev jumpscare list`), rein clientseitig nur beim Ziel | `feat(scare)` |
| F-066 | `/invsee <Spieler>` + `/enderchestsee <Spieler>` — Live-Container-Inspektion | `feat(devtools)` |
| F-067 | `/dev player multiplier mining set <Spieler> <Faktor>` — Abbau-Tempo-Boost | `feat(devtools)` |
| F-068 | Schwarzes Loch V2: Doppler-Akkretionsbänder, Lensing-Rampe + chromatische Aberration, Stern-Streaks, Terrain-Verschlingen mit Spaghettisierung, 3-Klassen-Shatter + Nachbeben, Spiralarm-Formationen, FOV-Atmung | `feat(credits)` |
| F-069/F-012 | Classic-Audit: 13 AI-Look-Texturen durch vanilla-abgeleitete pixel-exakte Rebuilds ersetzt + `CLASSIC_BLOCK_AUDIT.md` + Generator | `fix(classic)` |
| F-070 | Zauberstab-FX: Pfad-Identitäten (RISS/GLUT/STERN), 12 neue Photon-FX, Tier-Skalierung, Cast-Akzent-Overlay, neues Pfadwahl-UI | `feat(wandfx)` |
| F-023/047 | End-Timeline (Herold Tag 7, End-Disc Tag 12, Drache Tag 13) + Insel-Crash-Finale (Inseln krachen als Displays zu Boden, Mittelinsel weg nach Kampf, nur kleine Brocken bleiben) | `fix(end)` |
| F-024 | Windaltar wirft jetzt dynamisch bis über die höchste Plattform (+Slow-Fall + Kurskorrektur) | `fix(end)` |
| F-025 | Mesa-Pyramide: leere Chunks unter Landmark-Boxen werden repariert (DiscRepairService) | `fix(worldgen)` |
| F-026 | Schneeberg: Fluss friert (frozen_river-Biom + Packeis über y96), kein Schmelzwasser mehr | `fix(worldgen)` |
| F-027/053 | Herold: Kampfmusik beim Spawn, Siegesmusik erst beim Tod; 9,5-s-Spawn-Cutscene via `/dev event start herold` | `feat(herald)` |
| F-028 | Tutorialwelten: 7 unterschiedliche Era-Maps (disjunkte Chunk-Fenster), Farbfilter statt AI-Texturen, eine Musik-Stimme | `feat(xbox)` |
| F-030–034 | Sturm: Half-Res-Raymarch + adaptive Steps (Optimierung), Kampfverhalten (wächst, Kern löst sich, Debris-Orbits, echte Wurfblöcke als Displays), längere Burst-Anim, Photon-Nahfeld-LOD | `feat(storm)` |
| F-035 | Nether-Öffnung Tag 2: 47-s-Photon-Sequenz (Asche, Beben, Block-Ruptur, Eruption) + permanente Rauch-Feuer-Wolke überm Loch | `feat(nether)` |
| F-036–041 | Zauberstab-Rework: 48-Knoten-Skilltree mit Rebirths + Veil-Ladungs-Upgrades, 30 datengetriebene Zauber (10 je Richtung), keine Cooldowns (nur Veil-Ladung), Phasenwelle → Umbra-Lanze, Tab nur mit Stab in Hand, `/dev wand xp/level` | `feat(wand)` |
| F-042/043 | Backrooms: Dread-System (Lichter-Aus-Wellen, Mob-Lautstärke-Rampe beim Anrennen, Laternen-Flackern) + 5 Ebenen (neu: Flooded Halls, The Hollow) | `feat(backrooms)` |
| F-044–046 | Tagesriss am Himmel (Photon) mit Display-Fallout, der sich um die Mittelinsel sammelt; Tag-14-Portal-Formation + Riesenschlüssel-Aktivierung → Tür bricht auf, lila Geister, Schiff→Arena und zurück; Ferryman-Spezialattacken; `/dev start_ferryman` | `feat(ferryman)` |
| F-048/049 | Glitch: Void-Effekt in Lila, Altar-Ambient-Aktivierung (Impuls vom Block), Farb-Parameter im `/dev glitch`-Command | `feat(glitch)` |
| F-050–052 | `/dev skin <Spieler> <URL/NameMC>`, lila `/dev adminskin`, `/msg` nur an Sonic0810 | `feat(admin)` |
| F-054 | `/dev structure <id>` platziert jede Struktur geerdet (StructureGrounding) | `feat(herald)` |
| F-055 | „Letzte Überfahrt“-Erklärung neu geschrieben | `feat(ferryman)` |
| F-056–058 | Credits-Finale: langer Blackscreen → Ortho-Kartenrand → Schwarzes Loch (Veil-Post-Distortion + Spiral-Displays) frisst die Map, Weltall-Skybox, Ergrauen, „Minecraft Eclipse“ bis victory_theme-Ende, Blackscreen bis `/dev end_event`; Insel/Altar-Shatter in tausende Teile; tausende Formation-Displays, Spieler unsichtbar, Auto-Laufen raus | `feat(credits)` |
| F-059 | 20 Biome (10 neu: 4 Oberfläche + 6 Cave) + 15 neue Flora-/Kristallblöcke mit Loot/Models/Features | `feat(biomes)` |
| F-060 | Photon-Editor-Erkundung: Bericht `docs/plans_v3/PHOTON_EDITOR_CAPABILITIES.md` (Editor-Workflow, Feature-Zensus über 145 .fx, Upgrade-Rezepte) | `docs(photon)` |
| F-061 | Legacy-Race: prozeduraler Rundkurs (18 960 Blöcke, 7 Checkpoints, 3 Runden, Podium), ersetzt Elytra-Race; Arena-Schild + Verlassen-Flow gefixt | `feat(minigames)` |
| F-001 | custom_payload-Kick beim Testwelt-Join (STRING_UTF8-32K-Limit; Chunked-Sync + LARGE_UTF8) | `fix(net)` |
| F-002 | Limbo-Portal/Disc kamera-gekoppelt → feste Himmelsrichtung wie Vanilla-Sonne | `fix(limbo)` |
| F-003 | Deckhands: 3s-Ruck (GeckoLib-Reset-Loop), Ruder-Culling, Spiegel-Flackern | `fix(limbo)` |
| F-004 | Bossbars: Ursache war GL_NEAREST-Minification; jetzt komplett prozedural, 4 Farb-Themes | `fix(hud)` |
| F-005 | Outpost schwebte: Plateau-Sitz jetzt über Footprint gesampelt + Fundamente | `fix(structures)` |
| F-006 | Blackscreens: Kamera-im-Riss-Guard + 3s-Client-Reißleine für alle Fades; Expansion sendet gar keine Fades mehr | `fix(structures)` / `feat(expansion)` |
| F-007 | Struktur-Anim: Riss 5s, Blitz-Sounds, bis 640 Displays mit Hover-Wirbel | `fix(structures)` |
| F-008 | Riesen-Monolithen am Map-Rand (waren nie sichtbar: falscher Zeitpunkt/Radius/view_range) | `feat(expansion)` |
| F-009 | Map-Erweiterung 2,3× schneller (141,6s → 60,7s gemessen) | `feat(expansion)` |
| F-010 | GUI-Scale: Akzent-Zeile zentriert sich jetzt pro Frame | `fix(packcheck)` |
| F-011 | EMI-Versionscheck (Build-Metadata-Toleranz) + volle Versionsanzeige + aktuelle Pins | `fix(packcheck)` |
| F-013 | Limbo-Bausperre (nur /devmode baut) | `feat(limbo)` |
| F-014 | Limbo-PvP-Sperre (+ /dev limbo pvp on, Bosskampf-Ausnahme) | `feat(limbo)` |
| F-015 | Fröhlicher intro_storm-Track beim Kentern entfernt — Limbo-Ambient läuft durch | `feat(limbo)` |
| F-016 | Sturm wird vor der Blende gespawnt; Freigabe erst nach Client-Bestätigung | `feat(intro)` |
| F-017 | Debris-Choreografie: Orbit um den Sturm, Blitz-Kicks, Spiral-Kollaps in die Insel | `feat(intro)` |
| F-018 | Echte Musik-Fades (Root-Cause: Dimension-Hop stoppt alle Sounds + Idle-Tick-Bug) | `feat(intro)` |
| F-019 | Altar-Quest: echter Touch-Trigger + 2-min-Karenz | `fix(altar)` |
| F-020 | Schutzzone 96→71, Fallschutz 112→87 | `fix(altar)` |
| F-021 | Kein Herzfragment per Shift-Klick mehr; Shift = einzahlen, Rechtsklick = Menü | `fix(altar)` |
| F-022 | Splitterladen zeigt Item-Icon/Anzahl/Börse; 6 irreführende Texte korrigiert | `fix(altar)` |

## Fertig (frühere Sessions, Auszug)

- Volumetrischer Veil-Sturm (Raymarching, Selbstschatten, Spiralbänder), Sturm-Occluder/EXO-Fixes
- Glitch-Zonen-System mit Shadern (matrix, void, static, outline), `/dev glitch`-Commands
- Altar-UI mit Tages-Gating + versiegelte Angebote, Spawn-Protection + DEVMODE
- Skilltree-Gates im Limbo, Bestiary-Gates, Level-2-Bug, Arm-Artefakt-Timing
- Übersetzungs-Audit (Umbral Shards, Voice Sealed, Altar-Level, Orin, Tür, Zeitleiste …)
- Phase-Wave-Journal crashsicher, Backpack-Rezepte entfernt, Doppel-XP-Angebot im Altar
- Backrooms: kein Bauen/Zaubern, 20-Block-Aggro, Exit am Altar, 3 Ebenen
- Nether-Eingangsbereich ohne Fallschaden, Himmel eskaliert pro Tag, Tageswechsel-Texte dedupliziert
