# EVAL2-C — Mobs / Items / Progression (Evaluations-Runde 2, Team C)

**Datum:** 2026-08-02 · **Modus:** statisches Read-only-Audit (kein Gradle, keine Code-Änderung)
**Methode:** Datei-Evidenz, nicht Report-Vertrauen. Für die Snap-Prüfung wurde die
POLISH2-§4-Messmethode offline reimplementiert (Python-Sampler über die
`.animation.json`s: t0-Rotationspose des One-Shots gegen die über die volle
Loop-Periode gesampelte Basis-Pose, dt = 0.02 s, Molang-sin/cos in Grad, gewrappte
Winkeldistanz). **Kalibrierung:** Deckhand-`attack` aus `idle_sag` ergibt 49.4° auf
`arm_right.rotx` — exakt der POLISH2-Report-Wert. Die Zahlen unten sind also
methodisch 1:1 vergleichbar mit der Entscheidungstabelle in
`POLISH2_ACTIONBLEND_REPORT.md` §4.

---

## 1. Noten-Tabelle

| Unterbereich | Note | Ein-Satz-Begründung |
|---|---|---|
| **Mob-Craft** | **8 / 10** | Alle fünf Code-Modell-Konversionen (Herald, Ferryman, Gazer, Stalker, Sunmote) sind geliefert, mit Glowmask, frame-exakten Death-Fenstern (70t/100t/30t/28t/24t == Clip-Länge) und sauber behandelten F-9-Fallen — aber die NEUEN One-Shots stehen durchweg wieder auf Transition 0 und reproduzieren exakt die 45°-Pop-Klasse, für die POLISH2 gebaut wurde (Ferryman 64°, Stalker 97.5°, Orin 66°, Sentinel 58°). |
| **Item-Craft** | **9 / 10** | Der Alt-Befund „3 Items noch 2D" ist vollständig geschlossen (POLISH3: `separate_transforms`-Wiring in den Model-JSONs verifiziert, GUI-Icons unangetastet) und die neuen Item-One-Shots sind pop-frei authoriert (gemessen: feast 0.8°, night_bite 0.6°, present 2.5°, sigil-shatter 1.5° auf Nicht-Spin-Kanälen) — Abzug allein für den nie verdrahteten `feast`-Trigger (totes Content-Highlight). |
| **Progression-Robustheit** | **9 / 10** | QuestEngine/Awards/Shard-Ledger/Offering/Minigames hängen sämtlich an SavedData mit idempotenten Grant-Ids, Boot-Resume, Pending-Delivery und Catch-up-Pfaden; kein Broken-State-Pfad gefunden, nur eine Härtungs-Empfehlung (Backrooms-Exit-Heightmap). |
| **Sync / Lebenszyklus** | **9 / 10** | Login-/Respawn-/Dimensionswechsel-Resync ist flächendeckend (58 Handler-Dateien), die W6B-Dragon-Fixes und der F-109-SoftBorder-Fix stehen verifiziert im Live-Tree, das Dragon-Bossbar-Muster deckt Relog/Walk-in/Restart; Abzüge nur für Kleinkram (stale Bossbar-Einträge, Backrooms-Exit). |
| **i18n / Doku** | **7 / 10** | Sprachseite nahezu perfekt (en_us == de_de mit 2 872 Keys, ALLE 179 Langdrops gemerged, alle 26 Items + 29 Entities + 35 + 188 Blöcke übersetzt, nur 3 Dev-Handbook-Keys fehlen) — aber die README beschreibt Herald/Ferryman/Sunmote noch als die GELÖSCHTE Code-Modell-Generation, und die MA3/MA4-Integrator-Löschpatches für die Legacy-Renderer wurden nie angewandt. |

---

## 2. Befunde

### 2.1 Critical

**Keine.** Es wurde kein Crash-, Progression-Blocker- oder Datenverlust-Pfad gefunden.
Die in der Charter genannten Verdachtsklassen sind geprüft und (bis auf die
High/Polish-Reste unten) geschlossen — Details in §4 (Gut-Befunde).

### 2.2 High

**H-1 — Ferryman-One-Shots poppen härter als der Deckhand-Befund, der POLISH2 auslöste.**
- **Datei/Zeile:** `entity/boss/FerrymanEntity.java:353-358` (`registerActionTriggers`:
  `kneel`, `oar_sweep`, `harvest`); kein `actionTransitionTicks`-Override → Default 0
  aus `entity/geo/EclipseGeoMonster.java:88`.
