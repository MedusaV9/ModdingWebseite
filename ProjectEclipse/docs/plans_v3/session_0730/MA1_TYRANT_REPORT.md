# MA1 — Fog Tyrant (Welle M-A, Mob/Item-Zensus F-098)

**Auftrag:** MOB_ITEM_CENSUS §5 Welle M-A Zeile MA1 — (a) Trail-Locator-Bones an den
Lanzenspitzen, (b) Mantel-4-Segment-Kette mit Nachschwing, (c) death auf die
A5-Implosionskette timen, (d) Scythe-Detach beim Statue-Handoff fixen (F-081..087),
(e) storm_step_out/in mit `robe_tatter_*`-Flare.

**Datei-Besitz (exklusiv, §5-G1/G5):** `entity/boss/fog/*` (inkl. `TyrantStatue`-Java),
`client/entity/fogboss/*`, `geo/animations/textures fog_tyrant*`,
`scripts/geckolib_gen/mobs/fog_tyrant.py`, `docs/uv/fog_tyrant.md`.
**Nicht angefasst:** `fx/boss/tyrant_*` + `BossPhotonFxRows` (A5), FROZEN-Basen,
`validate_geo.py`/`paint_lib.py`, `sounds.json`/lang (kein Bedarf — keine neuen Events).

---

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 0.1 A5-Todeskette — Timing aus `tools/photon/tyrant_death_fx.py` (NUR gelesen)

`FxCues.CUE_TYRANT_DEATH_IMPLOSION` feuert in `FogTyrantEntity.tickDeath` bei
`DEATH_THUNDERCLAP_TICK = 60` (Body-Center +1.5, Range 96). Der Root
`boss/tyrant_death_collapse` fährt ab dann:

* L1 `slab_infall` r=10-Schale, radial −14→−52 (Kollaps BESCHLEUNIGT), burst t=0.
* L2 `shred_infall` r=6.5 flat −40, bursts t=2 (+2 Zyklen à 9t).
* L3 `floor_drag` Bodenscheiben radial −38→−12, burst t=0.
* L4 `collapse_seed` **burst t=30** → Birth-Kette (Kette wird über die GEBURTSZEIT des
  Parents sequenziert, Regel 2 im A5-Header): `collapse_core` (Fresnel-**Dome-Snap**,
  Overshoot-Settle, Alpha-Peak bei 10 % von 22t Life) → `shock_ring` (burst t=0/t=1)
  → `tyrant_soul_wisp` (~3× auf dem r=5.5-Ring).

**Konsequenz:** Fresnel-Snap ≈ FX-t 30–32 = **deathTime ≈ 90–92**. Der alte Java-Wert
`DEATH_DURATION_TICKS = 70` entfernte den Körper 20t VOR dem Snap — der Einfall
konvergierte auf leere Luft. Genau das adressiert Auftragspunkt (c).

### 0.2 Step-FX-Timing aus `tools/photon/tyrant_step_fx.py` + G-4-Fix (Bestand)

