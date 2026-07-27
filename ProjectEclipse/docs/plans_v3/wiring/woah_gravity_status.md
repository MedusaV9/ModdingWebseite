# WOAH-02 GRAVITATIONSBRUCH — Status „Der Krater, in dem der Staub nach oben fällt"

Ein permanenter Einschlagkrater (r 28, 13 tief) im Bambus-Dschungel bei `(−239, 167)`
(die zentral eingefrorene Landmark-Zeile, Stage 4 — NICHT das Plan-Original
(−40, 290)/moonlit_grove): 218 BlockDisplays kreisen in drei gegenläufigen Schalen um
ein pulsierendes Amethyst-Herz, in der Zone gilt Mond-Schwerkraft, alle 45 s wirft ein
Gravitationspuls jeden in der Schüssel in die Höhe, ein 8-Stufen-Parkour aus ECHTEN
Blöcken führt auf +46 zur Loot-Scholle, und wer das Herz schlägt, kehrt die
Schwerkraft 10 Sekunden lang um.

## Was gebaut wurde

### Server (`woah/gravityrift/`)

- **`GravityRiftZone`** — die eine Geometrie-Quelle: Landmark-Spiegel (−239/167,
  Stage 4), Krater-/Zonen-/Puls-/Inversions-Konstanten, deterministische Tabellen für
  218 Orbital-Pieces (Schale 0 „Kies" 110 × r 6–14/y +3..+12 · Schale 1 „Schollen"
  48 Slots + 12 Unterplatten-Komposits (60) r 12–20/y +12..+28 · Schale 2 „Inseln" 10
  Moos-Deck-Komposits mit 2–3 Unterplatten + 4 Dschungelbaum-Fragmenten (45) r 11–16.5/
  y +28..+38 · Herz-Komposit 3 Displays), 8 Parkour-`STEPS` (+6 bis +44, zwei
  Puls-Hero-Gaps), 2 `MEGA_FLOES` mit echten Mini-Dschungelbäumen, Loot-Scholle auf
  +46. Eigenes `hash01` (FallbackBuilders-Algorithmus, dort nicht public).
- **`GravityRiftState`** — SavedData (`built`/`anchor`/`lastInvert`/`invertUntil`/
  `lootPlaced`, Versionsfeld fürs Rebuild-Gate; ChronoStasisData-Schule).
- **`GravityRiftBuilder`** — Zwei-Phasen-Materialisierung (SitePrep-Plateau mit
  Canopy-Sweep → budgetierter Terrassen-Carve über `BudgetedBlockWriter` →
  synchroner Insel-/Sockel-/Kisten-Stempel → relight/resend): Moos-Strata außen,
  Tuff/Deepslate-Mitte, polished-deepslate/Sculk/Amethyst-Boden, Dschungel-Palette
  auf allen Schollen, Herz-Sockel 3×3, Loot-Kiste mit `setLootTable`, vergrabener
  Crying-Obsidian-Sentinel (Idempotenz + Selbstheilungs-Probe).
- **`GravityRiftService`** — Stage-4-Enqueue über den `WorldStageService`-Listener;
  Low-G-Zone über VERIFIZIERTE transiente Attribute (GRAVITY ×0.30, JUMP ×1.35,
  SAFE_FALL +20, FALL_DAMAGE ×0.40 → Sprung-Apex ≈ 6.7; Membership alle 5 t aus
  `getModifier(id)` re-deriviert, nichts leakt über Respawn/Logout); Puls auf dem
  statelosen Absolut-Raster `gameTime % 900 == phaseOffset(anchor)` (Telegraph-Cue
  30 t vorher, Beat: Launch vy 0.9 ≈ Apex 17 für die Hero-Gaps, `hurtMarked` +
  `fallDistance`-Reset, Shake-Payload); Herz-Schlag (`AttackEntityEvent` auf der
  getaggten `minecraft:interaction`-Hitbox) startet die 300-t-Inversion
  (200 t aktiv: Spieler-Levitation-Pass, Item-/XP-Updrift bis Ceiling +24;
  Cooldown 2400 t, Dud-Cue bei Cooldown), 200-t-Sentinel-Selbstheilung,
  Aktivitäts-Gate (ohne Spieler in 128 Blöcken tickt nur der Inversions-Vergleich).
