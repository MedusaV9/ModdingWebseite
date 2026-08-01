# WAVE5_PLAN — Polish-Welle 5 (F-105): „Der Sturm antwortet, der Altar atmet, die Abnahme sieht"

Planner-Dokument für Polish-Welle 5, Branch `cursor/project-eclipse`. Drei dateidisjunkte
Team-Charters (A/B/C) für parallele Fable-5-Max-Thinking-Teams auf DEMSELBEN Worktree.
Dateidisjunktheit ist HART: die Ownership-Matrix in §6 ist Vertragsbestandteil jedes Charters.

Quellenlage: `AGENTS.md` (Hausregeln), `UserFeedback.md` (F-001…F-104),
`WAVE4_COMBAT_REPORT.md`, `WAVE4_HEARTS_REPORT.md`, `WAVE4_LIMBO_REPORT.md`,
`WAVE3_NEWFX_REPORT.md`, `FX_RESPAWN_HYGIENE_REPORT.md`, `CREDITS_RISK_CLOSEOUT_REPORT.md`,
`NETHER_MASS2_REPORT.md`, `STORM_MASS_PLAN.md`, Ideensammlungen `ideas_wave4/IDEA-01…20`
(Konsum-Status per `rg -n "IDEA-\d+ [#§]"` gegen den Live-Tree verifiziert, Stand dieses Commits).

---

## 1. Bestandsaufnahme — offene / deferred Punkte

### 1.1 Explizit an Welle 5 übergeben (aus den Welle-4-Reports)

| # | Punkt | Quelle | Befund (verifiziert) |
|---|---|---|---|
| D-1 | **`/eclipsefx limbo wakehold`** — Foto-Hilfe für den C2-Ghost-Wake. Sub-2-s-Vanilla-Partikel (SPLASH/SOUL/GLOW) sind auf der GPU-losen VM nicht bildfähig (ParticleEngine altert in ECHTZEIT, `tick rate 2` hilft nicht — S6-Präzedenz F-096/F-101). Ein Dev-Loop, der Splash+Wake an allen Ruderblättern dauerhaft nachfeuert, macht die Optik abnehmbar. | WAVE4_LIMBO_REPORT §„C2-R2 Live-Abnahme" | OFFEN — `rg -rn "wakehold" src/` → 0 Treffer; Vorbild `storm flashhold` (F-101 T4) + `limbo streakhold` (W4C C7); nächste freie ACTION-Ids in `FxDevPayloads`: 12, 13 |
| D-2 | **A1-Tyrant-Desperation-Flicker nur statisch abnehmbar** — die 1–2t-Blackouts sind llvmpipe-seitig unfangbar; analoger `flickerhold`, der den Blackout-Zustand des Emissive-Passes clientseitig HÄLT. | WAVE4_COMBAT_REPORT §2 A1 + §5 Check 5 | OFFEN — `rg -n "flickerhold" src/` → 0; Blackout-Logik sitzt in `FogTyrantRenderer.EnrageGlowLayer.desperationBlackout()` (Zeile 111), rein clientseitig |
| D-3 | **Q2-Hygiene-Zähler in `/dev photon status`** — Welle 4 mit Beweis gestrichen (Dist-Crash-Risiko im Server-Command); die im Report empfohlene 1-Zeilen-Lösung sitzt in `FxDevClient.photonStatus()` (Zeile ~163), damals Team-C-Verbotszone, jetzt frei. Accessors `PhotonBridge.hygieneDirtyScrubs()/hygieneLinksRemoved()` sind public static (Zeilen 830/835). | WAVE4_COMBAT_REPORT §4 | OFFEN — `rg -n "hygiene" src/main/java/dev/projecteclipse/eclipse/cutscene/dev/FxDevClient.java` → 0 |
| D-4 | **Woah-Audio G-2** (3 dedizierte Audio-Beds) | AUDIT_REVERIFY / F-095 | **BLOCKIERT — NICHT einplanen** (`TREBLO_API_KEY` fehlt in der Umgebung; Specs+Prompts liegen fertig) |

### 1.2 Beobachtungsposten (nicht chartern, nur wissen)

- NETHER_MASS2 §7: llvmpipe-Restrisiko Kegel-Dichte (`veil_cone`-Regler bereitliegend) + Slam-Beat bei niedriger Pressure — Abnahme war PASS, nur bei künftigen Beschwerden drehen.
- MC4 §7.3: Ghost-Nametag-Fenster-Ränder (Austritt zeigt Klartext einen Frame) — kosmetisch, kein Charter.
- MA2 §8.3: Warden-Schatten steht während Vanish in voller Größe (synced Blink-Flag wäre nötig) — Scope-Creep-Gefahr, Backlog.
- MB3 §8.2: `glow_hood` seitlich unsichtbar — bewusst so.
- FX_RESPAWN_HYGIENE „Beifang": `Finished uploading vanilla shaders`-INFO-Flood nach Punktlicht-Aktivierung auf llvmpipe ist Veil-intern, harmlos, NICHT fixen.
- Ownership-Learning aus W4A/Q2: `PhotonBridge` ist `@OnlyIn(Dist.CLIENT)` — Referenzen aus Server-Command-Kontexten sind `NoClassDefFoundError`-Risiken. Renderseitige Ausgaben gehören in `FxDevClient`.

### 1.3 Ideensammlungs-Census (was ist noch offen?)

Verifiziert per Marker-Grep gegen den Live-Tree (`W4-*`/`IDEA-*`-Kommentar-Konvention):

