# C4 — Kleine Cues + Neue Effekte (FX-Welle 13, §7 Welle C Zeile C4)

**Auftrag:** Cue-Familien `supply`, `landmark`, `quest`, `minigame`, `race`, `glide`,
`sky_launch`, `portal`, `sig` auf Welle-13-Niveau + die drei neuen Effekte
**N8** Contract-Brandmal, **N14** Sanctum-Konfession, **N10** End-Statik.

**Datei-Besitz (beansprucht, siehe §1.1):** `tools/photon/worldevents_fx.py`,
`newfx_a_fx.py`, `sig_fx.py`, `gen_ph_social.py` (je ganz) + die `portal_*`-Builder in
`events_fx.py` und die `supply_*`/`sky_launch_*`-Builder in `build_world_fx.py`
(teil-exklusiv, §1.2) + deren `.fx`/`.fxproj`. NEU: `tools/photon/wave13c_smallcues_fx.py`,
`veilfx/SmallCueFxRows.java` (Registrar **inklusive** des N14-Fensters als verschachtelte
Klasse `SanctumConfession` — §3.3 begründet, warum daraus keine eigene Datei in
`client/sanctum/` wurde), `pinwheel/post/end_static.json`,
`pinwheel/shaders/program/end_static.fsh` + `.json`, `veilfx/EndStaticFx.java`.
Cue-Hook (minimal, 3 Stellen / +33 Zeilen): `contracts/ContractService.java`.

---

## 1 Bestandsaufnahme (verifiziert am Repo, nicht aus dem Gedächtnis)

### 1.1 Generator-Zuordnung — welcher kleine Cue lebt wo

Die Konflikt-Einheit ist laut §7 Konflikt-Gesetz 1 **der Generator**, nicht das einzelne
`.fx`. Zuordnung per `rg -l` über `tools/photon/` und Abgleich mit den Welle-13-Zeilen:

| Generator | Assets | C4? | Begründung |
|---|---|---|---|
| `worldevents_fx.py` | `supply_herald`, `contract_omen_ripple`/`_release`, `minigame_gate_fanfare`/`_collapse`, `race_finish_ribbon`/`_gold`, `dungeon_maw_breath`/`_idle`, `rim_recede`, `boss_summon_beacon_0..3` | **ganz** | Jedes Asset fällt in eine C4-Familie (supply/minigame/race) oder ist unzugeteiltes Welt-Event. Kein anderes Welle-13-Team nennt den Generator. |
| `newfx_a_fx.py` | `quest_sigil_burst`/`_pillar`, `landmark_flare`/`_echo`, `collection_tier_halo`/`_gold_rain`, `skill_spend_glint`, `wizard_catalyst_handover` | **ganz** | `quest` + `landmark` sind namentlich C4. `collection_*` steht zwar in B6s Paket-Text, B6 hat den Generator aber **nicht angefasst** (§1.3) — Konflikt-Gesetz 1 (Generator = Einheit) schlägt die Namensliste, also kommen sie als Beifang mit. |
| `sig_fx.py` | `sig/crown_verdict`, `sig/crown_verdict_coda`, `sig/gold_rush`, `sig/sanctum_bloom`, `sig/deep_rumble_bed` | **ganz** | „sig-Familie" ist wörtlich C4. |
| `gen_ph_social.py` | `glide_trail`, `contract_mark`, `theft_soul_rise`/`_launch`/`_arrive`, `rebirth_aura_1/2/3`, `ghost_wisp` | **ganz** | `glide` + `contract` sind C4. B6 listet `rebirth_aura_*` explizit als **nicht angefasst / keinem Team zugeteilt** (B6-Report §1.1) und liefert nur ein Patch-Snippet — ich übernehme den Generator als Ganzes und fixe den dort gemeldeten `radial`-Bug gleich mit. |
| `events_fx.py` | **nur** `portal_iris_open_xbox`/`_backrooms`, `portal_loop_xbox`/`_backrooms` | **teil** | `portal` ist C4. `intro_burst_ring`, `credits_*` (C5 läuft parallel!), `structure_slam_mushroom`, `slam_dust_puff` bleiben **byte-identisch** (§1.2-Verfahren). |
| `build_world_fx.py` | **nur** `supply_drop_contrail`, `supply_landing_dust`, `sky_launch_charge`, `sky_launch_contrail` | **teil** | `supply` + `sky_launch` sind namentlich C4 und existieren NUR hier. `breach_*` = A6, `end_void_wisps` = C1 (GPU-Instancing läuft parallel!), `storm_crown_halo` = F-096 — alle drei bleiben byte-identisch. |

