# WAVE4 Combat Feel — Team-A-Report (F-104, Polish-Welle 4)

Team A „Combat Feel Vollausbau" — Implementierungsreport. Alle Items aus IDEA-02
(`docs/plans_v3/ideas_wave4/IDEA-02_combat_feel.md`), Erst-Verifikation gegen den
Tree nach Commit „eclipse v4 wave" (Top-Picks waren bereits konsumiert).

## 1. Erst-Verifikations-Tabelle

| Item | Befund | Beweis-Kommando (vor Implementierung) |
|---|---|---|
| A1 Tyrant-Core-Flicker | OFFEN | `rg -n "flicker\|desperation\|blackout" src/main/java/dev/projecteclipse/eclipse/client/entity/fogboss/FogTyrantRenderer.java` → 0 Treffer (nur Enrage-Pulse/Speed-Lines); `rg -n "DATA_PHASE\|DATA_CORE_LIT" …/FogTyrantEntity.java` → beide synced vorhanden |
| A2 Glitch-Death-Dissolve | OFFEN | `rg -n "getRenderColor\|dissolve\|entityTranslucent" src/main/java/dev/projecteclipse/eclipse/client/entity/glitch/GlitchedGeoRenderer.java` → 0 Treffer (nur Flicker/Pop/UprightDeath) |
| A3 Crit-Sparkles | OFFEN | `rg -rn "CriticalHitEvent" src/main/java` → 0 Treffer im ganzen Tree |
| A4 Damage-Magnitude-Bursts | OFFEN | `rg -rn "CombatFeedbackFx\|magnitude" src/main/java` → 0 Treffer; `drama/` enthielt nur HitStop/KillConfirm/… |
| A5 Whiff-Reward | OFFEN | `rg -n "whiff\|dodge\|Wind" …/FogTyrantEntity.java …/GroundSlamGoal.java` → 0 Treffer |
| A6 Hound-Stagger-Tell | OFFEN | `rg -n "stagger" …/StormHoundEntity.java …/StormHoundRenderer.java` → 0 Treffer (STAGGER nur als Goal-interne Phase); `rg -n "defineSynchedData" …/StormHoundEntity.java` → kein Override |
| A7 wave4_combat-Familie | OFFEN | `ls src/main/resources/assets/eclipse/fx/ \| rg wave4` → leer; `ls tools/photon/ \| rg wave4` → leer |
| Fertige Feel-Klassen | DONE — nicht angefasst | `rg -l "HurtSparks\|KillConfirmService\|HitStopService" src/main/java` → alle drei vorhanden; Colossus-Death-Slam (`rg -n "deathSlam\|DEATH_SLAM" …/FogColossusEntity.java`) und Warden-Stagger-Slump (`rg -n "StaggerGlowLayer\|applyRotations" …/RiftWardenRenderer.java`) bereits implementiert |
| Q2 Hygiene-Zähler | GESTRICHEN | Beweis + Begründung in §4 |

## 2. Was gebaut wurde

### A7 — Photon-Cue-Familie `wave4_combat` (zuerst, weil A1–A6 sie konsumieren)

Neuer uuid5-deterministischer Generator `tools/photon/wave4_combat_fx.py` nach
exakt dem `wave3_fx.py`-Muster (lokale HDR/units-Helfer, `varied()`-random_gradient
überall, `.fxproj`-Siblings, Round-Trip-Validierung im `write()`). Vier Assets in
`assets/eclipse/fx/`: `wave4_crit_gleam` (13 Sprites, das billigste — höchste
Frequenz), `wave4_heavy_impact` (29 Sprites, Streak-Blume + Flash + Payout-Ring),
`wave4_stagger_arc` (26 Sprites, 40t-Fenster == `ChargedLungeGoal.STAGGER_TICKS`,
Crackle + Dizzy-Orbit-Halo), `wave4_dissolve_motes` (28 Sprites, Cyan/Magenta-
Pixel-Split via random_gradient + schrumpfender Alpha-Veil). V2.1-Stacking-Law:
dunkle Birth-Tints überall, HDR ≤ 1.45 (`hdr()`-Clamp), CullBox auf jedem Emitter,
nur One-Shots, keine Loops/Prewarm. Palette = ausschließlich Wave3-Token (SAC-Gold,
ERA-Amber/Ember, GLI-Cyan/Magenta, GLI_DEAD-Births) → 0 neue Palette-Advisories.

