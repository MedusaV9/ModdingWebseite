# WOAH-04 RESONANZFELD — Status „Das Tal der singenden Kristalle"

Neun 20–40-Block-Kristallmonolithe in einer terrageformten Talschale bei `(−395, −30)`
(crystal_steppe, Stage 5): sie singen pentatonisch, wenn man näherkommt, Anschläge
kaskadieren über pulsierende Photon-Lichtbahnen von Kristall zu Kristall, und die
Stimmgabel am Altar startet ein Melodie-Nachspiel-Rätsel, dessen Finale eine
120-Block-Lichtsäule, Arpeggio-Flut, Glitzerregen und 6 Umbral-Scherben liefert.

## Was gebaut wurde

### Server (`woah/resonance/`)

- **`ResonanceFieldService`** — der Dirigent: 20-t-Self-Enqueue-Poll (SkyLauncher-Muster,
  KEINE DiscMapDefaults-Zeile; idempotent gegen `StructurePendingRegistry`
  placed/pending), Display-Spawn-Queue (4/t Budget), Strike-Routing (Attack + Use auf
  den Interaction-Hitboxen, Use am Altar = TEACH), Nachbargraph-Kaskade
  (Tiefe ≤ 2, 3 t/Hop, Queue-Cap 32, Glow-Pulse 10→14 mit 8-t-Restore), 200-t-Selbstheilung
  (fehlende Displays/Hitboxen aus SavedData nachbauen), Session-Sweep-Doktrin gegen
  persistierte Display-Strays, Login-/Change-Resync des Payloads, 128-Block-Aktivitäts-Gate
  (ohne Spieler tickt nur der Cooldown-Vergleich).
- **`ResonanceFieldBuilder`** — `AsyncSitePlacer`-Site `eclipse:resonance_field`
  (Footprint 88): Talschale (r 36, Tiefe 7, Rim +2) mit Calcite/Basalt-Adern,
  deterministisches Monolith-Layout (Golden-Angle um den Anker; 4×S/3×M/2×L),
  Schichten-Displays nach dem Boulder-Vorbild (Kern-Segmente mit Taper/Twist/Jitter,
  Golden-Angle-Facettenschalen, Glow-Nadeln 15/15, Sockel-Skirts) ≈ 105 Displays gesamt,
  `minecraft:interaction`-Hitboxen pro Kristall + Altar, Altar aus 6 Displays
  (Stimmgabel-Look), FX-Anchor `eclipse:resonance_center`.
- **`ResonanceFieldData`** — SavedData (`eclipse_resonance_field`): Geometrie
  (Anker/Altar/PlateauY/9 Monolithe mit Seeds, Tone-Index, Nachbarn), Melodie-Seed +
  Rätselzustand (State/Since/Progress/Fails/Cooldown/Solves) — Displays werden NIE
  persistiert, nur die Seeds.
- **`ResonanceMelodyMachine`** — Statemachine IDLE→TEACH→LISTEN→FINALE/FAIL→COOLDOWN:
  TEACH 14 t/Beat (5-Noten-Melodie, `ResonanceTones`-Pentatonik A3–E5), LISTEN-Fenster
  600 t mit Glow-Hint (config-gated), FAIL = Dissonanz-Dyade + Reroll nach 3 Fehlversuchen,
  FINALE 160 t (Arpeggio-Flut → Akkord → 6 Umbral-Shards + 300 XP über die Kristallfüße
  → Schwell-Ausklang; Erstlösung zusätzlich Vitae-Shard + Analytics-Zähler),
  COOLDOWN 12000 t (10 min) mit Restzeit-Caption am Altar.
- **`ResonanceTones`** — geteilte Pentatonik-Tabelle ({−12,−10,−8,−5,−3,0,+2,+4,+7}
  Halbtöne → `2^(n/12)`), Melodie-Roll (keine Direktwiederholung), Finale-Akkord.
- **`S2CResonanceFieldPayload`** — Geometrie + Zustand an die Clients (Kristalle mit
  basePos/height/girth/tone, Kantenliste, State/Since), gesendet bei Build/State-Flip/Login.
- **`DevResonanceCommands`** — `/dev woah resonance spawn [here] | melody [print|new] |
  solve | reset | status` (Perm 2, DevCommandDoc-Zeilen registriert, Audit-Logs).
- **`ResonanceCues`** — die 4 Cue-Ids via `FxCues.cue(…)` (STRIKE/PULSE/FAIL/FINALE).

### Client (`woah/resonance/client/`)

- **`ResonanceFieldClient`** — Payload-Spiegel (immutable Snapshot, voice/top-Helfer,
  Logout-Clear).
- **`ResonanceChoir`** — das Pentatonik-Singen: eine `AbstractTickableSoundInstance` pro
  Kristall (SanctumHum-Ableitung), Attenuation NONE + manuelle Distanzkurve
  `0.65 × clamp(1 − (dist−4)/44)^1.5`,

  Voice-Budget 4 (nächste zuerst, Hysterese 44/52, leiseste wird verdrängt), Sing-LOD
  hart < 48 Blöcke; Sound-Event `eclipse:ambient.crystal_voice` wird dynamisch
  aufgelöst, bis dahin gepitchter `AMBIENT_LIMBO_LOOP`-Fallback.
