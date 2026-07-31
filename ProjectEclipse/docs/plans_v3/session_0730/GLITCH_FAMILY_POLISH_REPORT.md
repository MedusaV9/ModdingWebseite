# F-102 TEAM A — GLITCH-FAMILIE TIEFENPOLITUR (GLITCH_FAMILY_POLISH_REPORT)

**Session 0731, Polish-Welle 2 (F-102).** Auftrag: die 8 Glitch-Zonen-Post-Shader — in F-100
gerade erst entstorben, aber nie einzeln poliert — bekommen je einen eigenen
Plan→Ideen→Implement→Iterations-Zyklus, sodass **jeder Effekt im Standbild sofort
unterscheidbar** ist (llvmpipe-Gesetz: Silhouette ist Pflicht, Bewegung ist Bonus).

**Geänderte Dateien (exklusiver Besitz):**

| Datei | Änderung |
|---|---|
| `include/eclipse_glitch.glsl` | + `gzHex()` (analytisches Hex-Gitter, self-contained, pure ALU) |
| `program/glitch_outline.fsh` | O6 Schwarz-Crush, O7 zweistufige Kanten-Glut |
| `program/glitch_datamosh.fsh` | D1 Slab-Ebene, D2 Motion-Smear, D3 Blocking-Seams, D4 DC-Tilt |
| `program/glitch_scanlines.fsh` | S6 Bildröhren-Wölbung + Bezel, S7 RGB-Triaden-Maske |
| `program/glitch_invert.fsh` | I1–I6 komplett neuer radialer Wellen-Motor (Invert-PULSE) |
| `program/glitch_void.fsh` | V2 Event-Horizon-Ring, V3 radialer Einzug (Sog) |
| `program/glitch_dome.fsh` | Hex-Schale auf der Blickrichtungs-Sphäre + Fresnel-Kante |
| `program/dome_shell.fsh` | echtes Hex-Interferenz-Gitter, zellweiser Touch, 4 Bare-`return`-Minen entschärft |
| `program/end_static.fsh` | 4 Static-Veil, 5 Signalverlust-Beats, 6 Interferenz-Bänder |

**Bewusst NICHT geändert:** kein Java (Uniform-Kontrakt unangetastet — alle neuen Layer laufen
über die bestehenden Feeds `Strength`/`Time`/`Detail`/`AccentColor`/`AccentAmount`/
`Origin`/`OriginMode`; Zone-Sync bleibt epsilon-gated und silent). Kein Langdrop
(`GLITCH2.json` entfällt: keine neuen Commands/UI-Strings). `rift_glitch`/`border_glitch`/
`black_hole` gehören anderen Teams.

---

## 1. Werkzeug: glslang-Harness mit echter Veil-Include-Semantik

`/tmp/f102_glitch_validate.py` (Session-Tool, nicht committet — FX_CENSUS-§8-Gewohnheit).
Unterschied zum B4-Harness (`/tmp/gzvalidate.py`): Includes werden **mit Veils echter
Splice-Semantik** expandiert — jeder `#include`-Body landet an Body-Index 0 des einbindenden
Trees (`ShaderPreProcessor.Context.include` → `addAll(0, …)`), mehrere Includes also in
**umgekehrter Quellreihenfolge** (der letzte Include liegt ganz oben). Genau die Falle, die
der Header von `eclipse_glitch.glsl` dokumentiert: `eclipse_glitch` wird ÜBER
`eclipse_common` gespleißt; ein Harness, das in Quellreihenfolge einfügt, validiert eine
Lüge. Zusätzlich: `#veil:buffer veil:camera VeilCamera` → synthetischer std140-UBO-Block;
Bare-`return`/Streu-`#`-Lint (die glsl-processor-0.2.3-NPE-Mine, die glslangValidator nicht
sehen kann — `black_hole` ist der Beweis).

Baseline vor der Arbeit: 8/8 PASS, aber Befund: **`dome_shell` trug 4 latente Bare-`return`s**
(0 Streu-`#` — noch nicht scharf, aber jedes künftige `#` in einem Kommentar hätte die
Pipeline still abgemeldet). In diesem Zyklus entschärft.

---

## 2. glitch_outline — „alles schwarz, nur grüne Outlines"