- **`GravityRiftOrbitals`** — der Choreograph: 218 Displays fixed-mount auf
  `floorY + 30`, Posen sind reine `gameTime`-Funktionen (Orbit + Wobble + Bob +
  Spin, per-Piece-Hashes), Puls-Lift-Hüllkurve, Inversions-Sturz mit Taumel-Spike
  (Extra-Spin läuft in der Gleitphase aus — kein Sichtsprung), Herz-Atem 1.4↔1.8
  mit Puls-/Inversions-Übersteuerung, 90°-Fenster-Gesetz + Reconcile/Sweep gegen
  persistierte Strays, LOD über `viewRange`-Staffelung (3/6/8).
- **`GravityRiftPayloads`** — selbstregistrierender Registrar (`v1woahgravity`,
  DoorPayloads/EchoGrove-Muster): `S2CGravityRiftPayload` (built/anchor/
  invertRemaining) bei Login/Build/Inversionswechsel — nie per Tick; Pulse werden
  NICHT gesynct (beide Seiten rechnen dasselbe Raster).
- **`GravityRiftCues`** — 5 Cue-Ids via `FxCues.cue("woah_gravity_…")`
  (PULSE/INVERT/RESOLVE + die 2 Loop-Ids MOTES/COLUMN).
- **`GravityRiftDevCommands`** — `/dev woah gravity build | pulse | invert |
  orbitals | tp | status` (Perm 2, DevCommandDoc-Zeilen, Audit-Logs, eigener
  `literal("dev")`-Baum — Brigadier merged).

### Client (`woah/gravityrift/client/`)

- **`GravityRiftClientState`** — Payload-Spiegel + abgeleitete Werte (Kamera-Distanz,
  geeastes `amount`, Puls-Kick-Hüllkurve vom lokalen Raster, Inversions-Hüllkurve),
  Logout-Reset.
- **`GravityRiftFxRows`** — 5 PhotonFxRegistry-Rows (Mode LAYER über
  Quasar-Fallbacks `revive_thunderbloom_ring`/`rift_spark`/`unlock_burst`/
  `crater_updraft`/`summon_beacon_pillar`); Invert-Leg skaliert den Dud auf 0.35×.
- **`GravityRiftAmbience`** — Fenster-Controller (Column-Loop 150/170,
  Motes-Loop 52/64, Hysterese) + positionaler Drone am Herz
  (`ambient.gravity_hum` dynamisch aufgelöst, Fallback `event.rift_drone` @0.75;
  Volume-Rampe 64→14, Pitch-Bend +0.35 bei Inversion).
- **`GravityRiftLensFx`** — Veil-Post `eclipse:gravity_lens` (FEATURE-Priorität,
  static-init-Registrierung — StormVolumeFx-Seam): Refraktions-Shimmer, der
  AUFWÄRTS strömt, Radial-Lean, Puls-Schockfront, Inversions-Ripple; Uniforms
  Strength/Center/Aspect/Time/Pulse/Invert/Detail, `reducedFx` → Detail 0.

### Assets

- **Photon** (`tools/photon/woah_gravity_fx.py`, fxlib; alle 5 validiert +
  lint-clean, je mit `.fxproj`-Sibling): `gravity_light_column` (Loop: 90-Block-Beam
  + Aufstiegs-Streaks + Kronen-Glints), `gravity_core_motes` (Loop: Staub-Motes
  32×10×32-Box mit Aufwärts-Drift, Violett-Glints, Dschungel-Sporen),
  `gravity_pulse_ring` (One-Shot 110 t, STAGED: 30 t Konvergenz-Telegraph →
  Boden-Ring r 4→34 + 80-t-Säule + 60er-Staub-Kick), `gravity_invert_burst`
  (One-Shot 60 t: REVERSE_SUB-Maw + Radial-Kollaps → Shard-Shatter +
  Debris-Sheet), `gravity_resolve_wave` (One-Shot 50 t: Settle-Regen + Boden-Ring
  + Herz-Relight).
- **Veil**: `pinwheel/post/gravity_lens.json` + `shaders/program/gravity_lens.json/.fsh`.
- **Loot**: `data/eclipse/loot_table/chests/gravity_rift_loft.json` (Wind Charges,
  Amethyst, Slow-Falling-Potions, garantierte Feather-Falling-IV-Diamantstiefel +
  Umbral-Shard).
- **Langdrop**: `docs/plans_v3/langdrop/woah_gravity.json` (19 Keys en+de).
- **Sounds-Ask**: `docs/plans_v3/wiring/woah_gravity_sounds.json` (nur
  Bestands-Sounds; optionale `ambient.gravity_hum`-Row dokumentiert).

## Verifikation (kein `./gradlew` — Regel)