- **Konsumiert** (nicht erneut einplanen): IDEA-01 #1–3, IDEA-02 komplett (W4A), IDEA-05 #1–3, IDEA-09 #1–3 (+#7 Dawn-Toll via `CUE_DAWN_TOLL`), IDEA-12 #1–3, IDEA-13 komplett (W4B), IDEA-14 §1–3, IDEA-15 §1/§2/§3/§6, IDEA-16 #1/#2/#3/#7, IDEA-17 (Großteil, W4-NETHER), IDEA-18 komplett (W4C), IDEA-03-Jackpot/IDEA-09-Omen/IDEA-12-Kaufblüte (Wave 3).
- **Offen und in dieser Welle chartered**: IDEA-15 §4/§5/§7/§8/§9/§10 (Team B); IDEA-16 #5/#8/#10 (Team A), #6 (Team C, HUD-Datei); IDEA-12 #4/#5/#6/#9/#10 (Team C); IDEA-09 #4 (Team C).
- **Offen, Backlog Welle 6+**: IDEA-16 #4 (Sky-Reaktionen — neues Protokoll + Sky-Stack-Risiko), #9 (Summon-Fly-by — Letterbox-Contention); IDEA-09 #5/#6/#8/#9/#10; IDEA-12 #7/#8; IDEA-01 #4–#10; IDEA-05 #4–#10 (bis auf C-Stretch); IDEA-04/06/07/10/11/20-Reste.

---

## 2. Ideation — priorisierte Ideenliste

Dauerauftrag: „massiv jeden Veil-/Photon-/BlockDisplay-Effekt weiter polieren + neue
Spektakel-Momente schaffen". Suchraster war: Events ohne FX-Kopplung, UI-Beats ohne
Zeremonie, Mobs ohne Tell — entlang der Journey Tag 1 → Nether → Stürme → Herold → End →
Credits, Limbo-Loop, Altar-Ökonomie, Backrooms, Glitchzonen.

