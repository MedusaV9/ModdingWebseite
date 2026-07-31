# C2 — fxlib-Infrastruktur (FX-Welle 13, §7 Welle C Zeile C2)

**Auftrag:** (1) Deterministische Transform-UUIDs (C4 §6.1-Empfehlung), (2) Range-Codec-Fix
in `_min_max()` (C5 §3-Fund), (3) CullBox-/Prewarm-Audit über den ganzen Bestand + neue
Lint-Regel. Branch `cursor/project-eclipse`, **nicht committet** — der Integrator committet
zentral; die Commit-Aufteilung steht in §6.

**Datei-Besitz:** `tools/photon/fxlib.py` (Owner diese Welle), alle FX-Generatoren
(einzige .fx-schreibende Instanz dieser Welle laut Auftrag), `lint_baseline.txt`,
regenerierte `.fx`/`.fxproj`.

---

## 1 Plan (vor der ersten Zeile Patch — Audit-Befunde am Bestand)

### 1.1 Paket 1 — Deterministische UUIDs

C4 §1.2 belegt: `fxlib.py` würfelt in `_FxObject.__init__` pro Objekt `uuid4()` →
jeder Generator-Lauf schreibt ALLE seine Assets byte-verschieden. C4s Snippet
(`uuid5(NS, f"{owner_asset_id}/{name}")`) ist als Idee richtig, als Schlüssel aber
**nicht eindeutig**:

* Zwei gleichnamige Objekte im selben Asset → gleiche UUID → `validate` bricht mit
  „duplicate transform.id" (und der Editor kann die Transforms nicht unterscheiden).
  Der Bestand hat solche Namens-Dubletten (z. B. `rim_streamers` in zwei Dateien ist ok,
  aber innerhalb EINER Datei sind Wiederholungen möglich und erlaubt).
* Verschachtelung: `child_of` erzeugt Hierarchien; ein flacher Name kollidiert, sobald
  zwei Eltern gleichnamige Kinder tragen.

**Design:** UUID-Zuweisung wandert von `__init__` (Objekt kennt Asset und Position noch
nicht) nach `FxBuilder.build()`. Schlüssel = `{builder.name}/{hierarchischer Pfad}`,
Pfad = Namenskette Wurzel→Objekt, Namens-Dubletten unter demselben Eltern-Pfad werden
per Vorkommens-Index disambiguiert (`name`, `name#1`, `name#2` … in flacher Objektlisten-
Reihenfolge — die ist generator-deterministisch). `child_of` merkt sich zusätzlich die
Objekt-REFERENZEN; `build()` schreibt `_parentId`/`_childrenId` daraus neu, damit die
Neuzuweisung idempotent ist (`write()` ruft `build()` mehrfach; `.fx` und `.fxproj`
desselben Builders tragen identische UUIDs). Standalone-`build()` außerhalb eines
`FxBuilder` behält den uuid4-Platzhalter (rückwärtskompatibel; kein Generator tut das,
per `rg` verifiziert: niemand fasst `.uuid`/`_parent_id`/`_children_ids` an).

Danach: ALLE Generatoren laufen lassen (44 Skripte + `fxlib.py templates`), die
`.fxproj`-Siblings von `newfx_d_fx.py` (schreibt bewusst keine) über die CLI nachziehen.
Beweise: (a) Zweitlauf = leerer Diff, (b) UUID-normalisierter Binär-Diff jeder geänderten
Datei gegen HEAD = NUR UUIDs, (c) `validate --lint` 0 NEUE.

### 1.2 Paket 2 — Range-Codec-Fix

Selbst nachverifiziert am Bytecode (`javap -v Range.class`, LDLib2 2.2.29-all):
`Range.CODEC` = RecordCodecBuilder mit `fieldOf("a")` / `fieldOf("b")`; die Felder der
Klasse heißen `a`/`b`. `fxlib._min_max()` schreibt `min`/`max` → deserialisiert auf
Defaults. Photon-Seite verifiziert: `ColorBySpeedSetting.speedRange` ist ein
LDLib2-`Range`-Feld (ebenso Size/Rotation/LifetimeByEmitterSpeed).

Bestands-Audit über alle 267 ausgelieferten `.fx` (Session-Skript `/tmp/c2_audit.py`):

