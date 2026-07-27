# END-ARRIVAL (F-077) — Status „Der Altar ruft das End"

~50-Sekunden-Kino, wenn das End erscheint: Der Sanctum-Altar saugt die Umgebung leer,
schießt eine violette Säule in den Himmel, dort reißt ein riesiger End-Riss auf, und
hunderte Endstein-Brocken strömen sichtbar aus Altar und Riss auf das entstehende
Himmels-Archipel, während der echte Disc-Bau synchron darunter läuft.

## Was gebaut wurde

### Server (`sequence/endarrival/`)

- **`EndArrivalSequence`** — der autoritative Phasen-Automat (Muster
  `NetherOpeningSequence`), Tick-Tabelle:

  | Phase | Ticks | Inhalt |
  |---|---|---|
  | OMEN | 0–160 (0–8 s) | Sog-Streaks auf den Altar (`CUE_SUCTION` + gerichtete REVERSE_PORTAL-Baseline), tiefes Grollen, Beben-Pulszug 0.06→0.22, Whisper-Caption |
  | CHARGE | 160–400 (8–20 s) | `erupt`-WIRING-Punkt, Energie-Ringe (`CUE_RINGS`), Tick 200 Säule (`CUE_PILLAR`, Y-skaliert auf echten Altar→Riss-Abstand) + Beacon/Whoosh, Tick 240 Riesen-Maw (`CUE_MAW`) + End-Portal-Spawn + kleiner Veil-Distortion-Ring, Beben 0.28→0.6 |
  | SPILL | 400–800 (20–40 s) | `EndDiscService.materialize` startet ECHT (announceCrash = globales 2.0-Beben, Drachen-Growl, Chat-Announce, Client-Crash-Timeline), `EndArrivalDebrisFx` strömt, Wisps alle 25 t (`CUE_WISP`), violette Blitze alle 50 t (`FX_LIGHTNING_STRIKE` — weißer Kern, violetter Zerfall, kein Feuer), Dragon-Breath-Ausatmen am Riss |
  | FINALE | 800–1000 (40–50 s) | Debris-Kollaps, `CUE_IMPLOSION` + `FX_SHOCKWAVE`(0.9/45)-Distortion-Puls, `CUE_GLITTER` (Säule zerfällt), Rift-Thud + Explosion, Tick 850 ferner Drachen-Schrei, Tick 870 Titel-Caption „DAS END IST GEKOMMEN", Beben 0.85→0.12 |

  Beat-Clock armiert auf den ersten Cutscene-Preload-ACK (Timeout-Fallback 100 t, das
  `EndShatterSequence`-Gesetz); ohne Spieler in Altar-Nähe läuft sie sofort frei.
- **`EndArrivalDebrisFx`** — die „Baustoff-Show": 220 BlockDisplays (Cap 260) aus
  end_stone/obsidian/purpur/chorus, StormDebrisFx-Doktrin 1:1 (EIN Mount auf der
  Säulenachse, view_range 8×≈512 Blöcke, Batch-Spawn 10/2 t, 3-t-Slice-Pushes,
  Presence-Gate 384 Blöcke, Watchdog 2400 t, Tag `eclipse_end_arrival_debris` +
  Live-UUID-Sweep). Flugbahn: 50 t Helix den Pfeiler hoch, 76 t Auswärts-Spirale vom Riss
  auf einen Ring-Slot der Disc (Radius 0.30–0.96 × r), Snap-out auf 0-Scale; gelandete
  Stücke werden RECYCELT (konstanter Strom, null Spawn-Churn). Jede 4. Landung stempelt
  `CUE_PUFF` + END_ROD/PORTAL-Baseline (max. 2/Tick).
- **`EndArrivalFxCues`** — die acht Cue-Ids via `FxCues.cue(…)` (FxCues.java gesperrt).

### Client

- **`veilfx/EndArrivalFxRows`** — selbstregistrierender Row-Registrar (Muster
  `FerrymanFinaleFxRows`): 8 REPLACE-Rows mit Quasar-Floors (`altar_indraw`,
  `altar_levelup_ring`, `altar_beam`, `riss_maw_shimmer`, `vortex_wisp`, `rift_spark`,
  `unlock_burst`, `stern_funke_fall`), alle im SEQUENCE-Budget-Kanal. Säule/Glitter
  Y-skalieren über Payload `a` (Modellhöhen 260/240); Wisp/Puff nutzen
  `allowMulti=true`-Legs (viele Stempel an je neuen Positionen).

### Photon-Assets

- **`tools/photon/end_arrival_fx.py`** generiert (validiert, .fx + .fxproj):
  `end_arrival_suction`, `_rings`, `_pillar` (260-Block-HDR-Beam, 620 t), `_maw`
  (r=14-Wirbel, dunkel-auf-hell wie `day_rift_maw`, 560 t), `_wisp`, `_puff`,
  `_implosion`, `_glitter` — SAC-Violett-Palette + GLI-Funken.