**Bewusst NICHT beansprucht:**

* `newfx_d_fx.py` — enthält zwar `portal_draw_in`, ist aber mehrheitlich fremd
  (`breach_drift_cocoon` = A6, `totality_diamond_ring` = A9, `storm_outrunners` = F-096).
  Konflikt-Gesetz 1 würde mir mit einem Asset den ganzen Generator geben; das Risiko steht
  in keinem Verhältnis. Nicht angefasst.
* `ferryman2_fx.py` (`portal_soul_veil`) — A3 namentlich.
* `woah_*`/`chrono`/`echo_grove`/`resonance` (C3 parallel), `credits*`/`end_arrival*`
  (C5 parallel), `mobs_fx`/`scare_fx` (B2 frisch), `ceremony_fx`/`gen_player_fx` (B6 frisch).

### 1.2 REPO-BEFUND: `.fx`-Regeneration ist NICHT deterministisch

Vor der ersten Zeile Politur geprüft: alle sechs Generatoren **ohne jede Quelländerung**
laufen lassen und `git status` gelesen. Ergebnis: **jedes** erzeugte `.fx` gilt als geändert.

Ursache ist `fxlib.py:706` — `self.uuid = str(_uuid.uuid4())`. Jedes fx-Objekt bekommt bei
jedem Lauf eine frische Transform-UUID, die als `transform.id` (und in den `children`-Listen)
im NBT landet:

```
raw len old/new: 6605 6605     # gleiche Struktur …
raw equal: False               # … aber:
old: …\x08\x00\x02id\x00$b171710f-0cd3-47ba-b654-574069d2caec…
new: …\x08\x00\x02id\x00$d135e032-17c9-4171-bdad-5422ee35637d…
```

Konsequenz für die geteilten Generatoren: `python3 tools/photon/build_world_fx.py` schreibt
**auch** A6s `breach_*`, C1s `end_void_wisps` und F-096s `storm_crown_halo` neu — reine
UUID-Churn, aber ein garantierter Binär-Merge-Konflikt mit parallel laufenden Teams.

**Mein Verfahren** (statt fxlib zu patchen — gehört A0):

```bash
python3 tools/photon/build_world_fx.py
git checkout -- <alle .fx/.fxproj die mir nicht gehören>
```

Damit bleiben Fremd-Assets bit-identisch zu HEAD. Verifiziert über `git status` am Ende
jedes Regen-Schritts (§4). Patch-Snippet für eine deterministische UUID-Ableitung
(fxlib gehört A0) steht in §6.1 — das ist kein C4-Fix, aber ein wave-weiter Stolperstein.

### 1.3 Einheiten — das ×20/×100-Muster von B6 gilt auch hier

B6 hat für `ceremony_fx.py` nachgewiesen (und ich habe es unabhängig am Photon-Jar
verifiziert, siehe unten): Photon liest `startSpeed` und `velocityOverLifetime.linear` in
**Blöcken pro SEKUNDE** (`×0.05`/Tick), `radial` mit `×0.01`/Tick, `orbital` in rad/SEKUNDE.

Jar-Verifikation (nicht aus B6 übernommen, selbst dekompiliert):

* `Sphere`/Shape: setzt Richtung `× 0.05`, danach `mulInternalVelocity(startSpeed)`.
* `VelocityOverLifetimeSetting`: `linear × 0.05`, `radial × 0.01`, `orbital × 0.05`.