**Plan.** Flaggschiff (`/dev glitch test outline`), Kern-User-Wunsch wörtlich. Die
W13-Fassung zeichnet gut (Tiefen-Trace, signierte Silhouette), aber der Fill-Wash 0.16 lässt
die Welt GRAU statt schwarz, und die Kanten sind einstufig — sie zeichnen, sie leuchten nicht.

**Ideen.** (a) Schwarz-Crush: Gain runter + Gamma-Kurve — ANGENOMMEN. (b) Zweistufige
Kanten-Glut aus den bereits berechneten Silhouetten-Rohwerten (zwei zusätzliche smoothsteps,
**0 neue Taps**) — ANGENOMMEN. (c) Echter Gauß-Halo über zweite Kantenabtastung — VERWORFEN
(4–8 zusätzliche Depth-Taps; der Pass liegt schon bei ~10). (d) Scanner-Gitternetz — VERWORFEN
(Clutter gegen die Silhouetten-Pflicht).

**Implementierung.** [O6] `FILL_GAIN` 0.16 → 0.055 mit `FILL_GAMMA` 1.6: Mittelgrau (Luma 0.4)
behält ~1.3 % statt ~6 % — die Welt ist schwarz, nur echte Highlights atmen. [O7]
`silSkirt`/`silCore` aus `rawSil`: breiter Akzent-Saum + heißer Kern, der um `WHITE_LIFT`
Richtung Weiß gehoben wird — überfahrener Phosphor.

**Iteration 1.** Skirt-Einsatz 0.06 war zu niedrig (Block-Treppchen glimmen flächig und
untergraben den Crush) → Band auf 0.10–0.60. `WHITE_LIFT` 0.45 kippte den Kern nach Cyan-Weiß
(Blau-Kanal überholt Grün) → 0.35: „Grün, das weiß ausglüht".

**Iteration 2.** Numerik-Gegenprobe `outline_purple`: gzAccent liefert (0.78, 0.25, 1.25),
Kern (0.87, 0.53, 1.18) — Hue bleibt Besitzer, klippt nicht nach Weiß. Detail-0-Pfad: Skirt +
Kern statisch aktiv (Standbild unter reducedFx bleibt zweistufig). Kosten: 0 neue Taps.

## 3. glitch_datamosh — Blocky-Smear / Kompressions-Artefakte

**Plan.** Broken-Codec-Zone. Ist-Zustand verschob Blöcke als saubere Kopien — im Standbild
ein Puzzle, kein Mosh.

**Ideen.** (a) Richtungs-Smear entlang des Motion-Vektors — ANGENOMMEN (+2 Taps). (b) Grobe
Slab-Ebene 12×7 mit eigenem, langsamerem Re-Roll — ANGENOMMEN (die Makroblock-Silhouette).
(c) Blocking-Seams auf Makroblock-Grenzen (fract, 0 Taps) — ANGENOMMEN. (d) DC-Farbkipper
(grün/magenta, klassisch kaputte DC-Koeffizienten) — ANGENOMMEN. (e) Rolling-P-Frame-Balken —
VERWORFEN (Rolling-Bars sind das Gesicht von scanlines, Familientrennung). (f) Echter
Frame-Hold — VERWORFEN (kein History-Buffer in Veil-Post).

**Implementierung.** [D1] `SLAB_GRID` 12×7 auf 1.25-Hz-Clock (teilt die 5-Hz-Feinebene, kein
Beat), Verschiebung ±3 Slab-Einheiten, ZUERST angewandt (zwei Generationen Decode-Fehler).
[D2] 2 Taps rückwärts entlang der Gesamt-Verschiebung, kopfgewichtet — branchless No-op auf
unversehrten Pixeln. [D3] Dunkle 1-Texel-Naht auf dem Fein-Gitter, nur wo `broken`. [D4]
Hash-gesplitteter DC-Push; kommandierte Farbe ersetzt den Split (luma-neutralisierter
signierter Tilt) → `datamosh_red` kippt seine Blöcke rot.

**Iteration 1.** Rechenfehler: `SLAB_SHARE` 0.16 ergab ~13 verschobene Platten auf 84 Slabs
(= Suppe) → 0.07 (~5 Platten = Drama).