Neue selbstregistrierende Row-Klasse `veilfx/Wave4CombatFxRows.java` (Muster
`Wave3FxRows`): 4 Rows, alle `Mode.LAYER`, Quasar-Leg `null` (legal — Baseline vor
der Row war nichts), Channel BURST, `reducedFx`-Drop in jedem Leg mit dokumentiertem
Fallback. `FxCues.java` unangetastet — Cue-Ids via `FxCues.cue("wave4_…")` beidseitig
re-deriviert (Wave3-Naming-Contract).

### A3 + A4 — `drama/CombatFeedbackFx.java` (NEU)

Zwei stateless Server-Listener, Guard-Muster von `HitStopService` gespiegelt.
**A3**: `CriticalHitEvent` (feuert beidseitig aus `Player.attack`, VOR dem Schaden) →
Server-Guard via `level() instanceof ServerLevel`, nur lebende `LivingEntity`-Opfer;
sendet den bestehenden `eclipse:impact_light`-Quasar-One-Shot an die Opfer-Brust
(`S2CQuasarPayload`-Seam wie `WandPhaseService`; Client-Handler budgetiert BURST) plus
den neuen `wave4_crit_gleam`-Photon-Cue auf der Positions-Lane. **A4**:
`LivingDamageEvent.Post`, nur `EclipseGeoMonster`-Opfer, nur spielerverursachter
Schaden (`getSource().getEntity() instanceof ServerPlayer` — deckt Melee + eigene
Projektile), Buckets auf `getNewDamage()`: ≥ 4 → skalierter `sendParticles`-CRIT-Burst
(6–11 Sterne), ≥ 8 → dichterer Burst (12–28, ~1.6/Schadenspunkt) + `wave4_heavy_impact`
mit `a` = Schaden (skaliert das Asset 0.9–1.25).

### A5 — Whiff-/Dodge-Reward (`FogTyrantEntity`, `GroundSlamGoal`)

Neuer geteilter Helfer `FogTyrantEntity.sendWhiffReward(level, player, ability)`:
privater Wind-Pass = `playNotifySound(BREEZE_WHIRL)` (nur dieser Spieler hört es) +
targeted `sendParticles(player, SMALL_GUST, …)` (nur dieser Spieler sieht es) + eine
DEBUG-Sonde pro Send (Muster der Hygiene-Populations-Sonde). Trigger: (1)
`releaseLances` — unstruck Teilnehmer, die im Near-Miss-Korridor einer gefeuerten
Lanze stehen (`LANCE_HALF_WIDTH` + 1.8 Blöcke, gleiche along/offLine-Mathematik wie
der Hit-Test — wer quer durch die Arena flieht, bekommt nichts); (2) `releaseSquall` —
jeder `covered`-Spieler (LOS gebrochen = der beabsichtigte Counterplay); (3)
`GroundSlamGoal.slam` — airborne Spieler außerhalb des Cores, die der Skip-Branch
überspringt (der getimte Sprung). Log-Sonde: `[w4a-whiff] <name> dodged <ability>`.

### A6 — Hound-Stagger-Tell (`ChargedLungeGoal`, `StormHoundEntity`, `StormHoundRenderer`)

`StormHoundEntity` bekommt das synced Flag `DATA_LUNGE_STAGGERED` (+
`defineSynchedData`-Override, public Getter, package-private Setter — nur das Goal
schreibt). `ChargedLungeGoal` setzt es in `beginStagger`, löscht es am Fenster-Ende
in `tickStagger` UND in `stop()` (Tod/Preemption lassen das Tell nie hängen).
`StormHoundRenderer.preRender` hält während des Flags einen `eclipse:rift_spark`-
Quasar-Loop attached (`ensureAttached`, BURST — Budget-Refusals retrien gratis) und
feuert auf der steigenden Flanke EINMAL `wave4_stagger_arc` über
`PhotonFxRegistry.dispatchEntity` (Entity-Attach → Photon räumt bei Mid-Stagger-Tod
selbst auf; 40t-Asset == 40t-Fenster, kein Loop-Bookkeeping nötig). Fallende Flanke
detacht im `preRender`; ein `ClientTickEvent.Post`-Sweep ist der Backstop für Hounds,
die mid-stagger aus dem Sichtfeld/der Welt verschwinden (culled Entities rendern nicht).

### A1 — Tyrant-Desperation-Core-Flicker (`FogTyrantRenderer`)