Weg-Formel: `Blöcke = v × 0.05 × Lebensdauer_in_Ticks` (linear/startSpeed),
`Blöcke = v × 0.01 × Lebensdauer_in_Ticks` (radial).

Audit über alle C4-Assets (Skript rechnet die Ist-Strecke je Emitter aus). Die
gravierendsten Treffer — Kommentar-Absicht gegen tatsächlich gelaufene Strecke:

| Asset · Emitter | Absicht laut Kommentar/Name | Ist-Strecke vorher |
|---|---|---|
| `boss_summon_beacon_0.indraw` | Motes r=2.2 in den Beacon gesogen | **0.09 Blöcke** |
| `contract_omen_ripple.cinders` | Funken steigen über dem Siegel auf | **0.11 Blöcke** |
| `contract_omen_release.reverse_cinders` | Rückwärts-Einzug ins Siegel | **0.07 Blöcke** |
| `contract_omen_release.gray_exhale` | grauer Ausatem zieht ab | **0.00 Blöcke** |
| `supply_herald.shimmer` / `.tear_wisps` | Riss-Schimmer / Wisps am Riss | **0.01–0.03 / 0.08** |
| `quest_sigil_pillar.base_glints` | Glints am Säulenfuß | **0.02–0.05 Blöcke** |
| `landmark_echo.echo_glints` | Echo-Glints laufen aus | **0.04 Blöcke** |
| `collection_tier_halo.crown_glints` | Kronen-Glints | **0.05 Blöcke** |
| `skill_spend_glint.*` | Linse + Konstellation | **0.00 Blöcke** |
| `sig/deep_rumble_bed.ceiling_dust` | Deckenstaub rieselt | **0.00–0.03 Blöcke** |
| `theft_soul_rise.in_wisps` | Wisps ziehen zur Seele | **0.01 Blöcke** (radial) |
| `rebirth_aura_*.rising_motes` | Motes steigen in der Aura | **0.03 Blöcke** |
| `ghost_wisp.wisps` | Wisp-Drift | **0.03 Blöcke** |
| `sky_launch_contrail.slip_rings` | Ringe schlüpfen nach hinten | **0.00 Blöcke** |

`rim_recede` ist die Ausnahme: bereits in b/s geschrieben (9–17.5 Blöcke) und bleibt
unangetastet in den Einheiten.

### 1.4 Welle-13-Hebel, die im C4-Paket fehlten

`random_gradient`: **0 von 43** Emittern (einzige Ausnahme: zwei `random_color`-Flicker in
`portal_loop_*`) — der Klon-Look ist über das ganze Paket flächendeckend.
Birth-Tints: durchweg hell (erster RGB-Stop = Peak-Farbe) statt dunkel.
HDR über der 1.45-Decke an 14 Materialien (Spitze: `sig/crown_verdict.verdict_flash` 2.60,
`minigame_gate_collapse.implosion_flash` 2.40, `portal_iris_open_*.iris` 2.60).
Timing: Attack/Decay symmetrisch statt „kurz rein, lang raus".

---

## 2 Plan

### P1 Kleine-Cue-Politur (6 Generatoren, 43 Assets)

Gemeinsames Haus-Vokabular, in jedem Generator lokal (fxlib gehört A0, also **kein**
neuer shared Helper dort): `hdr()`-Clamp auf 1.45, `varied()` für `random_gradient`,
dunkle Birth-Tint-Konstanten je Palette, `SEG_SNAP_*`-Segmente. Muster 1:1 aus
`ceremony_fx.py` (B6-poliert) übernommen, damit das Repo EINEN Stil hat.

1. **Einheiten** — jede Geschwindigkeit auf die im Kommentar dokumentierte Strecke
   zurückgerechnet (`×20` linear/startSpeed, `×100` radial, orbital auf rad/s).
2. **`random_gradient`** auf jedem Emitter mit ≥ 3 Partikeln.
3. **Dunkle Birth-Tints** (V2.1-Stacking-Gesetz): erster RGB-Stop unter der Zielfarbe,
   Peak erst bei t ≈ 0.2–0.35.
