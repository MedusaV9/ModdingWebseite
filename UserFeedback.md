# UserFeedback — Project Eclipse

> **So funktioniert diese Datei:**
> Schreib neues Feedback / Wünsche einfach unten in den Abschnitt **„NEUES FEEDBACK“** (auf GitHub direkt editieren + committen auf `cursor/project-eclipse`).
> Der Agent zieht die Datei regelmäßig (alle ~30 min, sobald der aktuelle Stapel abgearbeitet ist), verschiebt neue Punkte in den Backlog und hält die Status hier aktuell.
>
> Status-Legende: 🔴 offen · 🟡 in Arbeit · 🟢 fertig (gepusht) · ⚪ braucht Design-Entscheidung von dir

---

## NEUES FEEDBACK (hier eintragen!)
Der Kampf im Sturm sollte beginnen in dem die Spieler eine Statur schlagen und nicht einfach nur weil sie dort sind.

Wenn jemand im Sturm Boss kampf stirbt sollte der Kampf zurück gesetzt werden (pass auf das Grab auf.)

Irgendwie muss man erst in dem Einem Sturm den Boss bekämpfen sonst spawnt der andere im anderen Nebel nicht

Wenn man Stirbt beim Sturm kampf dann bleiben manche BlockDisplays für immer stuck an ihrem Punkt auch nachdem kampf.

Im Sturmkampf solltest du auch aufpassen das Bosse keine Gräber bewegen oder zerstören können

Stelle sicher das keine Zauber Gräber beschädigen können

Gräber sollten von Boss NICHT zerstört werden können.

Beim Limbo Schiff ganz am Anfang ist immernoch irgendein Objekt von Veil glaube ich und das blockiert die sicht ultra das ist irgendwas großes pinkes was nicht das Meer ist.

Bei Strukturen Spawnen kriegt man immernoch einen Blackscreen.

Die Credits Scene muss noch mehr verbessert werden.

Warum generierst du nicht einmal die Map vor? und lädst die dann einfach immer? ist das nicht schneller als immer wieder neu die Chunks generierern zulassen? und dann kannst du es ja krasser Animieren oder?
Am Rand die Felsen sind nicht groß genug sie sollen einmal wie riesige Berge sich auftürmen am rand und dann die map quasi ein kreisen und dann sich langsam immer weiter zurück bewegen und sie sollen von der ganzen Map aus sehbar sein.

Allgemein finde die wie auch zb am Start Event die Chunks erst noch reingenierer sieht komisch aus. Baue eventuell ein /dev preload everything Command und der generiert einmal alles vor und dann entlädt er die bereiche so das sie danach einfach wieder rein geladen werden

Das Schwarze loch ist nicht krass genug die Map soll richitig kaputt gerissen werden mit heftigen Animations und Effekten.


_(leer — hier neue Punkte reinschreiben; zuletzt gezogen: 26.07. 23:34-Commit → einsortiert als F-071…F-079)_

## Aktuell in Arbeit

| # | Punkt | Status |
|---|-------|--------|
| F-062 | 5 „Woah“-Map-Features: Pläne fertig (`docs/plans_v3/woah/PLAN-01…05`) — Mansion-Glitch-Dome, Gravitationsbruch (kreisende Schollen + Low-G + Lensing), Chrono-Stase (eingefrorener Blitz/Explosion/Regen + Zeit-Ruck), Resonanzfeld (singende Riesenkristalle + Melodie-Rätsel), Echo-Hain (Geister-Erinnerungen + Vergangenheits-Flut). 5 Implementierungs-Agents laufen parallel | 🟡 |
| F-072 | Credits-Szene + Schwarzes Loch + gesamte Cutscene NOCH viel weiter verbessern (V3) | 🟡 |
| F-073 | „ECLIPSE-Trailer-4K": ~30 s Remotion-Trailer, 4K 60 fps, deutsch, mit Song/Sounds/Animationen, am Ende in die Repo | 🟡 |
| F-074 | Altar-UI: bessere Lesbarkeit; Shop-Tab mit Kaufbestätigung + Kauf-Animation + kurzer Nach-Kauf-Cutscene je nach Item | 🟡 |
| F-075 | Altar-Insel-Aura (Photon+Veil), magisch, skaliert mit Altar-Stufe | 🟡 |
| F-076 | Altar-Block als richtiges Blockbench/GeckoLib-Modell mit Animationen — mächtig wirkend | 🟡 |
| F-077 | Cutscene mit Riesen-Effekten wenn das End erscheint (Altar „spuckt" die End-Blöcke o.ä.) | 🟡 |
| F-071/078/079 | Dauerbetrieb: alle ~30 min Feedback-Check; wenn leer → Photon/Veil-Effekte mit Planner-/Ideen-Teams immer weiter iterieren; nur Fable 5 Max Thinking als Subagent-Modell | 🟡 (läuft) |

## Backlog (offen, in Priorität)

| # | Punkt | Status |
|---|-------|--------|
| — | _(leer)_ | |

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
