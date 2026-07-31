# F-102 TEAM C — „Nether-Masse" (NETHER_MASS2)

Auftrag: die 47-s-Photon-Sequenz der Nether-Öffnung (F-035) las sich in der In-Game-Abnahme
bis ~Sekunde 30 statisch. Drei Bausteine: (1) Phasen-Lesbarkeits-Leiter — jede Phase bekommt
einen **dominanten Silhouetten-Wechsel, der im STANDBILD erkennbar ist** (llvmpipe!), (2)
fühlbare **Einschlag-Beats** pro Phase über bestehende Cue-/Payload-Pfade (nichts Neues am
Wire-Format), (3) die **permanente Rauch-Feuer-Wolke** mehrschichtig verdicken.

> **Tester-Hinweis (Pflicht):** Photon cached .fx statisch — nach dem Asset-Regen im
> laufenden Client **`/photon_client clear_client_fx_cache`** (Client-Chat, nicht RCON),
> sonst spielt der Replay die alten Blobs.

## §1 PLAN — Sequenz-Timeline aus dem Code (Ist-Stand vor F-102)

Quelle: `sequence/NetherOpeningSequence` (Tick-Tabelle), `sequence/NetherUpheavalFx`
(Block-Displays), `client/nether/NetherOpenClientFx` + `NetherPitPlume` (Client),
`veilfx/NetherOpenPhotonFxRows` (Rows). `t` = Ticks seit `begin` (Replay identisch,
nur `carve=false`).

| Phase | abs. t (s) | Server | Wire | Client (vorher) |
|---|---|---|---|---|
| OMEN | 0–240 (0–12) | Server-Partikel alle 10t, Quarry-Sounds alle 60t | `S2CNetherOpenPayload OMEN` @t=0; `RUMBLE`-Raster alle 20t (0.10→0.32) | `nether_omen_ash` one-shot (Asche-Quellen + Glints — **kein** eigener Umriss) |
| TREMOR | 240–600 (12–30) | `NetherUpheavalFx.beginTremor`: Hop-Waves à 9 Blöcke, Kadenz 14–56t (Pressure 0.25→1.0), Hop = 26t Sinus | `TREMOR` @t=240; `RUMBLE` 0.34→0.80 | 5 `nether_quake_fissure`-Stempel (Ring r=11.5, deterministische Yaws) — Risse ≤140t, danach ~4 s LEER bis zur Eruption |
| RUPTURE | 600–880 (30–44) | `erupt`: 380 Fontänen-Bögen + 15 % JET-Säule; Carve (nur echter Lauf); Aftershock-Sounds lokal t=18/46 | `RUPTURE` @t=600; Shake-Peak 1.0, Hold 70t | `nether_eruption` (FX-W11: Feuersäule + Soot-Core + Schock-Ringe + Staub-Vorhänge) + 1 Hard-Hit-Shake |
| AFTERMATH | 880–940 (44–47) | Swarm-Release; B7 `beat_nether_ember_tear` @880, Nachbeben @910 | `AFTERMATH` @t=880 | `NetherPitPlume.onOpened()` → Fenster-Fast-Track |
| permanent | ab ~940 | `BreachTransferService.ambientTick` (photon-lose Baseline) | — (WINDOWED-only, kein Wire) | `nether_pit_plume` + `nether_ash_snow` Loops (Fenster 128/152, Physik-Probe) |

**Befund deckungsgleich mit der Abnahme:** OMEN hat keinen Umriss (nur Dichte), TREMOR
lebt allein von Block-Hüpfern + kurzlebigen Rissen (Standbild: leerer Boden), zwischen
t≈520 und 600 ist der Boden komplett stumm, und keine Phase vor der Ruptur hat einen
einzelnen fühlbaren SCHLAG (nur das 20t-Rumble-Raster).

## §2 IDEEN — Silhouetten pro Phase (3+ je Phase, Auswahl begründet)

**OMEN (Asche):**
1. **Fallender dunkler Schleier-KEGEL über dem Maul (GEWÄHLT)** — ein stehender Kegel
   (Apex 22 Blöcke) ist im Standbild eine FORM, nicht Dichte; „fallend" invertiert die
   heilige Vertikale (alles andere im Spiel steigt) → sofort „falsch/ominös".
2. Asche-Kuppel (Dome) — verworfen: statisch, kollidiert optisch mit der
   mansiondome/dome_shell-Familie anderer Teams.