4. **HDR-Decke 1.45**, Hue-Ratio bleibt erhalten.
5. **Timing-Snap** — Attack 8 t → 3–5 t, Decay verlängert.

### P2 N8 `contract_seal_brand`

Neues Asset in neuem Generator `wave13c_smallcues_fx.py`. Siegel-Glyphe brennt sich in den
Boden und glimmt **60 s** (1200 t) nach. Server-Trigger im `contracts`-Paket neben
`CUE_CONTRACT_OMEN`; Row in **neuer** Registrar-Klasse `veilfx/SmallCueFxRows.java`
(Zwei-Seiten-Cue-Muster aus `CutsceneBeatFxRows.java`: Server hält die private
`FxCues.cue(...)`-Konstante, der Client leitet dieselbe `ResourceLocation` neu ab).

### P3 N14 `sanctum_confession`

Neues Asset im selben Generator. Schrift-Glyphen steigen beim Betreten des L5-Sanctums wie
Gebete in die Lightfall-Säule. Fenster: dasselbe Hysterese-Fenster, an dem
`client/sanctum/SanctumLightfall.java` hängt — neuer Controller `SanctumConfession.java`,
der `SanctumLightfall` **nicht** verändert (One-Shot beim ENTER, re-armt beim Verlassen).

### P4 N10 `eclipse:end_static` (Veil FEATURE)

`pinwheel/post/end_static.json` + `program/end_static.fsh` + `veilfx/EndStaticFx.java`.
Feine chromatische Aberration + Sternfeld-Bleed in Schattenpartien, Nähe zu den
`CUE_RIFT_AMBIENT`-Fenstern. `VeilPostController.register(...)` ist bereits `public` —
**kein** Patch an fremdem Code nötig (§6.2). Idle-Uniform 0 ⇒ bit-identischer Frame,
Degenerate-Depth (`depthSample == 0.0`) nach A0-Muster gehärtet, llvmpipe-tauglich.

---

## 3 Was tatsächlich entstanden ist

### 3.1 P1 Politur — 44 Assets geändert, 0 Fremd-Asset angefasst

Alle sechs Generatoren tragen jetzt dasselbe lokale Haus-Vokabular (`hdr()`, `varied()`,
`*_BIRTH`-Konstanten, `SEG_SNAP_*`), 1:1 im Stil von `ceremony_fx.py`. Messung über die
**ausgelieferten `.fx`-Bytes** (nicht über den Generator-Quelltext), HEAD gegen Arbeitsbaum,
alle 46 C4-Assets:

| Befund | HEAD | nach C4 |
|---|---:|---:|
| Emitter mit Sub-Block-Strecke (der ×20-Einheiten-Bug) | 24 | **1** |
| Material-HDR über der 1.45-Decke | 41 | **0** |
| Klon-Farbrampen auf Emittern mit > 12 Partikeln | 54 | **0** |

Das eine verbliebene Sub-Block-Ergebnis ist `skill_spend_glint.constellation` (4 Partikel,
0.1 b/s): ein absichtlich **fast stehendes** Funkeln über dem Unterarm, im Generator seit
diesem Pass ausdrücklich als Ausnahme kommentiert. Die ×20-Regel wurde dort angewandt, wo
die **Strecke** falsch war, nicht mechanisch — dieselbe Linie ziehen `glyph_shards`,
`gold_rain` und `catalyst_drop` (physics-/cull-box-gebunden, siehe Generator-Docstring).

Wichtig für das Nachrechnen: **Schwerkraft ist die zweite Bewegungsquelle** und steht in
keinem Velocity-Term. Photon integriert sie (`v += g` je Tick, `x += v·0.05`), also fällt ein
Partikel `g · 0.05 · life² / 2` Blöcke. `sig/deep_rumble_bed.ceiling_dust` ist mit
`startSpeed 0.00–0.01` authored und fällt trotzdem ~4 Blöcke aus 3.4 m Höhe auf den Boden —
ein Audit, das nur `startSpeed`/`velocityOverLifetime` liest, meldet dort einen Fehlalarm.
Die Tabelle oben rechnet die Schwerkraft mit.