| Prio | Idee | Journey-Moment | Team | Warum |
|---|---|---|---|---|
| P1 | D-1 `limbo wakehold` + D-2 `tyrant flickerhold` + D-3 Q2-Zeile | Abnahme-Infrastruktur | A | Zwei Welle-4-Deliverables sind ohne sie dauerhaft nicht fotografierbar; jede künftige Welle profitiert |
| P1 | Sturm-Schwelle „Gulp" (IDEA-15 §7) | Sturm-Betreten | B | Der dramatischste Übergang des Mid-Game ist heute ein Gradient — Schwelle statt Verlauf |
| P1 | Sturmtod = „der Nebel schluckt den Schrei" (IDEA-15 §4) | Sturm-Tod | B | Ein Spieler-Tod IM Sturm ist heute komplett stumm für alle draußen — der stärkste ungenutzte Horror-Beat |
| P1 | Last Call am Altar (IDEA-09 #4) | Tages-Deadline | C | Offerings verfallen wortlos — einziger täglicher Beat, der Spieler real Werte kostet |
| P1 | Armed-Offering-Spannungsfenster (IDEA-12 #6) | Altar-Ritual | C | 100t-Fenster existiert nur als Actionbar-Zeile — „stummer" UI-Beat par excellence |
| P1 | Dawn-Verdict-Blüte (IDEA-12 #10) | Morgen-Liturgie | C | `resolveDay` kürt den Gewinner, der Altar bleibt physisch tot |
| P2 | Sub-10%-Arena-Herzschlag-Crescendo (IDEA-16 #10) | Bosskampf-Finale | A | Alle 4 Bosse enden heute ohne Spannungs-Rampe |
| P2 | Marked-Player-Spotlight (IDEA-16 #8) | Herold/Ferryman-Gaze | A | Team-Play-Tell fehlt komplett (Gaze ist opferprivat) |
| P2 | Tageslicht-Wand-Rim (IDEA-15 §5, EVAL-4 obs#3) | Sturm bei Tag | B | Bekannte Lesbarkeits-Schwäche mit fertiger Rezeptur |
| P2 | Fog-Mob-Glowmask-Atmung (IDEA-15 §8) | Sturm-Interior | B | „Augen zuerst, Körper später" — reine Client-Multiplikation, großer Dread-Gewinn |
| P2 | Milestone-Chime-Leiter (IDEA-12 #5) + Aberrations-Puls (IDEA-12 #4) + Level-Atem (IDEA-12 #9) | Altar-Ökonomie | C | Der Altar bekommt Ohren, Reflexe und einen Puls — 3 kleine Edits, ein Charakter |
| P2 | Bossbar-Phase-Break-Shatter (IDEA-16 #6) | Bosskampf-HUD | C | Rein clientseitige HUD-Zeremonie, 0 Netzwerk, deckt alle 4 Bosse in einer Datei |
| P3 | Boss-Trophäen-Monument + NEU „Trophäen-Resonanz" (IDEA-16 #5 + eigener Photon-Wisp-Loop WINDOWED) | Nach-Sieg | A | Arenen sind nach dem Sieg tote Orte; ein Monument mit leisem Idle-Wisp macht den Sieg dauerhaft sichtbar |
| P3 | NEU „Hold-Inventar": `/eclipsefx holds` listet alle aktiven Dev-Holds | Abnahme-Infrastruktur | A | Vier Hold-Systeme (flashhold/streakhold/wakehold/flickerhold) — stale Holds verfälschen sonst künftige Abnahme-Fotos |
| P3 | Lair-Dread (IDEA-15 §9) + Chest-Open-Reaktion (IDEA-15 §10) | Sturm-Loot-Camp | B | Loot bekommt einen Preis, der tiefste Sturm einen Puls |
| P3 | Shard-Bank-Arpeggio (IDEA-12 #8) + Day-Timer-Lub-Dub (IDEA-05 #4) | Ökonomie/HUD | C | Stretch — nur wenn P1/P2 grün sind |

Nicht eingeplant: Woah-Audio G-2 (blockiert, s. §1.1 D-4), IDEA-16 #4/#9 (Backlog-Begründung §1.3).

---

## 3. Team-Charter A — „Abnahme-Augen & Boss-Punktuation"

**Mission**: Die zwei nicht-fotografierbaren Welle-4-Effekte dauerhaft abnehmbar machen
(wakehold/flickerhold), den Q2-Rest schließen, und den Bosskampf-Bogen um die drei fehlenden
Punktuations-Beats ergänzen (Spotlight, Crescendo, Monument).

### Scope / Deliverables

1. **A1 `/eclipsefx limbo wakehold on|off`** — flashhold-Präzedenz 1:1 (`FxDevCommands`-Leaf →
   `FxDevPayloads.ACTION_LIMBO_WAKEHOLD = 12` → `FxDevClient.limboWakeHold` → statischer
   Hold-State in `DeckhandRenderer`). ON: pro gerendertem Frame (throttled, z. B. min. alle 10t
   Level-Zeit) feuert `spawnCatchSplash`/`spawnGhostWake` an ALLEN sichtbaren Ruderblättern
   nach — unabhängig vom 60t-Anker, damit auf llvmpipe in jedem Present-Intervall frische
   Partikel stehen. OFF: restlos weg, Live-Pfad bit-identisch (Hold-Branch = einziger
   Konsument). Logout/Dimension-Wechsel cleart (FxDevClient-Hygiene, streakhold-Muster).
   Zeichnet als Operator-Override auch unter `reducedFx`. DEBUG-Sonde `[w5a-wakehold]`
   (Fire-Count pro Rower) im `[c2-splash]`-Muster.
2. **A2 `/eclipsefx tyrant flickerhold on|off|blackout`** — `ACTION_TYRANT_FLICKERHOLD = 13`.
   Statischer Override in `FogTyrantRenderer`: `blackout` hält `desperationBlackout()`
   dauerhaft TRUE (Emissive-Pass aus — fotografiert den Blackout-Zustand), `on` hält eine
   gedehnte Kadenz (z. B. 20t an / 20t aus statt 1–2t), `off` restauriert den
   SplitMix64-Hash-Schedule bit-identisch. Wirkt phasen-unabhängig (der Hold ist die
   Foto-Hilfe — der Live-Pfad bleibt Phase-3-gated). DEBUG-Sonde `[w5a-flickerhold]` bei
   Zustandswechsel.
3. **A3 Q2-Closeout** — genau die im W4A-Report empfohlene Zeile: `FxDevClient.photonStatus()`
   hängt `hygiene: scrubs=<N> links=<N>` (aus `PhotonBridge.hygieneDirtyScrubs()/
   hygieneLinksRemoved()`) an die bestehende Status-Ausgabe. KEINE Änderung an
   `PhotonBridge`/`DevPhotonCommands`.
4. **A4 Marked-Player-Spotlight (IDEA-16 #8)** — während Herold-P2-Gaze und
   Ferryman-Lantern-Gaze aktiv sind: alle 20t eine dünne serverseitige Partikelsäule
   (END_ROD, 2 Blöcke) bzw. `S2CQuasarPayload`-Beam am markierten Spieler, damit Mitspieler
   peelen können. Hooks: `HeraldEntity.tickGaze`, `FerrymanEntity` Gaze-Begin/Refresh.
   Log-Sonde `[w5a-spotlight] <victim> <boss>` pro Send-Fenster (throttled, max 1 Zeile/s).
5. **A5 Sub-10%-Herzschlag-Crescendo (IDEA-16 #10)** — in allen 4 `tickFight`-Pfaden: unter
   10% HP `WARDEN_HEARTBEAT` an `livingParticipants` mit fallender Kadenz 30t → 20t → 12t
   (HP-gestaffelt), Arena-Wand-Partikel-Kadenz im selben Fenster verdoppelt
   (`RiftAnchor.particleWall`/`FogTyrantArena.particleWall`-Callsites; Herold nutzt sein
   bestehendes `sendPrivateHeartbeat`-Plumbing). Throttle nach
   `DEFLECT_CUE_INTERVAL_TICKS`-Muster. Log-Sonde `[w5a-crescendo] <boss> hp=<f> cadence=<t>`.
6. **A6 Boss-Trophäen-Monument (IDEA-16 #5) + Trophäen-Resonanz (NEU)** — am Ende der
   Skript-Tode: 1-Block-Marker am getrackten Arena-Zentrum (Herold Amethyst-Cluster,
   Rift-Warden Obsidian+End-Rod, Tyrant Lightning-Rod, Ferryman Soul-Laterne am Heck —
   übersteht `restoreShip`, das nur Wasser sweept). Air-Check vor Platzierung, Gate auf die
   `EclipseWorldState`-Defeat-Flags (Re-Summons stapeln keine Monumente). Optional
   (Photon-Budget vorhanden): ein leiser `wave5_trophy_wisp`-Loop (WINDOWED, Hysterese,
   CullBox, `reducedFx` skippt) über dem Monument via eigener `Wave5BossFxRows`.
7. **A7 (Stretch) `/eclipsefx holds`** — listet die vier Hold-Zustände
   (flashhold/streakhold/wakehold/flickerhold) im Client-Chat; reine Lese-Ausgabe in
   `FxDevClient` (flashhold-State via bestehendem `stormfx/StormFlashDevHold`-Getter —
   NUR lesen, Datei gehört Team B).

### Akzeptanzkriterien (llvmpipe-real, Log-Sonden bevorzugt)

- **A1**: frischer Client → `eclipse tp_limbo Dev`, Kamera auf die Ruderbank →
  `execute as Dev run eclipsefx limbo wakehold on` → binnen 30 s Screenshot mit sichtbarer
  Soul-Driftlinie + Glow-Glint an ≥1 Ruderblatt; `rg -c "\[w5a-wakehold\]" run/logs/debug.log`
  wachsend; `off` → 60 s warten, keine neuen Sonden, Folge-Screenshot ohne Nachfeuern;
  danach `rg -c "\[c2-splash\]"` wächst weiter (Live-Pfad unangetastet).
- **A2**: `summon eclipse:fog_tyrant ~10 ~ ~` → `eclipsefx tyrant flickerhold blackout` →
  Screenshot Krone/Auge/Core DUNKEL; `off` → Screenshot Glow zurück; Sonde loggt beide
  Wechsel; Gegenprobe: ohne Hold + Phase 1 kein Flicker (W4-Verhalten erhalten).
- **A3**: `execute as Dev at Dev run dev photon status` → Client-Chat enthält die
  hygiene-Zeile (Screenshot oder `run/logs/latest.log`-Echo); Dedicated-Server-Boot bleibt
  crash-frei (keine neue PhotonBridge-Referenz außerhalb `Dist.CLIENT`-Code).
- **A4**: Herold summonen, Gaze abwarten (`rg "\[w5a-spotlight\]" run/logs/debug.log` ≥1);
  Screenshot der Säule über dem markierten Dev-Spieler (statische Säule, fotografierbar).
- **A5**: Boss per `damage` unter 10% drücken → Sonden-Kadenz verifiziert 30→20→12t
  (Zeitstempel-Deltas im debug.log); Arena-Wand sichtbar dichter (Screenshot-Paar davor/danach).
- **A6**: jeden Boss per Dev-Pfad töten → RCON `execute if block <x y z> <block>` = pass;
  Re-Summon + Re-Kill → weiterhin genau EIN Monument; falls Wisp gebaut: 0 neue
  fxlib-Findings, Doppellauf byte-identisch, `reducedFx`-Gegenprobe (Loop weg).
- **Gates**: `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` BUILD
  SUCCESSFUL; bei `.fx`-Assets zusätzlich `python3 tools/photon/fxlib.py validate --lint`
  0 NEW + `processResources` grün; Lang-Keys NUR als `docs/plans_v3/langdrop/WAVE5A.json`.

### Datei-Ownership (exklusiv Team A)

`cutscene/dev/FxDevCommands.java`, `cutscene/dev/FxDevPayloads.java`,
`cutscene/dev/FxDevClient.java`, `cutscene/dev/FrameTimeProbe.java`,
`client/entity/DeckhandRenderer.java`, `entity/DeckhandEntity.java`,
`client/entity/fogboss/FogTyrantRenderer.java`, `entity/boss/HeraldEntity.java`,
`entity/boss/FerrymanEntity.java`, `entity/boss/rift/RiftWardenEntity.java`,
`entity/boss/rift/RiftAnchor.java`, `entity/boss/fog/FogTyrantEntity.java`,
`entity/boss/fog/FogTyrantArena.java`; NEU: `tools/photon/wave5_boss_fx.py`,
`veilfx/Wave5BossFxRows.java`, `assets/eclipse/fx/wave5_*.{fx,fxproj}`,
`docs/plans_v3/langdrop/WAVE5A.json`, Report
`docs/plans_v3/session_0730/WAVE5_A_DEVHOLDS_BOSS_REPORT.md`.

**Verbotszonen**: ALLE Team-B-Dateien (insb. das gesamte `stormfx/`-Package inkl.
`StormFlashDevHold` — nur lesen, `entity/boss/fog/FogBankMarker.java`, `client/entity/fog/**`,
`network/fx/FxPayloads.java`, `veilfx/EclipseFxState.java`), ALLE Team-C-Dateien (insb.
`ritual/**`, `offering/**`, `client/hud/**`, `client/AltarAberration.java`,
`veilfx/QuasarSpawner.java`, `economy/**`, `progression/realtime/**`) sowie die globalen
Frozen-Zonen (§5).

---

## 4. Team-Charter B — „Der Sturm antwortet" (Fogstorm-Schwellen & Schluckmomente)

**Mission**: Die sechs offenen IDEA-15-Restposten — der Sturm bekommt eine Schwelle, eine
Antwort auf Tod und Loot-Griff, Tageslicht-Lesbarkeit, atmende Mobs und einen Lair-Puls.

### Scope / Deliverables

1. **B1 First-Breach-Swallow (IDEA-15 §7)** — `StormInteriorFx.onClientTick`-Edge-Detection
   (`prevSmoothed < 0.5 && smoothed >= 0.5`, rising only): einmal pro Crossing
   `EVENT_STORM_BURST` (1.2/0.5) + `TransitionFx.glitchPulse(0.15F, 10)` (via bestehendem
   `glitchPulseSafe`-Muster) + Fog-Near-Plane-Pinch 6→2 über 10t (`breachTicks`-Zähler im
   `onRenderFog`). Falling Edge (<0.3): leiser Exhale. DEBUG-Sonde
   `[w5b-breach] enter|exit smoothed=<f>`.
2. **B2 Sturmtod-Schlucken (IDEA-15 §4)** — NEU `stormfx/StormDeathFx.java`
   (`LivingDeathEvent`, `EventPriority.LOW`, house-Präzedenz `WitnessedLossService` — die
   Datei selbst NICHT anfassen): Guard ServerPlayer horizontal in `StormRegistry.storms()`
   -Radius. Am Corpse: Fog-Inhale (zwei schrumpfende CLOUD-Ringe 6→2 über 10t) + gedämpfter
   `EVENT_STORM_BURST` 0.6. Für Hörer AUSSEN (in-dimension, ≤96 Blöcke von der Schale,
   außerhalb radius): gedämpfter Schrei vom nächsten Schalenpunkt (`center + n̂·radius`,
   `StormLoopSound.updatePosition`-Projektion) + 8t später `EVENT_LIGHTNING_FAR` 0.7. Für
   Spieler INNEN: 15t-Regen-Surge via neuer `FX_STORM_SURGE`-Id auf der
   `FxPayloads.sendFxEvent`-Lane (Client: temporär `EclipseFxState.setStormInterior`-Rain
   ×1.6 — der `RainAmount`-Uniform von `storm_interior` ist verdrahtet). DEBUG-Sonden
   `[w5b-swallow] corpse|outside|inside <details>` pro Lane.
3. **B3 Tageslicht-Wand-Rim (IDEA-15 §5, EVAL-4 obs#3)** — `StormWallRenderer`:
   `dayBoost = 1 − skyDarken/15` einmal pro Frame; Churn-Band in Tageslicht verbreitern,
   äußere Additiv-Schale (`shellIndex == 0`) im oberen Drittel `alpha ×(1 + 0.5·dayBoost)`.
   Nur Konstanten/Formeln, keine neue Geometrie; EVAL-4-M4-Occluder-Hysterese in derselben
   Nachbarschaft mit erledigen. ACHTUNG Haus-Gesetz: nichts Depth-schreibendes in die
   Volumetrik (AGENTS.md-Occluder-Falle).
4. **B4 Fog-Mob-Glowmask-Atmung (IDEA-15 §8)** — `client/entity/fog/`-Renderer
   (`StormHoundRenderer`, `FogColossusRenderer`, `FogRevenantRenderer`): Emissive-Alpha
   skaliert mit `StormInteriorFx.interiorAmount()` (`0.6 + 0.8·interior`). Rein
   clientseitiger Multiplikator; W4A-Stagger-Tell (`rift_spark`-Attach in
   `StormHoundRenderer.preRender`) darf NICHT verändert werden — nur der Emissive-Pass.
5. **B5 Lair-Dread (IDEA-15 §9)** — Server: `FogBankMarker.stampBankPillars` gewichtet die
   Pillar-Ring-Rauchdichte Richtung nächstem Beobachter (`+0.35·sin(bearing−angle)`).
   Client: protokollfrei — innerhalb 30 Blöcke vom Sturm-ZENTRUM (Lair == Site-Center per
   `FogStormSites.reconcileTyrantLair`) bei `interior > 0.6` läuft der §1-Heartbeat als
   Doppel-Thump, Kadenz 16t, INNEN weiter. Sonde `[w5b-lairdread] cadence=16`.
6. **B6 Chest-Open-Reaktion (IDEA-15 §10)** — NEU Listener in `worldgen/fog/`
   (`PlayerContainerEvent.Open` gegen `fogSiteState(siteId).chests()`): pro Chest einmal
   pro Session ein Schalen-Arc-Volley am WALL-Punkt Richtung Chest (Server-projiziert,
   EVAL-4-`storm bolt`-Learning: nie am Spieler ankern) + `EVENT_LIGHTNING_FAR` 0.8; 30%
   ein `fog_revenant` 12–16 Blöcke draußen via kleiner PUBLIC Hook in
   `EventSpawnRules` (Gates/Caps respektieren, nie duplizieren). Sonde
   `[w5b-chest] site=<id> pos=<p> revenant=<bool>`.

### Akzeptanzkriterien

- **B1**: Dev fliegt bei `tick rate 20` durch die Wand → `rg "\[w5b-breach\]" run/logs/debug.log`
  zeigt GENAU 1 enter pro Crossing (rein/raus/rein = 2 enter + 1 exit, keine Doppel-Fires
  beim Verweilen); Sichtprobe optional (Pulse ist 10t — Log ist der Beweis).
- **B2**: Dev in den Sturm, `damage Dev 1000` → alle drei Sonden-Lanes feuern; die
  outside-Zeile loggt den projizierten Schalenpunkt (Koordinaten-Plausibilität: |p−center|≈radius);
  Respawn/Geist-Flow unbeeinflusst (`[c2-splash]`/Hearts-Verhalten normal, keine neuen WARN).
- **B3**: `time set noon` → Screenshot der Wand aus ~40 Blöcken: sichtbare Silhouetten-Kante
  + Grauvarianz; `time set midnight` → Screenshot: Nacht-Optik unverändert lesbar
  (Vorher-Referenz aus STORM_MASS_PLAN-S-Serie); `flashhold`-Foto-Pfad von F-101 bleibt intakt.
- **B4**: `summon eclipse:storm_hound` AUSSEN → Screenshot normal; Hound in den Sturm
  locken/teleportieren, Kamera drinnen → Screenshot mit deutlich hellerem `glow_spine`;
  `reducedFx`-Gegenprobe: Multiplikator aktiv lassen oder dokumentiert gaten (Entscheidung
  im Report begründen).
- **B5**: am Lair-Sturm (`/dev`-Storm-Kommandos bzw. bestehende Site) → Sonde zeigt
  16t-Kadenz nur im 30-Block-Kern bei interior>0.6; außerhalb Kern normale §1-Leiter.
- **B6**: Fog-Site-Chest öffnen → 1 Sonde, Re-Open still; 10× öffnen (verschiedene Chests)
  → Revenant-Quote plausibel, Caps nie überschritten (`EventSpawnRules`-Log), Arc ankert
  an der Wand (Log-Koordinaten), nie am Spieler.
- **Gates**: compileJava offline grün; falls Photon-Assets: fxlib 0 NEW + Doppellauf
  byte-identisch; `FxPayloads`-Diff additiv (nur neue Id + Handler-Case);
  `EclipseFxState`-Diff additiv (Surge-Feld + Decay); Lang-Keys nur als
  `docs/plans_v3/langdrop/WAVE5B.json`.

### Datei-Ownership (exklusiv Team B)

Gesamtes `stormfx/`-Package (inkl. NEU `stormfx/StormDeathFx.java`; `StormFlashDevHold`
nur falls für einen Getter nötig — additive Änderung), `client/entity/fog/**`,
`entity/boss/fog/FogBankMarker.java` (Carve-out aus der Boss-Zone — Team A besitzt dort
NUR `FogTyrantEntity`/`FogTyrantArena`), `worldgen/fog/**` (+ neuer Listener),
`entity/spawn/EventSpawnRules.java`, `network/fx/FxPayloads.java`,
`veilfx/EclipseFxState.java`; NEU optional: `tools/photon/wave5_storm_fx.py`,
`veilfx/Wave5StormFxRows.java`, `docs/plans_v3/langdrop/WAVE5B.json`, Report
`docs/plans_v3/session_0730/WAVE5_B_STORM_REPORT.md`.

**Verbotszonen**: ALLE Team-A-Dateien (insb. `cutscene/dev/**`, `entity/boss/**` außer
`FogBankMarker`, `client/entity/fogboss/**`, `client/entity/DeckhandRenderer.java`), ALLE
Team-C-Dateien (`ritual/**`, `offering/**`, `client/hud/**`, `veilfx/QuasarSpawner.java`,
`client/AltarAberration.java`), `drama/WitnessedLossService.java` (Koexistenz über
Priority-Slot, NICHT editieren), `lives/**`, globale Frozen-Zonen (§5).

---

## 5. Team-Charter C — „Morgen-Liturgie & Altar-Seele" (Tages-Ritual, Altar-Ökonomie, HUD-Zeremonie)

**Mission**: Die stummen Beats der Altar-Ökonomie und der Tages-Deadline bekommen Zeremonie:
Last Call, Spannungsfenster, Verdikt-Blüte, Chime-Leiter, Aberrations-Puls/-Atem — plus die
eine HUD-Zeremonie, die alle vier Bosse in einer Datei abdeckt.

### Scope / Deliverables

1. **C1 Last Call am Altar (IDEA-09 #4)** — `RealtimeDayService.onServerTick`: bei T-10 min
   und T-90 s (einmal pro Stage pro Boundary, Flags in `onDayApplied` resetten) bekommt
   jeder Online-Spieler mit `!OfferingService.hasOfferedToday(player)` eine PRIVATE
   Whisper-Caption (`S2CCaptionPayload`, STYLE_WHISPER — `CAPTION_NETHER_RETURN`-Lane) +
   gedämpfte Glocke (`playNotifySound(BELL_BLOCK, 0.4F, 0.6F)`). In der letzten Minute
   flackert der `ritual/BeamEmitter` am Sanctum (3–4 kurze Emits). Guards: Engine armed &&
   !paused; nie in der LastMinuteHush-Kollision (T-90 s statt T-60 s ist bereits die
   Ausweich-Position). Anonymität wahren: kein globaler Text, keine Namen. Sonde
   `[w5c-lastcall] stage=<10m|90s> player=<name>`.
2. **C2 Armed-Offering-Spannungsfenster (IDEA-12 #6)** — Arm-Branches von
   `AltarBlockEntity.handleOffering`/`handleHeartSacrifice` senden einmal ein
   `S2CQuasarPayload` mit NEUEM one-shot Emitter `quasar/emitters/offering_armed.json`
   (Klon von `altar_beam.json`: `max_lifetime` 100, dunkle #5B1E99-Motes in enger Säule —
   „ein Beam, der die Luft anhält"). Kein Cleanup nötig (bounded one-shot, kein `loop`).
3. **C3 Dawn-Verdict-Blüte (IDEA-12 #10)** — `OfferingService.resolveDay`: nach einer
   Resolution MIT Gewinnern 3× `BeamEmitter.emit` über ~40t am
   `EclipseWorldState.getSanctumAltarPos()` (null-Guard für Pre-Intro-Welten); der Gewinner
   (falls online) hört privat `OFFERING_ACCEPT` bei 1.3F. Duplikat-annullierte Tage bleiben
   dunkel (lehrt die Regel wortlos). Sonde `[w5c-verdict] winners=<n>`.
   (Erst-Verifikation: `sig/crown_verdict` ist die BOSS-Kill-Signatur — der Offering-Verdikt
   hat heute KEINE physische Antwort; `rg -n "crown|verdict" offering/OfferingService.java` → 0.)
4. **C4 Milestone-Chime-Leiter (IDEA-12 #5)** — `AltarBlockEntity.handleMilestoneDeposit`:
   Chime-Pitch `0.7 + 0.5·(updated/count)` statt fix 0.8. Sonde loggt den Pitch
   (`[w5c-chime] pitch=<f>` DEBUG — Audio ist auf der VM stumm, der Log ist die Abnahme).
5. **C5 Aberrations-Puls + Level-Atem (IDEA-12 #4 + #9)** — `client/AltarAberration`:
   statisches `pulse(float)` (+0.20, linearer Decay ~15t, geclampt ≤ MAX_STRENGTH — der
   Single-Uniform-Contract bleibt frozen); Trigger client-lokal aus
   `veilfx/QuasarSpawner.spawnOrFallback` bei Emitter-Id `ALTAR_BEAM` (1-Zeilen-Notify);
   für Shard-Banking ein `S2CQuasarPayload(ALTAR_BEAM…)` im Deposit-Branch von
   `ritual/AltarBlock.onSneakRightClick`. Atem: `feedPost`-Frequenz `0.3 + 0.03·altarLevel`
   Hz (auf 0.01 Hz gesnappt — Wrap-seamless bleibt bewiesen), Amplitude bis ±14%, Level aus
   `ClientStateCache.altarLevel` (nur LESEN). `reducedFx`: Puls skippen, Atem bleibt
   geflattet (Bestand). Sonden `[w5c-abpulse]`/`[w5c-breath] hz=<f>` (einmal pro Änderung).
6. **C6 Bossbar-Phase-Break-Shatter (IDEA-16 #6)** — `client/hud/BossbarSkin`: beim
   client-detektierten Phasen-Break (Bossbar-Progress kreuzt 2/3 / 1/2 / 1/3 abwärts, oder
   `getPhase()`-Sprung bei Sichtweite) 10t Weißglut-Spike auf dem bestehenden
   `glowAlpha`-Parameter + 6–8 fallende 2×2-px-Fragmente ab der Notch-Position. Null neues
   Netzwerk, deckt alle 4 Boss-Themes. Sonde `[w5c-barshatter] theme=<t> notch=<f>`.
7. **C7 (Stretch) Shard-Bank-Arpeggio (IDEA-12 #8)** — `economy/ShardEconomy.deposit`:
   Chime-Queue `min(1 + amount/8, 6)`, alle 3t, Pitch 1.2→1.8; Map-Clear im bestehenden
   `onServerStopped`. **C8 (Stretch) Day-Timer-Lub-Dub (IDEA-05 #4)** —
   `client/hud/DayTimerLayer`: finale 10 s doppelter Visual-Puls.

### Akzeptanzkriterien

- **C1**: Boundary via `/dev phase`-Werkzeugen nah setzen → Dev OHNE Offering bekommt beide
  Whisper (Sonden-Zeilen T-10m/T-90s genau je 1×); Dev MIT Offering (Dev-Deposit) bekommt
  KEINE; Beam-Flicker-Screenshot in der letzten Minute; nach Boundary reset ⇒ nächster Tag
  armt frisch.
- **C2**: Offering armen (erster Klick) → bei `tick rate 2` Screenshot der dunklen
  Warte-Säule (100t = ~50 s Echtzeit — fotografierbar); Fenster verfallen lassen → Säule
  fadet ohne Residuum; Confirm → Accept-Beam ersetzt sie sichtbar.
- **C3**: Gewinner-Tag erzwingen (2 Spieler-Werte via Dev-Offerings oder Single-Player-Win)
  → `[w5c-verdict]`-Sonde + Screenshot einer Beam-Salve; Duplikat-Tag → Sonde `winners=0`,
  kein Beam.
- **C4**: Milestone via RCON-Give + Deposits hochgrinden → Pitch-Sonden strikt monoton
  steigend bis zum `completeMilestone`-Sting.
- **C5**: Deposit am Altar → `[w5c-abpulse]`-Sonde; Sichtprüfung als Serie (Aberration ist
  Screen-Space-subtil — Screenshot-Paar Peak/Idle bei `tick rate 2`, sonst Log-Abnahme);
  `/dev`-Altar-Level ändern → `[w5c-breath]`-Sonde zeigt neue Hz; `reducedFx`-Gegenprobe.
- **C6**: Boss summonen, per `damage` über eine Phasen-Schwelle drücken → bei `tick rate 2`
  Screenshot des Glut-Spikes + Fragmente (10t ⇒ ~5 s), Sonde 1× pro Break, NIE beim
  Heilen/Progress-Aufwärts.
- **Gates**: compileJava offline grün; `offering_armed.json` JSON-valide +
  `processResources` grün; Lang-Keys (Captions C1) NUR als
  `docs/plans_v3/langdrop/WAVE5C.json` (en+de parity); kein `.fx`-Asset nötig — falls doch,
  volle fxlib-Gates.

### Datei-Ownership (exklusiv Team C)

`ritual/AltarBlockEntity.java`, `ritual/AltarBlock.java`, `ritual/BeamEmitter.java`,
`client/AltarAberration.java`, `veilfx/QuasarSpawner.java`, `offering/OfferingService.java`,
`progression/realtime/RealtimeDayService.java`, `client/hud/BossbarSkin.java`,
`client/hud/DayTimerLayer.java`, `economy/ShardEconomy.java`; NEU:
`assets/eclipse/quasar/emitters/offering_armed.json`, `docs/plans_v3/langdrop/WAVE5C.json`,
Report `docs/plans_v3/session_0730/WAVE5_C_ALTAR_RITUAL_REPORT.md`.

**Verbotszonen**: ALLE Team-A-Dateien (`cutscene/dev/**`, `entity/boss/**`,
`client/entity/**`), ALLE Team-B-Dateien (`stormfx/**`, `network/fx/FxPayloads.java`,
`veilfx/EclipseFxState.java`, `worldgen/fog/**`), `drama/**` (insb. `DawnCeremony` —
C1 läuft über RealtimeDayService, NICHT über die Ceremony), `hearts/**`, `awards/**`,
`timeline/AnnouncementService.java`, `client/hud/SidebarPanel.java`/`SidebarExpanded.java`
(W4-FEEL-Bestand), globale Frozen-Zonen (§5).

---

## 6. Gesetze für ALLE Charters + globale Frozen-Zonen

Jedes Team MUSS (aus AGENTS.md + Wave-Historie):

1. **Erst-Verifikation vor jeder Codezeile**: Tabelle im Report mit `rg`-Beweisen, dass
   jedes Item wirklich offen ist (W4-Muster). Bereits Konsumiertes wird mit Beweis
   gestrichen, nicht doppelt gebaut.
2. **`.fx`-Assets NUR via `tools/photon/fxlib.py`-Generatoren** (uuid5-deterministisch,
   eigener Generator pro Team, `.fxproj`-Sibling committen, `fxlib.py validate --lint`
   0 neue Findings, Doppellauf byte-identisch). Quasar-Emitter-JSONs sind handschreibbar
   (JSON, kein NBT), Feldschema von Bestands-Emittern kopieren.
3. **V2.1-Stacking-Law**: Birth-Tints dunkel, HDR ≤ 1.45, Schalen breit, Counts getrimmt;
   CullBox auf JEDEM Emitter; Loops nur WINDOWED mit Hysterese; `reducedFx`-Gates
   (Operator-Holds dürfen als expliziter Override zeichnen — streakhold-Präzedenz);
   Quasar-/Vanilla-Fallbacks für jede neue Photon-Row (LAYER, Quasar-Leg `null` nur für
   NEUE Cues legal).
4. **Lang-Keys NUR als `docs/plans_v3/langdrop/WAVE5<X>.json`** (en+de). NIEMAND ruft
   während der Parallel-Phase `merge_langdrops.py` auf — bei 3 parallelen Teams wäre der
   Merge in die zwei lang-JSONs ein Write-Konflikt. Der Hauptagent merged zentral in der
   Abnahme.
5. **Keine `data/minecraft/tags`-Duplikate** (generated-Root prüfen).
6. **Gradle immer `flock /tmp/gradle.lock ./gradlew … --offline`**; laufende Server-/
   Client-JVMs NIE killen oder starten (die Live-Abnahme macht der Hauptagent; das
   F-103-Learning „frische JVM nach Kompilieren" gilt für IHN, nicht für euch).
7. **`UserFeedback.md` gehört dem Hauptagenten**; `FxCues.java`, `PhotonBridge.java`,
   `PhotonFxRegistry.java`, `tools/photon/fxlib.py`, die beiden lang-JSONs, `limbo.fsh`,
   `limbo/GhostShipBuilder`/`LimboSeascape`, `veilfx/LimboAmbience.java`/
   `LimboRowChant.java`, `drama/CombatFeedbackFx.java`, `hearts/**`, `lives/**`,
   `network/hearts/**`, `credits*`-Klassen und -Generatoren sind GLOBALE Frozen-Zonen
   (kein Team fasst sie an). Cue-Ids beidseitig via `FxCues.cue("…")` re-derivieren.
8. **DEBUG-Sonden im `[c2-splash]`/`[w4a-whiff]`-Muster** (`EclipseMod.LOGGER.debug`,
   landet in `run/logs/debug.log`): Team-Präfixe `[w5a-*]`, `[w5b-*]`, `[w5c-*]`.
   Log-Sonden sind auf der llvmpipe-VM das primäre Abnahme-Werkzeug — jede visuelle
   Behauptung braucht entweder einen statisch fotografierbaren Zustand (Hold, tick rate 2,
   Dauer ≥ ~3 s) oder eine Sonde.
9. **Additive Diffs, kein Reformat fremder Zeilen**; jede Fremd-Datei-Änderung als
   klar kommentierter `WAVE5 (F-105 <TEAM>)`-Hook.
10. **Reports** nach W4-Muster: Erst-Verifikationstabelle, Umsetzung je Item,
    Gate-Belege, RCON-Abnahme-Drehbuch für den Hauptagenten (llvmpipe-tauglich:
    `tick rate 2`-Hinweise, Log-Sonden-Kommandos, Screenshot-Spots).

### Ownership-Matrix (Kurzform, HART)

| Zone | A | B | C |
|---|---|---|---|
| `cutscene/dev/**` | ✅ | ❌ | ❌ |
| `entity/boss/**` (außer FogBankMarker) + `client/entity/fogboss/**` + Deckhand-Renderer/-Entity | ✅ | ❌ | ❌ |
| `stormfx/**`, `client/entity/fog/**`, `FogBankMarker`, `worldgen/fog/**`, `EventSpawnRules`, `network/fx/FxPayloads`, `veilfx/EclipseFxState` | ❌ | ✅ | ❌ |
| `ritual/**`, `offering/**`, `client/AltarAberration`, `veilfx/QuasarSpawner`, `progression/realtime/**`, `client/hud/BossbarSkin`+`DayTimerLayer`, `economy/ShardEconomy` | ❌ | ❌ | ✅ |
| Eigene NEUE Dateien (Generator, Rows, Assets, Langdrop, Report) | je Team, Namensraum `wave5_<team>…`/`WAVE5<X>` | | |

---

## 7. Abnahme-Reihenfolge (Hauptagent, nach Merge aller drei Teams)

1. Langdrops zentral mergen (`python3 tools/langmerge/merge_langdrops.py WAVE5A/B/C.json`),
   `flock … compileJava/processResources`, `fxlib validate --lint` (falls Assets).
2. **Frische Client-JVM** (F-103-Regel) + `/photon_client clear_client_fx_cache` falls
   `.fx` regeneriert wurden.
3. Team A zuerst (die neuen Holds sind Werkzeuge für die B/C-Fotos), dann B (Sturm-Session),
   dann C (Altar/Boundary-Session). `tick rate 20` nach jedem Block restaurieren, Mobs
   aufräumen, Holds explizit `off` schalten (`/eclipsefx holds` prüfen, falls A7 gebaut).
