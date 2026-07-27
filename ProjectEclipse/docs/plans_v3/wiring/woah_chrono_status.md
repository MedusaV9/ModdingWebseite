# WOAH-03 CHRONO-STASE — Status

Implementierung von `docs/plans_v3/woah/PLAN-03_chrono_stasis.md`. Feature-Code in
`dev.projecteclipse.eclipse.woah.chronostasis` (+ `.client`); geteilte Dateien nur über die
sanktionierten Ausnahmen (Details: `woah_chrono_wiring.md` daneben).

## Gebaut (fertig, kompiliert)

**Server** (`woah/chronostasis/`):

- `ChronoStasisSite` — Landmark-Materialisierung im FogStormSites-Muster: Stage-3-Listener
  → `StructurePendingRegistry`-Async-Placer → `SitePrep.preparePlateau` → budgetierter
  Carve (Kosinus-Senke r24/T3, Moos/Podzol-Kern, 2×2-Blackstone/Magma-Krater,
  Turmstumpf-Ruine, 7 geknickte Rand-Birken + 2 liegende Stämme) → `SitePrep.finish` →
  SavedData-Flags + Seed-Roll + `FxAnchors.CHRONO_CENTER`-Publish + Service-Handoff.
  Restart-Restore (`ServerStartedEvent`) und Stage-Rollback (Teardown) inklusive.
- `ChronoSceneBuilder` — ~460 BlockDisplays deterministisch aus dem persistierten Seed
  (Gruppen BOLT/BLAST/TOWER/SPHERE/AMBIENT; Blitz bis ~Y+58, Explosionsschalen,
  Turm-Kollaps-Bogen, Chronosphäre mit Ringen + Sanduhr, Vögel/Laub). Identity-Tags
  (`eclipse_chrono_prop` + Prop-Tag), SanctumOrbitals-Reconcile
  (adopt/dedupe/respawn), Budget-Spawn ≤60/t, Pose als reine Funktion
  (`poseOf(prop, params)`) — kein Drift, beliebig wiederholbar.
- `ChronoStasisService` — Statemachine FROZEN→JOLT(×5)→DISCHARGE→REWIND mit
  Pose-Wellen ≤80 Pushes/t, Slowness-IV/Mining-Fatigue-Aura (Mobs, nicht Spieler) +
  Projektil-Dämpfung, Interaction-Pad (2.8×2.8, `eclipse_chrono_sphere_pad`,
  Cancel + Re-Click-Guard), Belohnung (1. Entladung: `chrono_core` + 64 Shards +
  LandmarkDiscovery; danach 8 Shards, 5-min-Cooldown), Watchdog (600 t → FROZEN),
  Boot-Pose-Heilung nach Crash mitten in DISCHARGE.
- `ChronoStasisData` — SavedData (placed, sceneSeed, joltCount, discharges,
  rewardClaimed); `ChronoCues` — 2 Cue-Ids via `FxCues.cue(...)`;
  `ChronoStasisItems` — eigener DeferredRegister für `chrono_core`
  (unter dem WOAH-03-Anker in `WoahFeatures` registriert);
  `ChronoStasisDevCommands` — §9-Befehle (legt den `/dev woah`-Literal erstmalig an).

**Client** (`woah/chronostasis/client/`):

- `ChronoZoneState` — Kamera-Distanz zum `CHRONO_CENTER`-Anker, geeastes `amount`
  (12-Block-Rampe), Jolt-/Discharge-Fenster-Timer, `suppressVanillaRain()`-Gate.
- `ChronoGradeFx` — Veil-GRADE `eclipse:chrono_grade` (Desaturierung, kühler Tint,
  Vignette, Zeitstaub-Glitzer, Discharge-Weißkick; `reducedFx`/Iris-Gate wie XboxEraFx).
- `ChronoRainField` — Photon-Loop-Fenster nach Distanz-LOD (Fern-Säule 640–96,
  eingefrorener Regen ≤3 Slots, Dust-Schimmer, Sphären-Corona, Bolt-Glow < r26);
  Discharge-Umschaltung auf `chrono_rain_release`.
- `ChronoTickSound` — Uhrschlag, Periode 1.7 s (Rand) → 3 s (Sphäre), Pause im JOLT,
  Mute in DISCHARGE/REWIND; `ChronoStasisFxRows` — PhotonFxRegistry-Rows der 2 Cues
  (Jolt-Puls mit Dust-Variante a<0, Discharge-Burst + Fenstersteuerung).

