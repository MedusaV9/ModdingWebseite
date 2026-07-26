# UserFeedback — Project Eclipse

> **So funktioniert diese Datei:**
> Schreib neues Feedback / Wünsche einfach unten in den Abschnitt **„NEUES FEEDBACK“** (auf GitHub direkt editieren + committen auf `cursor/project-eclipse`).
> Der Agent zieht die Datei regelmäßig (alle ~30 min, sobald der aktuelle Stapel abgearbeitet ist), verschiebt neue Punkte in den Backlog und hält die Status hier aktuell.
>
> Status-Legende: 🔴 offen · 🟡 in Arbeit · 🟢 fertig (gepusht) · ⚪ braucht Design-Entscheidung von dir

---

## NEUES FEEDBACK (hier eintragen!)

Ich will das du weiterhin regelmäßig hier checkst also ca. alle 30minuten. und nicht aufhörst und immer wenn du mit den aufgaben fertig bist und noch kein neues feedback hast will ich das du die Photon und Veil Effekt verbesserst mit mehreren Plannern und Ideen sammler und dann quasi immer weiter iterreieren tust das es immer besser wirst und dabei dran denkst immer wieder hier rein zuschauen. dnek dran nur Fable 5 Max Thinking zunutzen

verbessere die Credits scene noch weiter sowje verbessere das Schwarze Loch und die ganze Cutscene noch viel mehr

erstelle einen Trailer ca. 30s in 4K 60fps mit Remotion und du sollst alles selber entscheiden etc der Trailer soll auf deutsch sein. ich will das du den am Ende hier in die Repo rein packst als "ECLIPSE-Trailer-4K" du sollst einfach einen passenden Song raus suchen und denk an sounds und animations etc nutze wie gesagt hier auch sehr viele Fable 5 Max Thinking Subagents zusammen. 

Verbessere das Altar UI noch etwas mehr das alles etwas leichter lesbar ist und beim Shop Tab mach das man seinen kauf bestätigen muss plus so eine Kauf Animation hat und dann so eine kurze Cutscene danach jenachdme was man geholt hat

mach das die Altar Insel eine Aura um sich hat mit Photon und Veil das man quasi merkt hier ist was magisch und mach es passend zu der Altar Stufe. 

Baue den Altar Block als Richtiges Model in Blockbench/Blender und er soll auch mit GeckoLib Animations haben. Er soll mächtig wirken.

Erstelle eine Cutscene samt riesen Effekten mit Photon und Veil wenn das End erscheint mach eventuell das mit dem neuen Altar Model dann so eine krasse Animation kommt wie der Altar die Blöcke ausspuckt oder überlege dir was krasses selber

denk dran immer viele (soviele du willst gleichzeitig) subagents auf fable 5 max thinking als model eingestellt zu nutzen. 

wenn du mit allem durch bist verbessere alle Effekte,Veil und Photon mehr, mehrfach. Kontrolliere alle 30min die Repo nach neuem Feedback wenn du an diesem Verbesserung punkt angekommen bist 

_(leer — hier neue Punkte reinschreiben; zuletzt gezogen: alle Punkte bis „GPT5.6SOLMAXTHINKINGFAST“-Nachricht → einsortiert als F-062…F-070)_

## Aktuell in Arbeit

| # | Punkt | Status |
|---|-------|--------|
| F-062 | 5 „Woah“-Map-Features (Photon+Veil), #1: Mansion-Glitch-Dome (grüne Outlines drin, zerschlagbares Dach-Gerät mit Blockbench-Modell, Scanline-Schildblase, von außen nur Lichtstrahl) — 20 Fable-Idea-Subagents sammeln gerade Ideen | 🟡 |
| F-063 | Dev-Command zum Skippen der dunklen Phase zwischen Tageswechsel und Map-Erweiterung | 🟡 |
| F-064 | `/dev ghostscreen <Spieler>` (Geist + Glitch-Text + Knall, nur deren Screen) + `/dev backroomsscare <Spieler>` (gleicher Effekt → Blackscreen → 20–30 s Backrooms-Clip, unsterblich, Schaden ⇒ Glitch + zurück zum alten Spot) | 🟡 |
| F-065 | `/dev jumpscare <Version> <Spieler>` — 30 verschiedene Jumpscares (Veil/Photon/Shader), nur für den Zielspieler | 🟡 |
| F-066 | `/invsee <Spieler>` + `/enderchestsee <Spieler>` als Dev-Commands | 🟡 |
| F-067 | Dev-Multiplier-Command: Abbaugeschwindigkeits-Boost pro Spieler | 🟡 |
| F-068 | Schwarzes Loch + gesamte End-Szene noch viel mehr Polish (mehr BlockDisplay-Anims, mehr Subagents) | 🟡 |
| F-069 | Restlichen Backlog abarbeiten (F-012 Classic-Audit) | 🟡 |
| F-070 | Zauberstab-Effekte visuell massiv verbessern + erstes Auswahl-UI schöner | 🟡 |

## Backlog (offen, in Priorität)

| # | Punkt | Status |
|---|-------|--------|
| F-012 | Classic-Blöcke recherchieren; KEINE AI-Blöcke mehr im Classic-Bereich | 🟡 (läuft in F-069) |

---

## Fertig (diese Session)

| # | Punkt | Commit |
|---|-------|--------|
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