Im `EnrageGlowLayer` (der Layer, der den Stock-Glowmask-Pass besitzt):
`desperationBlackout()` — bei `getPhase() >= 3` (== dem ≤25%-HP-Break aus
`updatePhase`) und `isCoreLit()` droppt der GESAMTE Emissive-Pass (Krone, Auge,
Storm-Core, inkl. Enrage-Overdrive) für 1–2t auf einem deterministischen
(EntityId, GameTime-Fenster)-Hash-Schedule — dieselbe SplitMix64-Kadenz-Mechanik wie
`GlitchedGeoRenderer.isAltFrame` (8t-Fenster, ~5/8 stottern, unregelmäßig, nie
Strobe). `reducedFx` und `deathTime > 0` stehen komplett still (der Death-Gutter
besitzt sein eigenes `setCoreLit(false)`). Null per-Frame-State, kamera-cut-stabil.

### A2 — Glitch-Death-Dissolve (`GlitchedGeoRenderer`, Mini-Hook in `GlitchedMonster`)

Über die letzten 10t von `deathAnimTicks()` (Husk/Hound 30t, Tick 20t) fadet der
Körper linear von Alpha 1.0 auf 0.05: `getRenderColor`-Override liefert Weiß mit
Fade-Alpha, `getRenderType`-Override schaltet währenddessen auf `entityTranslucent`
(Cutout ignoriert Vertex-Alpha). Beim Öffnen des Fades feuert einmalig
`wave4_dissolve_motes` positions-verankert am Korpus-Zentrum (Entity-Attach würde
mit dem Removal sterben — die Motes SIND der Rest des Körpers und überleben den Poof
um 6–16t). Dedup über ein `HurtSparks`-Muster-Set (fired-once pro EntityId,
Wholesale-Valve; ein theoretischer Re-Fire landet in Photons Same-Anchor-Dedup).
Mini-Hook: `GlitchedMonster.deathDissolveWindow()` — public-final Sicht auf das
protected `deathAnimTicks()` (4 Zeilen + Doc; die Kind-Klassen bleiben unberührt).
Der serverseitige POOF-Broadcast bleibt byte-identisch (außerhalb des A2-Scopes);
er landet auf einem 5%-Alpha-Geist und liest sich als Residuum unter den Motes.

## 3. Gate-Ergebnisse

| Gate | Ergebnis |
|---|---|
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** (2 warnings: deprecated `bus = Bus.MOD` — Codebase-Konvention, 70 Bestandsdateien nutzen exakt dieselbe Annotation, u. a. `Wave3FxRows`) |
| `python3 tools/photon/fxlib.py validate --lint` (alle 288 Dateien) | **0 NEW error/warn**, 27 grandfathered / 149 advisory — Baseline unverändert |
| `python3 tools/photon/fxlib.py validate --lint src/main/resources/assets/eclipse/fx/wave4_*.fx` | **0 NEW, 0 grandfathered, 0 advisory** (die vier neuen Assets sind komplett sauber) |
| Generator-Doppellauf | **byte-identisch** (`sha256sum` aller 8 Dateien vor/nach identisch; z. B. `wave4_crit_gleam.fx` = `b21d570b…f4124`) |
| `flock /tmp/gradle.lock ./gradlew processResources --offline` | **BUILD SUCCESSFUL** — alle 8 `wave4_*`-Dateien in `build/resources/main/assets/eclipse/fx/` |

Keine Lang-Keys nötig (kein user-sichtbarer Text) → kein `WAVE4A.json`-Langdrop.

## 4. Q2 — GESTRICHEN (Begründung mit Beweis)

Die Accessors existieren und sind public (`rg -n "hygieneDirtyScrubs|hygieneLinksRemoved"
src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonBridge.java` → Zeilen 830/835,
beide `public static long`). ABER: `PhotonBridge` ist als Klasse `@OnlyIn(Dist.CLIENT)`
(Zeile 85) — jede Referenz aus `devtools/dev/DevPhotonCommands.java` (Server-Kontext:
die Command-Handler laufen auf dem Server und schicken nur eine Action-Payload an den
Client) wäre auf einem Dedicated Server ein `NoClassDefFoundError`-Risiko. Der Ort, an
dem `/dev photon status` tatsächlich RENDERT, ist `cutscene/dev/FxDevClient.photonStatus()`
(Zeile 163) — `cutscene/dev/` ist Team-C-Verbotszone. Die Auflage „NUR
DevPhotonCommands.java, PhotonBridge byte-unangetastet" lässt damit keinen legalen,
crash-sicheren Implementierungspfad: Q2 gestrichen. (Empfehlung fürs Backlog: eine
Zeile in `FxDevClient.photonStatus()` — dort ist der Zugriff Dist-sicher und trivial,
sobald die Datei wieder freigegeben ist.)

