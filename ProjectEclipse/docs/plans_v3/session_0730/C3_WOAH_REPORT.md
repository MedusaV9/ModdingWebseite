# C3 — Woah-Sets Feinschliff (F-062, Welle 13)

Team C3, Session 0730. Feinschliff aller 5 Woah-Map-Features auf Welle-13-Niveau.
Basis: FX_CENSUS_WAVE13.md §4 (`woah.*`-Zeilen) + §7 Zeile C3. Datei-Besitz: alles
unter `woah/`, die zugehörigen Photon-Generatoren (`chrono_fx.py`, `echo_grove_fx.py`,
`resonance_fx.py`, `woah_dome_fx.py`, `woah_gravity_fx.py`) und die woah-eigenen
Veil-Pipelines (`dome_shell`, `glitch_dome`). `worldgen/end` (B3) nur gelesen.

---

## 1. Gravitationsbruch (`woah.gravityrift`) — Inversions-Beat mit Massen-Trägheit

**Ist-Stand:** `GravityRiftOrbitals.poseAt` fährt den Orbit als
`phase0 + omega·gameTime` — konstante Winkelgeschwindigkeit, die Inversion senkt die
Stücke nur ab (`fallDepth`-Drop) und boostet den Tumble. Zwei Befunde:

1. Kein Richtungswechsel — der Zensus-Beat („Orbit kehrt Drehrichtung sichtbar träge
   um") fehlt komplett.
2. Der Tumble-Boost ist `spinRate · gameTime · (1 + 4·envelope)` — der Term skaliert
   mit dem absoluten Weltalter: bei gameTime ≈ 10⁶ bedeutet ein Envelope-Delta von
   0.5 zwischen zwei 40-t-Fenstern ≈ 10⁴ rad Sprung → unkontrollierter Spin-Blur,
   der mit jedem Spieltag schlimmer wird.

**Änderungen:**

- **Träge Orbit-Umkehr (stateless):** Orbitwinkel wird `phase0 + omega·Θ(t)` mit
  Θ(t) = t − 2·∫reversal − completedBefore·D. Richtungprofil pro Stück:
  smoothstep-Rampe +1→−1 über `flipTicks`, voller Retrograd-Lauf, Rückrampe −1→+1
  endet exakt bei τ = 300 t (INVERT_TOTAL). `flipTicks = 25 + mass01·95` t —
  leichtester Kies dreht in 25 t um, die schwersten Moosdecks brauchen 120 t
  (W13-B3-Massegesetz: `mass01` aus ∛(sx·sy·sz), normiert 0.25→3.3 Blöcke).
  |dir| ≤ 1 hält das 90°-Fenster-Gesetz unverändert ein.
- **Persistenz ohne Snap:** Jedes Fenster hinterlässt eine Orbit-Schuld
  D = 2·(300 − flipTicks) Ticks (380–550 t je Masse). `GravityRiftState` bekommt ein
  neues Long `invertCount`; zusammen mit dem bereits persistierten
  `lastInvertGameTime` ist Θ(t) über beliebig viele Fenster hinweg eine absolute
  Funktion der Spielzeit — Restart-/Overwrite-sicher, kein Snap beim Fensterwechsel.
- **Tumble-Boost-Fix (Zeitunabhängigkeit):** Boost-Winkel wird
  `spinRate · boostFactor · ∫envelope(τ)` (∫ = 210 t am Fensterende) statt
  `· gameTime · (1+boost)`. `boostFactor = min(4, 0.0742/|spinRate| − 1)` deckelt den
  Sweep auf ≤ 170°/40-t-Fenster (Anti-Slerp-Aliasing); Schuld-Buchhaltung teilt sich
  den `invertCount`-Mechanismus mit dem Orbit.
- **Photon-Politur:** `gravity_invert_burst` erhält einen `retro_swirl`-Emitter
  (18 Motes, Ring r 9.5, orbital −0.05, Delay 12 t, Life 30–44 t) — die Partikel
  erzählen die Umkehr auf dem gleichen Beat mit; HDR ≤ 2.0 (Stacking-Gesetz).

## 2. Mansion-Glitch-Dome (`woah.mansiondome`) — 3-Klassen-Shatter + Touch-Puls

**Ist-Stand:** `DomeShatterFx` rollt alle 240 Scherben aus EINER Verteilung
(2.6 ± 0.35 Platte, Life 80–120 t, Flug 0.35–0.85 R, Sag 5–14, Tumble 0.75–2.5 U) —
kein Masse-Lesen, keine Anker-Akzente. `dome_shell.json`/`.fsh` hat KEINEN
Touch-Puls-Uniform (geprüft; `glitch_dome.fsh` ebenfalls nicht) → der Zensus-§1-Punkt
(„Touch-Intersection-Puls, Uniform-Puls von Java") wird neu gebaut.

**Änderungen:**

- **3-Klassen-Shatter (EndShatterSequence-Muster, B3):** Größe wird ZUERST gerollt
  (1.7–3.5 Blöcke, pow-1.6-Bias Richtung Splitter), `mass01 = (size−1.7)/1.8`;
  daraus abgeleitet: Flugdistanz ×(0.85→0.40 R leicht→schwer), Up-Bias 1.0→0.30,
  Sag 4→16 Blöcke (schwer fällt TIEF), Life 80→130 t (schwer = langsam), Tumble
  2.5→0.6 Umdrehungen. Jede ~12. Scherbe ist ein **Keystone**: ×2.4 Platte
  (6.2 Blöcke), immer Tinted Glass, Sag 18, Life 140 t, ~0.2 Umdrehungen — der
  Anker-Brocken, an dem das Auge die Masse des Felds abliest (W12-Akzentgesetz).
  Klassen emergieren aus der stetigen Ableitung, keine Hard-Branches (außer Keystone).
- **Dome-Touch-Puls:** `dome_shell.fsh` + `dome_shell`-Feeder bekommen den
  Uniform-Satz `TouchPos` (kamera-relativ, VolCenter-Gesetz), `TouchAge` (s),
  `TouchStrength` (0..1). `MansionDomeClient` erkennt Berührungen client-seitig:
  lokaler Spieler-Edge-Trigger (|dist−R| < 2.0, Cooldown 15 t) + Projektile in
  Hüllen-Nähe. Shader zeichnet einen expandierenden Fresnel-Ring um den Touch-Punkt
  (Chord-Distanz auf der Kugel, Front 7 Blöcke/s, Bandbreite 1.4 + 2·age, Fade
  1.1 s) — additiv im Dome-Grün, Detail-0/reducedFx-gated wie der Rest des Passes.

## 3. Chrono-Stase (`woah.chronostasis`) — Zeitlupen-Drift + Flacker-Beat

**Ist-Stand:** ALLE eingefrorenen Loops fahren `startSpeed 0` (Frozen-Rezept) — die
Szene steht 100 % still; `dischargeFlash()` ist ein monotoner 14-t-Decay (Zensus:
„Release-Beat verstärken").

**Änderungen:**

- **Zeitlupen-Drift:** `chrono_dust_shimmer` bekommt einen zweiten Emitter
  `drift_motes` (16 max, GPU-instanced): Speed **0.05–0.09 Blöcke/SEKUNDE**
  (= 0.0025–0.0045 B/t — sichtbare Zeitlupe erst beim Fixieren), Life 160–260 t,
  Kugel r 8, world space, Rate 0.07/t (≈ 14.7 sustained — Headroom unter dem Cap,
  Polish-Iteration). Der Kontrast steht-vs-kriecht macht die Stase lesbar
  „gefroren, nicht pausiert".
- **Flacker-Beat beim Brechen:** `ChronoZoneState.dischargeFlash()` wird ein
  3-Zacken-Stotterblitz: 1.00 @ t0 (8 t Decay) → 0.55 @ t14 (7 t) → 0.30 @ t26
  (8 t) ≈ 1.8 Hz — deutlich unter der 3-Hz-Fotosensitivitätsgrenze; Feeder/Uniform
  (`Flash` in `chrono_grade`) bleiben unverändert — ein Uniform-Puls, nie ein
  zweiter Pass.

## 4. Resonanzfeld (`woah.resonance`) — Wellen vom Zentrum + Display-Vibration

**Ist-Stand:** Monolith-/Altar-Displays (≈ 110–140) stehen nach dem Spawn statisch;
Pulse laufen nur als Brightness-Roundtrips + Photon-Hops zwischen Nachbarn. Nichts
läuft vom ZENTRUM nach außen.

**Änderungen:**

- **Neuer Server-Choreograph `ResonanceWaveFx`:** Beat-Raster
  `gameTime % 600 == offset(anchor)` (stateless, deterministischer Hash-Offset),
  nur bei `playersNear`. Wellenfront läuft mit 0.45 Blöcke/t vom Altar (r 0→~44
  über ~98 t). Erreicht die Front einen Monolithen (XZ-Distanz), vibriert er 24 t:
  Push-Kadenz 2 t, Tremor-Periode 8 t (2.5 Hz), Amplitude 0.07 Blöcke radial mit
  sin-Hüllkurve (0 an beiden Enden — kein Snap, Rückkehr exakt auf die
  Basis-Transformation). Basis-Transforms werden beim Spawn registriert
  (UUID→Transformation; Self-Heal re-registriert automatisch). Budget: Treffzeiten
  folgen dem Doppelring (4 innen r 13.5–16.5 → t 30–37, 5 außen r 24–28 →
  t 53–62); schlimmster Fall = ein ganzer Ring zittert gleichzeitig, 5 Kristalle
  × 9–15 Displays auf 2-t-Kadenz ≈ 30–40 Pakete/t gemittelt für ≤ 33 t/Welle —
  weit unter dem 240-Display-DomeShatter-Burst. **MSPT-Guard:** avg > 45 ms →
  Wellen-Start übersprungen (StormDebrisFx-Muster).
- **Photon `resonance_wave_ring`:** Boden-Ring am Altar, Radius 0→36 Blöcke über
  80 t — exakt die Server-Frontgeschwindigkeit 0.45 B/t (near-linear-eased
  Bézier, Abweichung ≤ 0.6 Blöcke Radius, LINT-LINEAR-CURVE-konform) + Glint-Saum
  DIREKT auf der Front (function-shape mit t-Sweep `t·36`, ~7 alive); HDR ≤ 1.45
  (Stacking-Gesetz, Dauer-Garnish). Neuer Cue `CUE_RESONANCE_WAVE` + Row (kein
  Quasar-Fallback — Ambient-Garnish, kein Gameplay-Telegraph).

## 5. Echo-Hain (`woah.echogrove`) — Flut-Beat als kontinuierliche Radial-Welle

**Ist-Stand:** `MemoryFloodService.tickFlood` pusht die 4 Radius-Bänder bei
t = 0/1/2/3 — mit 20-t-Interpolation wachsen praktisch ALLE ~620 Overlays
gleichzeitig; der „Welle vom Zentrum"-Read existiert nicht. `echo_spores` (1400
Partikel, Zensus C1) fährt bereits `use_gpu_instance=True` — geprüft, kein Handlungsbedarf.

**Änderungen:**

- **Flut-Beat:** `OverlaySpec` bekommt ein `dist`-Feld (exakte XZ-Distanz zum
  Baum). `pushWave` setzt pro Display
  `interpolationDelay = dist/distMax · 36 t` (Grow, innen zuerst) bzw.
  `(distMax−dist)/distMax · 36 t` (Shrink, außen zuerst — die Flut zieht sich in
  den Baum ZURÜCK). Die Front läuft ≈ 30 Blöcke in 36 t (0.83 B/t) als
  KONTINUIERLICHE Welle statt 4 Stufen; kostet NULL Extra-Pakete (der Delay reist
  im selben Transform-Push mit). `shrinkStart` rückt um die Reisezeit vor
  (`hold − 20 − 36`, geklemmt auf ≥ hold/2 für kurze Dev-Floods); Voll-Bloom-Hold
  bleibt ≈ 48 t.

---

## Validierung

- `python3 tools/photon/fxlib.py validate --lint` — Baseline vor Änderungen:
  0 NEW error/warn, 27 grandfathered, 129 advisory. Ziel: identisch (0 NEUE).
- Geänderte Generatoren erneut ausgeführt (write() round-trip + `.fxproj`-Sibling).
- `./gradlew compileJava`.

## Polish-Iteration (durchgeführt)

Kritischer Pass nach der Erst-Implementierung — 4 Befunde, alle gefixt:

1. **Chrono `drift_motes` Sättigung:** Rate 0.08/t × Ø-Life 210 t = 16.8 sustained
   > Cap 16 → permanenter Spawn-Churn (Motes sterben ehe die Zeitlupe lesbar wird).
   Rate auf 0.07/t gesenkt (≈ 14.7 sustained, Headroom 8 %).
2. **`resonance_wave_ring` LINT-LINEAR-CURVE:** die exakt lineare
   size-over-lifetime-Kurve riss ein NEUES Lint-Finding. Fix: near-linear-eased
   Bézier-Segment (0, 0, 0.25, 0.30, 0.75, 0.70, 1, 1) — Kontrollpunkte ~0.035
   neben der Chord, Radius-Abweichung von der Server-Front ≤ 0.6 Blöcke; 0 neue
   Findings.
3. **Resonanz-Budget ehrlich gerechnet:** die erste Javadoc-Schätzung („≤ 2
   gleichzeitig") ignorierte, dass die Ring-Radien nur 3–4 Blöcke streuen — bei
   0.45 B/t liegen die Treffzeiten eines Rings 7–9 t auseinander, das
   24-t-Fenster überlappt also ringweise. Worst Case korrekt: 5 Kristalle
   gleichzeitig ≈ 30–40 Pakete/t gemittelt (Javadoc + Report korrigiert; bei
   9 Monolithen und 30-s-Raster unkritisch, MSPT-Guard bleibt davor).
4. **Gravity-Tumble-Boost gedeckelt:** `boostFactor` klemmt den geboosteten
   Spin auf ≤ 170°/40-t-Push-Fenster — ohne Deckel aliast der Slerp bei den
   schnellsten Kies-Stücken (>180°/Fenster wählt die kurze Gegenrichtung).

## Ergebnis-Nachträge (nach Implementierung)

- `python3 tools/photon/fxlib.py validate --lint`: 267 Dateien, **0 NEW
  error/warn, 27 grandfathered** (Baseline unverändert), 128 advisory; alle
  geänderten/neuen `.fx` über Generatoren + `write_fxproj` regeneriert
  (`chrono_dust_shimmer`, `gravity_invert_burst`, `resonance_wave_ring` neu).
- `./gradlew compileJava`: **BUILD SUCCESSFUL**, 0 Warnings in `woah/`.
- Alle 5 Features stateless/restart-sicher: Gravity über
  `invertCount`+`lastInvertGameTime`, Resonanz über Anchor-Hash-Raster,
  Chrono/Echo/Dome über bestehende persistierte Timelines.
- Hinweis für den Integrator: die Generator-Round-Trips (`chrono_fx.py`,
  `resonance_fx.py`, `woah_gravity_fx.py`) haben ALLE Sibling-Outputs neu
  geschrieben (Byte-Churn, z. B. `chrono_bolt_glow.fx` 1566→1565 B) —
  inhaltlich geändert sind nur `chrono_dust_shimmer`, `gravity_invert_burst`,
  `resonance_wave_ring` (neu); validate/lint deckt alle 267 Dateien.

## Test-Kommandos (In-Game, Dev-Bäume)

- Gravity: `/dev woah gravity build` → `orbitals` → `invert` (Umkehr-Beat),
  `pulse`, `status`, `tp`.
- Dome: `/dev dome arm here [radius]` → `hits <n>` → `destroy` bzw. direkt
  `shatter` (3-Klassen-Shatter); Touch-Puls: als Spieler an die Hülle laufen
  oder Projektil hindurchschießen. `reset`, `status`.
- Chrono: `/dev woah chrono spawn` (Drift-Motes in der Stase beobachten) →
  `discharge` (3-Zacken-Flacker), `tick count <n>`, `reset`, `status`.
- Resonanz: `/dev woah resonance spawn here` → warten aufs 600-t-Raster (Welle
  + Tremor), `melody print/new`, `solve`, `reset`, `status`.
- Echo: `/dev woah echo spawn` → `flood [ticks]` (Flut-Beat: Welle wächst von
  innen, zieht sich von außen zurück), `finale`, `scene <id>`, `reset`, `status`.
