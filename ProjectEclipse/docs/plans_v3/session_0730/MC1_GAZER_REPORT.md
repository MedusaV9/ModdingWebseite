# MC1 — Gazer-GeckoLib-Konversion (F-098 Welle M-C)

**Status:** FERTIG — validate_geo 2/2 PASS (0 Errors/0 Warnings), `./gradlew compileJava`
UND `./gradlew build` grün, Painter deterministisch (Rerun byte-identisch, md5-geprüft).
Ergebnisse §6, Integrator-Snippets §7, B2-Koordination §8, Test-Rezept §9.
**Datei-Besitz (Zensus §5, Zeile MC1):** `entity/GazerEntity`,
`client/entity/Gazer{Model,Renderer}` (Löschung via Snippet), NEU: Assets `gazer*`
(geo/animations/textures), `scripts/geckolib_gen/mobs/gazer.py`, eigene
Renderer-Registrar-Klasse (`client/entity/gazer/`), `docs/uv/gazer.md`.

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

- **Ist-Zustand:** `GazerEntity` (PathfinderMob, KEINE Move-Goals — `VanishWhenSeenGoal`
  40t-Stare-Down, `RelocateGoal` Teleport 20–40 Blöcke in die Peripherie,
  `LookAtPlayerGoal` 32 Blöcke), unkillbar (`hurt` → vanish, außer
  `BYPASSES_INVULNERABILITY`), Tag-Fade. `GazerModel` (191→ zuletzt ~192 Z. Code-Modell:
  cloak 10×18×6 schwebend, mantle 12×3×8, hood 8×8×8 mit netHeadYaw-Tracking, face 6×6×1
  emissiv via `RenderType.eyes`-Layer, MOB-AMBIENT-Face-Rig: 2 Iris-Pips 1×2×1 mit
  Code-Dilatation + 2 Lids 7×3×1 mit Code-Blink). KEIN Keyframe-Sheet, KEIN Glowmask (F-7).
  Hitbox `EclipseEntities.GAZER` = 0.8×2.1, eyeHeight 1.6, MISC, MOVEMENT_SPEED **0.0**
  (Relocation ist Teleport-only) — bleibt unverändert, das neue Geo ist darauf gebaut.
- **FX-Anbindung (NUR gelesen, Besitz B2):** `gazer_gaze_beam` ist ein
  `PhotonMobFx`-LOOP (attach ALWAYS, 20-Block-Gate, Cap 2, `AutoRotate.LOOK`); **B2-Fix
  verifiziert in `tools/photon/mobs_fx.py`**: der Thread läuft jetzt lokal **+X** (die
  echte Blickachse, JOML-`rotateXYZ`-Herleitung im Datei-Kommentar), Physik-Anker
  `TETHER_REACH=3.2` Blöcke den Blick hinunter, Hypnose-Ringe in der YZ-Ebene.
  `gazer_tether_snap` = One-Shot **22 t**, Recoil läuft EINWÄRTS, Peak der
  Alpha-Hüllkurve bei 0.12 der 10–16t-Partikel-Lebenszeit (≈0.06–0.1 s nach Spawn).
  Der Riss wird client-lokal vom `MobPhotonFxRows.GazeTetherWatcher` abgeleitet:
  **LOCK 25° / RELEASE 45° (Hysterese), LOCK_TICKS 8, Range 20/22 Blöcke, Cap 2** —
  diese Konstanten sind die Timing-Wahrheit für `gaze_lock`/`tether_snap`.
- **Vorbild komplett gelesen:** MA3-Herald-Report (Flaggschiff-Muster: Geo/Anim +
  eigener Registrar mit `EventPriority.LOWEST`, Deprecation statt Löschung der
  Shared-referenzierten Altklassen), `AmbientRenderers` (`isBound()`-Guard),
  `DriftLanternEntity` (F-9-Delta-Muster, die()/tickDeath-Konvention),
  `herald.py`/`paint_lib.py` (same-salt-Glow-Zwillinge).
- **FROZEN:** `EclipseGeoMob/Monster/Animations/Renderer`, `validate_geo.py`,
  `paint_lib.py`; Controller-Contract `base`+`action` final;
  `EclipseEntityRenderers.java` SHARED (G2).