3. Asche-Teufel (kleine Wirbelsäulen) — verworfen: vertikale Säulen sind
   Eruptions-Vokabular, zerstört die Leiter (Phase 1 darf Phase 3 nicht vorwegnehmen).
4. Glut-Adern-Netz am Boden — verworfen: Boden-Glut gehört der Ruptur (Leiter-Trennung).

**TREMOR (Vorbeben):**
1. **Boden-Staubringe pro Hop-Wave-SLAM + Kiesel-Carpet (GEWÄHLT)** — die Ringe koppeln
   an die real sichtbaren Block-Landungen (ein Beat = Ring + Thud + Kick), der Carpet
   (springende Kiesel mit echter Kollision + kochender Flipbook-Staub) füllt die Fläche
   phasenlang — Standbild: „der ganze Boden arbeitet".
2. Stehende Staubwand am Kraterrand — verworfen: verdeckt genau die Block-Hüpfer, die
   das Schauspiel der Phase SIND.
3. Mehr/längere Fissuren — verworfen: das ist „mehr Partikel", kein Formwechsel (der
   User-Befund explizit); die 5 Riss-Stempel bleiben unverändert bestehen.
4. Sand-Geysire — verworfen: Fontänen = Eruptions-Vokabular (Leiter).

**RUPTURE (Block-Ruptur + Eruption):**
1. **Radiale RISS-GLUT-SPEICHEN am Boden + Schuttfontänen entlang der Linien (GEWÄHLT)**
   — 6 weißglühende Speichen VOM Loch weg = das Standbild sagt eindeutig „der Boden
   gibt nach", und der Stern ist bei jeder Kamera-Peilung lesbar.
2. Ein aufreißender Glut-RING — verworfen: Ring-Vokabular gehört jetzt den Tremor-Beats;
   ein Ring liest zudem als Druckwelle, nicht als Zerreißen.
3. Lava-Vorhänge (Curtain-Wall) — verworfen: llvmpipe-Füllrate + V2.1-Stacking (viele
   ALPHA-Lagen im selben Halbblock).
4. **PILZWOLKE als Kappe der FX-W11-Säule (ZUSÄTZLICH GEWÄHLT** — der Auftrag nennt die
   W11-Säule explizit als Basis): Flipbook-Puffs materialisieren als Kranz um den
   Säulen-Apex (y 43–52) und breiten sich lateral aus → Standbild = Säule **+ Pilz**.

**NACHGLUT:**
1. **Träge GLUTFLOCKEN im Asche-Schnee (GEWÄHLT)** — 40 glühende Flocken, die noch
   langsamer sinken als die Asche: „der Himmel erinnert sich ans Feuer".
2. Glut-Pfützen am Boden — verworfen: Boden-Anker überm frisch ausgehobenen Trichter =
   Schwebe-Artefakte (der Boden EXISTIERT dort nicht mehr).
3. Funken-Spiralen aufwärts — verworfen: Energie-Vokabular; die Nachglut soll müde sein.

**DAUERWOLKE (dicker):**
1. **Fog-SCHALEN (außen, träge, fast schwarz) + Ember-MOTES (innen, zuckend) +
   FEUERZUNGEN (probability-gated aus dem Maul) (GEWÄHLT)** — exakt der User-Wortlaut
   „Rauchwolke mit Feuer drin", drei Tiefen-Lagen = Volumen statt Fläche.
2. Zweite Wolken-Etage höher — verworfen: CullBox/Fenster wachsen, Nah-Read kaum besser.
3. Lava-Tropfen-Regen aus der Wolke — verworfen: bräuchte Kollision im Permanent-Loop
   (Budget) und kollidiert mit dem Glutflocken-Read.

## §3 IMPLEMENT

### §3.1 Assets (`tools/photon/nether_open_fx.py` — jetzt 8 Blobs)