## 5. RCON-Abnahme-Drehbuch (Hauptagent, llvmpipe-Client)

Vorbedingungen: Server + Client laufen bereits. RCON: `python3 tools/rcon/rcon.py "<cmd>"`.
Nach diesem Commit ist ein **Client-Neustart Pflicht** (neuer Client-Bytecode: Rows,
Renderer, Fade — die Pre-Fix-Bytecode-Falle aus dem F-103-Learning) und einmalig
`/photon_client clear_client_fx_cache` im CLIENT-Chat (FXHelper-CACHE überlebt F3+T;
bestätigen via `clear client cache fx: 4+` in `run/logs/latest.log`). Ein Dev-Spieler
(`Dev`) muss eingeloggt sein; `dev photon test` braucht `execute as … at …`.

**Schritt 0 — Setup (alle Checks):**
```
python3 tools/rcon/rcon.py "gamemode creative Dev" "tick rate 2"
```
`tick rate 2` streckt tick-gebundene Timelines ×10 (7-Tick-Effekte sind auf llvmpipe
sonst unfangbar): das 40t-Stagger-Fenster wird ~20 s, der 10t-Fade ~5 s Echtzeit.
**Nach der Abnahme zurücksetzen: `tick rate 20`.**

**Check 1 — A7-Assets isoliert (Photon-Testspawns, je ~5 s schauen):**
```
python3 tools/rcon/rcon.py 'execute as Dev at Dev run dev photon test "eclipse:wave4_crit_gleam" ~ ~1 ~2'
python3 tools/rcon/rcon.py 'execute as Dev at Dev run dev photon test "eclipse:wave4_heavy_impact" ~ ~1 ~2'
python3 tools/rcon/rcon.py 'execute as Dev at Dev run dev photon test "eclipse:wave4_stagger_arc" ~ ~1 ~2'
python3 tools/rcon/rcon.py 'execute as Dev at Dev run dev photon test "eclipse:wave4_dissolve_motes" ~ ~1 ~2'
```
Erwartung: crash-frei; (1) goldener Glint-Fächer + Pale-Flash ~0.7 s, (2) Amber-Streak-
Blume + Flash + flacher Ring ~1.5 s, (3) Cyan-Geknister + Orbit-Halo ~2 s (bei tick rate
2: ~20 s), (4) Cyan/Magenta-Motes steigen + dunkler Veil schrumpft ~1.5 s. Log-Gegenprobe:
`rg -c "wave4_" run/logs/latest.log` (dev-photon-test-Echos), 0 `Duplicate`/`ERROR`-Zeilen.

**Check 2 — A3/A4 (Crit + Magnitude an einem GeoMonster):**
```
python3 tools/rcon/rcon.py "summon eclipse:storm_hound ~2 ~ ~2 {NoAI:1b,PersistenceRequired:1b}" "effect give Dev minecraft:strength 60 4"
```
Dev: anspringen + im Fall schlagen (Vanilla-Crit) → Erwartung: Vanilla-Crit-Sterne +
`impact_light`-Miniflash + goldener `wave4_crit_gleam` an der Hound-Brust. Mit Stärke V
liegt der Melee-Schaden ≥ 8 → zusätzlich dichter CRIT-Burst + `wave4_heavy_impact`.
Ohne Strength (Faust, ~1 dmg) → NICHTS von A4 (unter dem ≥4-Bucket). Server-Log-Probe:
keine neuen WARN; der Hound stirbt ggf. → das ist bereits Check 4.

**Check 3 — A6 Stagger-Tell (Hound verfehlt die Lunge):**
```
python3 tools/rcon/rcon.py "kill @e[type=eclipse:storm_hound]" "summon eclipse:storm_hound ~8 ~ ~ {PersistenceRequired:1b}"
```
Dev (Survival/ohne NoAI-Flag am Hound): auf 6–14 Blöcke Abstand bleiben, das 20t-Windup
(Crouch + Glow-Ramp + Sonic-Charge-Sound) abwarten, während des Dashes SEITWÄRTS
strafen. Erwartung bei Miss: Hound friert 40t (bei tick rate 2: ~20 s) ein, dabei
`rift_spark`-Dauerknistern AM Hound + einmalig der `wave4_stagger_arc`-Cyan-Halo um den
Kopf; beides endet exakt mit dem Fenster (kein Nachleuchten — Falling-Edge-Detach).
Log-Probe: `rg -c "lunge missed — staggered" run/logs/latest.log` ≥ 1.