- **Messung (Sampler, POLISH2-Methode):** `kneel`/`oar_sweep`/`harvest` aus `idle_row`
  je **64.0° auf `arm_left.rotx`** (aus `walk` 30–35°). Zum Vergleich: der
  Deckhand-45°-Pop, der die ganze POLISH2-Welle begründete, lag bei 49.4°.
- **Failure-Mechanismus:** MA4 lief VOR POLISH2; die Konversion erbte den damals noch
  frozen Hard-0-Contract, und POLISH2 hat nur Deckhand/Colossus/Hound nachgerüstet.
  Der Tag-14-Boss — höchste Sichtbarkeit im Spiel — schnappt beim Kneel-Zeremoniell
  (P2-Phasenstart, jeder schaut hin) den Ruderarm in einem Frame um bis zu 64°.
- **Fix-Vorschlag:** `actionTransitionTicks`-Override in `FerrymanEntity` (POLISH2-
  Muster, ~6 Zeilen): `kneel` **3 t** (Corona ist 100t-Sustain, 3 t Versatz unsichtbar),
  `harvest` **2 t** (A3-Ring kontrahiert 2.0 s — 2 t Versatz irrelevant),
  `oar_sweep` **0 (bewusst hart lassen)** — der 26t-Kontakt-Beat
  (`SWEEP_TELEGRAPH_TICKS`, Damage-Tick im Clip) ist frame-exakt getimt, ein Blend
  verschöbe die Pose gegen den Treffer-Beat (POLISH2 §1.1-Verbotsklasse).

**H-2 — `UmbralBladeItem.triggerFeast` hat null Aufrufer: das `feast`-Highlight ist toter Content.**
- **Datei/Zeile:** `economy/UmbralBladeItem.java:72` (Helper existiert, nullsicher);
  `lives/LifecycleEvents.java:126-131` (Blade-Lifesteal-Branch OHNE den Trigger).
  `rg triggerFeast src/main/java` → nur Definition + eigener Javadoc-Verweis.
- **Failure-Mechanismus:** POLISH3 §6 hat den Einbau explizit als Ein-Zeilen-Snippet an
  den LifecycleEvents-Owner übergeben („NICHT eingebaut") — das Snippet wurde nie
  angewandt. Ergebnis: die aufwendigste Item-Animation der Welle (Auge dilatiert 2.1×,
  Kanten flammen, Wisps wehen) spielt im Spiel **niemals**, ausgerechnet im
  Lifesteal-Moment, für den sie gebaut wurde.
- **Fix-Vorschlag:** In `LifecycleEvents` direkt hinter dem Lifesteal-Log (Z. 131):
  `dev.projecteclipse.eclipse.economy.UmbralBladeItem.triggerFeast(killer);` — exakt
  das POLISH3-§6-Snippet, null Risiko (No-Op ohne Blade in der Haupthand).

**H-3 — Wizard Orin: `greet`/`trade`/`hurt` poppen 66° am meistbetrachteten NPC.**
- **Datei/Zeile:** `entity/wizard/WizardOrinEntity.java:291` (greet), `:608` (trade),
  `:645` (hurt); kein `actionTransitionTicks`-Override.
- **Messung:** je **66.0° auf `arm_left.rotx` aus `idle`** (30° aus `walk`) — `greet`
  feuert bei JEDER Spieler-Annäherung, `trade` bei jedem Handel, beides aus dem
  Idle-Stand direkt vor der Kamera des Spielers.
- **Failure-Mechanismus:** wie H-1 — MB2 lief vor POLISH2, POLISH2 hat Orin explizit
  als „FX-Besitz bei anderem Team, erben Default 0" ausgeklammert (Scope-Ausschluss,
  keine bewusste Design-Entscheidung).
- **Fix-Vorschlag:** Override mit `greet`/`trade`/`hurt` je **2–3 t**.
  **Hart lassen:** `sun_flare` (Nova-Beat bei 0.8 s = 16 t, frame-exakter Timer laut
  Javadoc Z. 104), `veil_step` (Riss-Rematerialize-Snap, Glitch-Klasse),
  `star_call`-Stab-Spin (`glow_staff_crystal` ist Molang-Dauerrotation — Spin-Hazard,
  Cultist-runes-Präzedenz).