`boss/tyrant_step_out` läuft ~14t gegen den 10t-Vanish; **Fold-Snap bei FX-t=8**
(= Anim-t 0.4 s, `fold_snap`/`snap_flash`). Der frühere Fix existiert und greift —
aber NUR für den Storm-Step: `FogTyrantEntity.STEP_VANISH_HIDE_TICKS = 2`
(`tickStormStepVanish` setzt `setInvisible(true)` für die letzten 2t; Restore in
`executeStormStep` + unconditional in `clearTelegraphs`). Der **Statue-Handoff** lief
dagegen ungeschützt: `TyrantStatue.awaken()` rief `discardPieces` im SELBEN Tick VOR
den Cover-Partikeln + `summonAt` — das Discard-Paket konnte die Partikel-Pakete
schlagen → Statue blinkt in klarer Luft aus (das dokumentierte F-081..087-Flackern,
der „Scythe-Detach"-Read der Effigie). Auftragspunkt (d).

### 0.3 Geo/Anim-Bestand vor dem Eingriff

25 Bones / 35 Cubes, 10 Anims (115 kf death). `cloak_back` (18×24×1) + `cloak_mid`
(14×16×1) waren zwei überlappende PLATTEN (z 6–7 / 7–8), keine Kette. Keine
`trail_*`-Bones — A5s Entity-Lanes zielen auf den Root. `storm_step_out/in`
animierten die vier `robe_tatter_*` gar nicht.

---

## 1. (a) Trail-Locator-Bones `trail_lance_l` / `trail_lance_r`

Cube-lose Locator (Painter ignoriert sie, kein UV), Kinder der Lanzen, Pivot exakt
auf der geometrischen Spitze (Blades hängen point-down; Schaft-Cube y 5..25, Spitze =
Unterkante):

| Bone | Parent-Kette | Pivot (Model-px) | Rest-Offset zur Entity-Origin |
|---|---|---|---|
| `trail_lance_l` | root›robe›torso›shoulder_left›arm_left›lance_left | **[11.5, 5, 0]** | ≈ (+0.72, +0.31, 0) Blöcke |
| `trail_lance_r` | root›robe›torso›shoulder_right›arm_right›lance_right | **[−11.5, 5, 0]** | ≈ (−0.72, +0.31, 0) Blöcke |

Rest-Offsets sind VOR Anim/Shoulder-Tilt (±6°) — A5 sampelt die Live-Bone-Matrix.
Relevante Tip-Fenster: `lance_volley` Arme −95..−100° X (Spitzen zeigen nach vorn,
Release-Snap bei Anim-t 1.2→1.3 s), `attack` arm_right −120° X bei t 0.25 s
(Swing-Release 0.25→0.45 s).

## 2. (b) Mantel: 4-Segment-Kette mit Nachschwing (catmullrom)

Geo-Re-Cut — eine hängende Kette statt zwei Platten, jedes Pivot auf der Unterkante
des Parent-Segments, Grund-Drape akkumuliert 6+4+3+3 = 16° nach hinten (hängt damit
frei von Robe/Torso, unterste Hem-Kante ≈ z 13–14 px hinter der Robe):

| Segment | Parent | Pivot | Cube | UV (neu) |
|---|---|---|---|---|
| `cloak_back` | torso | [0,42,6] rot 6° | 18×12×1 (y30–42) | (64,28) |
| `cloak_mid` | cloak_back | [0,30,6.5] rot 4° | 16×9×1 (y21–30) | (64,41) |
| `cloak_low` (NEU) | cloak_mid | [0,21,6.5] rot 3° | 16×9×1 (y12–21) | (68,113) |
| `cloak_hem` (NEU) | cloak_low | [0,12,6.5] rot 3° | 14×8×1 (y4–12) | (96,59) |

UV-Plan kollisionsgeprüft (Box-Rects, Skript-Check): die 4 neuen Rects belegen exakt
die freigewordenen Alt-Cloak-Regionen + den freien Block x68–102/y113–123.
Painter: `storm_cloak_chain(seg)` — der dunkel→fahl-Gradient läuft über die GANZE
Kette (`t = (seg + t_lokal)/4`), Rag-Alpha-Saum NUR am Terminus `cloak_hem`
(Zwischensegment-Cuts würden an jedem Scharnier horizontale Schlitze öffnen).
Kette bewusst NICHT emissiv (Glowmask byte-identisch geblieben).

Nachschwing-Keyframes:

* **stride** (1.6 s-Loop, Root-Bob-Periode 0.8 s): pro Segment eine 0.8 s-Welle,
  **0.12 s Lag pro Segment**, Amplitude wächst 4→5→6→7°, Basis fällt 14→10→7→5°.
  9 catmullrom-Keys pro Segment auf 0.2 s-Raster, Key(0.0)==Key(1.6) → nahtloser
  Loop. Peaks wandern 0.2 s (back) → 0.32 → 0.44 → 0.56 s (hem) = laufende Welle.
* **idle**: Molang-Kette `6+sin(90t)·3` / `4+sin(90t−40°)·3.5` / `3+sin(90t−80°)·4` /
  `3+sin(90t−120°)·4.5` (Phasen-LAG hemwärts, billige Dauerbewegung, §6.1).
* **storm_step_out/in, death**: explizite Lag-Keys, siehe §3/§5.
* Übrige Action-Anims keyen weiter nur `cloak_back` — mid/low/hem erben die
  Parent-Bewegung und behalten ihr idle-Molang-Nachschwingen (base-Controller).

## 3. (c) death auf die A5-Implosionskette

Anim bleibt **3.5 s** (`hold_on_last_frame`); Java hält die Silhouette jetzt bis zum
Snap: **`DEATH_DURATION_TICKS` 70 → 90** (`FogTyrantEntity`), Removal + POOF landen
exakt HINTER dem Fresnel-Snap — derselbe „hinter dem hellsten Beat verschwinden"-
Trick wie der G-4-Fold-Snap-Cut. Neue Beats im Sheet: Thunderclap-Ruck (der Einfall
„packt" den Leichnam), Einfalt-Fold, kompakte Halte-Silhouette inkl. leichtem
Root-Squash (Scale 1 → 0.92/0.86/0.92).

**Timing-Tabelle (Anim-Keyframes vs FX-Ticks) — auch das A5-Snippet:**

| deathTime | Anim-t | Java (`FogTyrantEntity`) | Anim-Keyframes | A5-Kette (FX-t ab Cue) |
|---|---|---|---|---|
| 0 | 0.0 | `die()` → `triggerAction(death)` | Start; Krone steigt 0.6 s | — |
| 0–32 | 0–1.6 | Spark-Shed alle 4t | Krone fällt 0.6→1.5 s, `glow_crown_*` Scale-Decay bis 2.2 s | — |
| 32 | 1.6 | `CORE_LIT=false` (Gutter) | `glow_core` 1.4→0.6 im Fenster 1.0→1.6 s, Flacker-Bounce bis 3.0 s | — |
| 60 | 3.0 | Thunderclap, `CUE_TYRANT_DEATH_IMPLOSION` + `CUE_SIG_CROWN_VERDICT`, Site-Explode | Ruck: root y −5→−3.5 (2.9→3.05), torso 26→20, Cloak-Kette-Böe 3.05/3.15/3.25/3.35 (Lag-Welle), Tatter-Flare ±22–30° @3.1–3.15 | t=0: slab/shred/floor-Einfall startet |
| 60–70 | 3.0–3.5 | — | Einfalt-Fold: torso →62°, Arme wickeln ein (−38/±26/±12), Lanzen −30°, root →y−11 + Squash | Einfall beschleunigt (−14→−52 radial) |
| 70–90 | (hold) | Körper bleibt (NEU — alt: POOF bei 70) | letzte Frame-Silhouette gehalten | Einfall konvergiert AUF die Silhouette |
| 90 | — | `remove(KILLED)` + POOF (NEU) | — | **t=30: Seed geboren → Fresnel-Dome-SNAP** |
| 91+ | — | — | — | t≈31 shock_ring, t≈33 soul_wisps |

Payout-Zeremonie unverändert (Intervall rechnet gegen `DEATH_THUNDERCLAP_TICK`,
Drain am Clap). Die W4-Slow-Mo-Notiz in `registerActionTriggers` wurde aktualisiert.

## 4. (d) Scythe-Detach beim Statue-Handoff (F-081..087)

**Prüfergebnis Bestandsfix:** `STEP_VANISH_HIDE_TICKS=2` greift korrekt — aber nur im
Storm-Step-Pfad (§0.2). Der Statue-Handoff hatte KEINE Deckung.

**Verfeinerung (`TyrantStatue`):** `awaken()` sendet jetzt zuerst die Cover-Schicht
(CLOUD/SPARK-Burst, Thunder, Shake) und `FogTyrantEntity.summonAt` (dessen eigene
Fog-Banks), und discardet die Displays erst **`HANDOFF_VANISH_COVER_TICKS = 2`** Ticks
später (`WandTickService.schedule`, dasselbe level-scoped Timer-Muster wie der
gradeThump-Release). Tick-Diagramm:

```
Tick T   (awaken):  state=FIGHT · CLOUD 40 + SPARK 30 auf die Statue · Thunder+Shake
                    · summonAt: Tyrant steht IN der Statue + 50er-fogBurst + 4 Ring-Banks
                    · Discard bei T+2 eingeplant
Tick T+1:           Cover-Partikel client-seitig live; Statue + Tyrant beide im Fog
Tick T+2:           discardPieces — Displays + Hitbox vanishen HINTER dem Fog
```

Sicherheiten: `statue.state` ist ab T `FIGHT` → kein `ensureArmed`-Self-Heal kann im
Fenster Pieces nachspawnen; `discardPieces` ist idempotent (Reset/Retire, das die 2t
schneidet, leert die Liste einfach zuerst); Hitbox-Treffer im Fenster laufen auf
`nearestStatue(state==ARMED) == null` → no-op; Server-Stop im Fenster fällt auf die
F-084-Join-Sweep-Doktrin zurück (persistierte Pieces werden beim Boot discardet).

## 5. (e) storm_step_out/in mit `robe_tatter_*`-Flare

* **step_out (0.5 s, hold):** alle vier Tatters flaren nach außen und peaken IN den
  Fold-Snap — front/back X 0→∓10→∓38 (0.35 s)→∓52 (0.5), left/right Z 0→±12→±40→±56
  (Vorzeichen wie die idle-Konvention). Sichtbar ist die Rampe bis ±38–40° — bei
  Anim-t 0.4 (= FX-t 8, Fold-Snap) schneidet `STEP_VANISH_HIDE_TICKS` den Körper.
  Das letzte sichtbare Bild ist der Fetzen-Blitz. Dazu Cloak-Ketten-Lag: mid/low/hem
  ziehen erst nach (+9/+10/+13°) und schlagen dann über den Parent hinaus
  (−27/−31/−36 vs. cloak_back −24).
* **step_in (0.6 s):** startet exakt im Hold-Endzustand (∓52/±56, Kette −27/−31/−36),
  peitscht durch (front −52→+16→−6→0; Kette +22/+24/+26 bei 0.35–0.45 s) und settlet
  auf idle-Neutral. Ketten-Keys enden auf 4/3/3° = Geo-Rest-Konvention.

---

## 6. Validierung

* `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` → **PASS, 0 Errors /
  0 Warnings** — 29 Bones / 37 Cubes, Anim-Bone-Cross-Check sauber; death jetzt
  27 Bones / **154 kf**, stride 64 kf, step_out 57 kf, step_in 59 kf.
* Painter: `python3 scripts/geckolib_gen/mobs/fog_tyrant.py` — deterministisch
  (Doppel-Lauf byte-identisch, md5 verifiziert); Albedo 10 396 px / Glowmask 900 px,
  beide 128², 8×-Eyeball ok (Ketten-Gradient läuft dunkel→fahl über 4 Rects,
  Rag-Saum nur am Hem, Glowmask ohne Cloak-Pixel).
* UV-Kollisions-Skript: neue Cloak-Rects überlappungsfrei (die zwei gemeldeten
  Alt-Überlappungen sind Box-UV-Bounding-Box-Artefakte von `robe_tatter_right`
  vs `wisp_left` — tatsächliche Face-Rects disjunkt, Bestand, nicht angefasst).
* `./gradlew compileJava` → **Exit 0** (einzige Note: vorbestehende Deprecation in
  `StormSiege.java` — fremdes Team, nicht von mir). Keine Isolation nötig.

## 7. Test-Rezept in-game (llvmpipe: 20–40 s Wartezeiten, Screenshots)

1. `./gradlew runClient` → Welt (allow-flight-Server: RCON-Route via `runServer` +
   `python3 tools/rcon/rcon.py` nur für Server-Logik — Optik braucht den Client, F-14).
2. **Kette/Tatters:** `/summon eclipse:fog_tyrant ~4 ~ ~` → idle-Seitenansicht
   (4-Segment-Drape, laufende Molang-Welle); locken/weglaufen → stride-Nachschwing.
3. **Step (d/e):** Kampf halten bis zum Storm-Step (P1: alle 220t) → das letzte
   sichtbare Bild vor dem Vanish muss der Tatter-Flare im Fold-Snap sein, kein
   Lanzen-Rand in klarer Luft; Reappear = Peitsch-Settle.
4. **Statue-Handoff (d):** frisches Fog-Lair (`FogBankMarker.markLair`-Pfad bzw.
   Sturm-Flow), Statue anschlagen, 3 s Awaken abwarten → Frame-für-Frame prüfen:
   Statue-Displays verschwinden erst NACH sichtbarem Cloud-Burst
   (Log: `displays vanish in 2t behind the cover fog`).
5. **Death (c):** `/kill @e[type=eclipse:fog_tyrant]` → Krone fällt (0–1.5 s), Core
   guttert (1.6 s), Thunderclap-Ruck (3.0 s), Einfalt-Fold, Silhouette HÄLT
   (3.5–4.5 s) während der Photon-Einfall konvergiert, Körper verschwindet im
   Fresnel-Snap. Photon-Reload-Gotcha: nach FX-Regeneration
   `/photon_client clear_client_fx_cache` (Client-Chat, AGENTS.md).
6. **Locator (a):** `lance_volley` beobachten — Spitzenbones bewegen sich mit; die
   eigentliche Lane-Anbindung testet A5.

## 8. Koordinations-Snippets

**→ A5 (BossPhotonFxRows / fx/boss/tyrant_*, ich fasse nichts davon an):**

* Trail-Lanes: Bones `trail_lance_l` / `trail_lance_r` (cube-los, Pivots = Klingen-
  Spitzen [±11.5, 5, 0] Model-px ≈ ±0.72/+0.31/0 Blöcke Rest). Heißeste Fenster:
  `lance_volley` Raise 0.5–1.2 s, Release-Snap 1.2→1.3 s; `attack` Swing 0.25→0.45 s.
* Death: Java hält den Körper jetzt bis deathTime 90 (= euer Fresnel-Snap bei
  FX-t 30 nach dem Cue). Volle Tabelle in §3 — falls ihr den Seed-Burst (t=30)
  verschiebt, bitte Bescheid: `DEATH_DURATION_TICKS` muss = 60 + Seed-Zeit bleiben.
* Statue-Handoff: `CUE_TYRANT_STATUE_IDLE` unverändert; die Displays leben nach dem
  Awaken-Beat jetzt 2t länger (unter eurem Step-Out-/Arrival-Fog-Fenster).

**→ Integrator:** kein langdrop/sounddrop, keine Shared-JSONs berührt, keine
Registrar-Snippets nötig (alles im MA1-Datei-Besitz). `compileJava` grün auf dem
Gesamtbaum (Stand dieses Laufs, inkl. der parallel liegenden Fremd-Diffs).