- **Lang:** `entity.eclipse.gazer` existiert in BEIDEN Sprachen (en „Gazer" / de
  „Starrer", rg-verifiziert Zeile 1903) → **kein langdrop nötig** (`MC1-GAZER.json`
  entfällt). Keine neuen Sounds → kein sounddrop.

## 1. Bone-Hierarchie (19 Bones / 15 Cubes, Canvas 64² — Standard, keine Ausnahme nötig)

```
root
└─ body (0,6,0)                        Schwebe-Bob (Position)
   ├─ cloak (0,24,0)                   10×18×6, y6..24; Pivot am Kragen (Hem-Rock)
   │  ├─ tatter_left_1 (-3,6,1)        Hem-Fetzen 3×3×1, 2-Segment-KETTE (Nachschwingen)
   │  │  └─ tatter_left_2 (-3,3,1)     unteres Segment, hängt bis y0 (streift den Boden)
   │  ├─ tatter_right_1 (3,6,1) └─ tatter_right_2 (3,3,1)
   │  └─ tatter_back_1 (0,6,2)  └─ tatter_back_2 (0,3,2)
   ├─ mantle (0,23,0)                  Schulter-Mantel 12×3×8
   └─ head (0,18,0)                    NUR Tracking (cube-los, KEINE Anim-Keys — Falle!)
      └─ hood (0,18,0)                 8×8×8; trägt ALLE Kopf-Anim-Keys
         ├─ brow (0,25,-4)             Glare-Sims 8×1×1, 0.75px proud (senkt sich im Lock)
         ├─ glow_face (0,22,-3.75)     Maske 6×6×1, Front z-4.25 — EMISSIV (Nordface)
         ├─ iris_carrier (0,22,-4)     cube-los: IRIS-DRIFT-Träger (Position)
         │  ├─ glow_iris_left (1.5,22,-4)    Pip 1×2×1, z-4.5 proud — Scale = Dilatation
         │  └─ glow_iris_right (-1.5,22,-4)
         ├─ lid_top (0,25.2,-4.25)     Lid 7×3×1, Pivot an der OBERkante; y-Scale 0.1 Ruhe
         └─ lid_bottom (0,18.8,-4.25)  Pivot an der UNTERkante; z-4.75 (verdeckt den Glow)
```

Silhouette = altes Modell (alle Maße aus den `PartPose`/`addBox`-Definitionen
übernommen, Y-up-konvertiert), verfeinert um: 2-Segment-Tatter-KETTEN (3 statt 2
Fetzen), den `brow`-Glare-Sims und das getrennte Iris-Rig. **Kopf-Tracking-Falle
beachtet:** `DefaultedEntityGeoModel(turnsHead=true)` überschreibt head-rotX/rotY
ABSOLUT jede Frame — `head` ist deshalb cube-los und taucht in KEINER Animation auf;
`hood` (Kind) trägt Lean/Whip/Tilt. Lids sind volle 3px-Cubes; die Ruhe-Sliver-Optik
(y-Scale 0.1) liegt in den Anims — **jede Animation keyt die Lid-Scale**, sonst stünden
die Shutter offen.

## 2. Animation-Sheet (`animation.gazer.*`, format 1.8.0 — 6 Anims)