`rim_recede` bleibt in den Einheiten unangetastet (war schon in b/s korrekt).

### 3.2 P2 N8 `contract_seal_brand`

Neues Asset (`wave13c_smallcues_fx.py`), fünf Emitter, Gesamtlaufzeit **1200 t = 60 s**:
`sear_flash` (Einbrennen, 26 t) → `seal_glyph` (die Hero-Glyphe, `random_curve` auf dem
Block-Licht, damit das Glimmen unregelmäßig atmet statt zu pulsieren) → `scorch`
(alpha-geblendete Brandscheibe) → `burn_smoke` → `ember_crawl` + `seal_motes` (kriechende
Glut auf dem 1.6-Block-Siegelradius).

Zwei-Seiten-Cue nach dem `CutsceneBeatFxRows`-Muster: `ContractService` hält eine **private**
`FxCues.cue("contract_seal_brand")`-Konstante, `SmallCueFxRows` leitet dieselbe id neu ab —
kein neues Feld in `FxCues`. Der Sender hängt in `finishWindow` direkt neben dem
bestehenden `sendOmenRipple(server, 1.0F)`, also **hinter demselben Trichter**, durch den
jeder Ausgang läuft (success/expired/voided/tables/prank): open und close bleiben ein
garantiertes Paar.

Anonymität: gesendet wird — wie beim Omen-Ripple — **eine Payload pro Online-Spieler an
dessen eigene Füße**. Das Brandmal steht damit überall und verrät niemanden.
`a` = Yaw des Empfängers (das Siegel liegt in Blickrichtung statt jedes Brandmal nach
Norden), `b` = 1 bei blutigem Ausgang, was die Client-Leg als breiteren Brand liest
(`BRAND_SCALE_BLOOD` 1.15 gegen `BRAND_SCALE_LAPSE` 0.85).

### 3.3 P3 N14 `sanctum_confession`

Neues Asset im selben Generator, vier Emitter über 200 t: `bowl_exhale` (die Schale atmet
aus) → `prayer_glyphs` (**der Hero-Layer**: Schrift-Glyphen steigen 7.1 Blöcke über eine
`SEG_PRAYER_PULL`-Kurve von 0.35 auf 2.6 b/s — langsam angesaugt, dann von der Säule
genommen) → `column_answer` (die Lightfall-Säule antwortet) → `arrival_sparks`.

Fenster: **dasselbe** Hysterese-Fenster, an dem `SanctumLightfall` hängt (26 / 40 Blöcke um
`FxAnchors.ALTAR_CENTER`, Altarstufe ≥ 5 aus `ClientStateCache`, plus dieselbe physische
Floating-Probe). `SanctumLightfall` selbst ist **unverändert** — der Controller ist eine
verschachtelte Klasse in `SmallCueFxRows` statt einer eigenen Datei in `client/sanctum/`,
weil er nichts weiter tut als die eigene Row zu feuern und so Cue-Konstante, Row und
Fenster in einer Datei zusammenbleiben (Datei-Besitz eindeutig, kein zweiter Eigentümer im
`client/sanctum/`-Paket). One-Shot beim ENTER, re-armt erst jenseits von `RELEASE_DIST`;
pausenfest; Retry-Kadenz 40 t / max. 4 Versuche, falls die Photon-Bridge den Spawn
verweigert.

### 3.4 P4 N10 `eclipse:end_static`

`pinwheel/post/end_static.json` + `program/end_static.fsh`/`.json` + `veilfx/EndStaticFx.java`.
**Kein Patch an fremdem Code**: `VeilPostController.register(...)` ist bereits `public`, und
die Registrierung läuft — wie bei `UmbralVeinsFx` — aus dem Static-Init.

Drei Lagen im Shader:

