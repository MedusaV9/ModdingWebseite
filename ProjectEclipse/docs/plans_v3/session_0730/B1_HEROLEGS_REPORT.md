# B1 — Quasar→Photon-Hero-Legs (`heart_burst`, `boss_slam`, `map_expand_materialize`)

**Welle 13 / §7 Welle B, Team B1.** Die drei meistgesehenen der 10 Quasar-only-Lanes
(FX_CENSUS_WAVE13 §3) bekommen eine Photon-Hero-Version. Quasar bleibt **unangetastet**
als Fallback-Lane darunter (Baseline-Gesetz) — kein `quasar/emitters/*.json` wurde
geändert oder gelöscht.

N4 (Grab-Laterne, `grave_soul_lantern`) ist bereits von einem anderen Team gebaut und
wird hier **nicht** angefasst.

---

## §1 Bestandsaufnahme — wo die drei Cues heute gefeuert werden

Alle drei laufen auf der **`S2CQuasarPayload`-Lane**, NICHT auf der `FxCues`-Lane. Das ist
der Grund, warum sie im Zensus als „Quasar-only" geführt werden: `PhotonFxRegistry.Row`
abonniert `FxCues`-Ids, und für diese drei existiert kein Cue.

Wire-Weg (client):

```
S2CQuasarPayload  ->  EclipsePayloads.handleQuasar
                        1. OfferingSwallowFx.intercept(id, pos)         (hardcodiert)
                        2. WorldStageArbiter.gateCue(id, pos)           (offene Registry!)
                        3. PhotonBridge.enhanceQuasarCue(id, pos)       (hardcodierte if-Kette)
                        4. QuasarSpawner.spawnOrFallback(id, pos)       (Baseline)
```

### Sender-Inventar (verifiziert per `rg`)

