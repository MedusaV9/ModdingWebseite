# UserFeedback — Project Eclipse

> **So funktioniert diese Datei:**
> Schreib neues Feedback / Wünsche einfach unten in den Abschnitt **„NEUES FEEDBACK“** (auf GitHub direkt editieren + committen auf `cursor/project-eclipse`).
> Der Agent zieht die Datei regelmäßig (alle ~30 min, sobald der aktuelle Stapel abgearbeitet ist), verschiebt neue Punkte in den Backlog und hält die Status hier aktuell.
>
> Status-Legende: 🔴 offen · 🟡 in Arbeit · 🟢 fertig (gepusht) · ⚪ braucht Design-Entscheidung von dir

---

## NEUES FEEDBACK (hier eintragen!)

_(leer — hier neue Punkte reinschreiben; zuletzt gezogen: 27.07. 10:57-Commit → einsortiert als F-080…F-093)_

## Aktuell in Arbeit

| # | Punkt | Status |
|---|-------|--------|
| F-080 | Server/Welt-Verlassen hängt für immer im SAVING-State statt sauber zu stoppen — Fix implementiert (Stop-Sweep räumt FX-Schwärme VOR dem Save, kein Sync-Chunkload im Stop mehr, Arena-Pit-Chunks werden freigegeben); dedizierter Server-Stop in ~10 s verifiziert ✅, Singleplayer-Quit-Test folgt | 🟡→🟢 |
| F-081 | Sturm-Bosskampf startet erst, wenn Spieler eine Statue schlagen — implementiert (4-teilige Display-Statue + Interaction-Hitbox, Photon-Idle-Aura, 3-s-Awaken); Spieler-Test folgt | 🟡 |
| F-082 | Tod im Sturm-Bosskampf ⇒ Wipe-Reset (Boss heilt/despawnt, Statue re-armt nach 30 s, KEINE Blockschreibungen ⇒ Gräber sicher) — implementiert, Spieler-Test folgt | 🟡 |
| F-083 | Stürme entkoppelt: reconcile markiert jetzt JEDE aktive Site — im Server-Log verifiziert (2 Lairs gleichzeitig armed) ✅ | 🟢 |
| F-084 | Display-Leak gefixt (LIVE_DISPLAYS-Chunk-Unload-Leak) + Scope-Tags + Orphan-Sweeps bei Kampfende/Reset/Serverstart/Chunkload — implementiert | 🟡 |
| F-085/086/087 | Grab-Schutz implementiert: Explosions-Pruning + LivingDestroyBlock-Cancel, Grab-Ausschluss in Sturm-Liftlogik, Zauber-Blacklist, Blast-Resistance 6→1200 | 🟡 |
| F-088 | Limbo-Pink-Objekt identifiziert (Eclipse-Aura exakt vor dem Schiffsbug, 81°-Glow-Fächer): 45° zur Seite gedreht, verkleinert (R86→60) + gedimmt; Sichttest folgt | 🟡 |
| F-089 | Blackscreen-Ursache: Spieler wird beim Struktur-Platzieren EINGEMAUERT (Inside-Block-Overlay = „Blackscreen“). Evakuierungs-Seam + Post-Paste-Sweep implementiert | 🟡 |
| F-091 | `/dev preload everything`: ganze Map einmal vorgenerieren + entladen, kein sichtbares Chunk-Reingenerieren mehr (auch Start-Event) | 🟡 |
| F-092 | Rand-Berge: riesig auftürmen, Map komplett einkreisen, von überall sichtbar, weichen beim Erweitern langsam zurück | 🟡 |
| F-090/093 | Credits-Szene + Schwarzes Loch V3: Map wird richtig zerrissen (heftige Animationen/Effekte) | 🟡 |
| F-073 | „ECLIPSE-Trailer-4K": ~30 s Remotion-Trailer, 4K 60 fps, deutsch — Stills fertig, 4K-Render läuft gerade, danach ins Repo | 🟡 |
| F-071/078/079 | Dauerbetrieb: alle ~30 min Feedback-Check; wenn leer → Photon/Veil-Effekte mit Planner-/Ideen-Teams immer weiter iterieren; nur Fable 5 Max Thinking als Subagent-Modell | 🟡 (läuft) |

## Backlog (offen, in Priorität)

| # | Punkt | Status |
|---|-------|--------|
| F-074 | Altar-UI: bessere Lesbarkeit; Shop-Tab mit Kaufbestätigung + Kauf-Animation + kurzer Nach-Kauf-Cutscene je nach Item | 🔴 |
| F-075 | Altar-Insel-Aura (Photon+Veil), magisch, skaliert mit Altar-Stufe | 🔴 |
| F-076 | Altar-Block als richtiges Blockbench/GeckoLib-Modell mit Animationen — mächtig wirkend | 🔴 |
| F-077 | Cutscene mit Riesen-Effekten wenn das End erscheint (Altar „spuckt" die End-Blöcke o.ä.) | 🔴 |
| F-062 | 5 „Woah“-Map-Features: Feinschliff/Iteration (Basis implementiert: Mansion-Glitch-Dome, Gravitationsbruch, Chrono-Stase, Resonanzfeld, Echo-Hain) | 🔴 |

---

## Fertig (diese Session)

| # | Punkt | Commit |
|---|-------|--------|
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