1. **Crackle-Hüllkurve.** „Knistern" ist kein Puls: `Time` wird in 10 Slots/s gerastert,
   jeder Slot würfelt seine eigene Amplitude, nur ~34 % zünden überhaupt, und innerhalb
   eines zündenden Slots klingt der Burst exponentiell ab. Ergebnis ist ein unregelmäßiger
   Klick-Zug ohne Rhythmus (Messkurve: Artefakt `end_static_crackle_envelope.png`).
2. **Chromatische Aberration**, radial aus der Bildmitte, zusätzlich von einem
   Band-Rauschen moduliert, das pro Slot neu würfelt — der Split ist nie gleichmäßig über
   das Bild verteilt. Gemessen: Mitte 0.0002, Bildrand 0.0119 (**75×**), Deckel ~3 px.
3. **Sternfeld-Bleed**, zwei Parallaxe-Lagen des geteilten `gzVoidStars`-Gitters entlang des
   Blickstrahls, verankert an der gewrappten Kameraposition. Sichtbar **nur** in
   Schattenpartien (Luma-Maske) und dort stärker, je weiter die Fläche entfernt ist.

Fenster: Proximity zum **`CUE_RIFT_AMBIENT`-Anker**. `EndRiftAmbient` feuert alle 600 t bei
`(centerX+0.5, surfaceY+40, centerZ+0.5)` aus `EndConfig.current()` — und diese Geometrie ist
über `EndConfig.warnFixedGeometry` fest an die eingefrorenen `DiscProfile.END_DISC_*`
gepinnt. Der Client rekonstruiert damit **exakt denselben Anker** ohne Paket und ohne
Server-Read. Die `CUE_RIFT_AMBIENT`-Row in `EndArrivalFxRows` (C5) bleibt unangetastet: eine
Post-Pipeline ist keine Photon-Leg, und eine zweite Row auf dieselbe logische id würde die
Registry ohnehin ablehnen. Materialisierungs-Gate: dieselbe physische Probe wie
`EndVoidWisps` (Block in der Mittelsäule geladen und nicht Luft).

Rampe: voll innerhalb 56 Blöcke, 0 ab 168, Slew 0.06/Tick. Unter `reducedFx` läuft der Pass
weiter, aber gedeckelt auf 0.45 und mit `Detail = 0` — und `Detail = 0` macht den Shader
**exakt zeitinvariant** (kein Burst-Zug, kein Twinkle, kein kochendes Korn).

---

## 4 Verifikation (Ergebnis)

`runClient` war auch in dieser Sitzung nicht fahrbar (der Arbeitsbaum ist parallel von C3 und
C5 belegt, siehe `git status`). Stattdessen dieselbe Werkzeugkette, die B4/B5 in dieser
Session etabliert haben — **auf demselben Renderer, den der Client auf dieser VM benutzt
(Mesa llvmpipe)**.

| Gate | Kommando | Ergebnis |
|---|---|---|
| Photon-Lint | `python3 tools/photon/fxlib.py validate --lint` | **0 NEUE** error/warn, **27 grandfathered** (= die vorgegebene Baseline). Datei- und Advisory-Zahl driften während der Sitzung (266→267), weil C3 parallel Assets anlegt — die beiden Gate-Zahlen tun es nicht. |
| Java | `./gradlew compileJava` | grün; die 2 Warnungen sind `removal`-Deprecations in C3s `ResonancePhotonFxRows` (fremd) |
| GLSL-Syntax | `python3 /tmp/gzvalidate.py` (Veil-Präambel-Komposit → `glslangValidator -S frag`) | **28/28** Shader OK (27 Baseline + `end_static`) |
| glsl-processor-Mine | derselbe Lauf, Bare-Return-/`#`-Lint | `end_static` meldet **0** Bare-Returns — die Mine ist per Konstruktion entschärft |
| Shader-Gesetze | `python3 /tmp/c4_endstatic.py` (echte Frames, llvmpipe) | **8/8 PASS**, siehe unten |
| Besitz | `git status` + UUID-normalisierter Diff aller 83 geänderten `.fx` | 46 gehören C4, davon **0 reine UUID-Churn**; die übrigen 37 (`chrono_*`, `credits4_*`, `end_arrival*`, `gravity_*`, `resonance_*`) sind C3/C5 und von mir nicht angefasst |