**Check 4 — A2 Dissolve (Glitched-Korpus):**
```
python3 tools/rcon/rcon.py "summon eclipse:glitched_husk ~3 ~ ~3 {NoAI:1b}" "damage @e[type=eclipse:glitched_husk,limit=1] 64"
```
Erwartung: Death-Anim hält (30t; Tick-Variante 20t), über die LETZTEN 10t (bei tick
rate 2: ~5 s) wird der Körper sichtbar durchscheinend bis ~5% Alpha, dabei steigen
Cyan/Magenta-Pixel-Motes aus dem Korpus (überleben den Poof); der POOF landet auf dem
fast unsichtbaren Geist. Gegenprobe `eclipse:glitched_tick` (20t-Fenster, Fade öffnet
bei deathTime 10).

**Check 5 — A1 Tyrant-Flicker (Phase 3):**
```
python3 tools/rcon/rcon.py "summon eclipse:fog_tyrant ~10 ~ ~" 
python3 tools/rcon/rcon.py "damage @e[type=eclipse:fog_tyrant,limit=1] 190"
```
(HP so drücken, dass < 25% übrig — `/dev` Boss-HP-Kommandos gehen auch; Phase-3-Log
abwarten: `rg -n "phase 2 -> 3" run/logs/latest.log`.) Erwartung: Glowmask (Krone +
Auge + Brust-Core) stottert unregelmäßig 1–2t-Aussetzer, ~1–2×/s (bei tick rate 2
deutlich gedehnt und auf llvmpipe gut fangbar); in Phase 1/2 und im Death-Collapse
KEIN Flicker. `reducedFx`-Gegenprobe (Client-Config): Flicker steht still, Glow stetig.

**Check 6 — A5 Whiff (Log-Sonde, GUI-frei abnehmbar):**
Tyrant aus Check 5 weiterverwenden (Phase egal): Dev stellt sich ~10 Blöcke vor ihn,
wartet die Lance-Volley-Telegraphierung (Electric-Spark-Trails) ab und strafed 2–3
Blöcke seitwärts (im Near-Miss-Korridor bleiben!). Beim Squall (Phase ≥ 2, Warden-
Sonic-Charge-Sound): hinter einen Block brechen. Beim Colossus
(`summon eclipse:fog_colossus`): nah ran, beim Slam-Impact (27t nach dem Roar) springen.
Erwartung pro Dodge: leiser Breeze-Whoosh + kleine Gust-Partikel NUR beim Dev-Client,
und pro Send exakt eine DEBUG-Zeile. Abnahme-Kommando:
```
rg -c "\[w4a-whiff\]" run/logs/debug.log        # >= 1 pro gelungenem Dodge
rg -n "\[w4a-whiff\]" run/logs/debug.log | tail -5   # ability-Feld: lance_volley / blind_squall / ground_slam
```

**Aufräumen:** `tick rate 20`, gespawnte Mobs killen
(`kill @e[type=eclipse:storm_hound] @e[type=eclipse:glitched_husk] …`).

## 6. Geänderte/neue Dateien (dieser Commit)

Neu: `tools/photon/wave4_combat_fx.py`, `veilfx/Wave4CombatFxRows.java`,
`drama/CombatFeedbackFx.java`, 8× `assets/eclipse/fx/wave4_*.{fx,fxproj}`, dieser
Report. Geändert (chirurgisch): `FogTyrantRenderer.java` (A1),
`GlitchedGeoRenderer.java` + `GlitchedMonster.java` (A2, 4-Zeilen-Hook),
`FogTyrantEntity.java` + `GroundSlamGoal.java` (A5),
`ChargedLungeGoal.java` + `StormHoundEntity.java` + `StormHoundRenderer.java` (A6).
Verbotszonen unberührt (insb. `PhotonBridge.java`, `PhotonFxRegistry.java`,
`FxCues.java`, `cutscene/dev/`, Lang-JSONs, fertige Feel-Klassen).