- Komplettes Paket (14 Java-Dateien) via `javac` gegen
  `build/classes/java/main` + `neoforge-21.1.238-merged.jar` + Gradle-Cache-Libs
  (authlib 6.0.54) kompiliert: **0 Fehler** (einzige Note: das deprecated
  `bus = MOD`-Attribut — identisch zum Haus-Muster `FerrymanFinaleFxRows`).
- Photon: `fxlib.py validate --lint` → 5/5 OK, 0 neue Lint-Findings.
- JSONs (Langdrop, Loot, Pinwheel, Sounds-Ask) geparst; Uniform-Namen
  Feeder ↔ `.fsh` abgeglichen; Quasar-Fallback-Assets existieren alle.

## Offen

1. Langdrop-Merge in `assets/eclipse/lang/*.json` (zentral; bis dahin rohe Keys).
2. Optionale `ambient.gravity_hum`-Sounds-Row (+ .ogg) — Fallback läuft ohne.
3. Zentraler Build + In-Game-Look-Pass (Photon-Optik generiert, nie gerendert).
4. Kein `LandmarkProtection`-Eintrag: Die Landmark-Zeile trägt r 40; falls das
   zentrale Schutzregime für WOAH-Sites nachzieht, Zylinder r 40 / Tiefe 16 um
   (−239, 167) analog RESONANCE.

## RCON-Testanleitung

1. `eclipse stage set overworld 4` (falls nötig; Perm 3) — der Stage-Listener
   enqueued den Bau automatisch; oder direkt `dev woah gravity build` (Gate-Bypass).
2. `dev woah gravity status` — `built`, Anker, Puls-Phase, Display-Zähler
   (Erwartung: 218/218 nach dem Spawn-Streaming).
3. `dev woah gravity tp` — Absetzpunkt an der Kraterkante im freigehaltenen
   Laufsektor, Blick aufs Herz: 3 Schalen kreisen, Staub steigt, Lichtsäule steht.
4. In die Schüssel gehen → Moon-Jump (Apex ≈ 6.7). Item wegwerfen → es driftet
   AUFWÄRTS und schwebt bei ~+24 aus.
5. `dev woah gravity pulse` — Telegraph-Sog 1.5 s, dann Ring + Säule + Abwurf
   (vy 0.9 → ≈ +17); die Sprünge AUF die Stufen +30 und +41 sind die beiden
   Puls-Hero-Gaps (von +23 bzw. +36 aus mit dem Beat abspringen).
6. Parkour bis +46, Loot-Kiste öffnen (Feather-Falling-IV-Stiefel garantiert).
7. Herz (Amethyst-Kern in den Glas-Käfigen) schlagen → 10 s Inversion: Orbitale
   stürzen taumelnd, Spieler/Items steigen, Lens ripplet; danach `resolve`-Welle.
   Sofort nochmal schlagen → Dud-Fizzle (Cooldown 2 min).
8. `dev woah gravity invert` — Inversion ohne Cooldown (FX-QA).
9. `dev woah gravity orbitals` — Display-Discard + Rebuild (Selbstheilungstest);
   `setblock` auf den Sentinel (crying_obsidian, 2 unter dem Sockel) → Auto-Heal
   nach ≤ 200 t.
10. Fern-Test: 200+ Blöcke weg → alle 45 s der violette Lichtstoß über dem
    Dschungel (Cue-Range 256); ≤ 150 die stehende Säule (Loop), ≤ 52 die Motes.

## Risiken / Bekanntes

- Photon-/Lens-Optik ist generiert, aber noch nie in-game gerendert — Look-Feintuning
  wahrscheinlich (alle Assets reproduzierbar über den Generator; Shader-Konstanten
  oben in der `.fsh` gebündelt).
- Displays sind Entities: > ~160 Blöcke unsichtbar (Tracking-Horizont) — das Fernbild
  tragen bewusst die ECHTEN Inseln + die Photon-Säule/Puls-Cues (Hybrid-Gesetz §1).
- Der Puls wirft auch Nicht-Parkour-Spieler in der Schüssel hoch; SAFE_FALL +20 und
  FALL_DAMAGE ×0.40 machen die Landung überall in der Zone straffrei — außerhalb der
  Zone landet niemand (Launch nur innerhalb `inZone`).
- `AttackEntityEvent` feuert vor `Interaction.skipAttackInteraction` (verifiziert) —
  sollte ein Mod die Reihenfolge brechen, bliebe das Herz stumm (kein Crash).
- Bambus wächst nach: der Canopy-Sweep räumt beim Bau, danach hält der versiegelte
  Rim-Ring die Sicht frei; einzelne nachwachsende Halme am Außenrand sind akzeptiert.