| Cue | Sender | Anker | Bemerkung |
|---|---|---|---|
| `heart_burst` | `economy/AltarBuyCeremony.beatGearCatch` | Käufer +1.0 | Gear-Kauf-Quittung |
| | `economy/AltarBuyCeremony.tickHeart` (age 30) | `crown +1.2` | **die Herzfragment-Einzahlung** |
| | `lives/HeartTheftService.celebrate` | Leiche | Herzdiebstahl-Baseline (LAYER unter `CUE_HEART_THEFT`) |
| | `lives/LifecycleEvents` | Spieler | Herzverlust |
| | `entity/boss/fog/FogTyrantEntity`, `HeraldEntity:1127`, `rift/RiftWardenEntity:975` | Spieler | Boss-Kill-Belohnung („Herz erhalten") |
| `boss_slam` | `entity/boss/FerrymanEntity` ×3 (Summon, Gunwale-Slam, P-Break) | `position()` = **Füße** | |
| | `entity/boss/HeraldEntity:414`, `:853` (Korona-Crash), `:1144` (Tod) | Füße / `crash.pos` (Boden) | |
| | `entity/fog/FogBlindBurstGoal:150` | Revenant `+1.2` | einziger Nicht-Boden-Anker |
| `map_expand_materialize` | `worldgen/stage/RingGrowthService:1094` | `surfaceY + 1.5` | max. alle 5 t, Radius 192 |
| | `sequence/ExpansionSequence:1825` | Oberflächenpunkt | ruft `QuasarSpawner.spawn` **client-lokal** (umgeht `handleQuasar` komplett) |
| | `veilfx/rift/RiftFx:158` | Riss | client-lokal, Riss-Ambient |

### Anker-Konsequenzen fürs Authoring

- `hero_heart_burst` — **freier Luft-Anker** (Altarkrone, Spielerbrust, Leiche). Keine
  Bodenannahme erlaubt: radialsymmetrisch, keine `Horizontal`-Bodendecals.
- `hero_boss_slam` — **Boden bei lokal y ≈ 0** (Füße). Der eine `+1.2`-Sender
  (FogBlindBurst) verträgt die 1,2 Blöcke Versatz, weil die Bodenlagen über
  `eclipse:soft_particle` weich an der Geometrie ausblenden statt hart zu schneiden.
- `hero_expand_materialize` — **Boden bei lokal y = −1.5** (`surfaceY + 1.5`).

---

## §2 Verdrahtung — was B1 selbst macht, was der Integrator patchen muss

**Selbst verdrahtet (offene Registry, kein fremder Datei-Touch):**
`WorldStageArbiter.registerCue` ist eine offene Registrierungs-API und wird von
`Wave13bPhotonFxRows` für `HEART_BURST` (A-Klasse, Pass-through) und
`MAP_EXPAND_MATERIALIZE` (B-Klasse, Bett — beansprucht nie den Token) aufgerufen.
`BOSS_SLAM` ist bereits von `SignaturePhotonFxRows` als S-Klasse registriert
(40 t Lease) — B1 fasst das nicht an (Erst-Registrierung gewinnt).

**Patch-Snippet für den Integrator (NICHT von B1 angewendet):** der einzige
Photon-Seam der Quasar-Lane ist die hardcodierte if-Kette in
`veilfx/PhotonBridge.enhanceQuasarCue` — eine geteilte Kern-Datei (§7.4:
„Neue Rows kommen in eigene neue Registrar-Klassen, nie in fremde"). Ein 1-Zeilen-Hook
ganz am Anfang der Methode reicht; die komplette Tabelle + REPLACE/LAYER-Semantik liegt
in `Wave13bPhotonFxRows`:

```java
// src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonBridge.java
     public static boolean enhanceQuasarCue(ResourceLocation emitterId, Vec3 pos) {
+        // FX-WAVE-13/B1 hero legs (heart_burst / boss_slam / map_expand_materialize).
+        Boolean b1 = Wave13bPhotonFxRows.enhanceQuasarCue(emitterId, pos);
+        if (b1 != null) {
+            return b1;
+        }
         if (S2CQuasarPayload.ALTAR_LEVELUP_RING.equals(emitterId)) {
```

`Boolean`-Rückgabe statt `boolean`: `null` = „nicht meine Cue, Kette weiterlaufen
lassen", `TRUE` = Quasar-Leg überspringen (REPLACE geglückt), `FALSE` = Quasar-Leg
fahren (LAYER oder Photon-Leg refused). Damit ist der Hook reihenfolgeneutral und die
bestehenden vier Zweige bleiben bitgleich.

**Zwei client-lokale Nebenpfade** (`ExpansionSequence:1825`, `RiftFx:158`) rufen
`QuasarSpawner.spawn` direkt und sehen den Hook NICHT. Das ist bewusst so gelassen:
beides sind Hochfrequenz-Ambient-Rufe (Überflug-Garnitur bzw. Riss-Ambient), für die
die günstige Quasar-Lane die richtige Wahl bleibt. Wer sie mitziehen will, ersetzt den
Ruf durch `Wave13bPhotonFxRows.playExpandMaterialize(pos)` — ebenfalls Patch-Snippet,
nicht angewendet.

---

## §3 Die drei Assets

Namensraum geprüft (`ls src/main/resources/assets/eclipse/fx/`): kein `hero_*` vorhanden,
alle drei Namen kollisionsfrei. Generator (exklusiver Besitz B1):
`tools/photon/wave13b_fx.py`.

Geschwindigkeitsgesetz durchgängig angewandt: `startSpeed`/`linear` sind Blöcke/**Sekunde**
(×0.05 pro Tick), `radial` skaliert ×0.01 pro Tick (1 Einheit ≈ 0,2 b/s). Alle
Alpha-Pässe sortieren `DISTANCE`, HDR-Deckel 1.45, Birth-Tints dunkel (SAC_VOID/SAC_DEEP).

### 3.1 `eclipse:hero_heart_burst` — 72 t, 6 Emitter

Erzählung: **zerspringen → treiben → Sog zurück in den Kern → Annahme → Nachglimmen.**
Die Herzfragment-Einzahlung ist der Moment, in dem der Altar etwas *annimmt* — deshalb
endet die Kette nicht im Verwehen, sondern in einem Gold-Akzent (SAC_GOLD = Belohnung/
Göttlichkeit, §1.1, ≤35 % der Partikel).

| t | Emitter | Was man sieht | Farbe (Birth → Mid → Tod) |
|---|---|---|---|
| 0 | `core_flash` | 1 additiver Kern-Blitz, Overshoot-Settle 0.18→**1.15**, 11 t | SAC_HOT → HEART_PINK → SAC_DEEP, HDR (1.38, 1.24, 1.45) |
| 0 | `heart_shards` | 18 Splitter, 5–9 b/s auswärts, StretchedBillboard, `colorBySpeed` 2→9 b/s | SAC_DEEP → SAC_VIOLET → SAC_VOID; heiß = SAC_HOT |
| 1 | `shard_dust` | 14 weiche Körper unter den Splittern (`soft_particle`), α ≤ 0.34 | SAC_VOID → SAC_DEEP → SAC_VOID |
| 12 | `indraw_motes` | 20 Motes auf r = 3.4 geboren, radial −8 → −30 (1.6 → 6 b/s einwärts), 22 t — **der Sog**; 2×2-Sheet-Pick (echte 4-Punkt-Sterne) | SAC_VIOLET → SAC_HOT → SAC_DEEP |
| 28 | `reforge_pulse` | 1 Ring, EASE_OUT_CREST 0.3→**2.6**, der Moment der Annahme | SAC_HOT → SAC_GOLD → **SAC_VIOLET** → SAC_VOID, HDR (1.45, 1.24, 0.72) |
| 30 | `afterglow_motes` | 16 langsam steigende weiche Motes, 40–60 t, α ≤ 0.30 — **Nachglimmen** | SAC_VOID → SAC_VIOLET → SAC_VOID |

Der Sog ist als **eigener Emitter** gebaut (Schale r = 3.4, `radial`-Kurve), nicht als
Vorzeichenwechsel auf den Splittern: Photon addiert `velocityOverLifetime` auf die
Start-Geschwindigkeit, ohne Dämpfung kehrt eine späte Negativ-Radiale die Splitter
nicht sichtbar um. Getrennte Lagen = lesbarer Sog (tyrant_death `gulp_motes`-Muster).

### 3.2 `eclipse:hero_boss_slam` — 130 t, 7 Emitter

Erzählung: **Aufschlag → Druckfront → ballistische Chips → Vorhang rollt aus → Staub
bleibt liegen.** Boden ist lokal y = 0; alle bodennahen Lagen laufen auf
`eclipse:soft_particle`, damit der Slam die Arena-Geometrie nicht aufsägt.

| t | Emitter | Was man sieht | Farbe |
|---|---|---|---|
| 0 | `impact_flash` | 1 additiver Aufschlag-Kern bei y 0.35, 0.4→**1.5**, 9 t | GLI_WHITE → SAC_VIOLET → SAC_VOID, HDR (1.30, 1.18, 1.45) |
| 0 | `shock_ring` | Horizontales Ring-Sheet, `soft_particle` (**SoftDistance 0.45**), 0.6→17.0 Blöcke, 30 t, **α ≤ 0.62** | SAC_HOT → SAC_VIOLET → SAC_VOID |
| 6 | `ring_echo` | zweiter, engerer Ring 0.5→11.0, 26 t, SoftDistance 0.4, α ≤ 0.42 — macht aus dem Decal eine Druckfront | SAC_VIOLET → SAC_DEEP → SAC_VOID |
| 0 | `ground_chips` | 22 Chips, **echte Physik** (Kollision, gravity 1.2, bounce 0.45), 7–13 b/s ballistisch, `colorBySpeed` 3→14 b/s, **4×4-Sheet-Pick + pixelArt(4)** | STM_SLATE → SAC_DEEP; heiß = SAC_HOT, HDR (0.50, 0.36, 0.72) |
| 1 | `dust_curtain` | 26 weiche Schwaden von r = 1.2, radial 30 → 6 (6 → 1.2 b/s abklingend), 60–90 t, SoftDistance 0.9 | STM_SLATE → SAC_DEEP → SAC_VOID, α ≤ 0.32 |
| 20 | `settled_bank` | 14 flache Bänke auf r = 5–9, praktisch stillstehend, 70–110 t, SoftDistance 0.6 — **der Staub, der liegen bleibt** | STM_SLATE → SAC_VOID, α ≤ 0.28 |
| 2 | `updraft_motes` | 12 kleine Glints steigen 1.5–3 b/s (2×2-Sheet-Pick) — vertikale Lesbarkeit | SAC_VIOLET → SAC_HOT → SAC_VOID |

`ground_chips` trägt Physik, also **kein** `parallelUpdate`/`useGPUInstance`
(LINT-GPU-PHYSICS). Alle anderen Lagen bleiben ebenfalls CPU — die Counts sind klein.

### 3.3 `eclipse:hero_expand_materialize` — 86 t, 5 Emitter

Erzählung: **der Chunk rastet ein.** Boden ist lokal y = −1.5. Der Cue feuert im
Wachstums-Sweep bis zu alle 5 t an gestreuten Punkten — das Asset ist deshalb bewusst
schlank (56 Partikel gesamt) und ohne Physik.

| t | Emitter | Was man sieht | Farbe |
|---|---|---|---|
| 0 | `column_seam` | Horizontaler Boden-Saum bei y −1.42, `soft_particle` (SoftDistance 0.4), 0.6→4.2, 26 t, α ≤ 0.6 | SAC_HOT → SAC_VIOLET → SAC_VOID |
| 0 | `materialize_columns` | 7 hohe **harte Slats** (`square_4x4.png`, 4×4-Sheet-Pick + pixelArt(4)), 0.33×1.7×0.33, steigen mit **1.4–2.4 b/s** vom Boden, α FLICKER_COMMIT (zögern, dann committen), α ≤ 0.62 | SAC_VOID → SAC_VIOLET → SAC_HOT, HDR (0.40, 0.26, 0.62) |
| 0 | `voxel_motes` | 10 harte Quads (`square_4x4.png`, 4×4-Sheet-Pick) — das „Block-hafte" der Quasar-Cubes — mit radial −6 → −14 zur Achse gezogen | SAC_VOID → SAC_VIOLET → SAC_DEEP, HDR (0.55, 0.42, 0.80) |
| 2 | `glint_veil` | 28 Glints in 3 Wellen (Burst-Cycles) über ein r = 1.7-Volumen, `random_gradient` + Noise-Schimmer, **2×2-Sheet über die Lebenszeit gescannt = das Funkeln selbst**, löst sich gestaffelt auf | SAC_VIOLET / SAC_GOLD_PALE (Zweit-Rampe) → SAC_VOID |
| 4 | `ground_dust` | 10 weiche Bodenschwaden, radial 10 → 3, 40–60 t, SoftDistance 0.85 | STM_SLATE → SAC_VOID, α ≤ 0.24 |

Der Schleier löst sich über **3 Burst-Zyklen** (t = 2/12/22) mit gestaffelten Lebenszeiten
auf statt kollektiv auszublenden — sonst liest sich das Auflösen als Dimmer-Schalter.

---

## §4 Polish-Iterationen (in-game, `/dev photon test`)

Verifiziert auf dem laufenden Dev-Client (llvmpipe) über RCON
(`execute as Dev at @s run dev photon test "<id>"`) + `xdotool`-Chat für
`/photon_client clear_client_fx_cache`. Zwei Durchgänge, beide aus dem Bild heraus:

### 4.1 Erster Durchgang — zwei echte Bugs

**(a) Sprite-Sheets ohne `uvAnimation` (der schwerste Fund).** `square_4x4.png` ist ein
4×4-Raster aus 16 Quadrat-Frames und `star_2x2.png` ein 2×2-Raster aus 4 Stern-Frames.
Ohne ein `uvAnimation`-Modul mappt Photon die **ganze PNG** auf den Quad: jeder Chip und
jedes Voxel-Mote rendert als kleine weiße Rubik's-Cube-Fläche, jeder „Stern" als
Vierer-Konstellation. Betroffen waren `ground_chips`, `voxel_motes`,
`materialize_columns` (nachträglich), `indraw_motes`, `updraft_motes`, `glint_veil`.
Fix: Helfer `sheet(tiles, frames)` → `uv_animation=dict(tiles=…, animation="WholeSheet",
frame_over_time=constant(0), start_frame=random_between(0, frames−1))`, also ein
zufälliger, über die Lebenszeit stehender Frame pro Partikel (Hausmuster
`gen_player_fx.riss_glitch_pop`). Beim `glint_veil` stattdessen ein FLICKER_COMMIT-Scan
über die 4 Frames — das Funkeln IST der Sheet-Durchlauf (`stern_komet_star_glint`).

**(b) Übergroße `circle.png`-Kerne.** `core_flash` (0.18→2.8) und `impact_flash`
(0.4→3.2) sind weiche Radialgradienten: über ca. 1,5 Blöcken hören sie auf, ein Blitz zu
sein, und werden eine graue **Blase**, die Altar bzw. Spieler verschluckt und die Chips
und den Ring verdeckt, die sie eigentlich einleiten sollen. Auf 1.15 bzw. 1.5 zurück,
Lebenszeiten 14→11 bzw. 10→9 t.

Mitgenommen: `reforge_pulse` 3.4→2.6 (war nach dem Schrumpfen des Kern-Blitzes das mit
Abstand größte Objekt des Legs und las sich als Portal-Reifen um den Spieler statt als
Puls, der das Fragment verlässt) + ein SAC_VIOLET-Stop vor dem Ausklang, damit der
Gold-Frame nicht als reiner Goldreifen endet.

### 4.2 Zweiter Durchgang — HDR auf großen Flächen

Nach (a) standen die Materialisierungs-Säulen als **harte** Slats — und waren
ausgebrannt weiß. Ursache: `hdrMode="ADDITIVE"` ist `rgb += HDR.rgb`, ein konstanter
Offset. Auf einem Kern oder einem Rim ist das genau der gewollte Bloom-Boost; auf einer
Fläche, die einen halben Bildschirm-Block bedeckt, clippt es die komplette Fläche nach
Weiß und die Violett-Identität ist weg. Das Stacking-Gesetz „HDR reitet nur auf
additiven Kernen/Rims" gilt also auch für Chips und Säulen:

| Emitter | HDR vorher | HDR nachher |
|---|---|---|
| `materialize_columns` | (0.95, 0.80, 1.25) | **(0.40, 0.26, 0.62)** + α-Peak 0.72→0.62 |
| `ground_chips` | (0.90, 0.72, 1.20) | **(0.50, 0.36, 0.72)** + Größe 0.10–0.26 → 0.09–0.20 |
| `voxel_motes` | (0.85, 0.68, 1.15) | **(0.55, 0.42, 0.80)** |

Ebenfalls in diesem Durchgang: `materialize_columns` von `circle.png` auf
`square_4x4.png` umgestellt. Ein gestreckter weicher Radialgradient las sich als weiße
**Flamme**, die aus dem Boden züngelt — die exakt falsche Fiktion für „Materie rastet
ein". Ein hartkantiger Slat ist Materie, teilt sich die Voxel-Sprache mit `voxel_motes`
und ist das, worauf die `veil:block`-Würfel der Quasar-Skizze hinauswollten. Steiggeschw.
2.2–3.6 → 1.4–2.4 b/s (bei 3.6 b/s über 38 t räumten die Säulen 6 Blöcke und verließen
als Lampen das Bild).

### 4.3 Bodenlagen: `SoftDistance` — begründet, hier NICHT verifizierbar

Der flache Schockring war auf Augenhöhe praktisch unlesbar. Erste Vermutung war
`SoftDistance`: der A0-Shader rechnet
`alpha *= smoothstep(0, 1, (sceneDepth − viewZ) / SoftDistance)`, und diese Distanz wird
**entlang des Sehstrahls** gemessen. Ein bodenparalleles Decal 0.08 über dem Boden ist
bei 10° Blickelevation nur 0.08/sin 10° ≈ 0.46 Blöcke von der Geometrie dahinter
entfernt — geteilt durch 1.8 bleibt vor dem Smoothstep 0.26, also rund ein Zehntel der
authorierten Alpha.

**Ein A/B auf dieser VM widerlegt das aber als lokale Ursache:** mit 1.8 ist der Ring von
oben genauso da wie mit 0.45. Grund ist A0_SHADER_FOUNDATION.md §7.1 — llvmpipe hier
wirft pro Frame `GL_INVALID_OPERATION in glBlitNamedFramebuffer(depth attachment format
mismatch)`, `SamplerSceneDepth` liest 0.0, der Härtungspfad des Shaders klappt den
Soft-Term auf 1.0, und **jeder `SoftDistance` in dieser Datei ist lokal ein No-op**.

Konsequenz, sauber getrennt:

- Die `SoftDistance`-Senkungen (Ring 1.8→0.45, Echo 1.5→0.4, Bank 2.0→0.6, Saum 1.4→0.4,
  Vorhang 1.6→0.9, Bodenstaub 1.5→0.85) bleiben drin — die Shader-Mathematik oben gilt
  auf echter Hardware, und die alten Werte hätten die Bodenlagen dort weggefressen. Sie
  sind hier **nicht** visuell bestätigt und gehören auf einer GPU nachgeprüft.
- Was den Ring auf dieser VM sichtbar gemacht hat, ist die getrennte **Alpha**-Anhebung
  (0.44→0.62 / 0.30→0.42 / 0.22→0.28). Ein flaches Ringdecal wird aus Spieler-Augenhöhe
  fast von der Kante gesehen; 0.44 reichte dafür schlicht nicht.

## §5 Test-Kommandos

```
# Roh-Asset (geht immer, auch ohne Registry-Eintrag — FxDevClient.photonTest fällt auf
# PhotonBridge.spawn(..., allowMulti) zurück):
/photon_client clear_client_fx_cache        # PFLICHT im CLIENT-Chat nach jedem Regen!
execute as <player> run dev photon test "eclipse:hero_heart_burst"
execute as <player> run dev photon test "eclipse:hero_boss_slam"
execute as <player> run dev photon test "eclipse:hero_expand_materialize"

# Volle Quasar->Photon-Lane (erst NACH dem §2-Patch-Snippet):
/eclipsefx emitter eclipse:heart_burst
/eclipsefx emitter eclipse:boss_slam
/eclipsefx emitter eclipse:map_expand_materialize

# Regenerieren + Gate:
python3 tools/photon/wave13b_fx.py
python3 tools/photon/fxlib.py validate --lint
```

## §6 Ergebnis

### Dateien (alle neu, alle exklusiv B1)

| Datei | |
|---|---|
| `tools/photon/wave13b_fx.py` | Generator (667+ Zeilen), einzige Authoring-Quelle der drei Blobs |
| `src/main/resources/assets/eclipse/fx/hero_heart_burst.{fx,fxproj}` | 6 Emitter, 72 t |
| `src/main/resources/assets/eclipse/fx/hero_boss_slam.{fx,fxproj}` | 7 Emitter, 130 t |
| `src/main/resources/assets/eclipse/fx/hero_expand_materialize.{fx,fxproj}` | 5 Emitter, 86 t |
| `src/main/java/dev/projecteclipse/eclipse/veilfx/Wave13bPhotonFxRows.java` | Registrar |
| `docs/plans_v3/session_0730/B1_HEROLEGS_REPORT.md` | dieses Dokument |

**Keine fremde Datei geändert.** `PhotonBridge.java` wurde für den End-to-End-Test
temporär gehookt und **vor der Übergabe zurückgesetzt** (`git diff` sauber); der Hook
liegt ausschließlich als Snippet in §2.

### Gates

- `python3 tools/photon/wave13b_fx.py` → 3× `valid` (write() round-trippt + prüft
  Shader-Refs, `write_fxproj` mitgeschrieben).
- `python3 tools/photon/fxlib.py validate --lint` → **0 NEW error/warn** (264 Dateien).
- `./gradlew compileJava` → **BUILD SUCCESSFUL**, keine Warnung aus `Wave13bPhotonFxRows`.

### In-Game (verifiziert)

Alle drei Legs laufen über `/dev photon test` auf dem Dev-Client; Chat quittiert je
`photon eclipse:hero_… spawned at …`. Gesehen und abgenommen:

- **heart_burst** — kompakter Kern-Blitz, violette Splitter mit sichtbarem
  Geschwindigkeits-Farbverlauf, konvergierende Sterne (der Sog), Gold-Ring auf t = 28,
  Nachglimmen bis ~3,5 s.
- **boss_slam** — expandierender Schockring, ballistische Einzel-Chips, die fliegen,
  **landen und liegen bleiben**, darüber der violette Staubteppich, der den Aufschlag um
  Sekunden überlebt. (Aus der Vogelperspektive aufgenommen: ein flaches Bodendecal ist
  aus Augenhöhe stark verkürzt — siehe §4.3.)
- **map_expand_materialize** — violette Slat-Säulen steigen aus dem Bodensaum, harte
  Voxel-Motes werden zur Achse gezogen, Glint-Schleier löst sich in Wellen als echte
  4-Punkt-Sterne auf.

**Nicht in-game verifiziert** (bewusst, kein Client-Neustart möglich — der VM-Client
gehört einer parallel laufenden Session und der RAM reicht nicht für einen zweiten):
die Java-Seite (`Wave13bPhotonFxRows`, Stage-Klassen-Registrierung, REPLACE/LAYER-Gating)
läuft nur über `compileJava`. Sie greift erst, wenn der §2-Hook gesetzt ist; dann ist
`/eclipsefx emitter eclipse:boss_slam` der End-to-End-Test.

## §7 Offene Punkte

1. **§2-Patch-Snippet anwenden.** Ohne den einen Hook in `PhotonBridge.enhanceQuasarCue`
   sind die Legs nur per `/dev photon test` erreichbar; die Quasar-Lane spielt weiter
   ausschließlich die Baseline. Danach `/eclipsefx emitter eclipse:heart_burst` /
   `…:boss_slam` / `…:map_expand_materialize` gegenprüfen.
2. **`SoftDistance` auf echter GPU nachprüfen** (§4.3) — auf dieser VM ist der Soft-Term
   wegen des A0-§7.1-Depth-Blit-Fehlers durchgehend 1.0, die Werte sind hergeleitet, nicht
   gemessen. Betrifft alle sechs `soft_particle`-Lagen der drei Legs.
3. **`ground_chips`-Budget bei Boss-Ketten.** Der Ferryman slammt mehrfach von derselben
   Deckposition; `allowMulti` lässt das bewusst zu, aber 3 gleichzeitige Slams sind 66
   physik-getickte Collider. Falls das auf schwachen Clients auffällt, ist der Burst-Count
   (22) der erste Regler, nicht `max_particles`.
4. **Zwei client-lokale Sender** (`ExpansionSequence:1825`, `RiftFx:158`) bleiben bewusst
   Quasar-only (§2). Wenn die Ring-Erweiterung durchgängig heroisch aussehen soll, ist der
   Einzeiler `Wave13bPhotonFxRows.playExpandMaterialize(pos)` die Stelle.
5. **`EXPAND_SPACING_BLOCKS = 14`** ist geschätzt, nicht gemessen — der Wert steuert, wie
   dicht Hero-Säulen an einer Wachstumsfront stehen dürfen, bevor auf Quasar
   zurückgefallen wird. Sollte einmal an einer echten Ring-Erweiterung beobachtet werden.
