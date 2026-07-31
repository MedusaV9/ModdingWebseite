# STORM_MASS_PLAN — „Dicke wabernde Masse aus Wind und Wetter" (Session 0730)

Auftrag (Projektinhaber, wörtlich): Stürme sollen **Kugeln aus Wind und Wetter** sein,
„wirklich sehr viele krasse Layer … eine dicke Masse statt nur ein paar Layer — sie
brauchen Tiefe und Höhe in dem was sie tun", volumetrisch in Veil, „von weiter weg der
simple Veil-Effekt, wenn man näher kommt Photon-Nahfeld".

Dieses Dokument ist ein reiner **Implementierungsplan** — kein Produktionscode wurde in
dieser Session geändert. Nachfolger von `docs/plans_v3/plans_v5/v7/PLAN-STORM2.md`
(STORM 2.0) und der STORM-VOL/F-030/F-034-Runden; alle dort eingefrorenen Verträge
gelten weiter (§2).

---

## 1. Ist-Analyse (verifiziert gegen den Quellstand, mit Zeilenverweisen)

### 1.1 Die LOD-Kette (funktioniert, bleibt)

```
 shellDist > 250          250 → 150                < 150                  innen
 ─────────────────  ───────────────────────  ─────────────────────  ────────────────
 StormWallRenderer  Volume fadet ein          Volume voll (Strength   storm_interior-
 far/impostor wall  (Strength-Rampe,          1.0) + Photon-Nahfeld-  Grade + Interior-
 (CPU-Shells)       StormVolumeFx L72/L208)   Loops voll (Channel A)  Uniform dämpft
                    + Photon-Loops attachen                           Volume −35 %
                    (StormNearfieldFx L56)                            (fsh L262)
```

- Zielauswahl/Uniform-Feeder: `stormfx/StormVolumeFx.java` — `VOLUME_RANGE = 250` (L70),
  `STRENGTH_FADE_START = 150` (L72), Step-Tiers 64/40/24 (L74–76), Coverage-Leiter +
  Fullscreen-Cap 48 (L80–97, L280–298), Siege-Cap 32 + Tier-Drop (L97, L304–307),
  Uniform-Feed (L187–256). `Time` kommt tick-basiert aus Java (L230) — Falle 3 aus
  AGENTS.md ist dort bereits korrekt gelöst.