| Asset | Δ F-102 | Kern |
|---|---|---|
| `nether_omen_ash` | +`veil_cone` (110), +`veil_slump` (34, Burst @t=120) | DER Kegel: function_shape Kegel-Mantel (r 14 → Apex 22), Soot rutscht die Mantelfläche hinab (−y linear + radial 0.02–0.05); Slump = flacher Ring-Poff auf dem Beat-Tick |
| `nether_tremor_waves` **NEU** | 360t-Carpet, @TREMOR-Entry | `pebble_pops` (110, echte Kollision, parallelUpdate off) + `heave_dust` (70, Flipbook-Boil, Alpha ≤0.4) — beide schwellen mit der Phase (swell-Kurve wie die Hop-Pressure) |
| `nether_tremor_ring` **NEU** | 50t-Beat-Stempel, via Cue | `dust_ring` (46er-Burst, Kreis r 8.8 → ~17 via SEG_APEX_DRAG) + `kiesel_burst` (Kollision) + `grit_glints` |
| `nether_rupture_spoke` **NEU** | 130t, 6 Stempel @RUPTURE | `spoke_glow` (Zackenlinie lokal +X 3..15, tear_off = sie REISST) + `spoke_rubble` (Schuttfontänen, Kollision) + `spoke_dust`; CullBoxen rotations-symmetrisch (Yaw-Stempel-Lehre) |
| `nether_eruption` | +`mushroom_cap` (46) | Kranz-Puffs y 43–52 (Bursts t=34/54/78 = Ankunftsfenster des 2.5–3.5 b/t-Soot-Cores), laterale Crown-Spread-Vektoren, SEG_APEX_DRAG → Kappe weitet ~7 Blöcke und HÄNGT |
| `nether_pit_plume` | +`fog_shells` (20) +`ember_motes` (60) +`tongue_flares` (14) | Schalen: 6–11-Block-Veils, Alpha ≤0.2, prewarm 200; Motes: GPU-instanced, 20–40t-Blitzleben, HDR 1.45; Zungen: probability-Bursts auf ko-primem 170t-Zyklus, StretchedBillboard |
| `nether_ash_snow` | +`glut_flakes` (40) | GPU-instanced, sinken −0.03..−0.06, random_gradient hell/dimmend, HDR 1.4 |
| `nether_quake_fissure` | unverändert (byte-identisch) | Riss-Stempel bleiben die TREMOR-Ergänzung |

### §3.2 Beats (Baustein 2 — jede Phase EIN fühlbarer Einschlag)

| Phase | Beat | Mechanik (bestehende Pfade!) |
|---|---|---|
| OMEN | t=120 „Schleier-Slump" | Poff ist als Burst IM Asset gebacken (`OMEN_BEAT_TICK=120`); `NetherOpenClientFx.Beats` armiert vom OMEN-Payload einen 120t-Client-Countdown → Kamera-Kick (0.55, f=1.1). Beide Hälften starten im selben Handler-Tick → kein neuer Sync. Pause friert Countdown UND Photon-Sim → bleibt deckungsgleich |
| TREMOR | Hop-Wave-LANDUNGEN | `NetherUpheavalFx` queued pro gespawnter Welle den Landetick (spawn+26), rate-limitiert 1 Beat/48t → 6–7 wachsende Beats über 18 s. Pro Beat: gedämpfter Thud (Vol 0.9+0.7·p, Pitch 0.3+0.08·p) + Cue `eclipse:fx/cue/nether_tremor_slam` über die GESHIPPTE `S2CFxEventPayload`-Lane (`a`=Pressure, Range 160). Client-Row: Ring-Stempel + `tremorSlamKick` (0.35+0.55·p, f=1.7 — scharfes Rattern ÜBER dem 0.55er-Rumble-Bett) |
| RUPTURE | bestehender Hard-Hit | unverändert (1.3/55t/1.4) — jetzt visuell vom Speichen-Stern getragen |
| AFTERMATH | bestehender B7-Ember-Tear @880/910 | unverändert |

Cue-ID-Namensvertrag (CreditsSequence-Präzedenzfall): beide Seiten leiten
`FxCues.cue("nether_tremor_slam")` ab — `FxCues.java` bleibt unangetastet. Eruption
verwirft pending Slams (`tickSlamBeats` cleart bei `erupting`): ab t=600 gehört der
Frame dem Ruptur-Punch.

### §3.3 Java-Dateien

- `veilfx/NetherOpenPhotonFxRows`: 3 neue Asset-Ids + `CUE_NETHER_TREMOR_SLAM`-Row
  (Channel BURST, Mode LAYER, Quasar-Leg `null` — photon-lose Slam-Baseline sind Thud +
  die echten Block-Displays selbst). Custom-Leg feuert den Kamera-Kick VOR dem
  Bridge-Spawn (reducedFx behält das Beat-GEFÜHL) und spawnt mit `allowMulti=true`
  (Folge-Slams teilen den Anker innerhalb der ~50t-Ring-Lebenszeit — Photon-Dedup würde
  sonst jeden zweiten Beat schlucken; B7-End-Crack-Präzedenzfall).