| speedRange-Encoding | Vorkommen |
|---|---:|
| `{min,max}` — **tot zur Laufzeit** | **2** (`echo_bloom_rain.petal_rain.colorBySpeed`, `rift_piece_flash.flash_petals.colorBySpeed`) |
| `{a,b}` — korrekt (Team-lokale Workarounds) | 66 |

Der Helfer hat genau drei Aufrufstellen in `with_curves` (`size_by_speed`,
`rotation_by_speed`, `color_by_speed`); die beiden toten Bestände kommen aus
`echo_grove_fx.py:365` und `build_rift_fx.py:159` (einzige Generatoren, die noch über
den `with_curves`-Pfad gehen — alle anderen 10 Generatoren tragen lokale
`with_module`-Workarounds mit a/b). Es gibt KEINE zentrale colorBySpeed-API mit dem
Fehler außer `_min_max` selbst — B2s Fund (`mobs_fx.py:816`) beschreibt exakt diesen
`with_curves`-Pfad.

**Fix:** `_min_max()` schreibt `a`/`b` (Umbenennung in `_range()` mit Alt-Alias wäre
API-Kosmetik; der Helfer ist fxlib-privat, alle Aufrufstellen intern → in-place-Fix +
Doku). Regen betrifft 2 Assets; `credits4_fx.py`s Hand-Workaround (`sizeBySpeed` +
`lifetimeByEmitterSpeed` roh mit a/b) wird auf den Helfer zurückgebaut —
Soll: byte-identische `.fx` (nur UUID-frei dank Paket 1 exakt prüfbar).
`FX_FORMAT.md` §Module wird auf `{a,b}` korrigiert (dokumentierte Schema-Quelle trug
noch das falsche `{min,max}`). Beweis per NBT-Readback über den ECHTEN
`Range.CODEC` (JVM-Harness, LDLib2-Jar + DFU): HEAD-Bytes → Defaults/Fehler,
neue Bytes → autorierte Werte.

### 1.3 Paket 3 — CullBox/Prewarm-Audit + Lint

Audit über 823 Emitter in 267 Dateien (Skripte `/tmp/c2_audit*.py`):

