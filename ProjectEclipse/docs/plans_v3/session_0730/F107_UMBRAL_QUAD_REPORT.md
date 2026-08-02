# F-107 Teil 3 — „Lila Ding kommt in Wellen ganz links am Rand": Umbral-Quad-Report

Anschluss an `F107_GODRAY_FIX_REPORT.md` (Teil 1, `8b3c241`) und
`F107_FOG_CLEARANCE_REPORT.md` (Teil 2, `eafed33`). Restbefund aus der Live-Abnahme:
in `eclipse:limbo` erscheinen **violette PLUS/KREUZ-förmige Cluster aus uniformen,
halbtransparenten, hartkantigen Rechtecken** (Himmel ~20–30°, zeitweise Mast-/Deckhöhe,
schieben beim Schwenk am Bildrand herein) — scheinbar korreliert mit dem
Umbral-Nacht-Event. Dazu zwei Nebenaufträge: Nacht-Event-Announcements liefen in
Limbo ein (Design-Bug, bestätigt), und ein Video-Restbefund („dunkle blockige Struktur
unter der Wasseroberfläche am Rumpf") war zu verifizieren.

---

## 1. Ergebnis (Executive Summary)

1. **Die Umbral-Korrelation war eine Fehlspur** (§2). Die Quads kommen aus zwei
   **immer-aktiven** `LimboAmbience`-Fenstern; die On/Off-Beobachtungen waren
   Window-Roll-Koinzidenzen (Emitter-Standzeit ~9–13 s + Partikel-Fade ≤ 6 s ≈ die
   gemessenen „binnen ~12 s weg").
2. **Producer A — `NEAR_MOTES`** (§3): das 8×8-`purple_wisp` auf 0.55–0.85-Half-Edge-
   Quads, per ungedämpftem Wind (0.012/t², Drift ≤ 87 Blöcke) DURCH die Kamera
   geschoben. Bei Nearest-Sampling ist jedes Texel ein hartes uniformes Rechteck und
   die plus-förmige Alpha-Maske des Sprites IST das gemeldete Kreuz. Fix: dedizierte
   128×128-Bokeh-Textur + Wind-Kur + Ring/Shape/Dichte-Retune.
3. **Producer B — `GODRAYS`** (§4): zwei Teil-1-Altlasten. (a) Der Emitter behielt den
   ungedämpften Wind 0.008/t² (Teil-2-Erkenntnis kam NACH dem Godray-Retune): jeder
   Schacht driftete bis ~58 Blöcke mit ~19 Blöcken/s am Lebensende — nachrückende
   Partikel = eine über den Himmel **marschierende Kapsel-Queue = „kommt in Wellen"**.
   (b) Die Teil-1-Gauss-Textur liest als **uniforme, hartkantige Kapsel („Pille")**,
   sobald nur EIN Schacht auf dem Schirm steht: Display-Gamma + 8-bit-Additiv-
   Quantisierung schneiden den Falloff mittig entlang einer Iso-Kontur ab. Fix:
   gleiche Wind-Kur + Power-Law-Falloff mit Null-Steigungs-Fuß + deterministischer
   Alpha-Dither + längere Vertikal-Fades. Genau das war der in Teil 2 §3.3 notierte
   Follow-up-Kandidat („dann: gleiche Wind-Kur").
4. **Zweiter Auftrag** (§6): `announceNightEvent`/`clearNightEvent` senden Announcement
   + Omen-/Dawn-Cues jetzt nur an Overworld-Spieler (`AnnouncementService
   .announceToOverworld` neu); der A1-State-Sync bleibt bewusst server-weit.
5. **Dritter Auftrag** (§7): die „dunkle Struktur unter Wasser" ist **legitime
   Schiffsgeometrie** (GhostShipBuilder-Kiel/Ballast auf waterline−2), kein Fremdkörper.

Geänderte Dateien: `limbo_motes_near.json`, `limbo_motes.json`, `limbo_godray.json`,
`limbo_godray_shaft.png` (regeneriert), `limbo_mote_bokeh.png` (NEU) +
`tools/art/gen_limbo_mote_bokeh.py` (NEU), `tools/art/gen_limbo_godray_shaft.py`,
`LimboAmbience.java` (NEAR_MOTES-Ring + Javadocs), `EclipseSpawner.java`,
`AnnouncementService.java`.

## 2. Beweiskette: die Umbral-Fehlspur

Die Auftrags-Fakten (none → weg in ~12 s, umbral → Quads, pale → keine) ließen einen
Event-gekeyten Producer vermuten. Live-Nachstellung ergab zunächst dasselbe Bild:

- `eclipse event set umbral` 06:51 UTC−1 → Kapsel am Himmel (`/tmp/verify_capsule_umbral.png`),
  `set none` + 18 s → weg (`/tmp/verify_capsule_none.png`).

Dann der Gegenbeweis:

1. **Kapseln erscheinen auch unter `none`**: beim manuellen Godray-Test stand eine
   Ambient-Kapsel im Bild, während das Event `none` war
   (`/tmp/verify_godray_manual_t14.png`, rechts, Azimut ~+35°).
2. **`LimboAmbience` hat null Event-Kopplung**: kein Fenster liest `NightDreadFx`
   (alle Getter sind ohnehin overworld-gegated und melden in Limbo `none`); die
   Fenster laufen in Limbo IMMER.
3. **Keine Cues kamen mehr an**: Server-Log `Announce payload sent to 0 overworld
   players … umbral` (05:46:26 / 05:51:18) — der Omen-Cue ist im selben Codepfad
   gefiltert; Client-Log zeigt im Fenster nur den A1-Sync
   `[w6a-nightsync] event=umbral day=13 (nightfall)` (by design, §6).
4. **Zeitkonstanten passen zur Koinzidenz**: GODRAYS-Kadenz 90–130 t bei maxLive 2 →
   Emitter-Standzeit ~9–13 s, Partikel-Lifetime 100±20 t → eine Kapsel-Position
   verschwindet nach ≤ ~19 s VON SELBST — die „binnen ~12 s nach `set none` weg"-
   Messung diskriminiert nicht. Ebenso NEAR_MOTES (Kadenz 70–100 t, Life 90+30 t).

## 3. Producer A: `NEAR_MOTES` — die Kreuz-Cluster

### 3.1 Optik-Zerlegung (Referenz `/tmp/f107_umbral_zoom.png`, `/tmp/f107_umbral_t37.png`)

Die 8×8-`purple_wisp`-Alpha-Maske ist ein Plus: 4×4-Kern (α 189), 1-Texel-Ring
(α ~120), **Ecken transparent**. Auf einem 0.55–0.85-Half-Edge-Quad, das bis an die
Kamera drandriftet, wird jedes Texel bei Veils Nearest-Sampling (blur=false, Teil 1 §5)
zu einem harten, uniform gefüllten Rechteck von zig Pixeln: der Kern = das große helle
Rechteck, der Ring = der dunklere Rahmen, die fehlenden Ecken = **das Kreuz**. Ein
zweites, leicht gedrehtes Quad daneben liefert die „eine Kante gekippt"-Beobachtung.
Genau dieses Bild zeigt der Referenz-Zoom — es ist die Textur-Signatur des Sprites,
nicht Photon-, Entity- oder POSITION_COLOR-Geometrie. (Der Kapsel-Fleck ganz links in
`f107_umbral_t37.png` ist Producer B, §4.)

### 3.2 Drift-Mathe (Teil-2-Formeln, §2/§3 dort)

Vorher: Ring 3–7, Sphere-Radius 1.75, Half-Edge ≤ 0.85, Wind 0.012/t² ungedämpft
(JSON-`strength` wird von Veil 4.3.0 nie angewendet), t_max 120 t → **Drift ≤ 87.1
Blöcke, Clearance −86.7** — die Motes fegten zwangsläufig durch die Kameraebene, immer
neue Partikel = „kommt in Wellen ganz links am Rand" beim Schwenk.

### 3.3 Fix (`limbo_motes_near.json`, NEU `limbo_mote_bokeh.png`, `LimboAmbience.java`)

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| `sprite` | `purple_wisp.png` (8×8) | **`limbo_mote_bokeh.png`** (128×128, NEU) | Weiche Out-of-Focus-Scheibe: flacher dunkler Kern + breiter Rim-Falloff, Rand-Texel exakt 0, vorverdunkelte Violett-Familie (#8C69C8→#5A3C96), Peak-α 158 < Wisp-Kern 189 |
| `wind_speed` | 0.012 | **0.0004** | Wind-Kur aus Teil 2 |
| NEU `veil:drag` | — | **0.96** | Terminal-v = a·d/(1−d) ≈ 0.19 Blöcke/s; Drift ≤ ~1.15 |
| Shape (Sphere-Ø) | 3.5 × 2.0 × 3.5 | **2.0 × 1.5 × 2.0** | Spawn-Offset Richtung Kamera 1.75 → 1.0 |
| `max_particles` / `rate` | 12 / 8 | **6 / 13** | 1–2 große Scheiben statt Pulk; Bokeh ist Garnitur |
| α-Peak | 0.07 | **0.05** | leiser; additiv können Scheiben nie decken |
| Window-Ring (`LimboAmbience`) | 3.0–7.0 | **4.5–8.0** | Clearance = 4.5 − 1.0 − 0.85 − 1.15 ≈ **+1.5** |

Look-Beleg nach Fix: weiche runde Bokeh-Scheiben statt Kreuz-Cluster
(`/tmp/verify_umbral_t15.png` links, `/tmp/soak_t45.png`).

### 3.4 Gleiche Wind-Kur für `limbo_motes` (Mid-Layer)

Wind 0.015 → **0.0006** + `veil:drag` **0.96** (Drift 91.6 → ≤ ~1.7 Blöcke). Sprite
bleibt `purple_wisp`: bei Half-Edge ≤ 0.085 ist das ganze Quad kleiner als ein
Bildschirm-Pixelblock in typischer Distanz — Texel können nicht auflösen. Look
(Dichte/Farbe/α 0.28) unverändert.

## 4. Producer B: `GODRAYS` — die Kapsel-Wellen

### 4.1 Identifikation

- Einzelne Ambient-Kapseln: `/tmp/verify_umbral_pan2_2.png` + Zoom
  `/tmp/verify_capsule_zoom.png` — uniforme Füllung, harte Kante, runde Kappen,
  „Waist"-Stufe wo zwei Quads überlappen; Geometrie (Ring 14–28, y Wasser+8..15,
  Quad-Kante 7–9 Blöcke) passt exakt auf das GODRAYS-Fenster.
- **5×-Stack-Test** (`/tmp/verify_godray_x5.png`): fünf manuell übereinander gespawnte
  `limbo_godray` (via `/eclipsefx emitter`) rendern dieselbe Kapsel hell und WEICH —
  bei 20 Quads liegt auch der Gauss-Tail über der Sichtbarkeitsschwelle. Ein
  EINZELNER Schacht (4 Quads à Tint 0.06) zeigt nur den Kern → harte Pille.
  Identität bestätigt, kein Entity-/Photon-Producer nötig.

### 4.2 Zwei Altlasten aus Teil 1

1. **Ungedämpfter Wind 0.008/t²** (die Teil-2-Bytecode-Erkenntnis „`veil:wind` ist
   ungedämpfte Beschleunigung, `strength` wird ignoriert" datiert NACH dem Teil-1-
   Godray-Retune): Drift a·N(N+1)/2 = **58 Blöcke** bei N=120, Endgeschwindigkeit
   ~19 Blöcke/s. Der Emitter emittiert kontinuierlich → am Himmel zieht eine Kette
   versetzter Kapseln vorbei — die gemeldeten „Wellen ganz links am Rand" beim
   Schwenk (Teil 2 §3.3 hatte genau das als Restrisiko notiert und die Wind-Kur als
   Follow-up definiert).
2. **Wahrnehmungs-Hartkante der Gauss-Textur**: additives Quad über fast-schwarzem
   Himmel. Display-Gamma expandiert die ersten ~2 % linearer Luminanz auf ~17 %
   wahrgenommene Helligkeit, und Beiträge < 1/255 pro Draw quantisiert das 8-bit-
   Target auf exakt 0. Der Gauss-Tail durchquert dieses Fenster in Bruchteilen eines
   Blocks → sichtbar/unsichtbar kippt entlang einer scharfen Iso-Alpha-Kontur =
   Pillen-Rand (Zoom-Messung: Übergang ~2–4 px auf einem ~110-px-Quad).

### 4.3 Fix (`limbo_godray.json`, `gen_limbo_godray_shaft.py` + PNG regeneriert)

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| `wind_speed` | 0.008 | **0.0005** | Wind-Kur; Richtung (0.4, 0, 1) bleibt |
| NEU `veil:drag` | — | **0.96** | Terminal ~0.25 Blöcke/s — „hängende, langsam sinkende Schächte" wieder wahr; Drift ≤ ~1.4 statt 58 |
| Textur-Falloff (H) | Gauss σ=0.34 | **(1−\|nx\|)^1.5** | Power-Law landet mit Steigung 0 AUF α=0 — der Fuß streckt sich über das äußere Quad-Viertel, egal wo die Sichtbarkeitsschwelle schneidet |
| Textur-Dither | — | **±3 α-Stufen, deterministisch (x,y-Hash), unter h=0.02 ausgeblendet** | Bricht die Quantisierungs-Kontur in feines Korn (~4 px bei Ring-Distanz) statt einer Linie; Rand-Texel bleiben exakt 0 |
| Vertikal-Fade `V_FADE` | 0.22 | **0.34** | Killt die „Waist"-Stufe überlappender Schacht-Quads |
| Textur-Peak-α | 0.80 | **0.55** | Flach gesättigter Kern war die halbe Pillen-Optik |
| JSON-Tint-α | 0.06 | **0.05** | Zusammen mit Peak: Einzelschacht ≈ 2 % Kern-Luminanz — leiser Schimmer statt Pille |

Look-Beleg nach Fix: Einzelschacht = dunkler, körnig ausgefranster Licht-Schimmer,
nahezu ortsfest über 5 s (`/tmp/verify_newgodray_t3.png`/`_t8.png`, 6×-Stretch
`/tmp/verify_dither_t15_stretch.png` zeigt das Dither-Korn statt Iso-Kante); Ambient
(`/tmp/soak2_t42.png` oben rechts) liest als hängender Nebelschacht.

## 5. Abgehakte Verdächtige / Leads des Auftrags

- **`NightDreadFx.eventDay()`**: liefert nur den Tages-Stempel (int) — einziger
  ungegateter Getter, alle Aufrufer intern/unkritisch; der rohe Event-String hat
  keinen ungegateten Accessor. Kein Visual-Producer.
- **Wave 6A A5 „The-Other-Nähe-Flüstern"**: GEFUNDEN — `TheOtherEntity
  .tickProximityWhisper()` (Probe `[w6a-otherdread]`). **Nur Sound** (AMBIENT_CAVE am
  Mob + WARDEN_HEARTBEAT am Ohr, private `ClientboundSoundPacket`), Entity-gebunden,
  `level.players()`-gescoped; The Other spawnt ausschließlich im Overworld
  (Pale Night). Keine Optik, kein Dimension-Leak.
- **`PlayerFxPhotonRows`**: liest keinerlei Nacht-Status (Herz-/Rebirth-/Contract-/
  Ghost-/Glide-Rows, alle event-/zustandsgekeyt). Kein Kandidat.
- **Server-Spawns auf Umbral**: `EclipseSpawner` ist durchgehend `server.overworld()`-
  gescoped (Stalker/Gazer/The Other); `SkillService`/`TimelineInspector`/
  `EclipseCommands` lesen das Event nur für XP/Text. Kein Spawn am Limbo-Spieler.
- **Quasar-Beine von Server-Cues**: `wave3_night_omen`/`wave6_dawn_release` sind
  One-Shot-Photon-Rows mit `quasar none` — und erreichen Limbo seit §6 gar nicht mehr.
- **Entity-Test** (Killer-Diagnostik 2): nicht mehr nötig — Producer per
  5×-Stack/Einzelspawn eindeutig als client-seitige Quasar-Ambience identifiziert.

## 6. Zweiter Auftrag: Nacht-Announcements/Cues → nur Overworld

**Fix** (`EclipseSpawner.java`, `AnnouncementService.java`):

- `announceNightEvent`: Announcement über neues `AnnouncementService
  .announceToOverworld` (iteriert `server.overworld().players()`, loggt
  `Announce payload sent to N overworld players`) + Omen-Cue-Schleife ebenfalls über
  `server.overworld().players()`.
- `clearNightEvent`: `wave6_dawn_release`-Cue + Exhale-Sound ebenso gefiltert
  (Probe `[w6a-dawnrelease] players=N`).
- **`NightPayloads.broadcast` (A1-Sync) bleibt bewusst server-weit** — Auftrag
  bestätigt: die Client-Renderer sind via `NightDreadFx` dimension-gegated, und wer
  mitten in der Nacht ins Overworld wechselt, muss den State bereits halten. Nur die
  MOMENT-Cues (Karte/Omen/Dawn) sind Overworld-Lore.
- `AnnouncementService.announce` (alle anderen Lanes) unangetastet.

**Live-Beweis** (Server-Log `/tmp/server_f107.log`, Client `/tmp/client_f107.log`):

```
05:46:26 Announce payload sent to 0 overworld players: title=announce.eclipse.night.umbral.title …   (Dev in Limbo)
05:46:26 [w6a-nightsync] event=umbral day=13 (nightfall)                                             (Sync kommt an — by design)
05:49:39 Announce payload sent to 1 overworld players: title=announce.eclipse.night.pale.title …     (Dev im Overworld)
```

Screenshots: Limbo umbral-Set OHNE Karte/Chat/Omen (`/tmp/verify_umbral_t15.png`);
Overworld pale-Set MIT „PALE NIGHT"-Karte + Typewriter „Something wearing your face
walks the dark." + Omen-Orbs (`/tmp/verify_ow_pale_t2.png`, `/tmp/verify_ow_pale_t5.png`).

## 7. Dritter Auftrag: Struktur unter der Wasseroberfläche = Schiffsrumpf

Video-Befund 01:38–01:52 (`/tmp/f107_frame_01_40/46/52.png`): dunkle, flache, blockige
Fläche unterhalb der Wasserlinie am Rumpf. Verifikation:

- RCON-Block-Proben am sichtbaren Bereich: `dark_oak_planks` (Rumpfwand),
  `blackstone` + `mud_bricks` (Kiel-/Ballast-Muschelbewuchs) auf y=46–48 — exakt das
  `GhostShipBuilder`-Blueprint (Kiel auf waterline−2 = 46, Wasserlinie 48). Kein
  Deepslate (die alte Testplatte y=50 bleibt entfernt, Gegenprobe leer).
- Blickwinkel-Fotos seitlich auf Wasserhöhe + von oben: `/tmp/f107_hull_side.png`,
  `/tmp/f107_hull_side_above.png`, `/tmp/f107_hull_underwater.png`,
  `/tmp/f107_hull_bow.png` — die „Struktur" ist der reguläre Unterwasser-Rumpf.

**Legitime Schiffsgeometrie — kein Fremdkörper, keine Änderung nötig.**

## 8. Gates

- `./gradlew compileJava processResources --console=plain` → **BUILD SUCCESSFUL**
  (Java-Änderungen: `EclipseSpawner`, `AnnouncementService`, `LimboAmbience`).
- JSON-Syntax-Check aller 7 Limbo-Emitter (`json.load`) → OK.
- Sprite-Generatoren doppellauf-**byteidentisch**: `gen_limbo_mote_bokeh.py` und
  `gen_limbo_godray_shaft.py` (md5 `e458f65e…` beide Läufe). Keine `.fx`-Dateien
  angefasst (fxlib nicht betroffen).
- Kein Client-Neustart nötig: Emitter-JSONs + Texturen laden über F3+T-Reload
  (Veil-Resource-Listener); Java-Änderungen sind server-seitig bzw. Javadoc-only.

## 9. Live-Verifikation (Event-Zyklus + Schwenks, frisch verbundener Client)

Setup: Server+Client neu gestartet (alle Fixes aktiv), Dev auf Deck (−1.5, 52.5, 0.5).

1. **Baseline `none`** 20 s: sauber (`/tmp/verify_none_baseline.png`).
2. **`set umbral`**, 3 Soaks über ~3 min inkl. 2× 360°-Schwenk + Himmel-Blick
   (t15/t37/t40/t75, `/tmp/soak_t45.png`, `/tmp/soak_pan_*.png`, `/tmp/soak2_t42.png`,
   `/tmp/soak2_sky_t22.png`): **keine Kreuz-Cluster, keine harten Kapseln, kein
   Wellen-Marsch** — nur weiche Bokeh-Scheiben, winzige Motes, gedimmte körnige
   Godray-Schimmer, Eclipse-Ring/Smoke/Godray-Sky-Pass wie designt.
3. **Video**: `/opt/cursor/artifacts/f107_part3_limbo_umbral_pan_after_motes_and_godray_fix.mp4`
   (langsamer 360°-Schwenk unter aktivem Umbral nach Fix).
4. **Announcements**: §6-Beweise (0 Empfänger in Limbo / 1 im Overworld inkl. Karte).
5. End-Zustand: Event auf `none` zurückgesetzt; manuelle Test-Emitter per
   Dimensions-Roundtrip geräumt (Veil cleart den Particle-Manager beim Level-Wechsel).

## 10. Offene Punkte

- **Godray-Look-Feintuning ist Geschmackssache**: der Einzelschacht ist jetzt bewusst
  leise (~2 % Kern-Luminanz + Dither-Korn). Falls die nächste Abnahme mehr „Präsenz"
  will: Tint-α moderat anheben (0.05 → 0.06) — die Kanten-Physik (Power-Law + Dither)
  bleibt davon unberührt.
- `limbo_motes` behält bewusst das 8×8-Wisp (Quads unter Pixelgröße, §3.4) — sollte
  je ein Mote-Layer vergrößert werden, zuerst auf eine weiche Textur wechseln.
- Die Teil-2-Tabelle §3.1 führt für GODRAYS/MOTES/NEAR_MOTES noch die alten
  Drift-Werte als „unangetastet" — dieser Report ist die Fortschreibung; die dortige
  §3.3-Restrisiko-Notiz ist hiermit eingelöst.

## 11. Nachtrag Runde 2 — Bokeh-Dichte (Video-Review-FAIL des Teil-3-Videos)

Der Review des §9-Videos meldete FAIL: bei 00:00–00:13 / 00:25–00:38 hängen links
und rechts vom Mast „große violette Massen" („large low-poly capsule shapes hovering
on the deck"). Frame-Zoom (`/tmp/p3_zoom_left2.png`): 5–6 überlappende WEICHE Kreise
der neuen `limbo_mote_bokeh`-Textur — Kanten-Physik gefixt, aber die Scheiben
STAPELN sich zu einer traubenförmigen, hellen, ~2–3 Blöcke großen Gesamtmasse.

### 11.1 Ursache des Stapelns (beide „Massen"-Producer, gleiche Anatomie)

- **NEAR_MOTES**: bis zu 6 gleichzeitige Scheiben à 1.1–1.7 Blöcke (Steady-State
  Lifetime/Rate ≈ 105/13 ≈ 8, Cap 6 dauerhaft ausgeschöpft) in einer nur 2 Blöcke
  breiten Spawn-Sphäre → nahezu deckungsgleiche Projektion, additiv aufgehellt.
- **GODRAYS** (im Runde-2-Soak als zweite Traubenquelle identifiziert,
  `/tmp/r2_zoom_t02_topright.png`): ~3.3 gleichzeitige 7–9-Block-Schaft-Quads
  (110/30) im nur 0.9 Blöcke breiten Spawn-Zylinder — die runden Schaft-Kappen auf
  verschiedenen Höhen lasen als gelappte Masse am Bildrand.

### 11.2 Fix (JSON-only; Ring 4.5–8 in `LimboAmbience.java` unverändert, nur Javadoc)

`limbo_motes_near.json`:

| Parameter | vorher | nachher | Wirkung |
| --- | --- | --- | --- |
| `rate` (Ticks/Spawn) | 13 | 35 | Spawn-Stagger 0.65 s → 1.75 s |
| `max_particles` | 6 | 2 | Worst-Case-Gruppe = 2er-Paar statt 6er-Traube |
| `base_particle_size` ± Variation | 0.55 ± 0.3 | 0.32 ± 0.12 | Quad 1.1–1.7 → 0.64–0.88 Blöcke |
| Sphere `dimensions` | [2.0, 1.5, 2.0] | [3.8, 2.0, 3.8] | gleichzeitige Scheiben separieren räumlich |
| `wind_speed` | 0.0004 | 0.0002 | Lifetime-Drift ≤ ~0.58 statt ~1.15 Blöcke |
| Alpha-Peak (2 Stützpunkte) | 0.05 | 0.035 | 2er-Überlappung summiert nur noch 0.07 |

Clearance-Fortschreibung (§3.3-Formel, Ring unverändert 4.5–8):
4.5 − 1.9 (Sphäre) − 0.44 (Half-Edge max) − 0.58 (Drift max) = **+1.58 Blöcke** —
die breitere Sphäre ist durch halbierten Wind + kleinere Quads finanziert, die
Teil-3-Garantie (≥ ~1.5) hält ohne Java-Verhaltensänderung (kein Client-Neustart,
F3+T genügt).

`limbo_godray.json` (gleiche Defektklasse, gleiche Hebel):

| Parameter | vorher | nachher | Wirkung |
| --- | --- | --- | --- |
| `rate` | 30 | 60 | Steady-State ≈ 1.8 → meist EIN Schaft je Emitter |
| `max_particles` | 4 | 2 | kurzer Crossfade-Overlap statt 3–4er-Stapel |
| Cylinder `dimensions` | [0.9, 9.5, 0.9] | [6.0, 9.5, 6.0] | koexistierende Schäfte separieren als eigene Strahlen |

Godray-Clearance unkritisch: Ring 14 − 3.0 (Spawn-Radius) − 4.5 (Half-Edge) ≥ ~6.5 Blöcke.
Größe/Alpha der Schäfte unangetastet — der Einzelschaft-Look hatte die Abnahme bestanden,
nur das Stapeln nicht.

### 11.3 Gates (Runde 2)

- `python3 -m json.tool` auf beiden Emitter-JSONs: OK.
- `./gradlew processResources compileJava`: BUILD SUCCESSFUL (Werte in
  `build/resources/main/...` verifiziert; Java-Diff ist Javadoc-only).

### 11.4 Live-Verifikation (Runde 2; Reload je Schritt per F3+T, Client-Log-Marker 06:37:49)

- **Vorher-Beleg** (altes JSON noch aktiv): `/tmp/r2_baseline_prereload.png` — Traube
  aus 2–3 großen Scheiben links vom Mast auf Deckhöhe, wie im Review.
- **Soak 1** (nur Motes-Fix, max 3): 12 Frames à 8 s `/tmp/r2_soak_t01..t12.png` —
  Deck-Ebene traubenfrei; ABER Godray-Bündel am oberen Bildrand als Restmasse
  identifiziert (`/tmp/r2_zoom_t02_topright.png`, `/tmp/r2_zoom_t03_right.png`) →
  Godray-De-Stack nachgezogen.
- **Soak 2** (beide Fixes): `/tmp/r2b_soak_t01..t12.png` + 6 Pan-Winkel
  `/tmp/r2b_pan_yaw{-135,-45,0,45,90,180}.png` — Godrays einzeln/als getrennte
  Doppelstrahlen; Motes einzeln, vereinzelt 3er-Grüppchen am Bildrand (distinkt,
  aber konservativ nachgeschärft: `max_particles` 3 → 2).
- **Finaler Soak** (Endstand): `/tmp/r2c_final_t1..t8.png` +
  `/tmp/r2c_final_pan0.png`, `/tmp/r2c_final_pan135.png` — **keine zusammenhängende
  Masse > ~1 Block mehr, in keinem Frame**. Nachher-Zooms: einzelne durchscheinende
  Scheibe auf Deckhöhe (`/tmp/r2_zoom_after_single_mote.png` — Planken/Fässer durch
  die Scheibe sichtbar) und Worst-Case-2er-Paar mit sichtbarer Taille
  (`/tmp/r2_zoom_after_mote_pair.png`).

Abnahmekriterium erfüllt: Near-Motes lesen als vereinzelte kleine weiche Lichtpunkte
im 4.5–8er-Ring; Godrays als einzelne schlanke Strahlen.