- Occluder-Handshake: `StormWallRenderer.java` — `OCC_VOLUMETRIC_CORE = 0.30F` (L169),
  Occluder-Schrumpfung + Soft-Tint (L551–569), `EXO_VOLUMETRIC = {}` (L191–196: die
  EXO-Shells werden bei aktivem Volume KOMPLETT übersprungen — „Eggshell"-Falle gelöst).
- Photon-Nahfeld: `StormNearfieldFx.java` — 3 WINDOWED-Loops (`storm_nearfield_wisps`,
  `storm_ground_scud`, `storm_updraft_motes`, L71–92), Attach/Full/Release 250/150/270
  (L56–60), Emissionsraten via Channel-A-Tuner (L249–261, L314 ff.). Fernere Belts
  (`storm_cloud_belt`, `storm_debris_belt`) laufen über `StormPhotonFx` mit den
  Channel-B-Expression-Variablen `eclStormR`/`eclStormH` (`StormPhotonFx.ExprVars`,
  L326–362). **Es gibt bisher KEINE Rotations-/Zeit-Variable** — Photon-Bänder driften
  frei, nicht synchron zum Volumen.
- Kampfkopplung: `StormSiege.java` (F-031, Header L54–70): Sturm wächst
  (`storm.radius = baseRadius * siegeScale`, `StormFxClient.java` L319–321), Kern löst
  sich auf (`siegeCoreFade`, `StormFxClient.java` L937–942), Debris-Orbits + Wurfblöcke.
  Das Volumen erfährt vom Kampf heute NUR indirekt (Radius/Steps) — kein Uniform trägt
  Siege-Zustand in den Shader.

### 1.2 Der Raymarcher — `pinwheel/shaders/program/storm_volume.fsh` (306 Z., komplett gelesen)

| Baustein | Zeilen | Befund |
|---|---|---|
| Uniforms | L28–40 | `VolCenter/VolRadius/VolYScale/Visibility/Strength/StepCount/ShadowTaps/Time/SunDir/Interior/FlashPos/FlashAmount` — 1 Flash-Slot, kein Siege-/Tier-Uniform |
| Konstanten | L46–84 | `ABSORB 0.55`, `DENSITY_GAIN 1.05` (Warnung L48–53: mehr Dichte ⇒ Sättigung ⇒ WENIGER Tiefe — Kontrast gehört ins Licht!), `BOUNDS_MARGIN 1.55` |
| Wind-Strata | L88–92 | Höhenleiter 0.6×/1.0×/1.5×/−0.8× (Polar-Cap gegenläufig) |
| Dichtefeld | L98–163 | EIN Feld: Differentialrotation (L106–110), Silhouette-rEff aus tower+bulge+anvil+skirt (L118–127), **EIN radiales Dichteband** rl 0.30–1.05 mit hohlem Auge (L132–133), Vertikalprofil Fade 0.92–1.04 / Cut < −0.18 (L135–137), 3-Arm-Log-Spirale (L144–148), fBm5+CurlWarp-Body (L152–158), Carve-Remap ×1.5−0.35 (L162) |
| Licht | L171–200 | 2/3 Sonnen-Selbstschatten-Taps (L176–180, Schatten-Diät: unwarped fBm2), Tag/Nacht-Sonnenfarbe (L183–184), **Höhen**-Ambient-Gradient (L185–186), Multi-Scatter-Lift `sqrt(lightT)·0.20` (L192–193), 1 Flash als Emission `exp(-fd/0.30R)` (L194–198) |
| March | L202–306 | Ellipsoid-Entry (L213–230), Depth-Clamp (L237–240), Distance-LOD 160→320 (L249–251), IGN-Dither (L256–258), Interior-Dämpfung −35 % (L262), HG-Phase g=0.45, Mix 0.72 (L264), adaptive Skips + Isosurface-Step-Back (L282–296), Early-out trans<0.02 (L273) |

Noise-Bibliothek `pinwheel/shaders/include/eclipse_volume.glsl`: `evNoise3` = 8 Hashes
(L16–30), `evFbm5/3/2` (L34–57), `evCurlWarp` = 3×`evNoise3` (L62–67), `evHgPhase`
(L70–73). Half-Res-Pipeline: `pinwheel/post/storm_volume.json` (volume_half RGBA16F,
`clear:false`) + bilateraler Upsample `storm_volume_upsample.fsh` (L61–79).

### 1.3 Defizit-Diagnose — warum es noch nicht als „dicke Masse" liest

1. **Eine Schale, kein Stapel:** Das radiale Profil (L132–133) ist EIN Band mit hohlem
   Auge. Alles „Innenleben" kommt allein aus dem fBm-Carving desselben Feldes — es gibt
   keine zweite, anders rotierende Schicht, die in Löchern der äußeren sichtbar würde.
   Genau das ist der fehlende „viele Layer"-Read.
2. **Tiefe hängt fast nur an den Schatten-Taps:** Licht kennt Höhe (Ambient L185) aber
   kaum RADIALE Tiefe: kein Powder-Term, keine dichteabhängige Albedo, Single-Lobe-Phase.
   Dicke Ballen und dünne Fetzen bekommen dieselbe Farbe pro Transmittanz-Slice.
3. **Höhenprofil ist eine gestauchte Kugel:** anvil/skirt modulieren nur rEff um ±12/6 %;
   es gibt keine Wallcloud-Basis, keine aufsteigenden Konvektionstürme, keine
   ausfransende Decke. `ny > 1.22`-Cut (L101) + Fade 0.92–1.04 (L135) deckeln alles.
4. **rEff-Headroom ist fast aufgebraucht:** max rEff ≈ 1 + 0.12(anvil) + 0.174(bulge) +
   0.105(tower) ≈ 1.40; ×1.05 = 1.47 gegen `BOUNDS_MARGIN 1.55` → nur ~0.08 Luft. Jeder
   neue Silhouettenterm sprengt die Bounds-Kugel (AGENTS.md-Falle 2), wenn nicht beide
   Margins (fsh L68 UND `StormVolumeFx` L79) angehoben werden.
5. **Blitz = 1 weicher Glow:** ein Slot, radialsymmetrisch — keine Adern, keine zweite
   gleichzeitige Zelle, kein Flackern der Umgebungsdichte.
6. **Photon läuft asynchron:** Belts/Nearfield haben keine gemeinsame Winkeluhr mit der
   Differentialrotation des Volumens — die Parallaxe-Kopplung („Fetzen, die MIT dem Kern
   drehen") existiert nicht.
7. **Kampf unsichtbar im Volumen:** Siege-Wachstum/Kernauflösung erreichen den Shader
   nicht als Zustand — der Sturm „tut" im Kampf volumetrisch nichts Besonderes.

---

## 2. Eingefrorene Regeln & Fallen-Matrix (gegen jeden Baustein geprüft)

| # | Falle/Regel | Quelle | Konsequenz für diesen Plan |
|---|---|---|---|
| F1 | Depth-Clamp: opake depth-schreibende Geometrie im Volumen schneidet Rays | AGENTS.md; fsh L237–240 | KEINE neue opake Geometrie im Volumen. `OCC_VOLUMETRIC_CORE` bleibt 0.30 (Experiment 0.25 nur als markiertes Risiko, §3 B9). Siege-Debris (Block-Displays) ist ok: per-Pixel-Occlusion ist dort korrekt |
| F2 | Silhouetten-Lumps müssen in BOUNDS_MARGIN passen | AGENTS.md; fsh L64–68 | B3 hebt Margin 1.55 → 1.70 **in fsh L68 UND `StormVolumeFx` L79 gleichzeitig**; rEff-Bilanz-Tabelle in §3 B3 |
| F3 | `VeilRenderTime` existiert nicht in Pinwheel-Post | AGENTS.md | Alle neuen Zeitgrößen kommen als Java-Uniforms (Muster `StormVolumeFx` L230) |
| F4 | Kein GPU (llvmpipe), Half-Res + adaptive Steps sind gesetzt | AGENTS.md | Budget in evNoise3-Einheiten pro Sample (§4); jedes Feature mit Tier-Gate |
| F5 | Uniform-Wachstum nur additiv; Wire-Format eingefroren | PLAN-STORM2 §1 | Neue Uniforms nur hinzufügen, keine Semantik bestehender ändern; alles client-derived |
| F6 | Photon-`.fx` niemals von Hand editieren | AGENTS.md | B8 nur über `tools/photon/`-Generatoren + `python3 tools/photon/fxlib.py validate` |
| F7 | EXO + Volume gleichzeitig = „Eggshell" | AGENTS.md; `StormWallRenderer` L191–196 | Kein Baustein reaktiviert EXO-Shells bei aktivem Volume |
| F8 | `DENSITY_GAIN`-Sättigungsgesetz | fsh L48–53 | Kein Baustein erhöht die Gesamtdichte; Layering moduliert lokal, Tiefe kommt aus Licht (B1/B5) |
| F9 | Frozen-Look-Garantie ohne Volume (Iris/evicted/fused) | `StormVolumeFx` L127–135 | Alle Änderungen leben im Shader/Feeder; CPU-Shell-Fallback bleibt bit-identisch |

---

## 3. Upgrade-Bausteine (Prioritätsreihenfolge)

Notation: Kosten in **N** = eine `evNoise3`-Auswertung (8 Hashes). Ist-Kosten pro
belichtetem Camera-Sample: Dichte 10 N (fbm5 5 + warp 3 + tower/bulge 2) + Schatten
2–3 Taps × 4 N = **18–22 N**. Leeres Sample (prof≤0.003): 2 N.

### B1 — Licht-Tiefenpaket: Powder + Dual-Lobe-Phase + dichteabhängige Albedo  ⟵ größter Masse-Gewinn pro Aufwand
**Ziel:** Ballen bekommen dunkle Bäuche und helle Sonnenkanten; dicke und dünne Stellen
lesen unterschiedlich → sofortiger „das ist Masse, kein Nebel"-Read. Kosten: **0 N**
(reine Mathematik auf vorhandenen Samples).

GLSL-Skizze (ersetzt L192–193 bzw. erweitert `volumeLight`):
```glsl
// Powder (Beer-Powder, Horizon/Nubis-Trick): frisch angestrahlte dünne Ränder hell,
// dicke Ballen saugen Licht weg — der klassische Cumulus-„Zucker"-Look.
float powder = 1.0 - exp(-dens * densMul * 14.0);
// Dichteabhängige Albedo: dicke Pockets kippen ins dunkle Schiefergrün der C8-Palette.
vec3 albedo = mix(vec3(1.0), vec3(0.62, 0.68, 0.66), clamp(dens * 2.2, 0.0, 1.0));
vec3 col = albedo * (sunCol * (lightT * phase * 4.6 * powder + ms * 0.20) + ambient);
```
Phase (ersetzt L264, Dual-Lobe: Silver-Lining + Rückstreu-Fülllicht):
```glsl
float phase = mix(evHgPhase(mu, 0.60), evHgPhase(mu, -0.22), 0.32);
phase = mix(0.0795775, phase, 0.78);
```
**Defaults:** Powder-k 14.0, Albedo-Dunkelpunkt (0.62,0.68,0.66) bei dens≥0.45,
g_fwd 0.60 / g_bwd −0.22 / Lobe-Mix 0.32.
**Fallen:** F8 beachtet — Kontrast kommt ausschließlich aus dem Licht. Tuning-Risiko:
Powder-k zu hoch ⇒ Ränder „glühen"; mit L264-Silver-Lining gegenprüfen (Screenshot S3).

> ✅ **umgesetzt** (Session 0730, Paket B1/B5/B9-Basis; Zeilen: Stand nach B2/B3/B7) —
> `storm_volume.fsh`: Dual-Lobe-Phase L413–418, Powder L313–316, dichteabhängige
> Albedo L317–321, Combine (albedo × [sun·powder + ms] + ambient, Flash bleibt
> Emission danach) L321–328; `volumeLight`-Signatur erweitert um `rl`/`dens` (L281).
> Abweichung: Powder/Albedo nutzen die PREMULTIPLIZIERTE Sample-Dichte (`dens`
> enthält in der Marschschleife bereits `densMul`) — für Powder ist das exakt die
> Plan-Formel `raw · densMul`; die Albedo greift dadurch bei fadenden Stürmen
> (Strength < 1) etwas später ins Dunkle, was dem Fade-Verhalten zugutekommt.

### B2 — Zweite Dichteschale + Anti-Phase-Body („da ist noch was dahinter")
**Ziel:** Löcher der äußeren Schale geben den Blick auf eine innere, ANDERS rotierende,
dunklere Schicht frei — der Kern des „viele Layer"-Wunsches. Kosten: **+1 N** camera-only
(Zusatzrotation ist cos/sin, der Body wird WIEDERVERWENDET).

GLSL-Skizze (in `stormDensity`, nach L133):
```glsl
// Innere Schale rl 0.16–0.50, führt der äußeren um +0.35 rad voraus (Extra-Spin) und
// nutzt den ANTI-PHASE-Body (1-body): wo außen Loch ist, ist innen Substanz.
float band2 = smoothstep(0.16, 0.34, rl) * (1.0 - smoothstep(0.44, 0.56, rl));
float spin2 = spin + 0.35 + Time * 0.035;           // eigene Winkeluhr
float cs2 = cos(spin2); float sn2 = sin(spin2);
vec3 q2 = vec3(cs2 * u.x - sn2 * u.z, u.y, sn2 * u.x + cs2 * u.z);
float cell2 = evNoise3(q2 * 3.4 + vec3(0.0, -Time * 0.03, 7.7));   // +1 N
float body2 = 1.0 - body;                                           // 0 N — Anti-Phase
float inner = band2 * max(body2 * 1.4 - 0.30, 0.0) * (0.55 + 0.45 * cell2);
// Kombination: max, nicht Summe — F8: die Gesamt-Optikdichte bleibt in der Sättigungszone
prof = max(prof, inner * 0.62);
```
`volumeLight`-Kopplung: innere Schale bekommt via `rl` dunkleres Ambient (siehe B5) —
sie darf NIE heller sein als die äußere. **Defaults:** inner-Gewicht 0.62, Lead 0.35 rad
+ 0.035 rad/s. **Fallen:** Schatten-Rays (detail 0) überspringen `cell2` (Midline 0.5
einsetzen) — sonst +1 N × Taps. Auge nicht zuschütten: band2 endet bei rl 0.16, das
Interior-Handover (L262) und die F-032-Kernauflösung (B7) bleiben funktional.

> ✅ **umgesetzt** (Session 0730, Paket B2/B3/B7) — `storm_volume.fsh`: band2/innerProf
> L201–208 (Early-out schließt innerProf ein, damit Löcher der äußeren Schale keine
> innere Substanz überspringen), inner-Block mit eigener Winkeluhr + `cell2` (Tier ≥ 2,
> Camera-only, Midline 0.775 sonst) L240–252.
> **Abweichung (wichtig):** Die Plan-Skizze kombinierte `prof = max(prof, inner·0.62)`
> VOR dem Carve-Remap — dort multipliziert die finale Formel `(body·1.5 − 0.35)` die
> innere Schale mit genau dem Loch, das sie enthüllen soll (Anti-Phase: body niedrig ⇒
> Faktor ≤ 0 ⇒ innere Schale unsichtbar). Implementiert ist die treue Variante: outer
> und inner werden GETRENNT geformt (inner = innerProf × max((1−body)·1.4−0.30, 0) ×
> cellMul × 0.62, geteilte Vertikal-Hülle `vert`) und erst NACH dem Carve per
> `max(outer, inner)` kombiniert (F8: max, nie Summe). `spin2` nutzt die B7-Churn-Uhr
> (`spinT`) statt roher `Time` — Eskalation bleibt winkelstetig.

### B3 — Höhenprofil v2: Wallcloud-Basis + Konvektionstürme + ausfransende Decke
**Ziel:** Der Sturm liest vertikal: schwere dunkle Basis, aufsteigende Türme über der
Schulter, zerrissene Anvil-Decke — „Tiefe und Höhe in dem was sie tun". Kosten: **+1 N**
camera-only (Zellenfeld; Fray reuse't `body`).

GLSL-Skizze (ersetzt/erweitert L118–137):
```glsl
// Konvektionszellen: vertikal kohärentes Säulenfeld im rotierenden Frame (y-frei!)
float convCell = evNoise3(vec3(q.x * 3.2, Time * 0.02, q.z * 3.2));          // +1 N
float towerCol = smoothstep(0.55, 0.85, convCell);           // wo Türme stehen
// Turmhöhe: Decke steigt lokal von 0.95 auf bis zu 1.30 (VOR VolYScale)
float towerTop = 0.95 + 0.35 * towerCol;
prof *= 1.0 - smoothstep(towerTop - 0.14, towerTop, ny);      // ersetzt L135
// Wallcloud: abgesenkter, verdickter Basisring (rl 0.62–1.0, ny < 0.30)
float wallCloud = smoothstep(0.30, 0.10, ny) * smoothstep(0.55, 0.80, rl);
prof *= 1.0 + 0.55 * wallCloud;                               // ersetzt L137-Boost
// Fray: Decke franst mit dem vorhandenen Body aus (0 N)
prof *= mix(1.0, smoothstep(0.30, 0.62, body), smoothstep(0.72, 1.0, ny));
// rEff: Türme brechen die Silhouette nach OBEN (statt des alten reinen anvil-Bulges)
rEff += 0.14 * towerCol * smoothstep(0.55, 0.90, ny);
```
**Pflicht-Begleitänderungen (F2!):**
- `BOUNDS_MARGIN 1.55 → 1.70` in fsh L68 **und** `StormVolumeFx.java` L79.
- `ny > 1.22 → ny > 1.42` (fsh L101).
- rEff-Bilanz neu: max ≈ 1 + 0.12(anvil, reduziert auf 0.08) + 0.174(bulge) +
  0.105(tower) + 0.14(convTower) ≈ 1.50; ×1.05 = 1.57 < 1.70 ✓ (0.13 Luft).
- Bounds wachsen ⇒ Chord +~10 % ⇒ dt +10 % gröber. Kompensation: **Y-Slab-Clip** des
  Rays gegen ny ∈ [−0.25, 1.45] im gestauchten Raum (2 Ebenen-Schnitte nach L230, ~6
  ALU) — reklamiert von oben/unten gesehen mehr Marschweg zurück als die Margin kostet.
**Fallen:** VolYScale staucht ny mit — bei Spawn (heightScale 0.25, `StormWallRenderer`
L1880–1888) sind Türme automatisch flach: gewollt. Fullscreen-Cap 48 Steps unangetastet.

> ✅ **umgesetzt** (Session 0730, Paket B2/B3/B7) — `storm_volume.fsh`: ny-Cut 1.22→1.42
> L139–143, convCell/towerCol (Tier ≥ 1 Camera, Midline 0.5 für Tier 0 + Schatten)
> L166–174, rEff-Umbau (anvil 0.12→0.08, +0.14·towerCol·Gate) L175–181, towerTop/vert
> L188–195, wallCloud (ersetzt den skirt×band-Boost) L196–199, Fray L253–257.
> `BOUNDS_MARGIN` 1.55→1.70 BEIDSEITIG (fsh L94, `StormVolumeFx.java` L87). Y-Slab
> (B9, bereits [−0.25, 1.45]) brauchte wie geplant keine Änderung — Decke 1.30 < Cut
> 1.42 < Slab 1.45. **rEff-Bilanz nachgerechnet** (Scan über ny, worst case Noise=1):
> Ridge-Max 0.2008 bei ny≈0.836 (Anvil- und Turm-Gate ÜBERLAPPEN dort — der Plan-Wert
> 1.50 war leicht zu optimistisch geschätzt), + bulge 0.174 + tower 0.105 ⇒
> **max rEff = 1.4802, ×1.05 = 1.5542 < 1.70 ✓ (Luft 0.146)**. Tier-0-Gegenprobe
> (towerCol 0.5): max rEff 1.4179, ×1.05 = 1.4888.
> Abweichungen: Fray wirkt auf das kombinierte Feld statt nur auf prof (die innere
> Schale erreicht ny > 0.72 praktisch nicht — visuell identisch, Code einfacher);
> Tier 0 erhält die NEUE Profilform mit konstanter Decke 1.125 (Plan: „Profilform
> bleibt, Säulenvariation entfällt") — der Tier-0-Look ist damit bewusst v2, nicht
> der alte 0.92–1.04-Fade.

### B4 — Warp v2: Zeit-Rotor + zweite Warp-Ebene (Tier 2 only)
**Ziel:** Das Wabern: Billows falten sich ineinander statt zu scrollen. Kosten: **+1 N**
nur Tier 2.
```glsl
vec3 w1 = evCurlWarp(np * 0.5, Time);                       // bestehend, 3 N
float w2 = evNoise3(np * 1.7 + vec3(Time * 0.05));          // +1 N, Tier 2
// Rotor: der Warp-Vektor dreht langsam um die Y-Achse — Falten statt Drift
float wa = Time * 0.04;
w1.xz = mat2(cos(wa), -sin(wa), sin(wa), cos(wa)) * w1.xz;
body = evFbm5(np + w1 * (1.0 + 0.35 * (w2 - 0.5)));
```
Gate: `if (DetailTier > 1.5)` — sonst bestehender Pfad. **Falle:** Warp-Amplitude >1.9
lässt Billows „reißen" (Lattice sichtbar); 1.6·1.35-Deckel einhalten.

> ✅ **umgesetzt** (Session 0730, Paket B4/B6/B8, F-096) — `storm_volume.fsh` L239–253:
> Zeit-Rotor `wa = Time·0.04` dreht `w1.xz` (inline 2×2 statt `mat2`-Konstruktor,
> gleiche Mathematik), zweite Warp-Ebene `w2 = evNoise3(np·1.7 + Time·0.05)` (+1 N,
> nur Tier 2 — Budget §4 Tier-2-Dichte 13 N ✓). **Deckel-Korrektur gegen die
> Plan-Skizze:** B7 hatte den Churn-Faktor (1+0.18·SiegeChurn) bereits auf dieselbe
> Amplitude gelegt; beide Faktoren MULTIPLIZIEREN sich (worst case 1.6·1.18·1.175 =
> 2.22 > 1.9). Gelöst als kombinierter Multiplikator
> `wm = min((1+0.18·SiegeChurn)·(1+0.35·(w2−0.5)), 1.1875)` ⇒ 1.6·1.1875 = 1.9 exakt
> am Deckel (L238, L252). Tier 0/1: `wm` bleibt der reine B7-Term, `w2`/Rotor werden
> nie ausgewertet — Pfad unverändert. Idle (SiegeChurn=0, Tier<2) bit-identisch zu B7.

### B5 — Radiale Ambient-Occlusion + analytische Sonnen-Tiefe (statt teurem 2nd march)
**Ziel:** Von außen nach innen wird es glaubwürdig dunkler; die sonnenabgewandte
Hemisphäre fällt großräumig ab — Tiefenwirkung OHNE zusätzliche Dichte-Samples.
Kosten: **0 N** (Geometrieterme). Ein echter 2. March Richtung Sonne (auch 2–3 Steps)
wäre +8–12 N pro Sample und ist auf llvmpipe NICHT drin — verworfen, §7.
```glsl
// Radiales AO: Kernnähe schluckt Ambient (liest als „Masse dahinter")
float radialAo = mix(0.30, 1.0, smoothstep(0.15, 0.85, rl));
// Analytische Großraum-Sonnentiefe: Projektion der Sample-Position auf die Sonnenachse
// — sonnenzugewandte Hälfte hell, abgewandte dunkel, VOR den lokalen Schatten-Taps
float sunSide = clamp(dot(u, sdir) * 0.5 + 0.5, 0.0, 1.0);
float macroShadow = mix(0.45, 1.0, sunSide);
vec3 ambient = ...bestehend... * radialAo;
float lightT = exp(-sh * ...) * macroShadow;
```
**Defaults:** AO-Floor 0.30, macroShadow-Floor 0.45. **Falle:** beide Terme multiplizieren
sich mit den Taps — Gesamtabdunklung gegen die „nicht zum Silhouetten-Klumpen
crushen"-Regel (L187–191) per Screenshot S3/S4 ausbalancieren.

> ✅ **umgesetzt** (Session 0730, Paket B1/B5/B9-Basis; Zeilen: Stand nach B2/B3/B7) —
> `storm_volume.fsh`: macroShadow (analytische Sonnen-Großraumtiefe, multipliziert
> `lightT`) L291–297, radialAo (multipliziert `ambient`) L301–306. Abweichung: `rl`
> steht in `volumeLight` nicht nativ zur Verfügung — statt die Silhouettenterme dort
> neu zu rechnen (+2 N) exportiert `stormDensity` die bereits bezahlte
> Profilkoordinate als `out`-Parameter (L132–138, L181–182); die Schatten-Taps rufen
> unverändert einen 2-Arg-Wrapper (L265–269). Kosten damit wie geplant 0 N.

### B6 — Blitz v2: zweiter Flash-Slot + Emissions-Adern
**Ziel:** Interne Blitze als räumliche Dichte-Emission: zwei gleichzeitige Zellen,
aderiges Aufglimmen statt radialem Glow. Kosten: **+1 N** nur bei aktivem Flash.

Shader (erweitert L194–198):
```glsl
uniform vec3 Flash2Pos; uniform float Flash2Amount; uniform float FlashSeed;
vec3 flashLight(vec3 pos, vec3 u, vec3 fp, float amt) {
    float fd = length(pos - fp);
    float vein = 0.55 + 0.90 * evNoise3(u * 9.0 + vec3(FlashSeed * 17.0)); // +1 N
    return vec3(0.70, 0.58, 1.00) * (amt * 2.5 * vein * exp(-fd / (0.30 * VolRadius)));
}
if (FlashAmount > 0.004)  col += flashLight(pos, u, FlashPos,  FlashAmount);
if (Flash2Amount > 0.004) col += flashLight(pos, u, Flash2Pos, Flash2Amount);
```
Java (`StormWeatherFx`): Flash-Scheduler (L105–128: `innerFlashAmount/Bearing/Lat` +
`innerFlashSerial`) um einen **zweiten unabhängigen Slot** erweitern (eigene Decay-Uhr,
eigener Bearing); `StormVolumeFx.feedVolume` füttert `Flash2Pos/Flash2Amount` nach dem
Muster L237–255 und `FlashSeed = innerFlashSerial() % 64`. **Falle:** F3 — keine
Shader-Zeit für den Vein-Flicker, der Seed wechselt pro Flash aus Java.

> ✅ **umgesetzt** (Session 0730, Paket B4/B6/B8, F-096) — Uniforms
> `Flash2Pos`/`Flash2Amount`/`FlashSeed` (fsh L58–60), Emission in `volumeLight`
> L355–365: der Vein-Term wird EINMAL gehoisted, wenn IRGENDEIN Slot > 0.004 ist
> (`vein = 0.55 + 0.90·evNoise3(u·9 + FlashSeed·17)`) — Doppel-Flash kostet +1 N
> statt +2 N, alle Tiers (Budget §4: „+1 N nur bei aktivem Flash" hält auch für zwei
> Zellen). Beide Slots additiv `amt·2.5·vein·exp(−fd/(0.30·R))`, gemeinsame Farbe
> `vec3(0.70,0.58,1.00)`. Java: zweiter unabhängiger Scheduler-Slot in
> `StormWeatherFx` (Arrays L108–111, State-Machine L281–295, Kadenz 130–340 t
> L71–72/L330–334 — bewusst gegen 90–260 versetzt: Überlappung kommt vor, ist aber
> nicht Dauerzustand; `envelope` → `envelopeAt(start)` refaktoriert L338–356).
> **Slot 2 ist volume-only:** bumpt NICHT `flashSerial`, claimt KEIN Punktlicht und
> KEINEN Interior-Beat — W-C-Photon-Vein + Licht bleiben Slot-1-exklusiv, sonst
> feuerte der Vein auf die falsche Zelle. Accessors `innerFlash2Amount/Bearing/Lat`
> (L157–176); `StormVolumeFx.feedVolume` füttert Flash2* nach dem FlashPos-Muster
> und `FlashSeed = innerFlashSerial() % 64` (L305–322). Idle-Regel geprüft: alle
> drei neuen Uniforms 0 ⇒ das Vein-Gate öffnet nie ⇒ Frame bit-identisch.

### B7 — Kampf-Uniforms: `SiegeChurn` + `CoreFade` (der Sturm „kämpft mit")
**Ziel:** Sichtbare Kampfeskalation im Volumen: schnellere Rotation, stärkerer Updraft,
Kern reißt auf wenn die Occluder-Kugel dissolvet (F-032) — synchron zur bestehenden
Server-Logik, rein visuell. Kosten: **0 N**.

Java (`StormVolumeFx.feedVolume`, additiv — F5):
```java
float coreFade = storm.siegeCoreFade(partialTick);                  // L937–942 Client
float churn = Mth.clamp((storm.siegeScale(partialTick) - 1.0F)
        / (StormSiege.RADIUS_SCALE - 1.0F), 0.0F, 1.0F);
pipeline.getUniform("CoreFade").setFloat(coreFade);
pipeline.getUniform("SiegeChurn").setFloat(churn);
```
GLSL:
```glsl
float spin = Time * ROT_SPEED * (1.0 + 1.6 * SiegeChurn) * stratumSpeed(...);
vec3 np = q * NOISE_FREQ + vec3(0.0, -Time * UPDRAFT * (1.0 + 2.0 * SiegeChurn) * NOISE_FREQ, 0.0);
// F-032-Spiegel: der Kern reißt auf — innere Schale (B2) und Bandinnenkante dünnen aus,
// damit die Arena sichtbar wird (Kampf-Sicht-Kontrakt), der Rand verdichtet als Ausgleich
prof *= 1.0 - CoreFade * (1.0 - smoothstep(0.35, 0.62, rl));
```
**Fallen:** Rotations-Sprünge vermeiden — `SiegeChurn` multipliziert die
WINKELGESCHWINDIGKEIT; damit der Winkel stetig bleibt, in Java stattdessen eine
**integrierte Winkeluhr** als `Time`-Offset füttern (oder churn nur auf UPDRAFT/Dichte
wirken lassen und Spin-Boost über eine separat integrierte `SpinPhase`-Uniform). Der
Siege-Step-Cap 32 (L97) bleibt — Kampf-Features müssen im gekappten Budget lesbar sein.

> ✅ **umgesetzt** (Session 0730, Paket B2/B3/B7) — die Falle wurde per Plan-Option
> „integrierte Winkeluhr" gelöst, dafür gibt es ein DRITTES Uniform:
> `SiegeChurn`/`ChurnTime`/`CoreFade` (fsh L52–64). `ChurnTime = ∫churn·dt` wird in
> `StormVolumeFx` pro Client-Tick akkumuliert (Feld L109–121, Uhr L168–171, Reset
> L376) und im Shader als `spinT = Time + 1.6·ChurnTime` (L144–150) bzw. Updraft-Scroll
> `Time + 2.0·ChurnTime` (L223–224) addiert — Raten ×2.6/×3.0 bei Voll-Siege, Winkel
> stetig. „Mehr Turbulenz": Warp-AMPLITUDE ×(1 + 0.18·SiegeChurn) (L227) — Deckel
> 1.6·1.18 = 1.888 < 1.9 (B4-Falle eingehalten). CoreFade-Aufriss exakt nach Plan-Formel
> auf das kombinierte Feld (L258–261). Java-Quellen: `storm.siegeCoreFade(partialTick)`
> (F-032-Ramp, `StormFxClient` ClientStorm), churn = clamp((siegeScale−1)/
> (siegeRadiusScale−1)) — normalisiert gegen den PAYLOAD-Scale statt des server-privaten
> `StormSiege.RADIUS_SCALE` (Helper `siegeChurn` L330–340, Feeds L251–258).
> Flash v2 (B6) ist NICHT Teil dieses Pakets — `StormWeatherFx` blieb unangetastet.

### B8 — Photon-Parallax-Sync: `eclStormSpin` + rotierende Regen-/Fetzenbänder
**Ziel:** „Von weiter weg simple Veil, näher Photon-Nahfeld" wird eine echte
Parallaxe-Sandwich: Photon-Bänder orbiten MIT der Volumenrotation. Kosten: 0 GPU;
0 neue Executor (Emitter werden in BESTEHENDE fx-Rows generiert).

- `StormPhotonFx.ExprVars` (L326–362): dritte Variable `eclStormSpin` — kontinuierlicher
  Orbitwinkel in Radiant, Java-seitig integriert aus derselben Tick-Uhr wie das
  `Time`-Uniform: `spin = (StormFxClient.ticks() + pt) / 20.0 * 0.07` (0.07 rad/s =
  Rim-Speed der Mittelstrata: `ROT_SPEED 0.10 × stratum 1.0 × (1.4 − 0.7·1.0)`,
  fsh L57, L106–107). Pusher-Signatur intern erweitern (beide Aufrufer:
  `StormPhotonFx.onClientTick`, `StormNearfieldFx.onClientTick` L143).
- Generator-Update (`tools/photon/storm_nearfield_fx.py` + Belt-Generator in
  `build_storm_fx.py`): Positions-Expressions der Belt-/Wisp-Emitter bekommen
  `+ eclStormSpin` im Bearing-Term; NEU je ein Emitter „rain_curtain" (Streak-Sheets bei
  0.92·eclStormR, fallend) und „shred_racers" (Fetzen bei 1.02·eclStormR, doppelte
  Orbitgeschwindigkeit = obere Strata) in den bestehenden Rows.
- Workflow (F6): NUR Generator → `python3 tools/photon/fxlib.py validate` →
  `/dev photon test eclipse:storm_nearfield_wisps` in-game.
**Falle:** Photon kennt keine Differentialrotation — ein Band = eine Winkelrate. Deshalb
zwei Raten (1× Rim, 2× obere Strata), nicht mehr; der Rest der Kohärenz kommt vom Auge.

> ✅ **umgesetzt** (Session 0730, Paket B4/B6/B8, F-096) — dritte ExprVar
> `eclStormSpin` in `StormPhotonFx.ExprVars`; Pusher-Signatur
> `pushExprVars(radius, height, spin)`, beide Aufrufer angepasst
> (`StormPhotonFx.onClientTick` L184, `StormNearfieldFx.onClientTick` L143–145).
> **Formel-Abweichung (dokumentiert):**
> `spin = (ticks/20 + 1.6·churnTimeSeconds())·0.07` statt der reinen Plan-Formel —
> B7 hat die Volumenrotation churn-abhängig gemacht (`spinT = Time + 1.6·ChurnTime`),
> also muss die Photon-Uhr dieselbe integrierte Winkeluhr lesen, sonst laufen die
> Bänder unter Siege aus dem Sync. Neuer package-private Accessor
> `StormVolumeFx.churnTimeSeconds()` (L162). **Vorzeichen-Gesetz (Plan-`+` war
> falsch):** der Shader rotiert das SAMPLING um +spin ⇒ Weltfeatures wandern mit
> −spin (θ=atan2(z,x)); Photon `orbital` ist rad/s (jar-verifiziert:
> `AngularVelocity` wendet orbital·0.05 rad/Tick an) und dreht θ ebenfalls Richtung
> −. Also: Bearing-Terme `−eclStormSpin` bei POSITIVEM orbital. Generatoren:
> `ring_shape`-Bearing beider Dateien (`build_storm_fx.py` L129,
> `storm_nearfield_fx.py` L136) und `COLUMN_BEARING` (Updraft-Säulen präzedieren
> mit) bekommen `−eclStormSpin`. NEU: `rain_curtain` in `storm_nearfield_wisps`
> (0.92r, 4 quantisierte Vorhang-Zellen ±0.55 Jitter, Fall −8…−11 blk/s linear,
> orbital +0.07, Rate 0.30/t; L243–275) und `shred_racers` in `storm_cloud_belt`
> (1.02r, 3 Zellen, Spawn `−2·eclStormSpin`, orbital +0.14 = obere Strata,
> Rate 0.5/t, prewarm; L333–360). Beide in den TUNED-Tabellen (Java
> `TUNED_EMITTERS`/`TUNED_BASE_RATES` + Python `BASE_RATES`) — Zero-Emission-Attach
> der Handover-Rampe bleibt intakt. Expr-Engine jar-verifiziert: statisches
> `Parser.parse` erlaubt beliebige Variablen (kein allow-List), `min`/`max` sind
> eingebaute 2-Arg-Funktionen, `PI` wird von Photons `Function`-Shape registriert —
> die Höhenkappungen `min(H·0.62, 34)` u. ä. parsen sicher. Idle: Spin-Push ist ein
> reiner Variablenwert; ohne aktive Photon-Rows keine Wirkung, .fx-Regeneration
> deterministisch (fxlib „valid", Lint 0 NEU gegen Baseline 50).

### B9 — Budget-Rebalance + In-Shader-Tier-Gate (`DetailTier`)
**Ziel:** Alle neuen Terme sauber tier-gegated, Worst-Case llvmpipe-fest. Kosten: neg.
- Neues Uniform `DetailTier` (0/1/2) aus `effectiveTier(storm)` (L304–307) — bisher
  erreicht nur `ShadowTaps` den Shader als Tier-Proxy.
- Gates: B2 `cell2` + B4 nur Tier ≥ 2; B3 `convCell` Tier ≥ 1 (Tier 0: towerCol = 0.5
  konstant — Profilform bleibt, Säulenvariation entfällt); B1/B5/B6/B7 alle Tiers.
- Y-Slab-Clip aus B3 für ALLE Tiers (spart, kostet nichts).
- Schatten-Diät bleibt unangetastet: `detail < 0.5`-Pfad rechnet weiterhin NUR
  tower+bulge+fbm2 (4 N) — B2/B3-Zellen dort per Midline-Konstante ersetzen.
- Markiertes Experiment (RISIKO, F1): `OCC_VOLUMETRIC_CORE 0.30 → 0.25` für +5 %
  Marschchord. Nur zusammen mit B2 (innere Schale deckt den Kern), Sichtprüfung S5
  Pflicht: Never-see-inside darf nicht aufweichen. Bei Zweifel: 0.30 behalten.

> ✅ **B9-Basis umgesetzt** (Session 0730, Paket B1/B5/B9-Basis; Zeilen: Stand nach
> B2/B3/B7): `DetailTier`-Uniform deklariert (`storm_volume.fsh` L51–54) und aus
> `effectiveTier(storm)` gefüttert (`StormVolumeFx.java` L246–250); Y-Slab-Clip
> ny ∈ [−0.25, 1.45] im gestauchten Raum für ALLE Tiers (Konstanten `SLAB_NY_MIN/MAX`
> fsh L95–102, Plane-Schnitte L360–378). Der Slab deckte den damaligen Dichte-Cut
> (−0.20/1.22) UND die B3-Decke (1.42) ab — B3 brauchte hier wie vorgesehen keine
> Bounds-Änderung.
>
> **Nachtrag (Paket B2/B3/B7):** Die Tier-Gates sind jetzt LIVE — B3 `convCell` Tier
> ≥ 1 (fsh L170–174), B2 `cell2` Tier ≥ 2 (L243–249); Schatten-Diät hält (detail <
> 0.5 ⇒ Midlines 0.5/0.775, weiterhin 4 N pro Tap). `BOUNDS_MARGIN` wurde mit B3 auf
> 1.70 angehoben (Bilanz siehe B3-Vermerk). Das markierte OCC-Experiment
> (`OCC_VOLUMETRIC_CORE` 0.30 → 0.25) bleibt NICHT umgesetzt — 0.30 steht. B4 (Warp
> v2 Tier 2) ist weiterhin offen.

### B10 (optional) — Upsample-Politur: Transmittanz-Kantenschärfung
**Ziel:** Halbres-Kanten an Turm-Silhouetten (B3 macht die Silhouette komplexer).
In `storm_volume_upsample.fsh` L70 die Similarity zusätzlich mit
`exp(-abs(tap.a - centerGuess) * 4.0)` gewichten (Transmittanz-Kontrast als zweiter
Edge-Detektor). Kosten: 0 zusätzliche Textur-Taps. **Verworfen dagegen:** temporale
Reprojektion/Blending über das persistente `volume_half` (`clear:false`) — ohne
Prev-Frame-Matrizen ghostet es beim Kameraschwenk; llvmpipe-Frametimes machen
Temporal-Artefakte zudem unbeurteilbar (§7).

> ⏸ **dokumentiert weggelassen** (Paket B4/B6/B8, F-096) — Entscheidung nach
> §6.5-Kriterium: B4 moduliert nur den Body INNERHALB der bestehenden Bounds
> (kein neuer Silhouettenterm — die Warp-Amplitude bleibt unter dem etablierten
> 1.9-Deckel, `BOUNDS_MARGIN` 1.70 unberührt), B6 ist reine Emission entlang
> bestehender Dichte, B8 ist komplett Photon-seitig. Erwartbar keine NEUEN
> Halbres-Kanten gegenüber dem B3-Stand; `storm_volume_upsample.fsh` bleibt
> unangetastet. Falls In-Game-Screenshots (Verifikationsplan §6, S3/S4) doch
> Turm-Kanten zeigen, ist die L70-Formel oben der vorbereitete nächste Schritt.

---

## 4. Performance-Budget (llvmpipe-Referenz, Half-Res bleibt)

Kosten pro **belichtetem** Camera-Sample in N (= 1 `evNoise3`):

| Pfad | Ist | Nach Plan | Delta |
|---|---|---|---|
| Tier 2 Dichte (Camera) | 10 (fbm5 5 + warp 3 + tower/bulge 2) | 13 (+cell2 +convCell +warp2) | +30 % |
| Tier 2 Schatten (3 Taps) | 12 (3×4, Diät) | 12 (unverändert — Diät hält) | 0 % |
| **Tier 2 gesamt/Sample** | **22** | **25** | **+14 %** |
| Tier 1 gesamt/Sample | 18 (2 Taps) | 20 (+convCell; kein cell2/warp2) | +11 % |
| Tier 0 gesamt/Sample | 18 | 18 (nur B1/B5/B6/B7 = 0 N) | 0 % |
| Leeres Sample | 2 | 3 (+convCell fürs rEff) | +1 N |
| Flash aktiv | +0 | +1 (vein) | selten |

Gegenrechnung: Y-Slab-Clip (B3/B9) spart bei Blick von oben/schräg 15–30 % Marschweg;
Early-outs (trans<0.02, Skips) unverändert. Worst Case bleibt durch die BESTEHENDEN
Java-Caps gedeckelt: Fullscreen 48 Steps (L89), Siege 32 (L97), Distance-LOD ×0.5
(fsh L249–251). Erwartung: Tier 2 ≤ ~15 % teurer im dichten Band, Tier 0 kostenneutral —
Abnahmekriterium V6.

---

## 5. Reihenfolge & Abhängigkeiten

1. **B1 + B5** (nur `volumeLight`/Phase, 0 N, kein Java) — sofortiger Masse-Sprung,
   isoliert screenshotbar. ⟵ *größtes visuelles Upgrade pro Aufwand*
2. **B9-Basis** (`DetailTier`-Uniform + Y-Slab-Clip) — Fundament für alles Weitere.
3. **B3** (Höhenprofil + Margin-Anhebung BEIDSEITIG) — größter Silhouetten-Gewinn;
   danach zwingend Bounds-Screenshot S2 (keine flachgeclippten Türme? F2).
4. **B2** (zweite Schale) — braucht B1/B5 (sonst säuft die innere Schicht schwarz ab).
5. **B7** (Siege-Uniforms) + **B6** (Flash v2) — Java-Feeder-Arbeit, unabhängig testbar.
6. **B4** (Warp v2, Tier 2) — Feinschliff des Waberns.
7. **B8** (Photon-Sync) — separater Workstream (Python-Generatoren + ExprVars), parallel
   zu 1–6 möglich; Integration erst nach B3 sinnvoll (Bänder gegen finale Silhouette).
8. **B10** (Upsample) — nur falls S2/S4 Halbres-Kanten zeigen.

Datei-Eigentum je Paket (PLAN-STORM2-Prozess): Shader-Pakete (1–6) besitzen
`storm_volume.fsh` + `eclipse_volume.glsl` + `StormVolumeFx.java` (+`StormWeatherFx` für
B6); B8 besitzt `StormPhotonFx.java`/`StormNearfieldFx.java` + `tools/photon/*` —
keine Überschneidung.

---

## 6. Verifikationsplan

**Statisch:**
- V1 `./gradlew build` (strikt; erster Build auf frischer VM 10–30 min — AGENTS.md).
- V2 Shader-Syntax: `glslangValidator` ist auf der VM NICHT installiert; Veil kompiliert
  Pinwheel-Shader zur Laufzeit — Kompilerfehler erscheinen im `runClient`-Log als
  `Failed to load shader` mit GLSL-Fehlerzeile. Log greppen: `rg "storm_volume" run/logs/latest.log`.
- V3 Photon: `python3 tools/photon/fxlib.py validate` nach jeder Generator-Runde (F6).

**In-Game (runClient, llvmpipe: Fenster klein, 20–40 s Wartezeiten, computerUse):**
- Setup: Singleplayer-Dev-Welt; `run/mods-client`-Jars NICHT nach `run/mods` kopieren
  (Iris würde die Veil-Pipeline deaktivieren — F9!). Sturm spawnen im Chat:
  `/eclipsefx storm add 48 96 sphere` (`FxDevCommands` L182–185; Default ohne Args wäre
  VORTEX — das Volume greift NUR bei sphere, `StormVolumeFx` L169).
  Entfernen: `/eclipsefx storm remove`. Für Server-seitige Checks (Status, Gating):
  `python3 tools/rcon/rcon.py "..."` — Visuals brauchen aber den Client.
- Screenshot-Punkte (je Tag `/time set noon` UND Nacht `/time set midnight`):
  - **S1** ~300 Blöcke: nur Far-Wall (Handover-Basislinie, muss unverändert sein — F9).
  - **S2** ~180 Blöcke: Blend-Zone; Silhouette gegen Himmel — Türme rund ausmodelliert,
    NICHT flach abgeschnitten (F2-Kontrolle nach B3).
  - **S3** ~100 Blöcke, Sonne HINTER dem Sturm: Silver-Lining + Powder-Ränder (B1).
  - **S4** ~100 Blöcke, Sonne im Rücken: Schattenbäuche, radiale Abdunklung (B5),
    innere Schale in Lücken sichtbar (B2), Photon-Bänder drehen synchron (B8 — 2
    Screenshots im Abstand ~30 s, Winkelversatz vergleichen).
  - **S5** ~30 Blöcke + innen: Wallcloud über dem Kopf, Interior-Handover weich; Kern
    bleibt blickdicht (F1/OCC-Kontrolle, besonders falls B9-Experiment aktiv).
  - **S6** Blitz: `/eclipsefx storm bolt 1.0` mit Blick auf die Wand — zwei Zellen,
    Adern-Struktur (B6).
  - **S7** Siege: `/summon eclipse:fog_tyrant` im Sturmfuß (FogBossEntities L29) →
    Kern-Dissolve + Churn-Eskalation (B7); danach Tyrant töten → EXPLODE-Beat intakt.
- A/B-Qualität: `stormVolumeQuality` 2/1/0 in der Client-Config
  (`EclipseClientConfig` L158) durchschalten — Tier 0 muss dem Ist-Stand entsprechen
  (Kostenneutralität, §4), kein Feature-Popping beim Tier-Wechsel.
- **V6 Perf-Abnahme:** fester Kamerapunkt (S4-Position), F3-Frametime vorher/nachher je
  Tier; Abbruchkriterium: Tier 2 > +20 % oder Tier 0 > +5 % im dichten Band.
- Regression: `/eclipsefx storm add 48 96 sphere` unter aktivem Iris-Shaderpack
  (Jars temporär in `run/mods`) — CPU-Shell-Fallback bit-identisch zum Ist (F9),
  danach Jars wieder entfernen (Server-Crash-Falle, AGENTS.md Mods-Layout).

---

## 6.5 Umsetzungsplan Paket B4/B6/B8 (F-096, VOR Implementierung notiert)

Reihenfolge B4 → B6 → B8, nach jedem Baustein `./gradlew compileJava`.

- **B4** (nur fsh, Tier 2, +1 N Camera): im `detail > 0.5`-Zweig von `stormDensity`
  Warp-Rotor `wa = Time·0.04` auf `w1.xz` + zweite Warp-Ebene
  `w2 = evNoise3(np·1.7 + Time·0.05)`. **Deckel-Korrektur gegen den Plan:** der
  B7-Churn-Faktor (1+0.18·SiegeChurn) und der B4-Faktor (1+0.35·(w2−0.5))
  MULTIPLIZIEREN sich — worst case 1.6·1.18·1.175 = 2.22 > 1.9 (Riss-Falle). Deshalb
  kombinierter Multiplikator `wm = min((1+0.18·SiegeChurn)·(1+0.35·(w2−0.5)), 1.1875)`
  ⇒ 1.6·1.1875 = 1.9 exakt am Deckel. Budget §4: Tier-2-Dichte 13 N ✓.
- **B6** (fsh + `StormWeatherFx` + Feed in `StormVolumeFx`): neue Uniforms
  `Flash2Pos` (vec3) / `Flash2Amount` / `FlashSeed` (float). Vein-Term wird EINMAL
  gehoisted (`vein = 0.55 + 0.90·evNoise3(u·9 + FlashSeed·17)`) wenn IRGENDEIN Slot
  aktiv ist — +1 N statt +2 N bei Doppel-Flash; beide Slots additiv
  `amt·2.5·vein·exp(−fd/(0.30·R))`, alle Tiers. Java: zweiter unabhängiger
  Scheduler-Slot in `StormWeatherFx` (eigene Arrays, eigene Hash-Salts, Kadenz
  130–340 t — bewusst versetzt zu 90–260, damit Überlappung vorkommt aber nicht
  Dauerzustand ist); Slot 2 bumpt NICHT `flashSerial` und claimt KEIN Licht/keinen
  Interior-Beat (W-C-Vein + Punktlicht bleiben Slot-1-exklusiv — sonst feuerte der
  Photon-Vein auf die falsche Zelle). Accessors `innerFlash2Amount/Bearing/Lat`;
  `feedVolume` füttert Flash2* nach dem FlashPos-Muster, `FlashSeed =
  innerFlashSerial() % 64`. Idle-Regel: alle 3 neuen Uniforms = 0 ⇒ bit-identisch
  (vein multipliziert nur INNERHALB der Amount-Gates).
- **B8** (`StormPhotonFx`/`StormNearfieldFx` + beide Generatoren): dritte ExprVar
  `eclStormSpin`, Pusher-Signatur `pushExprVars(radius, height, spin)`;
  `spin = (ticks/20 + 1.6·churnTime)·0.07` — B7-konsistent über einen neuen
  package-private Accessor `StormVolumeFx.churnTimeSeconds()` (Winkel bleibt auch
  unter Siege synchron/stetig; Abweichung von der reinen Plan-Formel, dokumentiert).
  **Vorzeichen-Gesetz (Plan-Skizze korrigiert):** der Shader rotiert das SAMPLING um
  +spin ⇒ Weltfeatures drehen mit −spin (θ = atan2(z,x)); JOML `rotateY(+a)` dreht
  ebenfalls θ → θ−a (jar-verifiziert: AngularVelocity wendet `orbital·0.05` rad/Tick
  an ⇒ orbital ist **rad/s**). Sync also: Bearing-Term `− eclStormSpin` (bzw.
  `− 2·eclStormSpin`) bei POSITIVEM orbital 0.07 bzw. 0.14 rad/s — das Plan-`+`
  hätte die Bänder mit 2ω GEGEN das Volumen laufen lassen. Generator-Änderungen:
  `ring_shape`-Bearings beider Generatoren + `COLUMN_BEARING` (Updraft-Säulen
  präzedieren sichtbar mit) bekommen `−eclStormSpin`; NEU `rain_curtain` in
  `storm_nearfield_wisps` (0.92r, 4 quantisierte Vorhang-Zellen, Fall −8…−11 blk/s
  [linear = Blöcke/s], orbital 0.07, Rate 0.30/t) und `shred_racers` in
  `storm_cloud_belt` (1.02r, 3 Zellen, orbital 0.14, Spawn `−2·eclStormSpin`,
  Rate 0.5/t). Beide in die TUNED-Tabellen (Java + BASE_RATES) — sonst bräche die
  Zero-Emission-Attach-Regel der Handover-Rampe. Neue Emitter: alpha + DISTANCE-
  Sorting (kein neues LINT-ALPHA-NOSORT; Baseline `storm_cloud_belt` band_* bleibt
  name-keyed stabil).
- **B10**: Entscheidung nach B4/B6/B8 — B4 moduliert nur den Body innerhalb der
  bestehenden Bounds, B6 ist reine Emission, B8 ist Photon-seitig: kein neuer
  Silhouettenterm ⇒ erwartbar keine neuen Halbres-Kanten; dann dokumentiert weglassen.

> ✅ **Paket GELANDET** (F-096) — B4/B6/B8 wie oben geplant umgesetzt (Details in den
> §B4/§B6/§B8-Status-Vermerken), B10 dokumentiert weggelassen (§B10-Vermerk).
> Verifikation: `compileJava` grün (stormfx-Paket gegen HEAD-Snapshot isoliert
> kompiliert — parallel-Team-Dateien `ExpansionBorderFx` u. a. waren zeitweise in
> nicht-kompilierendem Zwischenstand, NICHT unsere Änderungen); Photon-Regeneration
> deterministisch, alle 9 storm_*-Assets „valid"; `fxlib.py validate --lint`:
> 0 NEUE error/warn gegen die 50er-Baseline, keine Findings auf `rain_curtain`/
> `shred_racers`; GLSL-Syntax via glslangValidator (Includes aufgelöst,
> VeilCamera-UBO synthetisiert) OK.

---

## 7. Explizit verworfen (mit Begründung)

- **Echter 2. Raymarch Richtung Sonne** (auch 2–3 Steps): +8–12 N pro belichtetem Sample
  ≈ +50 % Gesamtkosten — auf llvmpipe indiskutabel; B5-Analytik + bestehende Taps liefern
  90 % des Reads.
- **3D-Noise-Textur statt prozeduralem `evNoise3`:** Veil-Texturbindung unterstützt
  Resource-PNGs/Framebuffer (Wiki `Shader.md` §Textures) — kein `sampler3D`-Pfad ohne
  Java-seitige Textur-Registrierung; auf llvmpipe ist Textur-Sampling ebenfalls Software.
  Aufwand/Nutzen negativ.
- **Temporale Reprojektion** im `volume_half`: keine Prev-Matrizen im Pinwheel-Post,
  Ghosting-Risiko, auf Seconds-per-Frame-llvmpipe nicht beurteilbar (B10-Notiz).
- **„Aperture"-Module:** existieren in Veil nicht (AGENTS.md) — jede Idee, die darauf
  baut, ist tot.
- **Mehr `DENSITY_GAIN` / mehr Oktaven im Schattenpfad:** verletzt F8 bzw. zerstört die
  AUDITFIX-4-Schatten-Diät für <5 % sichtbaren Gewinn.