### 4.1 Die acht Shader-Gesetze für `end_static`

| # | Gesetz | Ergebnis |
|---|---|---|
| 1 | Idle bit-identisch bei `StaticStrength 0` (exaktes `array_equal`, keine Toleranz) | PASS |
| 2 | Tote Tiefe (flach 0.0, A0-Muster): endlich **und** noch lesbar | PASS (mean 0.173) |
| 3 | Wertebereich endlich / sane bei voller Stärke | PASS (max 0.37) |
| 4 | Time-Sweep 0…100 s in 0.25-s-Schritten, jeder Frame endlich | PASS |
| 5 | `reducedFx` (`Detail 0`) exakt zeitinvariant | PASS (max Δ **0.000000**) |
| 6 | Wrap-Naht: `t = 0` gegen `t = 100 s` | PASS (max Δ 0.000000) |
| 7 | Bleed landet in Schatten, nicht in Lichtern | PASS (dunkel +0.0009 B gegen hell +0.0000 B) |
| 8 | Aberration wächst zum Bildrand | PASS (Rand 75× Mitte) |

Gesetz 6 hat beim ersten Lauf **gefehlgeschlagen** (Δ 0.187) und einen echten Bug gefunden:
der Slot-Wrap für die Crackle-Hashes war 32, die 100-s-`Time`-Klammer enthält aber 1000
Slots — Slot 1000 landete auf Hash-Eimer 8 statt 0, das ganze Muster wäre alle 100 s
gesprungen. Wrap ist jetzt 200 (1000/200 = 5 glatt, und die Crackle-Periode ist damit 20 s
statt 4 s, was ein Auge nicht mehr als Schleife erkennt).

### 4.2 Polish-Iteration

Nach der ersten Sichtung der gerenderten Frames war der Sternfeld-Bleed zu dünn: nur 0.64 %
der Schattenpixel trugen überhaupt etwas, das Ergebnis las sich als „fünf Nadelstiche" statt
als Feld. Nachgezogen auf `FAR_DENSITY 0.52` / `MID_DENSITY 0.30` / `STAR_GAIN 0.55` und das
Schattenfenster von 0.24 auf 0.30 geöffnet → 1.94 % und ein Feld, das als Bleed liest
(Artefakt `end_static_strength_ramp.png`).

---

## 5 Test-Kommandos

```bash
# --- Assets ---------------------------------------------------------------
python3 tools/photon/worldevents_fx.py     # 13 Assets
python3 tools/photon/newfx_a_fx.py         #  8
python3 tools/photon/sig_fx.py             #  5
python3 tools/photon/gen_ph_social.py      #  9
python3 tools/photon/wave13c_smallcues_fx.py   # N8 + N14 (neu)
python3 tools/photon/events_fx.py          # nur portal_* behalten, Rest zurücknehmen:
python3 tools/photon/build_world_fx.py     # nur supply_*/sky_launch_* behalten
git checkout -- <die .fx/.fxproj der Fremdteams>   # PFLICHT, siehe §1.2

python3 tools/photon/fxlib.py validate --lint      # 0 NEUE, Baseline 27

# --- Java + GLSL ----------------------------------------------------------
./gradlew compileJava
python3 /tmp/gzvalidate.py                 # alle Post-Shader durch glslangValidator
python3 /tmp/c4_endstatic.py               # die 8 Gesetze auf echten llvmpipe-Frames

# --- im Spiel -------------------------------------------------------------
/photon_client clear_client_fx_cache       # nach jeder Asset-Regeneration!
# N8:  einen Contract abschliessen -> Siegel brennt sich ein, glimmt 60 s
# N14: Altar auf Stufe 5, Sanctum betreten -> Glyphen steigen in die Lightfall-Saeule
# N10: zur End-Scheibe fliegen (0/360/0); ab ~168 Bloecken setzt das Knistern ein
/eclipsefx post eclipse:end_static on      # Pipeline erzwingen (Dev-Override)
```