- `sequence/NetherUpheavalFx`: Slam-Queue (`pendingSlamAges`) + `tickSlamBeats`
  (Rate-Limit, Pressure-skalierter Thud, Cue am Lip-Block-Center = derselbe Anker wie
  die Phasen-One-Shots).
- `client/nether/NetherOpenClientFx`: TREMOR spawnt zusätzlich den Waves-Carpet;
  RUPTURE stempelt den 6er-Speichen-Stern (ein Anker, 6 Yaws, `allowMulti` — 6 Spawns
  im selben Tick am selben Anker!); `Beats` (GAME-Bus-Nested-Class, SmallCueFxRows-
  Präzedenzfall) hält den OMEN-Countdown; `tremorSlamKick` ist die Kick-Hälfte der Row.
  Speichen-Stern um π/6 gegen den Fissuren-Stern verdreht (neue Geometrie statt
  Re-Ignition — die Riss-Partikel sind bei t=600 längst tot, s. §4 It. 2).

## §4 Selbst-Iterationen (harte Eigenkritik)

### Iteration 1 — Budget / Regeln / Degrade

- **Partikel-Budget (maxParticles-Deckel, Worst-Tick t≈600–650):** Eruption 890 (Bestand
  844 + Kappe 46) + 6×Speiche 468 + Rest-Carpet ≤180 (Emission endet @600, Leben ≤44t)
  + ggf. 1 Rest-Ring 88. Deckel-Summe ~1.6k, REAL gleichzeitig deutlich darunter (alle
  Raten kurvengetrieben, tear_off front-lastig). **Konsequenz gezogen: Speichen-Stern
  von geplanten 8 auf 6 getrimmt** (−156 Deckel) — 6 lesen als Stern genauso.
- **Executor-Budget (Bridge-Ceiling 24):** Worst-Tick = 7 neue (Eruption + 6 Speichen)
  + 1 Carpet + ≤2 Rest-Ringe ≈ 10 « 24. Loops erst ab AFTERMATH (2).
- **arc_mode-Falle:** Audit über den ganzen Generator — **kein einziges arc_mode**
  verwendet (Kreise über Burst-Vollringe/function_shape) → die Uniform-NPE-Klasse ist
  strukturell ausgeschlossen.
- **Stacking/HDR:** alle NEUEN Dauer-Materialien ≤1.45 (motes/tongues 1.45, glut 1.4);
  One-Shot-Glut folgt dem Bestands-Präzedenzfall (fissure_seam 2.2, W11-Feuer 2.4 →
  spoke_glow 2.4, grit_glints 1.6). Birth-Tints der Rauch-Lagen dunkel, Alpha-Decken
  0.09–0.5 dokumentiert je Emitter.
- **Degrade-Pfad verifiziert am Code:** `PhotonFxRegistry.dispatchInternal` ruft ein
  Custom-Leg UNBEDINGT (DEMOTED-Zweig greift nur mit Quasar-Leg; unseres ist `null` →
  „baseline law outranks demotion") → Slam-Kick + Thud + Block-Displays bleiben bei
  reducedFx/photon-los; Ring/Carpet/Speichen no-open über die Bridge-Guards; beide
  Loops released das Plume-Fenster bei reducedFx (unverändert).
- **Kollisions-Gesetz:** alle 4 Kollisions-Emitter (pebbles, kiesel_burst, spoke_rubble,
  ember_shrapnel) mit `parallel_update=False`; alle GPU-instanced-Emitter physikfrei.

### Iteration 2 — Standbild-Read / Timing-Ehrlichkeit (mit 2 Korrekturen)

- **KORRIGIERT — Speichen-Kommentar log:** die Behauptung „Speichen leuchten ZWISCHEN
  den Phase-2-Rissen statt Overdraw" war falsch begründet — die Riss-Partikel (Stempel
  @t=240, Leben ≤140t) sind bei RUPTURE (t=600) längst tot. Der π/6-Versatz bleibt
  (Begründung jetzt ehrlich: der Ruptur-Stern ist NEUE Boden-Geometrie — frische Linien,
  wo vorher nichts glühte = Eskalation statt Re-Ignition), Javadoc angepasst.
