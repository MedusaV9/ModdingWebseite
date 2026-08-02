# WAVE9-C — Mobs/Items/Progression-Polish (Team C, Welle 9)

**Datum:** 2026-08-02 · **Auftrag:** die 5 Bausteine aus
`docs/plans_v3/eval2/EVAL2-C_mobs_items_progression.md` (H-1…H-5, P-1, P-3, P-5).
**Compile:** `./gradlew compileJava` → **BUILD SUCCESSFUL** (verifiziert bis in die
Bytecode-Artefakte, s. §7). **Keine git-Operationen** — alles im Working Tree.

---

## 1. Baustein 1 — Blade-`feast` verdrahtet (EVAL2-C H-2, POLISH3 §6)

**Fix:** `lives/LifecycleEvents.java` — exakt das POLISH3-§6-Snippet, eine Zeile
direkt hinter dem Blade-Lifesteal-Log (der Stelle, die das Audit als „Z. 131" zitiert):

```java
dev.projecteclipse.eclipse.economy.UmbralBladeItem.triggerFeast(killer);
```

Platzierung IM Blade-Branch (`getMainHandItem().is(UMBRAL_BLADE) && < MAX_HEARTS`) —
der Feast spielt damit exakt dann, wenn die Klinge tatsächlich ein Herz trinkt
(= der Lifesteal-Moment, für den die Anim gebaut wurde). Helper ist ohnehin
nullsicher (No-Op ohne Blade in der Haupthand).

**Beleg:**

- Vorher: `rg triggerFeast src/main/java` → nur Definition (`UmbralBladeItem.java:72`)
  + Javadoc-Verweis (`:34`). **Null Aufrufer.**
- Nachher: dritter Treffer `lives/LifecycleEvents.java` (Aufruf);
  `javap -c LifecycleEvents | rg -c triggerFeast` → `1` im Bytecode.

**Restrisiko:** Steht der Killer am Herz-Cap, trinkt die Klinge nichts und der Feast
spielt nicht — bewusst so (Anim == tatsächlicher Lifesteal, keine Fehlversprechen).

## 2. Baustein 2 — Ferryman-Blend-Nachzug (H-1)

**Fix:** `entity/boss/FerrymanEntity.java` — `actionTransitionTicks`-Override im
POLISH2-Muster (Deckhand-Referenz 1:1: switch über Anim-Namen, Begründungs-Javadoc):

| Action | Audit-Messung (worst) | Blend | Begründung |
|---|---|---|---|
| `kneel` | 64.0° `arm_left.rotx` aus `idle_row` | **3 t** | Kneel-Corona ist 100t-Sustain — 3t Versatz unsichtbar |
| `harvest` | 64.0° | **2 t** | A3-`ferry_harvest_ring` kontrahiert 2.0 s — 2t irrelevant |
| `oar_sweep` | 64.0° | **0 (bewusst hart)** | Strike-Beat frame-exakt auf dem 26t-Kontakt-Tick (`SWEEP_TELEGRAPH_TICKS`-Fenster); Blend verschöbe die Pose gegen den Damage-Beat (POLISH2-§1.1-Verbotsklasse) |
| `death` | — | 0 | 100t-`tickDeath`-Fenster == Clip-Länge |

**Restrisiko:** `kneel` startet im selben Tick wie `CUE_FERRY_KNEEL_CORONA` /
`CUE_FERRY_LANTERN_SWARM`; der Körper landet jetzt bei ~14t statt 11t — im
80t-Swarm/100t-Corona-Fenster nicht wahrnehmbar (Audit-Einschätzung).

## 3. Baustein 3 — Orin-Blend-Nachzug (H-3)

**Fix:** `entity/wizard/WizardOrinEntity.java` — Override:

| Action | Audit-Messung | Blend | Begründung |
|---|---|---|---|
| `greet` | 66.0° `arm_left.rotx` aus `idle` | **3 t** | feuert bei JEDER Spieler-Annäherung, direkt vor der Kamera |
| `trade` | 66.0° | **3 t** | bei jedem Handel, aus dem Idle-Stand |
| `hurt` | — (Flinch-Klasse) | **2 t** | Damage vor Trigger, Follow-Through (Hound/Stalker-Präzedenz) |
| `sun_flare` | — | 0 (hart) | Nova-Beat bei 0.8 s frame-exakt gegen den 15t/16t-Telegraph-Timer |
| `veil_step` | — | 0 (hart) | Riss-Rematerialize-Snap = Glitch-Klasse, der Snap IST der Punkt |
| `star_call` | — | 0 (hart) | `glow_staff_crystal` = Molang-Dauer-Spin (Spin-Hazard, Cultist-runes-Präzedenz) |
| `death` | — | 0 | 40t-Sit-down-Fade == Clip-Länge |

(2–3t-Empfehlungsspanne des Audits aufgelöst als: sichtbare 66°-Pops → 3 t,
Hurt-Flinch → 2 t — identisch zur H-4/POLISH2-Aufteilung.)

## 4. Baustein 4 — Stalker + Beifang (H-4, P-1)

Alle vier im selben Muster (Override + Javadoc), NUR die im Audit als Pop
gemessenen Actions — `bloom` (0.0° gemessen), `cast_blind` (Molang-Spin),
Gazer `tether_snap` (Teleport-only-Basis) und PortalKey `unlock_turn`
(A3-Timing-Abstimmung nötig, nicht Team-C-Solo) bleiben unangetastet:

| Entity | Action | Audit-Messung (worst) | Blend |
|---|---|---|---|
| `entity/UmbralStalkerEntity` | `attack` | 52.0° aus `sprint`, **97.5°** aus `stalk_low` | **3 t** (Hound-Präzedenz POLISH2 §3) |
| `entity/UmbralStalkerEntity` | `hurt` | 50.0° aus `sprint` | **2 t** |
| `entity/pale/PaleSentinelEntity` | `attack` | 58.0° aus `walk` | **3 t** |
| `entity/fog/FogRevenantEntity` | `attack` | 30.0° aus `walk` | **3 t** |
| `ferryman/finale/SoulWispEntity` | `panic_scatter` / `attack` | 34° / 20° aus `walk` | **2 t / 2 t** (Finale-Schwarm, viele Instanzen) |

Alle `death`-Fenster bleiben hart (28t/35t/40t/24t == Clip-Länge, Audit-Gut-Befund 4).

## 5. Baustein 5 — Integrator-Paket (H-5, P-3, P-5)

### 5a. MA3/MA4-Removal-Patches angewandt + LOW-Krücke zurückgebaut

**Toter-Code-Beweis (Grep, VOR dem Löschen):** `HeraldModel`, `HeraldRenderer`,
`FerrymanModel`, `FerrymanRenderer`, `HERALD_LAYER`, `FERRYMAN_LAYER` wurden
ausschließlich referenziert von (a) `EclipseEntityRenderers` (den zu löschenden
Zeilen), (b) einander, (c) Javadoc/Kommentaren des deprecateten Hook-Blocks in
`FerrymanEntity`. Kein Fight-/FX-/sonstiger Code hängt daran. Nach dem Patch:
`rg "HeraldModel|FerrymanModel|HeraldRenderer\b|FerrymanRenderer\b|HERALD_LAYER|FERRYMAN_LAYER" src/main/java`
→ einzig ein historischer Kommentar `FerrymanGeoRenderer.java:49`
(„Old FerrymanRenderer footprint" — Herkunftsnotiz, kein Symbol-Bezug).

Angewandt (MA3 §7 + MA4 §7.1 wortgetreu):

- `client/entity/EclipseEntityRenderers.java`: `HERALD_LAYER`/`FERRYMAN_LAYER`-
  Konstanten, beide Layer-Bakes und beide Legacy-Renderer-Registrierungen raus;
  Umzugs-Kommentare im MC1/2/3-Stil rein (kein toter Layer-Bake pro Client-Boot mehr).
- **Gelöscht:** `client/entity/HeraldModel.java`, `client/entity/HeraldRenderer.java`,
  `client/entity/FerrymanModel.java`, `client/entity/FerrymanRenderer.java`,
  `scripts/skin_gen/ferryman_v2.py` (alle im MA-Patch als zu löschen dokumentiert;
  `herald_v2.py` hatte MA3 schon selbst entfernt).
- `entity/boss/FerrymanEntity.java`: der komplette `@Deprecated`-Client-Hook-Block
  (Felder `animAge*`/`animSpeed`/`raiseLerp*`/`kneelLerp*`/`plantLerp*`/`swingTicks`/
  `wasTelegraphing`/`swayBoost*` + `SWEEP_SWING_TICKS`; Methoden `tickClientAnim`/
  `animAge`/`raiseAmount`/`kneelAmount`/`plantAmount`/`sweepSwing`/`swayBoost`/
  `deathProgress`; `tickClientAnim()`-Aufruf in `tick()`) — **`isLanternFlameLit()`
  BLEIBT** (der GeckoLib-Renderer konsumiert es, MA4-Vorgabe). Zwei dadurch stale
  gewordene Kommentare (tickDeath-Javadoc, Kill-Slow-Mo-Kommentar) minimal auf den
  GeckoLib-Ist-Stand umformuliert.
- **Krücke zurückgebaut:** `FerrymanRenderers` von `EventPriority.LOW` und
  `herald/HeraldRenderers` von `EventPriority.LOWEST` auf Default-Priorität
  (Import raus, Javadoc erklärt jetzt den End-Zustand statt der Transition).
  Die GeckoLib-Registrare sind damit die EINZIGE Registrierung — die
  Regressions-Falle (Schutz nur per Prioritäts-Annotation) ist zu.

**Restrisiko:** `scripts/geckolib_gen/mobs/ferryman.py:4` erwähnt den gelöschten
`ferryman_v2.py`-Pfad als Herkunftsnotiz (Doku-Zeile, gleiche Lage wie nach MA3s
`herald_v2.py`-Löschung — bewusst nicht angefasst, Painter-Datei gehört nicht Team C).

### 5b. Die 3 fehlenden `dev.eclipse.doc.fogsite.*`-Keys (P-3)

**Flow wie etabliert:** neuer Langdrop `docs/plans_v3/langdrop/wave9c_fogsite.json`
(Schema `{"en_us": …, "de_de": …}`), gemerged via
`python3 tools/langmerge/merge_langdrops.py wave9c_fogsite.json` (Tool nur
AUSGEFÜHRT, nicht verändert). Texte aus den Command-Javadocs von
`DevFogSiteCommands` abgeleitet (list/rematerialize/retire).

**Beleg (Merge-Ausgabe):**

```
merged: en_us +3, de_de +3; totals en=2875 de=2875
parity OK
```

Diff auf `assets/eclipse/lang/`: exakt +3/+3 Zeilen, en_us und de_de key-identisch.

**Restrisiko:** Der Kommentar `DevFogSiteCommands.java:52-53` („descKey lang entries
are deliberately NOT shipped … no-lang-changes law") ist damit überholt — die Datei
liegt in `devtools/**` (nicht Team-C-Scope), Notiz an den Owner.

### 5c. README-Modell-Drift (P-5)

Genau die drei Audit-Stellen auf den GeckoLib-Ist-Stand gebracht, Verhaltens-/
Zahlen-Claims (vom Audit stichprobengeprüft korrekt) unangetastet:

- Sunmote-Tabellenzeile: „Fullbright 2-cube wisp" → GeckoLib-Wisp mit Strahlenkranz +
  Glowmask (MC3, 10 Bones, `SunmoteGeoRenderer`).
- Herald-Abschnitt: „26-cube … `HeraldModel`/`HeraldRenderer`" → MA3-Geo, 31 Bones,
  128² + Glowmask, `TelegraphGlowLayer` in `HeraldGeoRenderer`.
- Ferryman-Abschnitt: „18-cube … `FerrymanModel`" → MA4-Geo, 32 Bones, 128² +
  Glowmask, `FerrymanGeoRenderer` (Flamme/Robe an `isLanternFlameLit()`, Gaze-Shell).

## 6. Geänderte/gelöschte Dateien

| Datei | Änderung |
|---|---|
| `lives/LifecycleEvents.java` | +3 Zeilen: `triggerFeast(killer)` im Blade-Branch (POLISH3 §6) |
| `entity/boss/FerrymanEntity.java` | `actionTransitionTicks` (kneel 3/harvest 2); MA4-§7.1-Hook-Block-Removal; 2 Kommentare entstalet |
| `entity/wizard/WizardOrinEntity.java` | `actionTransitionTicks` (greet/trade 3, hurt 2) |
| `entity/UmbralStalkerEntity.java` | `actionTransitionTicks` (attack 3, hurt 2) |
| `entity/pale/PaleSentinelEntity.java` | `actionTransitionTicks` (attack 3) |
| `entity/fog/FogRevenantEntity.java` | `actionTransitionTicks` (attack 3) |
| `ferryman/finale/SoulWispEntity.java` | `actionTransitionTicks` (panic_scatter/attack 2) |
| `client/entity/EclipseEntityRenderers.java` | MA3/MA4-Lösch-Snippets (Layer-Konstanten, Bakes, Renderer-Zeilen) |
| `client/entity/FerrymanRenderers.java` | `EventPriority.LOW` → Default, Javadoc |
| `client/entity/herald/HeraldRenderers.java` | `EventPriority.LOWEST` → Default, Javadoc |
| `client/entity/{HeraldModel,HeraldRenderer,FerrymanModel,FerrymanRenderer}.java` | **GELÖSCHT** |
| `scripts/skin_gen/ferryman_v2.py` | **GELÖSCHT** (MA4 §7.1) |
| `docs/plans_v3/langdrop/wave9c_fogsite.json` | **NEU** (3+3 Keys) |
| `assets/eclipse/lang/{en_us,de_de}.json` | +3 Keys je Locale (via merge_langdrops.py) |
| `README.md` | 3 Modell-Drift-Stellen (Herald/Ferryman/Sunmote) |

**Nicht angefasst:** stormfx/quasar/pinwheel/tools(-Code)/photon, alle anderen
Animationen/Controller, `EclipseGeoMob`/`EclipseGeoMonster`/`EclipseActionController`
(Mechanismus unverändert, nur Opt-in-Overrides), PortalKey (`unlock_turn` braucht
A3-Abstimmung), Gazer, Cultist, Glitch-Familie, alle Item-Controller (P-6 ist
explizit nicht Teil des Auftrags).

## 7. Compile-Status

- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (mehrfach; Daemon wird von Parallel-Teams mitbenutzt,
  Läufe queuen über das flock).
- Bytecode-Verifikation gegen `build/classes/java/main` (weil parallele Läufe
  UP-TO-DATE melden können): `actionTransitionTicks` in allen 6 Entities via
  `javap -p` bestätigt; `triggerFeast`-Call in `LifecycleEvents` via `javap -c`
  bestätigt; `HeraldModel/HeraldRenderer/FerrymanModel/FerrymanRenderer`-Classfiles
  aus dem Output-Verzeichnis verschwunden; Negativ-Probe (Syntaxfehler-Datei) ließ
  den Build sofort fehlschlagen → der Daemon kompiliert wirklich den Ist-Stand.

## 8. Live-Abnahme-Plan

Alle Blends sind reine EINTRITTS-Glättungen: Erwartung ist überall „kein
Ein-Frame-Ruck mehr beim Anim-Start, Beat-Timing unverändert".

1. **Blade-Feast:** 2 Spieler; Killer `/give @s eclipse:umbral_blade`, Blade in die
   Haupthand, Killer unter Herz-Cap bringen; Opfer im PvP töten (STEAL-Verdict, kein
   Theft-Cooldown). **Erwartung:** Log `…'s umbral blade drank a heart from …` UND
   auf der Klinge der 1.2s-Feast (Pommel-Auge dilatiert 2.1×, Kanten flammen).
   Gegenprobe: Kill ohne Blade / am Cap → kein Feast.
2. **Ferryman:** Tag-14-Ritual oder `/eclipse boss ferryman summon` (Limbo).
   `kneel`: `/eclipse boss ferryman phase 2` → P2-Start; Ruderarm gleitet in 3t in
   die Kneel-Pose (vorher 64°-Snap), Corona/Swarm-Beat unverändert am Trigger-Tick.
   `harvest`: P3 (`phase 3`) Seelenernte abwarten — Einzug startet weich, YANK@40t/
   Strike@54t unverändert. **`oar_sweep`-Gegenprobe:** Sweep MUSS weiterhin hart
   anreißen und der Treffer exakt auf dem Blatt-Kontakt liegen (26t).
3. **Orin:** zu seiner Hütte laufen (`greet` bei Annäherung ≤6 Blöcke), Rechtsklick-
   Dialog (`trade`), einmal schlagen (`hurt`). Je weicher 2–3t-Eintritt statt
   66°-Armschnappen. Gegenprobe: `sun_flare`-Nova (melee-nah bleiben) und
   `veil_step`-Blink müssen weiter hart snappen; Stabkristall dreht ununterbrochen.
4. **Stalker:** nachts Tag 5+ oder `/summon eclipse:umbral_stalker`; jagen lassen
   (Sprint-Gang) → Biss ohne Bein-Snap; schlagen → weicher Flinch. Death: 28t-Kollaps
   endet weiterhin exakt im Poof.
5. **Beifang:** `/summon eclipse:pale_sentinel` (Anmarsch → attack),
   `/summon eclipse:fog_revenant` (Klauen-Rake; `cast_blind`-Wisps drehen hart
   weiter), SoulWisps im Ferryman-Finale (Schwarm scattert ohne Massen-Pop).
6. **Renderer-Removal:** Client-Boot; `/summon eclipse:herald` und Ferryman-Summon —
   beide rendern als GeckoLib-Geos (Glowmask nachts prüfen); im Log KEIN Bake von
   `eclipse:herald#main`/`eclipse:ferryman#main` mehr.
7. **Lang:** Dev-Handbook (STAGE-Kategorie) bzw. `/dev help` — die drei
   `/dev fogsite`-Zeilen zeigen in en_us und de_de Beschreibungstexte statt roher Keys.