**Iteration 2.** Smear-Gewichte nachgerechnet (0.625/0.225/0.15 — Streak sichtbar, Bild
lesbar); fp32-Hash-Argumente ≤ versandte Größenordnung (~277 k, gzHash3-Referenz 353 k);
Detail-0 kollabiert ALLE neuen Layer (broken=0 → Seams/DC/Smear aus) — konsistent mit dem
alten reducedFx-Verhalten. Tap-Budget: 6.

## 4. glitch_scanlines — CRT mit Bildröhren-Wölbung

**Plan.** Mandat nennt explizit die Wölbung als UV-Trick — sie fehlte komplett; der Pass
hatte das Band, aber nicht die RÖHRE.

**Ideen.** (a) Barrel-Distortion + schwarzer Bezel mit runden Ecken — ANGENOMMEN (Pflicht,
stärkster Standbild-Marker). (b) RGB-Triaden-Schattenmaske statt neutraler Grille —
ANGENOMMEN (eine cos()-Auswertung, Nahsicht-DNA). (c) Diagonaler Glas-Reflex — VERWORFEN
(billig wirkend, frisst Szene). (d) Echte Phosphor-Persistenz — VERWORFEN (kein
Feedback-Target; W13-Beleg), stattdessen Afterglow-Gain 0.11 → 0.15.

**Implementierung.** [S6] `uv = 0.5 + q·(1 + K·r²·s)` mit K 0.18 (Kanten-Mitte ~2 %, Ecken
~9 % — Consumer-Röhre, kein Fischauge) VOR allen Layern: Zeilenmaske/Bar/Jitter leben im
gewölbten Raum und folgen dem Glas. Bezel = weich gefederter Rand, ganz am Ende als letztes
Wort, ×s (schwache Zone = weiche Eckschatten statt harter schwarzer Ecken). [S7] Triade:
3-Phasen-cos pro Kanal auf der Grille-Phase, aus der Distanz luma- und hue-neutral
(mean = 1 − depth/2 auf allen Kanälen).

**Iteration 1.** Energie-Bilanz: Zeilenmaske (−14 % mean) + Triade 0.22 (−11 %) = −25 % —
Nachtszenen kippen → `TRIAD_DEPTH` 0.18. Alte 0.05-Grille ersatzlos raus (beide zusammen =
doppeltes Vertikal-Streifen + Moiré bei kleinen Fenstern).

**Iteration 2.** Aberration nutzt `fromCenter` im gewölbten Raum — wächst korrekt zum Rand
(physikalisch: Ecken tearen mehr). Detail-0: Wölbung bleibt statisch stehen (erwünschter
Standbild-Marker unter reducedFx). Der bestehende UV-Clamp fängt Out-of-Frame-Samples; der
Bezel überdeckt die Clamp-Streifen. Kosten: 0 neue Taps.

## 5. glitch_invert — Invert-PULSE (kompletter Umbau)

**Plan.** Mandat: wandernde Invert-Wellen vom Zentrum, NICHT statisch. Die W13-fBm-Flecken
waren organisch, aber ohne Herkunft und ohne Bewegung im Charakter.