- **GEPRÜFT — Kegel-Überhang in den TREMOR:** veil_cone-Partikel, die bei t≈239 geboren
  werden, leben bis ~t=380 in die Beben-Phase hinein. Bewertung: gewollter Crossfade
  (Alpha läuft pro Partikel aus, Emission endet hart @240); der Kegel hängt OBEN, die
  Tremor-Reads (Carpet/Ringe) arbeiten UNTEN — keine Silhouetten-Verwechslung, und ein
  hartes Abschneiden würde poppen. Keine Änderung.
- **GEPRÜFT — Beat-Übersteuerung:** Slam-Kick (f=1.7, 14t) vs. Rumble-Raster (f=0.55,
  26t): getrennte Frequenz-Signaturen, Impulse addieren nur kurz; Thud-Bänder
  (0.9–1.6 / Pitch ~0.3) bleiben klar unter dem Ruptur-GENERIC_EXPLODE (4.0/0.5).
  Slam-Cue-Range 160 > Kick-Fade 120 → der Ring bleibt für Fernstehende sichtbar,
  der Kick skaliert dort auf ~0.
- **GEPRÜFT — Ring-Geometrie:** SEG_APEX_DRAG-Mittel ≈0.154 × Start 1.5–2.3 b/t ×
  22–36t ≈ +8.5 Blöcke → Ring läuft r 8.8 → ~17 (Maulradius +) — liest als Druckwelle
  der Landung, endet vor dem Halo-Rand (CullBox +8 Puffer).
- **GEPRÜFT — Kappen-Timing:** Soot-Core (2.5–3.5 b/t, SEG_APEX_DRAG) erreicht y≈45 im
  Fenster t≈30–80 → Kappen-Bursts 34/54/78 materialisieren den Pilz genau, wenn die
  Säule oben „ankommt"; StretchedBillboard bewusst NICHT für die Kappe (Puffs sollen
  hängen, nicht streaken).
- **GEPRÜFT — allowMulti-Vollständigkeit:** Ring-Row ✓ (Folge-Slams), Speichen ✓ (6 ×
  selber Anker/Tick). Carpet/Slump/Kappe: Einzel-Spawns, Default-Dedup ist dort sogar
  der Replay-Schutz. Fissuren: 5 verschiedene Anker, Bestand unverändert.

## §5 Gates (Ergebnisse)

- `python3 tools/photon/nether_open_fx.py` → **8/8 WROTE**, round-trip-valid, `.fxproj`-
  Siblings (binary-blob diff law).
- `python3 tools/photon/fxlib.py validate --lint` → **0 NEW error/warn** (275 Dateien,
  27 grandfathered, 149 advisory-info). Nether-Anteil ausschließlich Advisories:
  LINT-PALETTE (Glut-Mittelwerte — dieselbe Klasse wie die Bestands-Glut-Assets) und
  LINT-PREWARM-FILL auf den Bestands-`jet_a/b/c` (bewusst: die Jets sollen als
  IRREGULÄRE Kaskaden anlaufen, kein stationäres Ambient; fog_shells/ember_motes/
  glut_flakes sind geprewarmt).
- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (Klassen inkl. `NetherOpenClientFx$Beats` frisch im Build-Output
  verifiziert).
- **Replay-Pfad intakt (Code-Beweis):** `/dev nether replay_fx` →
  `NetherOpeningSequence.begin(server, carve=false)` → Phase-Broadcasts →
  `NetherOpenClientFx.handle` referenziert `FX_NETHER_OMEN_ASH` (Kegel+Slump),
  `FX_NETHER_TREMOR_WAVES`, `FX_NETHER_ERUPTION` (Kappe), 6×`FX_NETHER_RUPTURE_SPOKE`;
  TREMOR-Entry ruft `NetherUpheavalFx.beginTremor` → Hop-Waves → `tickSlamBeats` →
  `CUE_NETHER_TREMOR_SLAM` → Row spawnt `FX_NETHER_TREMOR_RING`; AFTERMATH →
  `NetherPitPlume` → beide Loops. `DevNetherCommands` unangetastet (READ-ONLY
  eingehalten), keine Payload-/Wire-Änderung, `FxCues.java` unangetastet.
- `docs/plans_v3/langdrop/NETHER2.json`: **nicht nötig** — keine neuen UI-Strings
  (reines FX/Beat-Feature).

## §6 Verifikations-Skript für den Main-Agent

Vorbereitung (einmalig):