### Kamera

- **`assets/eclipse/cutscenes/end_arrival.json`** (+ Registrierung in
  `CutscenePaths.DEFAULT_IDS`): 1000-t-LOCAL-Fahrt (kein Teleport, skippbar, letterbox)
  für Spieler ≤128 Blöcke am Altar — Nahorbit → Erupt-Rückzug → Ritt die Säule hinauf →
  weite Krankurve am Riss vorbei → Totale → Implosions-Framing → Settle auf die Disc.
  Events im JSON bewusst LEER (der Server broadcastet Sound/Shake/Captions an die ganze
  Dimension, damit Frei-Zuschauer identisch hören/fühlen).

### Verdrahtung

- **`worldgen/end/EndDiscService.materialize`** (minimal-additiver Hook, 7 Zeilen +
  Import): der ALLERERSTE Start geht an `EndArrivalSequence.interceptFirstMaterialize`;
  die Sequenz ruft an der Phase-3-Grenze durch einen Latch (`buildingDisc`) wieder hinein.
  Restart-Resume (`materializationStarted == true`) und laufende Jobs umgehen die Show
  unverändert; stirbt der Server VOR Phase 3, feuert der Tag-Trigger einfach neu und die
  Show beginnt von vorn (das End war ja noch nicht da).
- **`devtools/dev/DevEndArrivalCommands`** — `/dev event start endarrival [fxonly]`,
  `/dev event stop endarrival` (eigener Brigadier-Baum, merged in die `/dev event`-Root;
  `DevEventCommands.java` unangetastet), inkl. `DevCommandRegistry`-Doku-Einträgen.

## Offene Verdrahtung (→ `end_arrival_wiring.md`)

1. `AltarModelTriggers.trigger(level, "erupt")` am CHARGE-Eintritt (Kommentar-Marker sitzt).
2. Langdrop `docs/plans_v3/langdrop/end_arrival.json` (en+de) in die Lang-Dateien mergen.
3. Optional: Cue-Ids nach `FxCues` konsolidieren.

## RCON-Testanleitung

```
# Voraussetzung: Welt mit gebautem Sanctum (sonst fällt die Bühne auf das Gelände
# unter dem Disc-Zentrum zurück). Operator in Altar-Nähe stellen für die Kamera.

# 1) Reine FX-Probe (beliebig oft, schreibt nichts):
/dev event start endarrival fxonly

# 2) Der echte Pfad (Disc materialisiert ab Phase 3; nur einmal pro Welt sinnvoll):
/dev event start endarrival

# 3) Abbruch/Aufräumen jederzeit:
/dev event stop endarrival
/kill @e[tag=eclipse_end_arrival_debris]      # Belt-and-braces

# 4) Trigger-Pfad end-to-end (statt Kommando): Tag >= 12 setzen und den 20-t-Poll
#    feuern lassen — /dev day set 12 (bzw. der Zeit-Befehl des Progressions-Workers).

# Sichtprüfung: Sog (0-8 s) → Ringe+Säule+Riss (8-20 s) → Chat-Announce + globales
# Beben + Brocken-Strom + violette Blitze (20-40 s) → Implosion + Schockwellen-Ring +
# Glitzer + Titel-Caption (40-50 s). Danach läuft der budgetierte Disc-Bau weiter
# (Minuten); EclipseDragonFight startet wie gehabt bei Bau-Abschluss.
```

## Risiken / Annahmen

- **Kamera-Framing ist geometrie-tolerant, nicht exakt**: LookAt-Offsets nehmen den Riss
  ~300–360 Blöcke über dem Altar an (Riss = surfaceY 360 + 80; Altar-Y variiert mit der
  Sanctum-Stufe). Die Einstellungen sind bewusst himmelsweit — Drift bleibt unsichtbar,
  aber ein Reshoot nach echtem Playtest ist einkalkuliert.
- **Steht der Altar weit vom Disc-Zentrum (0,0)**, wandert die Transit-Spirale
  entsprechend weit — Pfad bleibt stetig (Start-Radius wird vom echten Riss-Punkt aus
  gerechnet), aber die Show liest sich am besten mit Sanctum nahe Origin (Normalfall).
- **Restart in Phase 1/2** startet die Show neu (dokumentiertes Verhalten, kein
  Doppel-Build möglich — der Flag-Commit passiert erst am Phase-3-Reentry).
- **`/eclipse-worldgen end materialize`-Kommandopfad** läuft jetzt ebenfalls durch den
  Intercept (gleiches Kino). Wer den nackten Sofort-Bau will: erst
  `/dev event start endarrival` laufen lassen oder den Intercept-Guard temporär umgehen —
  bewusst so gelassen, damit der Event nie „zwischen zwei Ticks" erscheint.
- **Blitz-Farbe** hängt am bestehenden `StormFxClient`-Ribbon (weißer Kern, violetter
  Zerfall) — passt zur Vorgabe „violette Blitze, kein Feuer" ohne neuen Code.