- **`ResonanceFieldFx`** — WINDOWED-Loop-Controller (KEINE Registry-Loop-Rows):
  ≤4 Kristall-Auren (56/64), ≤6 Bahn-Loops (64/72, beide Enden; Yaw+Längen-Scale über die
  neue `PhotonBridge.spawnLoop`-Options-Überladung; COOLDOWN dimmt via 0.6-Scale-Respawn),
  Fern-LOD 160–400 Blöcke (≤4 Schäfte über den höchsten Kristallen + 1 Himmelspuls),
  Gesamtquote ≤ 12 Handles; ≤2 violette Veil-Punktlichter nachts (atmend, 40/48) +
  1 Finale-Licht (160-t-Envelope); Post-Shimmer-Envelope (Strike < 16 → 0.35/12 t,
  Finale < 48 → 0.6/40 t) als `VeilPostController.PipelineSpec` (FEATURE-Band,
  statische Registrierung).
- **`ResonancePhotonFxRows`** — 4 One-Shot-Rows, alle `Mode.LAYER` über
  Quasar-Baselines; STRIKE/PULSE mit Custom-Legs (allowMulti; PULSE rotiert 180°−a und
  streckt Z auf die Hop-Länge), STRIKE/FINALE-Legs füttern den Shimmer.

### Assets

- **`tools/photon/resonance_fx.py`** (fxlib) generiert validiert + lint-clean, je mit
  `.fxproj`-Sibling und CullBox: `resonance_crystal_aura`, `resonance_bahn` (Unit-Z-Beam
  + Richtungs-Motes), `resonance_strike_burst`, `resonance_pulse_hop`,
  `resonance_fail_flicker` (REVERSE_SUB + rotes Doppel-Ring-Flackern),
  `resonance_finale_column` (120-Block-Beam, Glitzerregen collide+die, Schockring,
  Kronen-Burst — in-Asset-Staging 0/10/10/20 t), `resonance_far_shaft`,
  `resonance_far_pulse`.
- **Quasar-Fallbacks**: `resonance_strike|pulse|fail|finale.json` (END_ROD-/Wisp-
  Kompositionen im Stil der shipped Emitter).
- **Veil-Post**: `pinwheel/post/resonance_shimmer.json` +
  `pinwheel/shaders/program/resonance_shimmer.fsh` (radialer chromatischer Offset ≤ 2 px,
  6.5-Hz-Tremble, Dither).
- **Docs**: `docs/plans_v3/langdrop/woah_resonance.json` (en+de),
  `docs/plans_v3/wiring/woah_resonance_sounds.json` (Sound-Inventar + deferred Row),
  `docs/plans_v3/wiring/woah_resonance_wiring.md` (geteilte Dateien + Merge-Punkte).

### Compile-Check

`javac` über den kompletten `src/main/java`-Baum (1171 Dateien) gegen
Minecraft+NeoForge-, Legacy-Classpath- und `run/mods`-Jars: **exit 0** (die einzigen
Fehler im ungefilterten Lauf lagen in fremden, parallel in Arbeit befindlichen
Feature-Lanes bzw. am fehlenden EMI-Jar im handgebauten Classpath).

## Offen

- **Langdrop-Merge** (en/de) — sonst rohe Keys in Captions/Dev-Feedback.
- **Optional**: `ambient.crystal_voice`-Row + .ogg (Choir schaltet automatisch um).
- **Optional**: FxCues-Konsolidierung, siehe Wiring-Doc.
- Feintuning der Photon-Optik im Editor (`/photon_editor` → die `.fxproj`-Siblings) nach
  dem ersten In-Game-Blick — die Generator-Werte sind Plan-treu, aber ungesehen.

## RCON-Testanleitung

1. `dev stage set overworld 5` (falls nötig) — oder direkt Schritt 2 in Dev-Welten.
2. `dev woah resonance spawn here` — Terraform + Bau am Standort (wenige Sekunden;
   `dev woah resonance status` zeigt `displays=…/…` beim Auffüllen).
3. Kristall anschlagen (Linksklick auf den Monolith) → Note + Glitzer-Cue + Glow-Pulse,
   Nachbarn echoen nach 3 t (Kaskade, Bahnen-Cues).
4. Altar (Stimmgabel im Zentrum) rechtsklicken → TEACH: 5 Kristalle blinken/klingen
   nacheinander; danach nachspielen. Falsche Note → Fail-Sting; richtige Folge →
   Finale (Säule + Regen + Shards).
5. `dev woah resonance melody print` — Soll-Reihenfolge mit Koordinaten (zum Nachspielen).
6. `dev woah resonance solve` — Finale-Abnahme ohne Rätsel.
7. `dev woah resonance reset` — Entity-Rebuild-Test (Selbstheilung).
8. Fern-LOD: 200+ Blöcke wegfliegen → hauchdünne HDR-Schäfte + 8-s-Himmelspuls
   (Client-seitig; `dev photon` für Executor-Zahlen).
9. Choir: < 48 Blöcke an die Kristalle — bis zu 4 positionale Stimmen (bis die
   crystal_voice-Row gemergt ist: tiefer Limbo-Loop-Drone, gepitcht pro Kristall).

## Risiken / Bekanntes

- Die Photon-Optik ist generiert, aber noch nie in-game gerendert worden — Look-Feintuning
  wahrscheinlich (bewusst alle Assets über den Generator reproduzierbar).
- `resonance_bahn`/`resonance_pulse_hop` verlassen sich auf Executor-Z-Scale = Kantenlänge;
  bei extremen Kanten (> ~40 Blöcke) wird der Mote-Strom dünner (Rate ist längenunabhängig) —
  akzeptiert, die Beam-Komponente trägt die Lesbarkeit.
- Ohne Veil-Renderer/Iris: keine Punktlichter/Shimmer — Glow-Displays (15/15) + `lights`-
  Module tragen die Nacht-Lesbarkeit (dokumentiertes Fake-Glow-Verhalten).
- Der LISTEN-Glow-Hint ist config-gated (`resonance.hintGlow`, Default an) — QA kann ihn
  für „pure" Playtests ausschalten.