```
# 1) Krater-Center ablesen (X/Y/Z; Y = Lip-Ebene):
python3 tools/rcon/rcon.py "execute as Dev run dev nether status"
# 2) Client-Chat (NICHT RCON — Client-Command!):
#    /photon_client clear_client_fx_cache
# 3) Kamera NAH (Boden-Phasen): ~26 Blöcke SO vom Center, 10 über Lip, Blick aufs Center:
python3 tools/rcon/rcon.py "tp Dev <cx+26> <lipY+10> <cz+26> -135 15"
# 4) Start:
python3 tools/rcon/rcon.py "execute as Dev run dev nether replay_fx"
```

Screenshot-Fahrplan (Sekunden ab Replay-Start; Kamera NAH, außer wo FERN vermerkt —
FERN = `tp Dev <cx+55> <lipY+18> <cz+55> -135 8`):

| s | t | Screenshot | Erwartete Optik (Standbild-Kriterium) |
|---|---|---|---|
| ~8–10 | 160–200 | S1 OMEN | Dunkler SCHLEIER-KEGEL steht über dem Maul (Apex ~22 Blöcke, zur Spitze dichter), Soot rutscht abwärts; darunter Asche-Quellen + einzelne Lava-Glints. Der Kegel ist die Form — vorher war hier nur Dichte |
| ~6 (Video) | 120 | S2 OMEN-Beat | Flacher dunkler Ring-Poff rollt vom Maul + EIN Kamera-Kick (deckungsgleich). Im Video prüfen, Standbild optional |
| ~15–25 | 300–500 | S3 TREMOR | Boden ARBEITET: springende Kiesel + kochender Staub-Teppich übers ganze Footprint; alle ~2.4 s ein SLAM-Beat = Staub-RING rast raus + Thud + kurzes scharfes Kamera-Rattern, synchron zur sichtbaren Block-Landung. Risse (Bestand) zusätzlich |
| ~31–32 | 620–650 | S4 RUPTURE | 6-strahliger RISS-GLUT-SPEICHEN-STERN am Boden (weißglühende Zackenlinien radial 3–15 Blöcke) + Schuttfontänen entlang der Speichen, darüber die Feuersäule |
| ~33–35 (FERN) | 660–700 | S5 PILZ | Säule trägt eine PILZ-KAPPE: Puff-Kranz um den Apex (~y 45), lateral gespreizt — Standbild = Säule + Pilz, nicht nur Säule |
| ~50+ | Loop | S6 WOLKE | Dauerwolke DICK: fast schwarze Fog-Schalen als Außen-Silhouette, innen zuckende Ember-Funken, alle paar Sekunden größere Feuerzungen aus dem Maul; Asche-Schnee mit einzelnen trägen GLUTFLOCKEN. Gegenprobe aus ~100 Blöcken: die Wolken-Silhouette bleibt lesbar |

Dauerwolken-Check zusätzlich: einmal >152 Blöcke weg und wieder heran (Fenster released/
materialisiert ohne Pop — Schalen/Motes sind geprewarmt); Pause-Menü während OMEN öffnen
und schließen (Beat bleibt synchron — Countdown friert mit der Sim).

Degrade-Gegenprobe (optional): `reducedFx` an → Ring/Carpet/Speichen/Wolke aus, aber
Thud + Kamera-Beats + Block-Displays bleiben (das Beat-Gefühl ist Photon-unabhängig).

## §7 Offene Risiken / Wünsche

- **llvmpipe-Restrisiko Kegel-Dichte:** 110 große Alpha-Quads könnten auf llvmpipe aus
  ungünstigen Winkeln (Kamera IM Kegel) dünn wirken — falls S1 zu schwach liest, ist der
  eine Dreh-Regler `veil_cone`-`max_particles`/Emission (Generator, 1 Zeile).
- **Slam-Beat-Wahrnehmung bei niedriger Pressure:** die ersten 1–2 Beats (p≈0.3) sind
  bewusst leise/klein — wirkt das im Video zu zaghaft, `SLAM_KICK_MIN`/`SLAM_THUD_
  VOLUME_MIN` anheben (je 1 Konstante).
- **fxlib-Wunsch (FROZEN, daher hier):** ein `lint`-Advisory „Burst-Zeit ≥ Emitter-
  Duration" hätte das Beat-Tick-Authoring (Slump @120 in 240t) doppelt abgesichert.