**H-4 — Umbral Stalker: Attack/Hurt-Snaps von 50–97.5° am Nacht-Terror.**
- **Datei/Zeile:** `entity/UmbralStalkerEntity.java:304` (attack), `:316` (hurt);
  Trigger-Registrierung `:240-245`, kein Override.
- **Messung:** `attack` aus `sprint` **52.0°** (`leg_bl_lower.rotx`), aus `stalk_low`
  **97.5°**; `hurt` aus `sprint` 50.0°. Beide Basen sind die realistischen
  Kampf-Zustände (Sprint = Jagd-Gang, `handleBaseState` Z. 156-164; `stalk_low` =
  Lauerpose, aus der das Ziel ins Melee laufen kann).
- **Failure-Mechanismus:** wie H-1/H-3 (MC2 vor POLISH2, im POLISH2-Scope
  ausgeklammert). Der Storm Hound bekam für die identische Situation (Biss aus Sprint,
  52.0°) einen 3-t-Blend — der Stalker mit denselben Zahlen nicht.
- **Fix-Vorschlag:** Override `attack` **3 t**, `hurt` **2 t** (Damage liegt vor dem
  Trigger, Follow-Through-Klasse — 1:1 der Hound-Präzedenzfall aus POLISH2 §3).

**H-5 — MA3/MA4-Löschpatch nie angewandt: Legacy-Herald/Ferryman-Renderer leben nur per Event-Priorität besiegt weiter.**
- **Datei/Zeile:** `client/entity/EclipseEntityRenderers.java:41-42` (Layer-Bake der
  toten Modelle) und `:50-51` (Registrierung `HeraldRenderer`/`FerrymanRenderer` auf
  NORMAL-Priorität); `client/entity/FerrymanRenderers.java:33-38` und
  `client/entity/herald/HeraldRenderers.java` überschreiben mit `EventPriority.LOW`
  („until the integrator applies the removal patch" — eigener Kommentar Z. 21-25).
  `HeraldModel.java`, `HeraldRenderer.java`, `FerrymanModel.java`,
  `FerrymanRenderer.java` existieren vollständig weiter.
- **Failure-Mechanismus:** funktional korrekt (LOW läuft deterministisch nach NORMAL,
  letzte Registrierung gewinnt), aber der einzige Schutz vor einer stillen Regression
  auf das alte 324-Zeilen-Code-Modell ist die Prioritäts-Annotation einer Datei, deren
  Selbst-Beschreibung sagt, sie sei transitional. MC1/MC2/MC3 haben ihre Lösch-Snippets
  nachweislich angewandt bekommen (Kommentare `EclipseEntityRenderers.java:39-40, 48-49`)
  — nur die BEIDEN Boss-Patches fehlen. Dazu bakt jeder Client-Boot zwei tote
  LayerDefinitions.
- **Fix-Vorschlag:** Die Removal-Snippets aus `MA3_HERALD_REPORT.md` §7 /
  `MA4_FERRYMAN_REPORT.md` anwenden: 4 Zeilen aus `EclipseEntityRenderers` löschen,
  die 4 Legacy-Klassen löschen, danach die `EventPriority.LOW`-Krücke in beiden
  `*Renderers`-Registraren auf NORMAL zurücknehmen (Kommentar anpassen).

### 2.3 Polish

**P-1 — Weitere Hard-0-Entry-Snaps der M-Wellen (gleiche Klasse, geringere Bühne).**
- `entity/pale/PaleSentinelEntity.java:340`: `attack` aus `walk` **58.0°**
  (`arm_left.rotx`) — Melee kommt fast immer aus dem Anmarsch. → 3 t.
  (`bloom` ist DAGEGEN sauber: feuert nur beim Tauen aus `freeze`, gemessen **0.0°**.)
- `entity/fog/FogRevenantEntity.java:88-90`: `attack` aus `walk` 30.0°. → 3 t.
  (`cast_blind`-`wisps` ist Molang-Spin — hart lassen.)
- `ferryman/finale/SoulWispEntity.java:94-96`: `panic_scatter`/`attack` aus `walk`
  34°/20° — Finale-Schwarm, viele Instanzen gleichzeitig. → 2 t.
- `ferryman/finale/PortalKeyEntity.java:218`: `unlock_turn` aus `fly` 25°
  (`body.rotx`, Nicht-Spin-Anteil) — der schwächste Finale-Beat aus dem FX-Zensus
  bekommt beim Einrasten einen sichtbaren Körper-Ruck. → 2 t, Timing mit A3 abstimmen.
- Gazer `tether_snap` aus `walk` 24° ist dagegen okay: der Gazer bewegt sich praktisch
  nie im `walk` (Teleport-only, Javadoc `GazerEntity.java:124-127`), und der Name sagt
  Snap.

**P-2 — Backrooms-Exit: Heightmap-Lookup ohne Gate/Sentinel (F-109-Randklasse).**
- **Datei/Zeile:** `backrooms/BackroomsEventService.java:554` —
  `overworld.getHeight(...)` an Altar+2/+2, Ergebnis-Y wird UNGEPRÜFT ins
  `teleportTo` gegeben.
- **Mechanismus:** einziger der 15 seit dem Wave-6-Audit NEU hinzugekommenen
  getHeight-Callsites ohne eigenes Load-Gate oder Min-Build-Sentinel. In der Praxis
  gedeckt, weil der Sanctum-Altar per `AltarSanctumBuilder` (Spawn-Re-Pin, Z. 189-191)
  in den immer geladenen Spawn-Chunks liegt — aber genau diese implizite Deckung
  bricht, falls `spawnChunkRadius` auf 0 steht oder der Altar je verlegt wird
  (Ergebnis wäre Teleport auf `minBuildHeight` = Void-Klasse).
- **Fix:** `if (y <= overworld.getMinBuildHeight()) → Anchor-/Spawn-Fallback` (der
  else-Zweig existiert schon) oder das `SoftBorder.groundSurfaceYLoading`-Idiom.

**P-3 — Drei Dev-Handbook-Lang-Keys fehlen (einzige i18n-Lücke).**
- **Datei/Zeile:** `devtools/dev/DevFogSiteCommands.java:56/58/61` referenziert
  `dev.eclipse.doc.fogsite.{list,rematerialize,retire}` — 305 von 308
  `dev.eclipse.doc.*`-Keys sind übersetzt, genau diese 3 fehlen in en_us UND de_de
  → rohe Keys in der STAGE-Kategorie des Dev-Handbooks.
- **Fix:** Langdrop mit 3+3 Keys (der W6-B6-Kommandosatz kam nach dem letzten
  Langaudit dazu).

**P-4 — Dragon-Bossbar sammelt stale Player-Referenzen bis Kampfende.**
- **Datei/Zeile:** `worldgen/end/EclipseDragonFight.java:716-738` (`syncBossBar`).
- **Mechanismus:** Disconnectete Spieler verschwinden aus `level.players()`, bleiben
  aber im `ServerBossEvent`-Set (der Z.-734-Sweep prüft nur `player.level() != level`,
  was für die tote Referenz weiterhin false ist). Kein Player-facing-Bug (Sends an
  geschlossene Connections verpuffen), aber unnötige Referenz-Haltung über lange
  Kämpfe; das Haus-Muster (`MinigameService.onPlayerLoggedOut` → `removeFromBossBar`)
  existiert bereits.
- **Fix:** LoggedOut-Hook oder `bossBar.getPlayers().removeIf(p -> p.hasDisconnected())`
  im 20t-Takt.

**P-5 — README-Mob-Doku eine Welle hinter dem Code (Doku-Drift, Alt-Befund-Klasse).**
- `README.md:625-627`: Herald = „26-cube floating godhead (`client/entity/HeraldModel`,
  128×128 skin …)" — real: GeckoLib-Geo mit 31 Bones + Glowmask, `HeraldGeoRenderer`.
- `README.md:661-663`: Ferryman = „18-cube floating robed skeleton
  (`client/entity/FerrymanModel` …)" — real: GeckoLib-Konversion (MA4).
- `README.md:610`: Sunmote = „Fullbright 2-cube wisp" — real: MC3-Geo mit
  Strahlenkranz und endlich Glowmask.
- Verhaltens-/Zahlen-Claims daneben stimmen (stichprobengeprüft: Sunmote-Orbit
  `6 + altarLevel` == `SunmoteEntity.java:137`, Chime ~200t == `:226`,
  Boss-Command-Namen == Permission-Keys in `EclipseCommands`).
- **Fix:** 3 Stellen umformulieren, idealerweise im selben Commit wie H-5.

**P-6 — Contract-Lücke: 7 GeckoLib-Items bauen ihre Action-Controller weiter als nackte Hard-0-`AnimationController`.**
- **Dateien:** `wand/EclipseWandItem.java:89-90`, `ritual/ReviveSigilItem.java:99-100`,
  `ritual/StormHeartItem.java:92-93`, `ritual/HeraldsLureItem.java:87-88`,
  `economy/UmbralBladeItem.java:60-61`, `economy/UmbralPickItem.java:71-72`,
  `economy/FerrymanTollItem.java:74-75` — nur ArmArtifact/HeartExtractor nutzen
  `EclipseActionController`.
- **Mechanismus:** aktuell KEIN sichtbarer Schaden — alle Nicht-Spin-Entry-Snaps
  gemessen ≤ 7° (sigil ritual 0°, shatter 1.5°, storm_heart awaken 7°, lure
  offering_prep 4°, feast 0.8°, night_bite 0.6°, present 2.5°; die 180°-Werte sind
  ausnahmslos Molang-Spin-Bones = bewusste Hart-Klasse). Aber jede NEUE Anim auf
  diesen Items erbt still Hard-0 ohne den Policy-Punkt, den POLISH2 genau dafür
  geschaffen hat.
- **Fix:** mechanischer Swap auf `EclipseActionController` mit Policy `0` (bit-identisch,
  reine Zukunftssicherung) — oder bewusst lassen und im P6-Contract als „Items:
  pop-frei zu authorieren ist Pflicht" festschreiben.

---

## 3. Top-5 Polish-Kandidaten für die nächste Welle (Impact ÷ Aufwand)

| # | Kandidat | Impact | Aufwand |
|---|---|---|---|
| 1 | **H-2 Blade-`feast` verdrahten** (1 Zeile, Snippet liegt seit POLISH3 §6 fertig da) | Hero-Item-Highlight wird vom toten Content zum Kill-Moment | trivial |
| 2 | **H-1 Ferryman `kneel` 3t / `harvest` 2t** (`oar_sweep` bewusst hart) | Tag-14-Boss, 64°-Pop im meistgesehenen Zeremonie-Beat | ~6 Zeilen + Sichtprüfung |
| 3 | **H-3 Orin `greet`/`trade`/`hurt` 2–3t** | Händler-NPC, 66°-Pop bei jeder Annäherung/jedem Trade | ~6 Zeilen |
| 4 | **H-4 Stalker `attack` 3t / `hurt` 2t** (+ P-1-Beifang Sentinel/Revenant/Wisp im selben Muster) | Nächtlicher Dauerkontakt, 50–97°-Pops; Hound-Präzedenz macht die Entscheidung risikofrei | ~4×6 Zeilen |
| 5 | **H-5 + P-5 Integrator-Paket**: MA3/MA4-Löschpatches anwenden, LOW-Priorität-Krücke entfernen, README-Modellzeilen aktualisieren | Entfernt 700+ Zeilen tote Klassen, schließt die Regressions-Falle und die Doku-Drift in einem Commit | Patch liegt in den MA-Reports fertig vor |

(P-2/P-3/P-4 sind Kleinsthärtungen für dieselbe Welle, jeweils < 10 Zeilen.)

---

## 4. Gut-Befunde (explizit)

1. **Heightmap-Bug-Klasse bleibt geschlossen.** Diff gegen die W6-B-Audit-Tabelle
   (63 Stellen): alle seither NEUEN Callsites tragen ein Schutzmuster —
   `entity/EclipseSpawner.java:435-441` und `entity/spawn/EventSpawnRules.java:476-482`
   (isLoaded-Gate + Sentinel), `minigames/MinigamePortal.java:91-96` und
   `backrooms/BackroomsPortal.java:78-80` (Sentinel + Spawn-Ring-Kontext),
   `sequence/ExpansionSequence.java:1317/1348` (Force-Load + Sentinel),
   `sequence/NetherUpheavalFx.java:598` (isLoaded), `cutscene/CutsceneService.java:714`
   (Force-Load + dokumentierter C6-Anti-Hoist), `border/SoftBorder.java:698-721`
   (getChunkNow-Null-Pfad bzw. bewusst dokumentierter Sync-Load). Einzige Rest-Stelle:
   P-2. Der W6-B6-Gate in `worldgen/fog/FogStormSites.java:323-326` steht verifiziert im Code.
2. **W6B-Dragon-Fixes und F-109 sind real im Tree** (nicht nur im Report):
   Sentinel-Guard `EclipseDragonFight.java:527`, Landing-Phasen-Guard `:392`,
   `isBorderExempt`/`groundSurfaceYLoading` in `SoftBorder.java:574/716/730`.
3. **Dragon-Bossbar-Relog-Idiom korrekt:** `syncBossBar` re-addiert Walk-ins, Relogs
   und Restart-Reattach und schickt das `THEME_BOSS`-Payload genau einmal pro
   Neu-Viewer (`EclipseDragonFight.java:721-729`).
4. **Death-Konvention flächendeckend frame-exakt:** Sunmote 24t=1.2s, Stalker 28t=1.4s,
   Gazer 30t=1.5s, Sentinel 35t=1.75s, Herald 70t=3.5s, Ferryman 100t=5.0s — jede
   geprüfte Entity matcht ihr `tickDeath`-Fenster exakt auf die Clip-Länge.
5. **Minigame-Lebenszyklus ist Vorbild-Klasse:** persistierte Tickets + Boot-Resume mit
   idempotentem Course-Rebuild (`MinigameService.java:145-171`), Login-Rescue in beide
   Richtungen (`:874-897`), Catch-all für JEDEN Dimensions-Exit (FFIX-B H1, `:914 ff.`),
   Racer-Slot-Freigabe beim Logout (`:911`).
6. **Progression-Persistenz sauber:** `ShardLedger` hält Pending-Queue und
   Delivered-Marker in EINEM SavedData gegen Crash-Replay (`ShardLedger.java:27-31, 77`),
   `OfferingState`/`MinigameState`/`AwardsState` sind SavedData, QuestEngine und
   AwardService liefern Pendings am Login nach (`QuestEngine.java:213-218`,
   `AwardService.java:77-90` inkl. Morning-Paper-Catch-up), `RealtimeDayService`
   pusht das Clock-Payload bei jedem Login (`:825-830`).
7. **Sundial-Katch-up + Stale-Level-Guard:** Mehrfach-Tageswechsel in einem Tick
   flushen die laufende Wander-Animation, tote Integrated-Server-Level werden nie
   getickt (`SundialPlaza.java:100, 134`).
8. **MusicMemory (W6 B7) korrekt:** per-Server-Key-Ledger, Repeat-Faktor wird EINMAL
   pro Voice im Konstruktor aufgelöst — kein Mid-Stream-Dip (`MusicMemory.java:53-66`).
9. **i18n-Disziplin hält:** en_us und de_de sind key-identisch (2 872), alle 179
   Langdrop-Dateien sind vollständig gemerged (0 fehlende Keys beidseitig), alle
   registrierten Items/Entities/Blöcke inkl. der 188 `classic_*` haben
   Description-Keys; die ~110 „Orphan"-Kandidaten der Gegenrichtung lösten sich in
   Stichproben ausnahmslos als dynamische Key-Familien auf (`analytics.eclipse.category.`
   + id etc.) — kein belastbarer Orphan-Befund.
10. **POLISH3-Qualität bestätigt:** `separate_transforms`-Wiring exakt wie
    dokumentiert (`models/item/umbral_blade.json`: builtin/entity-Base + `_2d`-
    Perspectives), 2D-Icons unangetastet, Entry-Snaps der drei neuen Items 0.6–2.5°
    — „pop-frei authoriert" stimmt messbar; `night_bite` (eigenes `mineBlock`) und
    `present` (`use()`) sind im Gegensatz zu `feast` korrekt verdrahtet.
11. **Spin-Hazard-Disziplin:** ALLE 180°-Messwerte (Herald `ring`/`halo`, Revenant
    `wisps`, Orin-Stabkristall, Sigil `ring_spin`, Lure `prongs`, Storm-Heart
    `glow_core`, Portal-Key-Präzession) sind Molang-Dauerrotationen — die bewusste
    Hart-Klasse aus POLISH2 §3 (Cultist-runes-Präzedenz), NICHT als Blend-Kandidaten
    zu behandeln.
12. **MC1/MC2/MC3-Integration vollständig:** Lösch-Snippets angewandt, Legacy-Modelle
    entfernt, Kommentare im Shared-Registrar dokumentieren den Umzug
    (`EclipseEntityRenderers.java:39-40, 48-49`) — der Kontrast macht H-5 erst sichtbar.
13. **Sentinel-`bloom`-Timing sauber gelöst:** der einzige Trigger sitzt am
    Tau-Moment aus `freeze` („the instant it may move", `PaleSentinelEntity.java:247`)
    und misst dort exakt 0.0° Entry-Snap — genau so authoriert man einen
    Hard-0-One-Shot richtig.