**Ideen.** (a) Konzentrische Ringwellen vom Bildzentrum, Invertierung nur im Wellenband —
ANGENOMMEN. (b) fBm-Warp des Radius (zerfressene Fronten, „snap, never flow") — ANGENOMMEN
(das fBm war schon bezahlt). (c) Wellen in Welt-Distanz (3D-Schalen) — VERWORFEN: Schalen um
einen Ursprung sind die Identität von glitch_void. (d) Mosaik-/Schachbrett-Invert — VERWORFEN
(kollidiert mit datamosh). (e) Akzent-Rim + Chroma-Ripple exakt auf der Front — ANGENOMMEN
(+1 Tap).

**Implementierung.** [I1] `wv = fract(rw/WAVELENGTH − Time/WAVE_PERIOD)` in
aspekt-korrigiertem Screen-Space; WAVE_PERIOD 4 s (25 Zyklen pro 100-s-Wrap, kein Sprung),
WAVELENGTH 0.55 → 1–2 laufende Ringe. [I2] `rw = r + (fBm − 0.5)·0.10` mit 50-s-Orbit-Drift.
[I4] Negativ/Hue-Snap/Posterize band-gewichtet (Erbe der Blot-Gewichtung). [I5] Rim-Spike auf
der Frontkante trägt den Akzent (SEAM_VIOLET-Erbe) und bricht das Bild (radiale UV-Ripple,
1 Tap). [I6] Quell-Glow im Zentrum flammt bei jedem Wellen-Launch auf (phase→0). Drops
(global, „almost recovers") und Hue-Detents überleben unverändert.

**Iteration 1.** Geometrie-Fehler: die Glocke hatte den langen Nachlauf AUSSEN (größere wv =
größerer Radius = vor der Front) — der Nachlauf lief der Welle voraus. Fix: steile Kante am
oberen Träger-Ende (0.45→0.52 hart), Tail nach innen (0.12→0.42 weich). Zweiter Befund:
Träger deckte ~85 % des Zyklus (kaum normaler Zwischenraum) → ~40 %: Ring und Welt
alternieren lesbar.

**Iteration 2.** Detail-0: `PARK_PHASE` 0.35 = stehende Ringe; `launch`-Flare dort exakt 0
(ruhiger Kern); Ripple detail-gated (kein reducedFx-Zittern). Farbe wirkt dreifach (Rim,
Quell-Glow, Wash). Tap-Budget: 2.

## 6. glitch_void — Sog + Event-Horizon (User-Liebling)

**Plan.** Altar-Ambient feuert `void_purple` mit `OriginMode` 1 vom Altarblock — Verhalten
unantastbar. Mandat: mehr Sog-Charakter. Ist-Zustand: Scanner, kein Schlund.

**Ideen.** (a) Event-Horizon-Ring bei fester Welt-Distanz auf dem bereits bezahlten
`range`-Read — ANGENOMMEN (0 Taps). (b) Radialer UV-Einzug zur Screen-Projektion des Origins,
2-Tap-Smear — ANGENOMMEN. (c) Stern-Streaks — VERWORFEN (Mehrfach-Lattice-Samples, Budget).
(d) UV-Twirl/Akkretionswirbel — VERWORFEN (Matsch mit dem Sog; Rotations-Linsen gehören
`black_hole`, fremdes Team).

**Implementierung.** [V3] Senke = projizierter Origin (`ProjMat·ViewMat·Origin` — Origin ist
schon kamera-relativ, daher OHNE CameraPosition-Subtraktion; `clip.w ≤ 0.1` → Fallback
Bildzentrum; Clamp ±0.5 Frame gegen degenerierte Pull-Vektoren); `pull` mit Boden-Floor, 2
Taps kopfgewichtet; die drained base + `thin`-Maske lesen das gesogene Bild → Restmasse
schliert einwärts. Zeitinvariant by construction (reducedFx-frei). [V2] `HORIZON_R` 14 Blöcke
(sitzt gut sichtbar in der 28er-Altar-Zone; bei Kamera-Origin trägt man den Horizont mit
sich), Shimmer detail-geparkt, `swallow` löscht innen den Rest-Wash (SWALLOW 0.85).

**Iteration 1.** Konsistenz: Projektion korrekt für local space; `swallow` auf Sky
konstruktionsbedingt 0 (range → far plane). Befund: Innerhalb des Horizonts zeigten sich
KEINE Sterne (das `thin`-Distanz-Gate 18–90 hält den Nahbereich zu) — das Innere war nur
tot-schwarz, „Sternenreste" fehlten genau dort.

**Iteration 2.** `thin = max(thin, swallow·0.40)`: der verschluckte Boden ZERFÄLLT in Sterne
— das Horizont-Innere wird das Loch in die Unendlichkeit, das der Effektname verspricht.
Tap-Budget: 6 (3 Farbe + 3 Depth).

## 7. glitch_dome + dome_shell — Hex-Schale, Fresnel-Kante

**Plan.** Paar-Feature (WOAH-01). Außen (`dome_shell`): „Hex" war Noise, das Zellen spielt;
plus 4 latente Bare-`return`-Minen. Innen (`glitch_dome`): keine Grenzfläche — Himmel/Hülle
im Readout tot-leer. Wichtig: Die Dome-Zone wird mit `originAtCentre = false` gearmt
(`MansionDomeService.createDomeZone`) — der Innenraum hat KEINEN Welt-Origin, der Hex-Layer
muss rein blickrichtungsbasiert sein.

**Ideen.** (a) Analytisches Hex-Gitter als geteilter Include-Helfer `gzHex` (ein mod-Paar,
Kantendistanz + Zell-Hash, self-contained nach dem Include-Gesetz — nutzt nur das private
`gzHash`) — ANGENOMMEN. (b) Innen: Hexes auf lon/lat des View-Rays, Distanz-Gate 30–70 Blöcke
(Hüllenradius clamp 48–72) + Sky — ANGENOMMEN (füllt exakt den toten Bildteil). (c)
Interferenz-Moiré aus zwei Lagen — ANGENOMMEN außen (dort IST die Schale das Objekt),
VERWORFEN innen (Readout schon dicht; Moiré flimmert auf llvmpipe). (d) Touch-Puls zeichnet
das Gitter nach — ANGENOMMEN. (e) Voronoi — VERWORFEN (teurer, Mandat sagt Hex).

**Implementierung.** `gzHex`: pointy-top über den Zwei-Offset-Gitter-Trick; Zell-Id
gesnappt (fp-Jitter), Kanten-Norm max(dot(g,n60),g.x), Kante bei 0. **Seam-Gesetz:**
Longitude-Skalen müssen GANZZAHLIG sein, damit die atan-Naht auf ganze Gitterperioden fällt
(innen 26, außen 26/28). Innen: Fresnel `pow(1−|ray.y|,3)` zur Horizont-Kante, Zell-Atmung
auf dem 5-s-Twinkle-Divisor (wrap-exakt), Gate schließt auf totem Depth-Buffer von selbst
(lC kollabiert zur Near-Plane). Außen: zwei Lagen counter-driften in Latitude → Moiré-Crawl;
Hex-Kanten Fresnel-gewichtet 4:1; Touch-Ring ×(0.45 + 0.85·borderA) = zellweises Aufleuchten;
`main()` komplett auf verschachtelte `if`s umgebaut (Minen weg — Harness-Warnung
verschwunden).

**Iteration 1.** Wrap-Audit: `dome_shell`-Time wrappt NICHT (monotone Tick-Uhr in
`MansionDomeClient.timeSeconds` — int-Ticks ohne Wrap), Drift also sicher; `glitch_dome`-Time
wrappt bei 100 s → innen ausschließlich der Twinkle-Divisor, KEIN Drift (ein 0.05er-Drift wäre
beim Wrap um 5.0 Gitter-Einheiten gesprungen, kein √3-Vielfaches).

**Iteration 2.** Skalen-Probe: 26 Hexes auf 360° ≈ 14 Blöcke Zellbreite am Äquator einer
60er-Kuppel — monumental, Schild-Look; Innen-Grundglühen über `fillAccent`(0.35+0.65·fresnel)
subtil gehalten, damit der Scanner-Readout die Bühne behält. Energie/Namens-Kollisionen
geprüft. Kosten: pure ALU, 0 neue Taps in beiden.

## 8. end_static — Weißrausch-Horror mit Signalverlust-Beats

**Plan.** Rift-Nähe-Effekt (`EndStaticFx`: Distanz-Ramp 56→168 Blöcke zum Rift-Anker ~40
über dem End-Disc). Ist: Knistern + feine Aberration — Interferenz ja, HORROR nein; das
Signal fiel nie AUS.

**Ideen.** (a) Static-Veil: grobzelliges Schnee-Mixing (2-px-Zellen — Pro-Texel-Pulver liest
sich als Sensor-Rauschen, 2-px-Zellen als TV-Schnee), Anteil s²·Envelope — ANGENOMMEN. (b)
Signalverlust-Beats: eigener 0.25-Hz-Slot-Zug (25 Slots/Wrap exakt, Duty 0.28), Kollaps-
Envelope 0.3 s Attack / ~1.5 s Recovery, Luma-Sturz + Desaturierung + vertikaler Frame-Slip +
Zeilen-Tear — ANGENOMMEN. (c) Interferenz-Bänder (7 Bänder, 35 Perioden/Wrap) — ANGENOMMEN.
(d) Rolling-Bar — VERWORFEN (scanlines-Familie). **Photosensitivity-Gesetz:** unter Detail 0
ist der Beat-Zug HART NULL (BackroomsFlickerOverlay-Regel), der Veil parkt zeitinvariant —
die Header-Zusage „Detail 0 = time-invariant" bleibt wahr.

**Implementierung.** `endBeat()` neben `endCrackle()`; Beat-Displacement als branchless
Identity bei beat=0; Veil `(VEIL_BASE·env + VEIL_BEAT·beat)·s²`, Clamp 0.78 (Rest-Silhouette
muss den tiefsten Beat überleben — Voll-Weiß ist nur ein Ladebildschirm); Schnee mit leichtem
Violett-Lean (END_STAR-Erbe).

**Iteration 1.** Reihenfolge-Entscheidung: Sterne werden VOR Kollaps+Veil addiert — sie
sterben mit dem Feed (der Beat ist der FEED-Tod; der Void gehört dem Sternen-Bleed zwischen
den Beats). Hash-Argumente geprüft (≤ ~62 k, im dokumentierten fp32-Rahmen).

**Iteration 2.** Beat-Kadenz-Audit: Ereignis ~1.7 s, dann ≥ 2.3 s Ruhe im 4-s-Slot, Duty 0.28
→ im Mittel ein Kollaps pro ~14 s — Horror-Beat, kein Strobe. Violett-Lean + 0.78-Kappe
final. Kosten: +0 Taps (der Veil ist ein Hash, kein Sample).

---

## 9. Validierungs-Outputs (Gates)

```
$ python3 /tmp/f102_glitch_validate.py
PASS  glitch_outline
PASS  glitch_datamosh
PASS  glitch_scanlines
PASS  glitch_invert
PASS  glitch_void
PASS  glitch_dome
PASS  dome_shell
PASS  end_static

all 8 shaders PASS

$ flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain
BUILD SUCCESSFUL

$ flock /tmp/gradle.lock ./gradlew processResources --offline --console=plain
BUILD SUCCESSFUL
```

Bare-Return/Streu-`#`-Lint: 0 Minen verbleibend in allen 8 Dateien (Baseline hatte 4 latente
in `dome_shell`). Kein Shader führt neue Uniforms ein; kein Java-Diff aus diesem Team.

---

## 10. Verifikations-Skript für den Main-Agent

Voraussetzung: laufender Dev-Server (`./gradlew runServer`) + Client (`runClient`) mit
eingeloggtem Spieler `Dev` (Operator, Perm 2). Alle Befehle via RCON; Screenshots je Effekt
nach ~3–5 s Wirkzeit (llvmpipe: 20–40 s Geduld pro Frame-Zyklus einplanen). Jeder Test läuft
nur auf dem Caller — kein Zonen-Aufräumen nötig.

```bash
# 1) outline — Kern-Wunsch
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test outline 45"
# ERWARTET: Welt SATT SCHWARZ (kein Grauschleier); grüne Kanten mit weichem Saum und
# heißem, weißlich ausglühendem Kern; Trace-Ebene wandert als Tiefen-Band durch die Szene.

python3 tools/rcon/rcon.py "execute as Dev run dev glitch test outline_red 45"
# ERWARTET: identisches Bild, aber Linien/Fill/Grain komplett ROT (Kern rot-weiß, nie cyan).

# 2) datamosh
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test datamosh 45"
# ERWARTET: 4-6 GROSSE dislozierte Bildplatten + feine versetzte Blöcke; in korrupten
# Blöcken RICHTUNGSSCHMIERE (Streaks, keine sauberen Kopien); dunkle Blocknähte NUR auf
# korrupten Regionen; einzelne grün/magenta verfärbte Blöcke (DC-Kipper).

# 3) scanlines
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test scanlines 45"
# ERWARTET: Bild sichtbar RÖHRENGEWÖLBT (Ecken gerundet schwarz — Bezel); Zeilenmaske folgt
# der Wölbung; in Nahsicht RGB-Streifen (Triade); Rolling-Bar mit Nachglühen darüber.

# 4) invert
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test invert 45"
# ERWARTET: KONZENTRISCHE, zerfressene Negativ-Ringe, die vom Bildzentrum nach AUSSEN
# laufen (steile Außenkante, weicher Nachlauf innen); violetter Saum exakt auf der Front;
# leichter Quell-Glow im Zentrum; zwischen den Ringen fast normales Bild.

# 5) void — Liebling; erst Standard, dann der Altar-Pfad
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test void_purple 45"
# ERWARTET: Welt fast schwarz mit lila Sonar-Ping; stehender LILA HORIZON-RING bei ~14
# Bloecken; INNERHALB des Rings zerfaellt der Boden in Sterne; Restmasse zeigt radiale
# Schlieren Richtung Bildzentrum (Sog).
python3 tools/rcon/rcon.py "execute as Dev run dev glitch altar"
# (Spieler muss <24 Bloecke am Sanctum-Altar stehen; sonst "unavailable".)
# ERWARTET: wie oben, aber Ping + Horizon-Ring + Sog-Senke zentriert auf dem ALTARBLOCK,
# nicht auf der Kamera — beim Umschauen bleibt die Senke am Altar kleben.

# 6) dome (Innenraum-Effekt solo — Hex auf Himmel/Ferngelaende)
python3 tools/rcon/rcon.py "execute as Dev run dev glitch test dome 45"
# ERWARTET: gruener Scanner-Readout + CRT-Zeilen; auf HIMMEL und FERNE ein Hex-Gitter mit
# atmenden Zellen, zur Horizontkante hin heller (Fresnel-Band).

# 6b) dome_shell (Aussenschale — echter Test-Dome)
python3 tools/rcon/rcon.py "execute as Dev run dev dome arm here 24"
# … dann ~450-590 Bloecke wegfliegen und zur Kuppel BLICKEN (Strength ist ein
# Distanz-Ramp 450->600 und innen 0!):
# ERWARTET: schwarze Kuppel mit gruenem HEX-GITTER (zwei Lagen, langsames Moire), Kanten
# an der Fresnel-Silhouette am hellsten; Projektil-Treffer zeichnen Ring zellweise nach.
python3 tools/rcon/rcon.py "execute as Dev run dev dome status" "execute as Dev run dev dome disarm"

# 7) end_static (Rift-Naehe am End-Disc; Anker ~ 0 400 0, voll <56 Bloecke)
python3 tools/rcon/rcon.py "tp Dev 20 390 0"
# (End-Disc muss materialisiert sein — Stage-abhaengig; sonst /eclipse stage vorziehen.)
# ERWARTET zwischen den Beats: sichtbarer TV-Schnee-Schleier + langsame horizontale
# Interferenz-Baender + violette Sterne in Schatten. Alle ~10-20 s ein SIGNALVERLUST-BEAT
# (~1.7 s): Bild stuerzt in dunklen entsaettigten Brei, Schnee fast voll, Frame verrutscht
# vertikal, Zeilen reissen seitlich — dann Erholung.
```

Gegenproben (je 1x empfohlen): `/dev glitch test <effect>` mit reducedFx an (Client-Config)
— NICHTS darf flackern; end_static darf unter reducedFx KEINE Beats zeigen. Und
`/dev glitch list` + Ablauf abwarten → alle Effekte müssen sauber auf Passthrough
zurückfaden (Strength-0-No-op-Gesetz, unverändert).

## 11. Offene Risiken

1. **Tuning ist rechnerisch, nicht gesehen.** Diese Session lief headless (paralleler
   Team-Betrieb auf dem Baum); alle Zahlen sind gegen Energie-Budgets/Geometrie gerechnet,
   aber kein Frame wurde gerendert. Kandidaten für Sicht-Nachjustierung: `HORIZON_R` (14),
   `SLAB_SHARE` (0.07), `CURVE_K` (0.18), `VEIL_BASE`/`VEIL_BEAT` (0.16/0.55).
2. **glitch_dome-Distanz-Gate** (30–70) ist auf den Standard-Hüllenradius 48–72 gerechnet;
   bei kleinen Test-Domes (`/dev dome arm here 12`) liegt die Hülle unter dem Gate und die
   Hexes erscheinen nur am Himmel — kein Bug im Ziel-Setup (Mansion-Dome), aber im
   Mini-Test-Dome sichtbar anders.
3. **end_static-Verifikation** hängt an der End-Disc-Materialisierung (Stage-Gate) — der
   Beat-Zug selbst ist stage-unabhängig, nur die Anfahrt braucht die richtige Welt.
4. **dome_shell-Time wrappt nicht** (monotone Tick-Uhr): nach vielen Stunden Session leidet
   die fp32-Präzision der Drift-Terme minimal — Bestandsverhalten, durch die neuen Layer
   nicht verschärft (Drift-Raten ≤ 0.05/s).