**Assets:** 8 Photon-`.fx` + `.fxproj` via `tools/photon/chrono_fx.py` (Lint: nur
INFO-Advisories, Stand aller Ship-Assets); `chrono_grade`-Pipeline/Programm/`.fsh`;
`chrono_core`-Modell + 16×16-Textur. **Docs:** Langdrop `woah_chrono.json` (en_us+de_de,
Key-Parität geprüft), `woah_chrono_sounds.json` (0 neue Sound-Events — alles live
gelayert), `woah_chrono_wiring.md`.

## Verifikation (ohne gradlew, Regel-konform)

- `javac` gegen `build/moddev/artifacts/neoforge-21.1.238-merged.jar` + Gradle-Cache-Deps
  (Veil 4.3.0, authlib 6.0.54 gepinnt): **alle 13 Feature-Klassen + die 3 angefassten
  geteilten Dateien fehlerfrei** (1133 .class inkl. transitiv gezogener Repo-Quellen).
- `python3 tools/photon/fxlib.py validate --lint`: chrono-Assets ohne WARN/ERROR.
- Alle neuen JSONs geparst; Textur als 16×16 RGBA verifiziert.
- Mixin-Ziele (`renderSnowAndRain`, `tickRain`) und alle Vanilla-Signaturen per `javap`
  gegen den merged Jar geprüft.

## Offen (bewusst — gesperrte Dateien / spätere Welle)

1. **Lang-Merge**: `docs/plans_v3/langdrop/woah_chrono.json` → `en_us.json`/`de_de.json`.
   Ohne Merge erscheinen rohe Keys (funktional).
2. **Optional**: Cue-Konstanten nach `FxCues`, Item nach `EclipseItems`, dedizierte
   `sounds.json`-Rows (Definitionen liegen in `woah_chrono_sounds.json`) — reine
   Konsolidierung, kein Funktionsloch.
3. **Kein In-Game-Lauf**: `./gradlew` war gesperrt; Runtime-Verhalten (Shader-Kompilat,
   Photon-Spawns, Display-Streaming) steht beim zentralen Build/Testlauf aus.

## RCON-Testanleitung

```
# 1) Site erzwingen (Stage-Gate-Bypass; async, ein paar Sekunden) + Status
dev woah chrono spawn
dev woah chrono status

# 2) Hinfliegen (Landmark -24/240; Y je nach Terrain ~68)
execute as @p run tp @s -24 80 240

# 3) Jolt-Treppe: 5× (tick/discharge brauchen einen Spieler-Kontext → execute as)
execute as @p run dev woah chrono tick
# … ×4 wiederholen, ODER abkürzen:
execute as @p run dev woah chrono tick count 4
execute as @p run dev woah chrono tick

# 4) Entladung erzwingen (ignoriert Zähler + 5-min-Cooldown)
execute as @p run dev woah chrono discharge

# 5) Selbstheilung: Props killen → Reconcile respawnt (≤ ~2 min) oder sofort:
kill @e[tag=eclipse_chrono_prop]
dev woah chrono reset
dev woah chrono status

# 6) Restart-Test: Server neu starten → status muss placed=true + Szene zeigen,
#    joltCount/discharges/rewardClaimed müssen den Werten vor dem Restart entsprechen.
```

Erwartung: `status` zeigt `placed=true`, Phase FROZEN, ~460 definierte Props, live-Zahl
steigt mit Chunk-Load; Rechtsklick auf die Sphäre = Jolt-Ruck + Actionbar `(n/5)`;
5. Klick = Blitz-Einschlag → Explosions-Auflösung → Turm-Kollaps → Item + Shards →
REWIND in die Grundpose.

## Risiken

1. **Shader ungetestet zur Laufzeit** — `chrono_grade.fsh` folgt exakt der
   xbox_era-Vorlage (Uniform-Feeding via `VeilPostController`), aber GLSL kompiliert erst
   im Client. Gegenprobe beim zentralen Testlauf; Fallback: Grade-Row deaktivieren.
2. **Display-Pop-in beim Einflug** (~460 Entities, 3×3 Chunks) — Budget-Spawn + harter
   600er-Deckel + Brightness statt Lichtblöcken; Präzedenz CreditsShatterAct (~1400).
   Falls doch spürbar: AMBIENT-Gruppe streichen (−55) / Rauchballen halbieren.
3. **Parallel-Wave-Merge** — `WoahFeatures`-Anker, `FxAnchors`, `LevelRendererMixin`
   werden von mehreren Agents editiert; alle drei Edits sind minimal-additiv an den
   vorgesehenen Ankerpunkten, Konfliktfläche klein.
4. **`/dev woah`-Literal-Kollision** — dieses Feature legt den Knoten an; andere
   Woah-Features müssen nur den Leaf-Namen (`chrono` ist belegt) meiden, Brigadier
   merged den Rest automatisch.