* **Loops:** 188; ohne CullBox nur **4 — alle `beam_emitter`**
  (`altar_aura_pillar.pillar_beam`, `gravity_light_column.column_beam`,
  `resonance_bahn.path_beam`, `resonance_far_shaft.far_beam`).
  LINT-CULL-LOOP klammert Beams bisher aus (Implementierungslücke: die goldene Regel
  sagt „every looping emitter"; 3 andere Loop-Beams im Bestand TRAGEN CullBoxen).
* **One-Shots:** 635. Sichtfenster (duration + max startLifetime + max startDelay;
  Trail: +time; Beam: +startDelay) über 200 t: 95 Emitter, davon 94 MIT CullBox und
  genau **1** ohne: `end_arrival_pillar.pillar_beam` (620 t, 260-Block-Säule).
  Bandverteilung darunter: (180,200]: 1 ohne Cull, (150,180]: 4, (120,150]: 5 —
  die Flottenkonvention bricht sichtbar bei ~200 t; die Schwelle 200 liefert echte
  Funde ohne Rauschen (deckt sich mit dem „~200t"-Hinweis des Auftrags).
* **Prewarm:** 167 Partikel-Loops, 120 mit prewarm>0 (median prewarm 55 t bei
  median Lebensdauer 70 t, Ratio-Median 0.67), 47 mit prewarm=0. Jar-verifiziert:
  prewarm fährt beim ersten `update()` N volle `emitParticle()+update()`-Iterationen
  — Trails und Physics inklusive, also sicher für Trail-Emitter.
  Von den 47 sind die meisten Action-/Entity-/Sequenz-FX (Fade-in gewollt: Trails am
  Spieler, Cutscene-Wände, Sturm-Choreographie F-096). ECHTE Chunk-Load-Ambients mit
  langem Auffüllfenster (≥ ~50 t = 2.5 s sichtbares Leerlaufen): `nether_pit_plume`
  (jet_a/b/c, 70 t), `breach_ash_geyser` (geyser_core 70 t, vent_glow 30 t),
  `breach_ember_updraft` (ember_risers 190 t!), `breach_drift_cocoon`
  (thread_carriers 55 t), `wizard_hearth` (window_motes 100 t, smoke_wisp 80 t,
  chimney_sparks 40 t), `altar_aura_rim_hi/mid` (rim_streamers 55 t).

**Regel-Zuschnitt:**

1. **LINT-CULL-LOOP erweitert auf `beam_emitter`** (error bleibt error — goldene Regel
   wörtlich). 4 Funde, alle im selben Paket gefixt (CullBox aus der Beam-Geometrie:
   end-Vektor + Breite + Marge).
2. **NEU `LINT-CULL-LONGSHOT` (warn):** One-Shot-Emitter mit Sichtfenster > 200 t ohne
   CullBox. 1 Fund (`end_arrival_pillar`), gefixt.
3. **NEU `LINT-PREWARM-FILL` (info, advisory):** Partikel-Loop mit prewarm=0 und
   max startLifetime ≥ 60 t — dokumentiert das Auffüllfenster, failt nie (ob ein Loop
   ein stationärer Ambient oder ein Action-FX ist, weiß nur der Autor; error/warn wäre
   Rauschen). Die identifizierten echten Ambients werden im selben Paket gefixt
   (prewarm ≈ min(max startLifetime, duration) — LINT-PREWARM deckelt auf duration).

---

## 2 Paket 1 — Ergebnis

**fxlib-Diff (3 Stellen):**

1. Neuer Namespace `_FX_UUID_NS = UUID("6f1d2c4a-0b3e-4a9f-8c71-2d5e9a0b4c13")` (C4s
   Konstante übernommen).
2. `_FxObject`: uuid4 bleibt als dokumentierter Platzhalter (Standalone-`build()`
   unverändert); `child_of` merkt sich zusätzlich Objekt-Referenzen
   (`_parent_obj`/`_children_objs`).
3. `FxBuilder.build()` ruft neu `_assign_deterministic_uuids()`: pro Objekt
   `uuid5(_FX_UUID_NS, f"{builder.name}/{pfad}")` mit hierarchischem Pfad
   (Wurzel→Objekt-Namenskette, Dubletten unter demselben Eltern-Pfad per
   Vorkommens-Index `name#1`, `name#2` …), danach `_parentId`/`_childrenId` aus den
   Referenzen neu verlinkt → idempotent über wiederholte `build()`-Aufrufe, `.fx` und
   `.fxproj` desselben Builders tragen identische UUIDs.

**Schlüssel-Härtetest** (Session-Skript): zwei gleichnamige `empty`-Pivots + drei
gleichnamige Emitter, davon zwei unter gleichnamigen Eltern → alle UUIDs eindeutig,
`validate_tree` grün, `build()` idempotent, frischer Neubau identisch, anderer
Builder-Name ⇒ andere UUIDs.

**Regen:** alle 44 Generatoren + `fxlib.py templates` fehlerfrei; **267 `.fx` + 267
`.fxproj`** neu geschrieben (100 % des Bestands ist generator-gedeckt). 7
`.fxproj`-Siblings waren gegen ihr `.fx` inkonsistent und wurden über die CLI
nachgezogen (`newfx_d_fx.py` schreibt bewusst keine Siblings; + die 2 Templates).

**Beweise:**

* **Determinismus:** kompletter Zweitlauf aller 44 Generatoren + Templates + Sibling-
  Check ⇒ `md5sum`-Vergleich über alle 534 Dateien **byte-identisch**, 0 Sibling-Rewrites.
* **Diff-Scope:** UUID-normalisierter NBT-Vergleich (jede UUID → Index ihres ersten
  Auftretens) jeder der 267 Dateien gegen `git show HEAD:` ⇒ **266 reine UUID-Diffs, 1
  echter Diff**: `boss/tyrant_step_in.fx` (HEAD: 3 Objekte, Generator: 5).
* **Lint:** `validate --lint` ⇒ 267 Dateien, **0 NEUE**, 27 grandfathered (= Baseline).

**Drift-Fund `boss/tyrant_step_in.fx` (kein C2-Eingriff, stale Binary repariert):**
Generator und Asset stammen aus DEMSELBEN Commit `1d3099c`, aber das committete Binary
trägt nur `burst_shell`/`burst_ring`/`burst_pillar` — der committete Generator baut
zusätzlich `land_flash` und `burst_embers`, und die Commit-Message verspricht die
„fallenden Ember-Flecken" wörtlich. Das Binary war also gegen den eigenen Generator
stale (Regen wurde damals offenbar wegen des uuid4-Rauschens vermieden — genau der
Stolperstein, den dieses Paket beseitigt). Der Regen stellt den vom Autor committeten
Generator-Stand her; `validate --lint` bleibt bei 0 NEUEN Findings.

## 3 Paket 2 — Ergebnis

**fxlib-Diff (2 Stellen):**

1. `_min_max()` schreibt `{a, b}` statt `{min, max}` (Reihenfolge (a,b) = (lo,hi)
   unverändert). Docstring erklärt die Codec-Lage (`Range.CODEC` =
   RecordCodecBuilder über `fieldOf("a")`/`fieldOf("b")`, jar-verifiziert
   ldlib2 2.2.29) — damit der Fix nie wieder „zurückkorrigiert" wird.
2. `with_curves()` kann neu `lifetime_by_emitter_speed=` (Zahl/NF oder
   `dict(multiplier=…, range=(lo,hi))`) — viertes und letztes speedRange-Modul,
   vorher nur roh über `with_module` erreichbar. Rein additiv, kein bestehender
   Aufruf ändert sich.

**Nutzer-Suche (`rg _min_max tools/photon/`):** alle Aufrufstellen liegen fxlib-intern
in `with_curves` (`size_by_speed`, `rotation_by_speed`, `color_by_speed`, neu
`lifetime_by_emitter_speed`); kein Generator ruft den Helfer direkt. Es gibt keine
weitere zentrale colorBySpeed-API — B2s `mobs_fx.py`-Fund war genau dieser
`with_curves`-Pfad (dort team-lokal per `with_module` umgangen, Bestand trägt a/b).

**Regen:** kompletter Lauf aller 44 Generatoren + Templates. Echte Diffs NUR an den
2 erwarteten Assets (+ `.fxproj`-Siblings): `echo_bloom_rain.fx` (Emitter `petals`)
und `rift_piece_flash.fx` (Emitter `flash_petals`) — die einzigen Bestände, die noch
über den kaputten Helfer-Pfad gingen. UUID-normalisierter Diff: einzige Nicht-UUID-
Änderung ist der speedRange-Schlüsselwechsel.

**credits4-Rückbau:** `credits4_fx.py`s Hand-Workarounds (`sizeBySpeed` +
`lifetimeByEmitterSpeed` roh mit a/b via `with_module`) auf `with_curves(size_by_speed=…,
lifetime_by_emitter_speed=…)` zurückgebaut ⇒ `credits4_jetburst.fx` **byte-identisch**
(dank Paket-1-Determinismus exakt beweisbar: md5 vor/nach Refactor gleich).

**NBT-Readback-Beweis** (JVM-Harness `NbtRangeProbe.java`: echte `.fx`-Bytes →
`NbtIo`-Decompress → exakter `speedRange`-Tag → `Range.CODEC.parse(NbtOps.INSTANCE, …)`
— identisch zum Photon-Ladepfad; Classpath = ldlib2-Jar + NeoForge-merged +
`serverLegacyClasspath`):

```
HEAD :: petals.colorBySpeed.speedRange = {max:0.3f,min:0.02f}
    -> DECODE FAILED -> DataResult.Error['No key b in MapLike[…]; No key a in MapLike[…]']
NEW  :: petals.colorBySpeed.speedRange = {a:0.02f,b:0.3f}
    -> Range a=0.02 b=0.3
HEAD :: flash_petals.colorBySpeed.speedRange = {max:1.7f,min:0.2f}
    -> DECODE FAILED -> DataResult.Error['No key b in MapLike[…]; No key a in MapLike[…]']
NEW  :: flash_petals.colorBySpeed.speedRange = {a:0.2f,b:1.7f}
    -> Range a=0.2 b=1.7
```

Bei DECODE FAILED behält das Setting seinen Java-Default (`Range(0,1)` bei
ColorBySpeed, jar-verifiziert) — d. h. die autorierten Fenster 0.02–0.3 bzw. 0.2–1.7
kamen zur Laufzeit nie an; jetzt schon.

**Doku:** `docs/plans_v3/plans_v5/photon/FX_FORMAT.md` korrigiert — neue
`Range`-Zeile in der Leaf-Typ-Tabelle (§2) + die 4 Modul-Zeilen
(`lifetimeByEmitterSpeed`, `colorBySpeed`, `sizeBySpeed`, `rotationBySpeed`)
von `{min,max}` auf `{a,b}`.

**Audit nach Fix:** speedRange mit min/max: **0**, mit a/b: **68**.
`validate --lint`: 267 Dateien, **0 NEUE**, 27 grandfathered. Zweitlauf aller
Generatoren ⇒ byte-identisch (Determinismus hält).

## 4 Paket 3 — Ergebnis

**fxlib-Diff (4 Stellen, alle rückwärtskompatibel — kein Generator-API-Bruch):**

1. Neue kalibrierte Konstanten `LONGSHOT_WINDOW_TICKS = 200` und
   `PREWARM_FILL_TICKS = 60` (Herleitung als Doku-Kommentar an der Konstante).
2. Neuer Helfer `_visibility_window(fx_type, config)`: obere Schranke der
   Sichtbarkeit EINER Wiedergabe (particle: duration + max startLifetime +
   max startDelay; trail: + time; beam: + startDelay; ara: duration).
3. **LINT-CULL-LOOP auf `beam_emitter` erweitert** (error bleibt error): die Regel
   klammerte Beams bisher aus, obwohl die goldene Regel „every looping emitter" sagt
   und 4 von 8 Loop-Beams im Bestand bereits CullBoxen trugen.
4. **NEU `LINT-CULL-LONGSHOT` (warn):** One-Shot ohne CullBox mit Sichtfenster
   > 200 t. **NEU `LINT-PREWARM-FILL` (info, advisory):** Partikel-Loop mit
   prewarm = 0 und max startLifetime ≥ 60 t — dokumentiert das Auffüllfenster,
   gate-t nie (ob Ambient oder Action-FX weiß nur der Autor).

**Audit-Zahlen (Bestand vor den Fixes, 825 Emitter / 267 Dateien):**

| Prüfung | Zahlen |
|---|---|
| Loop-Emitter | 188; ohne CullBox **4** — alle `beam_emitter` |
| One-Shots | 637; Sichtfenster > 200 t ohne CullBox: **1** (620 t); Bänder darunter: (180,200] 1, (150,180] 4 — Konvention bricht bei ~200 t |
| Partikel-Loops | 167; prewarm > 0: 120 (Median 55 t bei Median-Life 70 t); prewarm = 0 mit Fill ≥ 60 t: 17 (Lint-Infos) |

**Fix-Liste CullBox (5 — alle in DIESEM Paket gefixt, 0 Baseline-Einträge):**

| Asset :: Emitter | Fund | CullBox (aus der Beam-Geometrie + Marge) |
|---|---|---|
| `altar_aura_pillar` :: pillar_beam | Loop-Beam, 42-Block-Säule | (−2,−1,−2)–(2,44,2) — wie Sibling `pillar_motes` |
| `gravity_light_column` :: column_beam | Loop-Beam, 90-Block-Beacon | (−2,−1,−2)–(2,92,2) |
| `resonance_bahn` :: path_beam | Loop-Beam, Unit-Z-Kante (Executor streckt z) | (−2,−2,−1.1)–(2,2,0.1) — identisch zu Sibling `path_motes`, cullt als Einheit |
| `resonance_far_shaft` :: far_beam | Loop-Beam, 60-Block-Schaft | (−2,−1,−2)–(2,62,2) |
| `end_arrival_pillar` :: pillar_beam | **One-Shot 620 t**, 260-Block-Säule | (−6,−2,−6)–(6,270,6) — wie Sibling `climb_streaks` („+270 cull lid") |

Codec-Gegenprobe (Paket-2-Lektion): AABB-Accessor jar-verifiziert
(`AccessorRegistries`, ldlib2 2.2.29) — RecordCodecBuilder mit `fieldOf("min")`/
`fieldOf("max")`, exakt was fxlibs `aabb()` schreibt. CullBoxen sind also — anders
als `Range` — mit min/max KORREKT; die 94 Bestands-Boxen und die 5 neuen decodieren.

**Fix-Liste prewarm (6 Dateien / 8 Emitter, prewarm ≈ min(max startLifetime, duration)):**

| Asset :: Emitter | Fill | prewarm neu |
|---|---|---:|
| `wizard_hearth` :: window_motes / smoke_wisp / chimney_sparks | 100/80/40 t | 100/80/40 |
| `breach_ember_updraft` :: ember_risers | 190 t (!) | 190 |
| `breach_drift_cocoon` :: thread_carriers | 55 t | 55 |
| `altar_aura_rim_hi` + `_mid` :: rim_streamers | 55 t | 50 (Duration-Deckel, LINT-PREWARM) |

**Bewusst NICHT geändert (Abweichung vom Plan §1.3, nach Quell-Review):**

* `nether_pit_plume` jet_a/b/c: die Jets tragen ein EXPLIZITES
  Desync-Design (random startDelay pro Materialize + probability-Bursts, W13-Kommentar
  „the pit spits WHEN IT WANTS TO"); prewarm würde die Delay-Fenster aufessen und aus
  „öffnet jedes Mal anders phasiert" ein „immer mitten im Spuckstoß" machen. Den
  Established-Read trägt dort `smoke_swathes` (prewarm 60) bereits.
* `breach_ash_geyser` geyser_core/vent_glow: `prewarm=0` steht dort EXPLIZIT im
  Generator (autorisierte Entscheidung), und geyser_core fährt echte
  Collision-Physics ohne parallelUpdate — 70 Prewarm-Ticks × bis zu 220 Partikel
  Kollisions-Sim wären ein Ein-Frame-Spike beim Materialize.
  Beide bleiben als LINT-PREWARM-FILL-**Info** dokumentiert (advisory, gate-t nie).

**lint_baseline.txt: unverändert** — alle 5 error/warn-Funde wurden im Paket gefixt
statt grandfathered; die neue Info-Regel braucht keine Baseline (info gate-t nie).

**Regen + Beweise:** alle 44 Generatoren + Templates, `validate --lint` ⇒ **0 NEUE**,
27 grandfathered (Baseline exakt wie vorher), Advisory-Infos 145 → 142 (die drei
≥60-t-prewarm-Fixes räumten ihre eigenen Findings). Zweitlauf byte-identisch.
UUID-normalisierter Diff gegen HEAD über ALLE 267 Dateien: genau **13** Dateien mit
echtem Diff = 5 Cull (renderer.cull._enable 0→1 + cullBox) + 6 prewarm (nur das
prewarm-Feld) + 2 speedRange (Paket 2) + 1 Drift-Reparatur (Paket 1,
`boss/tyrant_step_in`). Kein einziges anderes Feld hat sich geändert.

## 5 Verifikations-Status

| Check | Ergebnis |
|---|---|
| Alle 44 Generatoren + `fxlib.py templates` | fehlerfrei (nach jedem Paket) |
| `validate --lint` | 267 Dateien, **0 NEUE** error/warn, 27 grandfathered (=Baseline), 142 Infos |
| `fxlib.py selfcheck` | PASSED |
| Determinismus | Zweitlauf aller Generatoren nach jedem Paket ⇒ alle 534 Dateien byte-identisch (md5) |
| Diff-Scope | UUID-normalisiert: 254 nur-UUID, 13 echte Diffs — alle beabsichtigt (§4) |
| Range-Fix NBT-Readback | HEAD-Bytes: DECODE FAILED (→ Default 0–1); neue Bytes: autorierte Werte (§3) |
| AABB/CullBox-Codec | jar-verifiziert min/max — fxlib-Output korrekt (§4) |
| `./gradlew compileJava processResources` | grün; `build/resources/main/.../fx/*.fx` md5-identisch zu `src/` |
| `lint_baseline.txt` | unverändert (kein neuer Grandfather-Eintrag) |

## 6 Empfohlene Commit-Aufteilung

Drei Commits in dieser Reihenfolge. `fxlib.py` trägt 11 Hunks aller drei Pakete →
per `git add -p` splitten; die Hunk-Grenzen sind sauber funktionsweise trennbar
(Diff-Anker: **P1** = Hunks bei `SEG_DECAY_TAIL`/~697 (`_FX_UUID_NS` + `__init__`),
`class _FxObject`/~734 (`child_of`), `class FxBuilder`/~1207
(`_assign_deterministic_uuids` + `build`); **P2** = die 3 Hunks in
`class ParticleEmitter` ~939/~968 (`with_curves`) + ~1031 (`_min_max`); **P3** =
`PALETTE_TOKENS`/~1705 (Konstanten), `_nf_max`/~1758 (`_visibility_window`),
`_child_burst_sum`/~1916 (Docstring) + die 2 `lint_file`-Hunks ~1960/~1994).
**Nicht von C2** (parallele Mob-Teams MA1/MA3/MA4, NICHT in diese Commits): alles
unter `scripts/geckolib_gen/`, `src/main/java/`, `docs/uv/`,
`assets/eclipse/{animations,geo,textures}/entity/` (fog_tyrant/ferryman/herald) und
deren `MA*_REPORT.md`. C2s Änderungsmenge ist exakt: `tools/photon/` (10 Dateien),
`assets/eclipse/fx/**` (534 Dateien), `FX_FORMAT.md`, dieser Report.

**Commit 1 — „photon: deterministic uuid5 transform ids (fxlib) + full regen"**

* `tools/photon/fxlib.py`, NUR die Hunks: `_FX_UUID_NS`-Konstante,
  `_FxObject.__init__`/`child_of` (Platzhalter-Kommentar + `_parent_obj`/
  `_children_objs`), `FxBuilder._assign_deterministic_uuids` + `build()`-Aufruf.
* ALLE `src/main/resources/assets/eclipse/fx/**` .fx/.fxproj **außer** den 24
  Dateien aus Commit 2/3 (s. u.): 510 Dateien, davon 508 nur-UUID +
  `boss/tyrant_step_in.fx`/`.fxproj` (Drift-Reparatur, §2).
* Hinweis für die Commit-Message: `tyrant_step_in` stellt den committeten
  Generator-Stand wieder her (stale Binary, §2).

**Commit 2 — „photon: fix Range codec keys min/max -> a/b in fxlib._min_max"**

* `tools/photon/fxlib.py`, Hunks: `_min_max()` (a/b + Docstring),
  `with_curves()`-Erweiterung `lifetime_by_emitter_speed` + Docstring.
* `tools/photon/credits4_fx.py` (Workaround-Rückbau — Output byte-identisch).
* `src/main/resources/assets/eclipse/fx/echo_bloom_rain.fx` + `.fxproj`,
  `rift_piece_flash.fx` + `.fxproj` (4 Dateien).
* `docs/plans_v3/plans_v5/photon/FX_FORMAT.md` (Schema-Korrektur {a,b} + Range-Zeile).

**Commit 3 — „photon: cull/prewarm lint rules + fleet fixes (beams, ambients)"**

* `tools/photon/fxlib.py`, Hunks: `LONGSHOT_WINDOW_TICKS`/`PREWARM_FILL_TICKS`,
  `_visibility_window()`, LINT-CULL-LOOP-Erweiterung + LINT-CULL-LONGSHOT +
  LINT-PREWARM-FILL, `lint_file`-Docstring.
* Generatoren: `altar_aura_fx.py`, `woah_gravity_fx.py`, `resonance_fx.py`,
  `end_arrival_fx.py`, `backlog_fx.py`, `build_world_fx.py`, `newfx_d_fx.py`,
  `altar_aura2_fx.py`.
* Assets (20 Dateien, je .fx + .fxproj): `altar_aura_pillar`, `gravity_light_column`,
  `resonance_bahn`, `resonance_far_shaft`, `end_arrival_pillar`, `wizard_hearth`,
  `breach_ember_updraft`, `breach_drift_cocoon`, `altar_aura_rim_hi`,
  `altar_aura_rim_mid`.
* `docs/plans_v3/session_0730/C2_FXLIB_REPORT.md` (dieser Report).

**Caveat Zwischenstände:** Commit 1 lässt die 24 Commit-2/3-Dateien auf ihrem
HEAD-Stand (uuid4-Bytes) — ein Generator-Lauf AUF Commit 1 würde sie einmalig
neu schreiben (UUID-Migration). Das ist der erwartete Teilrollout-Zustand; ab
Commit 3 ist der Baum vollständig regen-stabil (Zweitlauf = leerer Diff,
verifiziert). Wer die Zwischenzustände nicht braucht, kann 1–3 auch squashen —
die Pakete sind aber bewusst einzeln revertbar geschnitten.