| Anim | Länge | Loop | Inhalt / Timing-Anker |
|---|---|---|---|
| idle | 6.0 s | true | **Iris-DRIFT** (Identität): `iris_carrier`-Position = Summe zweier Sinus pro Achse (x: 120°/s+300°/s, y: 180°/s+420°/s — inkommensurabel wirkend, alle ·6s ≡ 0 mod 360 → nahtlos), Pips pulsieren ±0.06 (Whisper-Rhythmus); Blink-Keyframes bei 3.0–3.3 s (Lids 0.1→1→0.1; Phase de-synct über den per-Entity-Anim-Start); Body-Bob 60°/s ±0.8px (≈ alter 0.06 rad/t-Bob), Mantle-Konter, Cloak-Rock, Tatter-Ketten 120°/s mit +50°-Segment-Lag, Hood-Atmung (Scale 1±0.008) |
| walk | 3.0 s | true | Drift-Gleiten (spielt nur bei ECHTEM Gleiten, §4): Body-Vorlage 4°, Tatter trailen +10..18° mit Segment-Lag, Frequenzen 120/240°/s (·3s ≡ 0 ✓), Lids statisch 0.1 |
| gaze_lock | 0.5 s | **hold_on_last_frame** | **Pupille DILATIERT**: 0→0.08 s Konstriktions-Flinch 0.8, dann catmullrom-Overshoot auf 2.0 (0.3 s) → Halte-Pose 1.8; Lids reißen auf 0.02 auf (**der beobachtete Gazer blinzelt NIE** — Hold überschreibt den idle-Blink); `iris_carrier` friert ein + drückt z −0.3 nach vorn (lehnt in den Beam); brow senkt sich −0.8 (Glare); hood +3° Lean. Trigger = Server-Stare-Mirror bei LOCK_TICKS=8 — exakt der Tick, an dem der Client-Watcher den Tether ARMT (§8). Hold ist gewollt: der Stare ist ZUSTAND; JEDER Lock-Bruch feuert tether_snap (löst den Hold auf) |
| tether_snap | 1.1 s | false | = **22 t = exakte FX-Länge**. 0.0-Keys = die gehaltene Lock-Pose (nahtloser Übergang); 0.1 s: Iris SLAMMT auf 0.45 („das Licht geht aus" — dunkler Closing-Pop des FX) + Hood-Whip −6°/+4°; Iris-Slam + erster Zuck (0.15 s) sitzen auf dem FX-Recoil-Peak (~0.06–0.1 s); danach ZUCKEN: 3 abklingende Carrier-Shudder (0.15/0.3/0.5/0.75), Hood-Nachpendeln (catmullrom), Doppel-Settle-Blink (0.15/0.55), Body-Dip −1.2px, Tatter-Flare mit Phasenversatz → 1.1 s ALLES exakt Ruhelage |
| hurt | 0.35 s | false | = **7 t = Vanish-Delay**: Hood-Recoil −9°/+5°, Body-Zurückweichen, Iris-Konstriktion 0.55, Lid-Clench 0.75 → Ruhelage exakt wenn der Wisp-Puff feuert |
| death | 1.5 s | hold_on_last_frame | = 30t-`tickDeath`-Fenster (nur Bypass-Kills, /kill): letztes Aufbäumen (+0.6px, Iris-Flare 1.6) → Absacken −4px, Cloak knittert (Scale y 0.85), Hood-Bow +18°, Blick fällt (Carrier −0.8), Iris guttert auf 0.1, **Lids schließen für immer** (1.0 ab ~1.0 s, catmullrom) |

Anim-Ids: `animation.gazer.<name>` (`geoId()` = `"gazer"`). Mindest-Set: idle/walk/
Special(gaze_lock+tether_snap)/death erfüllt; `attack` entfällt bewusst — der Gazer
greift NIE an (Orin-Präzedenz: Nicht-Kämpfer ohne attack-Anim). `head` kommt in keiner
Anim vor (Tracking-Falle, §1).

## 3. Textur-Konzept (64², Albedo + ERSTMALS Glowmask)

Canvas 64×64 (Standard, kein Integrator-Flag nötig). Beide PNGs aus EINEM
deterministischen Lauf (`mobs/gazer.py`, Seed `0x6A2E77CD`).

- **Palette (aus dem alten Art-Brief verfeinert):** Cloak Indigo `#262040` mit
  Vertikal-Falten-Weave + Mittelsaum + Hem-Schatten (+ near-black Unterseite — er
  schwebt über dem eigenen Schatten), Hood `#1B1730` mit **purem Void-Ring** `#0A0714`
  um die Maske, Mantle `#383159` mit lichter Oberkante, Tatters kelp-ragged `#211C38`
  (untere Segmente dunkler + zerrissener), Brow `#141024` (dunkelster Stoff).
- **Die Maske ist das einzige Licht des Mobs:** bone-pale `#EFE6CC`→`#C9BC9E`
  (Radial-Dim zum Rand), 2 hohle Void-Slits `#0E0A1C` (face-lokal Spalte 1/4, Zeile
  2..3 — die Pips schweben exakt dahinter proud), abgeplatzte Ecke + geätzte Kinn-Marke.
  Iris `#E8D6FF`→`#A87CF0` mit seltenen Weiß-Glints.
- **Glowmask (NEU — ersetzt den alten `RenderType.eyes`-Re-Render):** `glow_iris_*`
  auto (Präfix, voll); `glow_face` über Custom-Painter (same-salt-Zwilling der
  Albedo-Maske): NUR die Nordface brennt, α215 mit Rand-Vignette auf ~125, Chip α60,
  Slits + Kantenflächen bleiben dunkel → die Pips lesen als eigene Lichter in den
  Löchern. Lids/Hood tragen keinen Glow und verdecken ihn beim Blink (z −4.75 proud) —
  Depth-Rejection, kein `withTranslucency()` nötig (alles Cutout).

## 4. Java-Umbau

- **`GazerEntity extends EclipseGeoMob`** (statt PathfinderMob): `geoId()="gazer"`,
  `registerActionTriggers` = super(death-hold) + `gaze_lock` (**hold**!) +
  `tether_snap`/`hurt` (once). Goals/vanish/watchSacrifice/Sounds UNBERÜHRT.
- **Stare-Mirror (NEU, `tickStareMirror`):** serverseitiger Spiegel des client-lokalen
  `GazeTetherWatcher` mit DENSELBEN Konstanten (25°/45°-Hysterese, 8t-Arm, 20/22-Band,
  Distanz von `player.position()`, Konus auf `getEyePosition()`, `hasLineOfSight`):
  Rising-Edge → `gaze_lock`, jeder Bruch eines Locks → `tether_snap`. EIN kanonischer
  Stare pro Gazer (Best-Dot-Kandidat) — der Client-Watcher ist per-Beobachter, aber die
  Hood zeigt nur in eine Richtung; für den angestarrten Spieler (den einzigen, der den
  Thread besitzt) sind Anim und FX tick-synchron.
- **`handleBaseState`-Override (F-9, verschärft):** Teleport-Relocation erzeugt EINEN
  großen Positions-Delta-Tick → `walk` würde pro Relocation aufblitzen. Delta wird
  deshalb von OBEN gegated (`1e-5 < Δ² < 0.25`): nur Sub-Block-Gleiten (externe Pushes,
  Wasser) spielt walk, ein ≥Halbblock-Sprung ist ein Teleport und bleibt idle.
- **Hurt-Flinch:** `hurt()` (weiter unkillbar, return false) triggert jetzt `hurt` und
  verlegt den Vanish um 7 t (`pendingVanishTicks`) — der Treffer LIEST auf dem Körper,
  bevor der Wisp-Puff ihn schluckt. Dabei wird ein gehaltener Lock LAUTLOS resettet
  (kein snap — sonst poppte ein späterer Snap von der Ruhelage auf seine dilatierte
  0.0-Pose); Stare-Mirror pausiert im Flinch-Fenster. Stare-Down- und Dawn-Vanish
  bleiben instant (der Puff ist dort der Beat; den Tether reißt der Client-Watcher
  am zuletzt gesehenen Auge).
- **Death-Konvention (3 Teile):** `die()` → death-Trigger, `tickDeath()` = 30t
  (Portal-Motes alle 5 t, dann `POOF` + `remove(KILLED)`), Renderer `withUprightDeath()`.
- **Neuer Renderer** `client/entity/gazer/GazerGeoRenderer`: `EclipseGeoRenderer`-Sub,
  turnsHead=true, `withGlowmask()`, `withUprightDeath()`, Shadow 0.4 (Parität zur alten
  Registrierung). Kein Custom-Layer nötig — der eyes-Pass des Alt-Renderers ist
  vollständig durch die Glowmask ersetzt.
- **Registrar** `client/entity/gazer/GazerRenderers`: `@EventBusSubscriber(Dist.CLIENT)`
  + `isBound()`-Guard + `@SubscribeEvent(priority = EventPriority.LOWEST)` —
  `registerEntityRenderer` ist last-write-wins, der Geo-Renderer gewinnt deterministisch
  gegen die Default-Priority der SHARED-Klasse (MA3-Muster; nach dem §7-Löschen
  redundant, aber harmlos).
- **Alte Klassen:** rg bestätigt — `GazerModel`/`GazerRenderer` werden NUR von
  `EclipseEntityRenderers` referenziert (shared, G2) → beide `@Deprecated` mit
  Verweis auf §7; sie kompilieren unverändert weiter (kein Entity-Hook entfernt — das
  alte Face-Rig rechnete rein client-seitig).

## 5. Validierung

1. `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` nach JEDER Änderung.
2. `python3 scripts/geckolib_gen/mobs/gazer.py` 2× + md5 + Eyeball beider PNGs
   (8×-Nearest-Preview: Maske mit Void-Slits + heiße Pips + Vignetten-Glowmask geprüft).
3. `./gradlew compileJava` + `./gradlew build`.
4. Client-Sichtprüfung ist auf dieser VM llvmpipe-langsam — Test-Rezept in §9.

## 6. Ergebnisse

### 6.1 Dateien

**NEU:**

| Datei | Inhalt |
|---|---|
| `src/main/resources/assets/eclipse/geo/entity/gazer.geo.json` | 19 Bones / 15 Cubes, 64², Hierarchie exakt wie §1 |
| `src/main/resources/assets/eclipse/animations/entity/gazer.animation.json` | 6 Anims (§2), Molang-Sinus + catmullrom, `head` nie gekeyt |
| `src/main/resources/assets/eclipse/textures/entity/gazer_glowmask.png` | ERSTER Gazer-Glowmask, 64², 42 unique Mask-Pixel (Maske 32 + Pips 10) |
| `scripts/geckolib_gen/mobs/gazer.py` | deterministischer Painter (Seed `0x6A2E77CD`), Albedo+Glowmask in EINEM Lauf |
| `src/main/java/.../client/entity/gazer/GazerGeoRenderer.java` | `EclipseGeoRenderer`-Sub: turnsHead, Glowmask, UprightDeath, Shadow 0.4 |
| `src/main/java/.../client/entity/gazer/GazerRenderers.java` | Registrar, `EventPriority.LOWEST` + `isBound()`-Guard |

**GEÄNDERT:**

| Datei | Änderung |
|---|---|
| `src/main/java/.../entity/GazerEntity.java` | `extends EclipseGeoMob`; `geoId()`; 3 Action-Trigger; Server-Stare-Mirror (Watcher-Konstanten gespiegelt); F-9-Teleport-Gate in `handleBaseState`; Hurt-Flinch mit 7t-Vanish-Delay + lautlosem Lock-Reset; die()/tickDeath()-Konvention (30t). Goals/vanish/watchSacrifice/Sound-Hooks UNBERÜHRT |
| `src/main/resources/assets/eclipse/textures/entity/gazer.png` | altes Code-Modell-Layout → neues GeckoLib-Sheet (weiterhin 64², 1809 Albedo-Pixel) |
| `src/main/java/.../client/entity/GazerModel.java` | `@Deprecated` + Verweis auf den neuen Pfad; Code unverändert (kompiliert standalone, Shared-Referenz) |
| `src/main/java/.../client/entity/GazerRenderer.java` | `@Deprecated` + Verweis; Code unverändert |
| `docs/uv/gazer.md` | komplett neu auf das 19-Bone-Geo (Herald-Muster) |

**GELÖSCHT:**

- `scripts/skin_gen/gazer_v2.py` — der alte In-Place-Face-Rig-Painter; ein Rerun hätte
  Iris-/Lid-Rects des ALTEN UV-Layouts auf das neue Sheet gemalt und die Glowmask nicht
  mitregeneriert. Nur von Doku referenziert (rg-geprüft: `docs/uv/gazer.md` — neu
  geschrieben — und die historischen Pläne `MOB-AMBIENT.md`/MB5-Report-Verzeichnisliste).
  MA3-Präzedenz (`herald_v2.py`).
- `GazerModel`/`GazerRenderer` NICHT gelöscht (SHARED-Referenz, G2) → `@Deprecated`;
  Löschung gehört dem Integrator zusammen mit dem Snippet in §7.

### 6.2 Zahlen + Validierungs-Status (wörtlich)

- **19 Bones / 15 Cubes**, Canvas 64×64; Hitbox 0.8×2.1 unverändert.
- **Anims:** idle 6.0s loop · walk 3.0s loop · gaze_lock 0.5s hold · tether_snap 1.1s
  (=22t FX-Länge) · hurt 0.35s (=7t Vanish-Delay) · death 1.5s hold (=30t tickDeath).
- `validate_geo.py gazer.geo.json gazer.animation.json` →
  **„validate_geo: 2/2 file(s) passed — all good"**, GEO
  **„PASS (0 error(s), 0 warning(s))"**, ANIM **„PASS (0 error(s), 0 warning(s))"**.
- `./gradlew compileJava` → **BUILD SUCCESSFUL**; `./gradlew build` (strict) →
  **BUILD SUCCESSFUL**. (Ein zwischenzeitlicher build-Fail kam aus `DriftLanternEntity`
  — MC3-Datei mitten im Parallel-Edit; nach deren Abschluss grün. Nicht MC1.)
- Painter-Rerun **byte-identisch**: albedo `2792edef2b6134e08a8716e0e46448ce`,
  glowmask `4c103173a4983d9b04c2be8787987286` (2 Läufe, identisch).
- **Loop-/Handback-Hygiene:** idle-Frequenzen 60/120/180/300/420°/s — alle ·6.0s ≡ 0
  mod 360; walk 120/240°/s ·3.0s ≡ 0; Blink-Keyframes first==last. Alle One-Shots enden
  exakt in der Ruhelage (tether_snap/hurt: alle Kanäle auf 0 bzw. Scale 1/Lid 0.1);
  gaze_lock/death halten BEWUSST (Stare-Zustand / Wrack) — jeder Lock-Bruch feuert den
  auflösenden Snap, dessen 0.0-Keys die Halte-Pose exakt wiederholen (kein Pop).
- **Polish-Iterationen:** (1) Selbstkritik: Stare-Mirror lief im Hurt-Flinch-Fenster
  weiter und ein Hurt während eines Locks hätte den nächsten Snap von der Ruhelage auf
  die dilatierte 0.0-Pose poppen lassen → tick()-Gate + lautloser Lock-Reset in
  `hurt()`; (2) F-9 verschärft: reines Delta-Muster (DriftLantern) hätte bei JEDER
  Teleport-Relocation einen walk-Frame geflickt → Obergrenzen-Gate `Δ² < 0.25`;
  (3) Anim-Review wie oben (Perioden/Handback/FX-Beats), Lid-Scale-Baseline in ALLEN
  sechs Anims verifiziert (Voll-Cubes + Anim-Sliver, §1).

## 7. Patch-Snippets für den Integrator (SHARED `EclipseEntityRenderers.java`, G2)

**Löschen (drei Zeilen), im SELBEN Commit `GazerModel.java` + `GazerRenderer.java`
entfernen** (Zeile 2 ist die letzte Referenz auf `GazerModel`; `GazerRenderer`
referenziert seinerseits `GAZER_LAYER` — einzeln gelöscht bricht der Build):

```java
// client/entity/EclipseEntityRenderers.java — Zeile 24:
    public static final ModelLayerLocation GAZER_LAYER = layer("gazer");
// … onRegisterLayerDefinitions, Zeile 42:
        event.registerLayerDefinition(GAZER_LAYER, GazerModel::createBodyLayer);
// … onRegisterRenderers, Zeile 52:
        event.registerEntityRenderer(EclipseEntities.GAZER.get(), GazerRenderer::new);
```

Bis dahin ist NICHTS kaputt: `GazerRenderers` registriert mit `EventPriority.LOWEST`
nach der Shared-Klasse (last-write-wins) — der Geo-Renderer gewinnt deterministisch,
die alte Layer-Definition wird nur ungenutzt gebacken. (Achtung beim Bündeln: MC2/MC3
liefern für Stalker/Sunmote analoge Snippets — die Zeilennummern verschieben sich,
die Zeilen-INHALTE oben sind eindeutig.)

**Lang/Sounds:** KEINE neuen Keys (`entity.eclipse.gazer` + `ambient.gazer_whisper`
existieren) — kein langdrop/sounddrop.

**Canvas:** 64² Standard — kein Ausnahme-Flag.

## 8. Koordinations-Snippet für B2 (FX — `gazer_gaze_beam`/`gazer_tether_snap`, nur Info)

```
ENTITY   eclipse:gazer — GeckoLib geo "gazer", turnsHead: head trägt hood/mask/iris/lids.
         Eye-Anker (FX attach): eyeHeight 1.6 (=25.6px). Iris-Zentrum im Geo: y=22px
         (=1.375 Blöcke) — der Beam-Ursprung hängt wie beim Alt-Modell ~0.22 Blöcke
         ÜBER den Pips. Falls der Thread an den Pips wurzeln soll: Row-Offset
         (0, -0.22, 0) auf der gazer-Zeile in PhotonMobFx (eure Entscheidung, kein
         Regress ohne — Zustand wie bisher).

BONES (falls FX andocken will):
  head (Tracking-Frame), hood, glow_face (Maske, Front z-4.25), iris_carrier
  (Drift-Träger), glow_iris_left/right (Pips ±1.5, 22, -4.5 — proud), brow,
  lid_top/lid_bottom (Shutter), tatter_{left,right,back}_{1,2}.

ANIM-TIMING (Server-Mirror = EURE Watcher-Konstanten, 25°/45°/8t/20-22 Blöcke):
  t=0      Stare-Konus armt (Server wie Client zählen ab hier)
  t=8t     LOCK: Server triggert gaze_lock — Pupille konstringiert 0.08s, dilatiert
           dann catmullrom auf 2.0 (Peak +0.3s), hält 1.8; Lids auf 0.02 gepinnt
           (der beobachtete Gazer blinzelt nie); Carrier lehnt z-0.3 in den Beam
           (B2-Fix beachtet: der Thread läuft die Blickachse entlang — die Dilatation
           liest jetzt DEN BEAM HINUNTER statt quer dazu).
  BREAK    Server triggert tether_snap (1.1s = 22t = exakt eure FX-Länge):
           0.10s Iris-Slam auf 0.45 (euer dunkler Closing-Pop) + Hood-Whip,
           0.15s erster Zuck = euer Recoil-Peak (~0.06-0.1s Partikel-Alpha-Max),
           danach 3 abklingende Shudder + Doppel-Settle-Blink, Ruhelage bei 1.1s.
  VANISH   (Stare-Down/Dawn/Hurt-Ende) bleibt instant discard — euer Watcher spielt
           den Snap am zuletzt gesehenen Auge (unverändert, Gone-Branch).
  HINWEIS  Der Mirror ist EIN kanonischer Stare pro Gazer (Best-Dot); euer Watcher
           bleibt per-Beobachter. Für den Thread-Besitzer sind Anim+FX tick-synchron,
           Dritte sehen die Anim seines Locks — kohärent, da die Hood ohnehin nur
           auf einen zeigt.
```

## 9. Test-Rezept (Client, llvmpipe: 20–40s Wartezeit einplanen)

```
./gradlew build            # strict, vor jedem Client-Start (AGENTS.md)
./gradlew runClient

# Nachtstellen (Gazer vanisht am Tag sofort):
/time set midnight
/summon eclipse:gazer ~5 ~ ~

# 1) idle: Iris-Drift (unstetes Wandern der Pips), Blink ~alle 6s, Bob + Tatter-Ketten,
#    Glowmask: Maske+Pips leuchten im Dunkeln, Hood/Cloak bleiben schwarz.
# 2) gaze_lock: seitlich auf <20 Blöcke nähern und die Hood auf sich zeigen lassen
#    (LookAtPlayerGoal) — nach 8t Konus-Halt dilatiert die Pupille und hält; kein Blink.
#    Gleichzeitig armt der gazer_gaze_beam-Tether (Photon aktiv, kein reducedFx).
# 3) tether_snap: hinter eine Wand treten oder schnell seitlich raus (>45°-Konus) —
#    Iris-Slam + Hood-Whip + Zucken, synchron zum Tether-Riss-FX.
# 4) hurt: einmal schlagen — 7t-Flinch, DANN Wisp-Puff (unkillbar, kein Schaden).
# 5) Stare-Down: 40t direkt anstarren (dot>=0.985) — instanter Vanish + Cave-Mood
#    (nur für den Starrer) + Client-Snap am letzten Augpunkt.
# 6) death (nur Bypass): /kill @e[type=eclipse:gazer] — 30t-Gutter-out aufrecht
#    (Lids schließen für immer), Portal-Motes, POOF bei t=30.
# 7) Relocation: warten (200-400t) — Teleport darf KEINEN walk-Frame flicken (F-9-Gate).
```
