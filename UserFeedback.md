# UserFeedback — Project Eclipse

> **So funktioniert diese Datei:**
> Schreib neues Feedback / Wünsche einfach unten in den Abschnitt **„NEUES FEEDBACK“** (auf GitHub direkt editieren + committen auf `cursor/project-eclipse`).
> Der Agent zieht die Datei regelmäßig (alle ~30 min, sobald der aktuelle Stapel abgearbeitet ist), verschiebt neue Punkte in den Backlog und hält die Status hier aktuell.
>
> Status-Legende: 🔴 offen · 🟡 in Arbeit · 🟢 fertig (gepusht) · ⚪ braucht Design-Entscheidung von dir

---

## NEUES FEEDBACK (hier eintragen!)

_(leer — hier neue Punkte reinschreiben)_

---

## Aktuell in Arbeit

| # | Punkt | Status |
|---|-------|--------|
| F-030–034 | Sturm: Optimierung, Kampfverhalten, Burst-Anim, Photon-Nahfeld | 🟡 |
| F-036–041 | Zauberstab-Rework (Skilltree, 30 Zauber, keine Cooldowns) | 🟡 |
| F-044–046 | Tagesriss + Ferryman-Portal + Arena + Attacken | 🟡 |
| F-035 | Nether-Öffnungsanimation Tag 2 | 🟡 |
| F-042/043 | Backrooms Scary-Part + mehr Ebenen | 🟡 |
| F-028 | Tutorialwelten (verschiedene Maps, Farbfilter) | 🟡 |
| F-023/024/047 | End-Fixes (Tag-7-Timing, Windaltar, Insel-Crash) | 🟡 |
| F-048/049 | Glitch lila + Altar-Aktivierung + Farb-Command | 🟡 |
| F-050–052 | /dev skin, /dev adminskin, /msg-Beschränkung | 🟡 |
| F-027/053/054 | Herald-Musik + Herold-Cutscene + /dev structure | 🟡 |
| F-025/026 | Mesa-Pyramide + Schneeberg-Schmelzwasser | 🟡 |

## Backlog (offen, in Priorität)

### Bugs / Fixes
| # | Punkt | Status |
|---|-------|--------|
| F-012 | Classic-Blöcke recherchieren; KEINE AI-Blöcke mehr im Classic-Bereich | 🔴 |
### Features / Verbesserungen
| # | Punkt | Status |
|---|-------|--------|
| F-056 | Credits: längerer Blackscreen → orthografische Sicht am Kartenrand → schwarzes Loch frisst die Map (Photon, viele BlockEntities) → Weltall-Skybox → Rauszoomen, Farben ergrauen → „Minecraft Eclipse“ bis victory_theme endet → Blackscreen bis `/dev end_event` | 🔴 |
| F-057 | Credits-Map: tausende BlockDisplays, besser platziert; Auto-Laufen ggf. raus; Spieler unsichtbar | 🔴 |
| F-058 | Mittelinsel + Altar zerspringen sichtbar in tausende Teile; Himmel zieht sich zusammen; Eclipse verschwindet langsam | 🔴 |
| F-059 | Biome: 9 → 20 (inkl. Cave-Biome), neue Blockbench/Blender-Modelle für Pflanzen etc. | 🔴 |
| F-060 | Photon Editor mit 3 Entdecker- + 5 Planer- + 10 Umsetzungs-Subagents erkunden und nutzen | 🔴 |
| F-061 | Race-Legacy-Map erstellen (Minigame-Fixes: Verlassen, Arena-Schild) | 🔴 |
| F-055 | „Letzte Überfahrt“-Erklärung neu machen | 🔴 (kommt mit Ferryman-Team) |

---

## Fertig (diese Session)

| # | Punkt | Commit |
|---|-------|--------|
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