Die drei `/tmp`-Skripte sind **Sitzungswerkzeuge** und nicht committet (die FX_CENSUS_WAVE13
§8-Gewohnheit, wie B4/B5 sie halten). `gzvalidate.py` stammt von B4; `c4_endstatic.py`
(die 8 Gesetze) und `c4_polish_table.py` (die Vorher/Nachher-Tabelle aus §3.1) liegen als
Artefakte bei diesem Lauf. Beide bauen auf B4s `gzrender.py`-Harness auf, das eine
synthetische Szene in ein Farb+Tiefen-FBO rendert und den `.fsh` als Veil-artigen
Fullscreen-Blit mit echtem `VeilCamera`-UBO darüberlaufen lässt.

---

## 6 Patch-Snippets / Handover

### 6.1 `fxlib.py` UUID-Determinismus (gehört A0 — NICHT von mir gepatcht)

Der in §1.2 belegte Befund ist der teuerste Stolperstein dieser Welle: jeder Generatorlauf
schreibt **alle** seine Assets neu, auch die fremder Teams. Vorschlag — UUID deterministisch
aus dem Asset-Pfad und dem Objektnamen ableiten statt zu würfeln:

```python
# fxlib.py:706  --  statt: self.uuid = str(_uuid.uuid4())
_FX_UUID_NS = _uuid.UUID("6f1d2c4a-0b3e-4a9f-8c71-2d5e9a0b4c13")  # fixer Eclipse-Namespace
self.uuid = str(_uuid.uuid5(_FX_UUID_NS, f"{owner_asset_id}/{name}"))
```

Damit ist ein Regen ohne Quelländerung ein leerer `git diff`, geteilte Generatoren hören auf,
Merge-Konflikte zu erzeugen, und das `git checkout`-Ritual aus §1.2 entfällt wave-weit.
**Achtung:** der Umstieg schreibt einmalig alle 266 `.fx` **und** ihre `.fxproj`-Geschwister
neu (die Sibling-Datei bettet dieselben Transform-UUIDs ein) — das gehört in einen eigenen,
sonst leeren Commit.

### 6.2 `VeilPostController` — kein Patch nötig

`register(PipelineSpec)` ist bereits `public` und wird von `UmbralVeinsFx`,
`LimboAmbience` und `BorderFxRenderer` aus dem Static-Init benutzt. `EndStaticFx` macht
es genauso; an `VeilPostController.java` ist **keine Zeile** geändert.

### 6.3 Für C5 (End-Arrival, läuft parallel)

`EndStaticFx` liest die Rift-Geometrie aus den eingefrorenen `DiscProfile.END_DISC_*` und
**nicht** aus `EndConfig`, damit die Klasse client-rein bleibt. Falls die End-Scheibe je
verschiebbar wird, ist die Ankerformel in `EndStaticFx.riftStrength` die eine Stelle, die
mitziehen muss — sie ist dort ausdrücklich als Spiegel von `EndRiftAmbient` kommentiert.
Die `CUE_RIFT_AMBIENT`-Row selbst habe ich nicht angefasst.

### 6.4 Offen / bewusst nicht gemacht

* `newfx_d_fx.py` (`portal_draw_in`) bleibt unpoliert — mehrheitlich fremder Generator,
  Begründung in §1.1.
* Sieben Fremd-Shader tragen weiterhin die latente glsl-processor-Mine (Bare-Return ohne
  streunendes `#`): `gravity_lens`, `rift_volume`, `storm_volume` (5×),
  `storm_volume_upsample`, `sun_halo`, `xbox_era`. `gzvalidate.py` listet sie bei jedem Lauf
  mit auf. `end_static` ist per Konstruktion immun.
