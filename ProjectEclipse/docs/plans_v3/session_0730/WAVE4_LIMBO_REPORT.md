# WAVE4 — Team C „Limbo: Die bewohnte Geistersee" (F-104)

Polish-Welle 4, Branch `cursor/project-eclipse`. Scope: IDEA-18-Restposten C1–C7 (reine
Client-Ambience — kein Server-Blockstate, keine Fight-Contracts, keine neuen Post-Uniforms,
`limbo.fsh` unangetastet). Alle Gates grün (Belege unten); die visuelle Live-Abnahme macht
der Hauptagent nach dem RCON-Drehbuch in §4.

## 1. Erst-Verifikation (Ideensammlung TEILKONSUMIERT — Befund vor jeder Codezeile)

| Item | IDEA-18 | Befund | Beweis (vor Implementierung) |
|---|---|---|---|
| Idee 1 (Reflexion) | §1 | FERTIG (implementiert, dann via LIMBOFIX absichtlich ENTFERNT — nicht anfassen) | `rg -n "water-reflection streak is GONE" client/sky/LimboSpecialEffects.java` → Klassendoc-LIMBOFIX-Absatz |
| Idee 2 (Horizon-Ships) | §2 | FERTIG | `client/sky/LimboHorizonShips.java` existiert (inkl. v4-Passing-Lantern) |
| Idee 3 (Fogbanks) | §3 | FERTIG | `quasar/emitters/limbo_fogbank.json` + `FOGBANKS`-Window in `LimboAmbience` |
| C1 Ruder-Dirge + Creaks | §4/§10 | OFFEN | `rg -l "LimboRowChant\|RowChant" src/` → 0 Treffer |
| C2 Ghost-Wake | §5 | OFFEN | `rg -n "GLOW\|SOUL" client/entity/DeckhandRenderer.java` → 0 Treffer (nur `SPLASH`) |
| C3 Laternen-Motten | §6 | OFFEN | kein `limbo_moths.json` unter `quasar/emitters/`; `rg -n "MOTH" veilfx/LimboAmbience.java` → 0 |
| C4 Ertrunkene Glocken | §7 | OFFEN | `rg -n "FERRYMAN_BELL\|bell" veilfx/LimboAmbience.java` → 0 |
| C5 Spire-Ember-Säulen | §8 | OFFEN | kein `limbo_embers.json`; kein Spire-Handler in `LimboAmbience` |
| C6 Grüne Sternschnuppen | §9 | OFFEN | `rg -in "streak\|shooting" client/sky/` → nur die LIMBOFIX-Doku über den ENTFERNTEN Reflexions-Streak, kein Schedule |
| C7 streakhold | — | OFFEN | `rg -rn "streakhold" src/` → 0 Treffer |

Nichts gestrichen: alle 7 Scope-Items waren offen und sind umgesetzt.

## 2. Umsetzung je Item

**C1 — Ruder-Dirge + Rigging-Creaks** (`veilfx/LimboRowChant.java`, NEU; getickt aus
`LimboAmbience.onClientTick` im `inLimbo && !isPaused`-Zweig). Dirge: auf jeder
60-t-Row-Clock-Grenze (`gameTime % 60 == 0`, der Catch-Beat) EIN positionierter
`note_block.didgeridoo`-Ton am nächsten sitzenden Rower; Pitch aus fester
Moll-Pentatonik-Tabelle indexiert mit `(gameTime/60) % 8`, jeder 4. Zyklus pausiert
(deterministisch, kein Audio-Asset). Creaks: auf dem Recovery-Beat (Phase 30) ein leiser
Holz-Groan/Ketten-Clink (`BAMBOO_WOOD_HANGING_SIGN_STEP`/`CHAIN_STEP`, hash-alternierend)
an einem hash-gepickten Dollbord-Punkt (Bench-Spalten × `GhostShipBuilder.halfWidthAt`,
Deck-Y vom `ship_deck`-Anker), nur ≤28 Blöcke vom Anker. Guards: kippt IRGENDEIN
gescannter Deckhand ins Tilt (`isTilt()`, der synced Client-Spiegel von
`OarAnimator.isTiltActive`) oder ist hostile → beide Lanes komplett stumm. DEBUG-Sonden
`Limbo row chant note …` / `Limbo rigging creak …` pro Fire.

**C2 — Ghost-Wake** (`client/entity/DeckhandRenderer.spawnGhostWake`, am bestehenden
`spawnCatchSplash`-Seam). Pro Oar-Catch 4–6 leuchtende Flecken an der Wasseroberfläche,
sternwärts (Welt −X, Bug ist +X) über ~1,5 Blöcke verteilt. Dekompilat-verifiziert:
`SOUL` respektiert die übergebene Velocity (`RisingParticle: xd = xd·0.01 + xSpeed`) und
zieht sichtbar achteraus; `GLOW` (GlowSquidProvider) IGNORIERT x/z-Speeds ≠ 0 und würde
wild streuen — deshalb genau EIN stationärer GLOW-Glint (Velocity 0) pro Catch plus
SOUL-Driftlinie. Erbt die Callsite-Guards (Tilt löscht die Sync-Marke, hostile rudert
nicht); `reducedFx` halbiert auf 2 Flecken ohne Glint.

**C3 — Laternen-Motten** (`quasar/emitters/limbo_moths.json` NEU + `MOTHS`-Window in
`LimboAmbience`). Emitter: winzige additive Billboards (`purple_wisp.png` wiederverwendet,
base_size 0.15, Lifetime 40±20), `veil:vortex` (Range 2, Strength 0.05) für den
Orbit-Read, blasse Soul-Grün-Gradiente. Window (3 live, 60–90 t Intervall) mit neuem
`biasToSoulLights`-Flag: Spawns landen 0,5 Blöcke neben einer gecachten
Soul-Lantern-/lit-Soul-Campfire-Position; der Block-Scan (16er-Würfel um die Kamera,
`BlockPos.betweenClosed`, Cap 12) läuft NUR beim Spawn-Fire und wird ≥100 t bzw. bis
8 Blöcke Kamerabewegung gecacht — kein Scan pro Tick. Fallback über offenem Wasser:
Kamera-Ring (die Buoy-Laternen säumen die Lane ohnehin).

**C4 — Ertrunkene Glocken** (im `LimboRowChant`-Ticker). Countdown
`nextIntBetweenInclusive(2400, 4800)`; beim Fire ein gedämpfter
`EclipseSounds.BOSS_FERRYMAN_BELL` (Vol 0.35, Pitch 0.55) bei y = Waterline−12
(`LimboSpecialEffects.clientWaterlineY`-Seam), 40–80 Blöcke seitlich. Guard: kein Toll,
solange ein `FerrymanEntity` im 160-Block-Umkreis ist (Client-Proxy für „Fight hörbar",
Scan NUR in Toll-Kadenz) — die echte Fight-Glocke bleibt eindeutig; der Guard re-armt
ein frisches Voll-Intervall. DEBUG-Sonden `Limbo bell toll @…` bzw.
`Limbo bell toll suppressed (Ferryman in range)`.

**C5 — Spire-Ember-Säulen** (`quasar/emitters/limbo_embers.json` NEU +
`SpireEmbers`-Handler in `LimboAmbience`). Emitter: additive Zylinder-Säule,
Cyan-Grün-Gradiente `#4FD8A0 → #1E5A46`, `initial_direction [0,1,0]`, Speed 0.02,
Lifetime 80±30, Steig-Wind 0.025. Handler: die 3 frozen `LimboSeascape.build`-Spires
(205/40 h13, −95/−215 h16, −230/−35 h10, per `rg -n "spire(" limbo/LimboSeascape.java`
verifiziert) als Konstanten; ≤1 Live-Emitter pro Spire, gespawnt nur <160 Blöcke
Kameradistanz (Distanz-Check alle 20 t), Detach beim Entfernen/Dimension-Wechsel über
den `clearWindows()`-Seam. Crest-Y = Client-Waterline + Höhe + 1,5 (Soul-Fire brennt auf
top+1) — kein Server-Traffic. Garnish-Tier: `reducedFx` skippt UND cleart.

**C6 — Grüne Sternschnuppen** (`client/sky/LimboSpecialEffects`). Deterministischer
Slot-Schedule auf der stündlichen Sekunden-Uhr (`LimboHorizonShips.hash01`, eigene Salts
`slot*37+3..7 / 1553`): jeder 47-s-Slot hostet zu ~50 % einen Streak (Ø ~1,6 min), 0,9 s
Lebensdauer, ~35° Bogen (Azimut-Sweep + Elevations-Fall), Alpha 0→0,5→0. Gezeichnet im
No-Fog-Fenster der Sterne AUSSERHALB des Zenit-Rotations-Push (streakt den Dom, nicht den
Disc-Frame), additiv, ein einziges getapertes POSITION_COLOR-Quad (Kopf hell
grün-weiß, Schweif transparent Stern-Grün) — rein geometrisch, NULL neue Post-Uniforms
(§3.3, `limbo.fsh` frozen), reine Skalar-Mathematik ohne Per-Frame-Allokation (§3.5,
Tesselator-Builder wie alle Nachbar-Draws). Garnish: `reducedFx` skippt den Live-Schedule.

**C7 — `/eclipsefx limbo streakhold on|off`** (flashhold-Präzedenz 1:1:
`FxDevCommands`-Leaf → `FxDevPayloads.ACTION_LIMBO_STREAKHOLD = 11` →
`FxDevClient.limboStreakHold` → `LimboSpecialEffects.setStreakHold`). ON hält EINEN
Streak an festem Dom-Punkt (Azimut ~17° steuerbord der Bug-Richtung +X, Elevation ~55°)
mit auf t=0,55 eingefrorener Hüllkurve — bit-identische Geometrie pro Frame, weil die
Sky-Uhr SEKUNDENbasiert ist und `tick rate 2` sie nicht streckt (deshalb ist der Hold
für llvmpipe-Screenshots zwingend). OFF ⇒ restlos weg (der Hold-Branch ist der einzige
Konsument des Flags; Live-Schedule bit-identisch). Logout cleart (FxDevClient-Hygiene).
Der Hold zeichnet als expliziter Operator-Override auch unter `reducedFx` (wie ein
forciertes `post … on`). Doc-Key via Langdrop `docs/plans_v3/langdrop/WAVE4C.json`
(en/de-Parität, Lang-JSONs NICHT direkt angefasst).

## 3. Gate-Belege

1. **Compile**: `cd /workspace/ProjectEclipse && flock /tmp/gradle.lock ./gradlew
   compileJava --offline --console=plain` → **BUILD SUCCESSFUL** (2 actionable tasks;
   einzige Warnings: die vorbestehenden `EventBusSubscriber.bus()`-Deprecations in
   `FxDevPayloads` Zeile 29, unverändert). `LimboRowChant.class` + frische
   `LimboSpecialEffects.class` im Build-Output verifiziert.
2. **Assets**: beide Emitter-JSONs `python3 -c "json.load(...)"`-valide, Feldnamen 1:1
   von `limbo_fogbank.json`/`limbo_motes.json`/`crater_updraft.json` (inkl.
   `veil:vortex`/`veil:drag`/`veil:wind`/`veil:color`-Modulschemata);
   `flock /tmp/gradle.lock ./gradlew processResources --offline` → **BUILD SUCCESSFUL**,
   `limbo_moths.json`/`limbo_embers.json` liegen in `build/resources/main/...`.
3. **Window-Vertrag**: Motten erben Cadence-Doppelung via `Window.tick`; Embers + Streaks
   Garnish (skip UND clear); Chant/Creak nur gerade Zyklen, Bell-Intervall ×2, Wake 2
   Flecken. Detach: `SpireEmbers.clear()` + Soul-Light-Cache + `LimboRowChant.reset()`
   hängen am bestehenden `clearWindows()`-Seam (läuft bei `!inLimbo` und bei
   `LoggingOut`) — kein Emitter/Zustand überlebt den Dimension-Wechsel.
4. **Hygiene**: kein `FX.createInternalRuntime()`, kein fremdes Reformat (Diff-Kontrolle:
   entfernte Zeilen sind ausschließlich die Window-Ctor-Signatur/Aufrufer, der
   verschobene `seconds`-Capture und der ersetzte Splash-Javadoc-Einzeiler).

## 4. RCON-Abnahme-Drehbuch (Hauptagent)

**Schritt 0 — frische Client-JVM (Pflicht!)**: neue Klassen + Emitter-JSONs erreichen
den laufenden Client nicht (F-103-Learning: Pre-Fix-Bytecode-Falle). Client-Prozess per
PID beenden, `runClient` neu starten. Server kann weiterlaufen (alle Änderungen sind
client-only; `FxDevPayloads` ist ein `.optional()`-Registrar, aber gleiche Jar-Basis
Server/Client im Dev-Setup ohnehin). RCON-Präfix unten: `python3 tools/rcon/rcon.py "…"`.

**Nach Limbo kommen**: `eclipse tp_limbo Dev` → landet auf der Spawn-Plattform des
Geisterschiffs (Schiffszentrum x/z ≈ 0/0, Deck = Waterline+3; Waterline laut Bootlog-Zeile
`Limbo seascape built at waterline y=…`, shipped Datapack y=48). ACHTUNG (AGENTS.md): auf
Saves mit gelaufenem start_event bounct `execute in eclipse:limbo run tp` am
Containment-Watchdog — `tp_limbo` ist der Dev-Weg; für die Tilt-Gegenprobe frische Welt
verwenden. Freies Kamera-Placement: `n Dev <x y z yaw pitch>` (Trailer-Präzedenz).

**Screenshot A — Motten an Laterne (nah)**: an eine Soul-Laterne stellen — am
einfachsten Buoy #1 der Laternen-Lane (`tp Dev 32 <waterline+2> 0`, Laterne hängt auf
Waterline+1) oder neben eine der Deck-Fight-Laternen. 20–30 s warten (Window-Intervall
3–4,5 s, max 3 live), Screenshot: blasse grünliche Wisps, die eng um die Laterne
kreisen (Vortex-Orbit).

**Screenshot B — Ember-Säule (fern)**: `n Dev 120 60 20 60 10` (Blick Richtung
Spire (205, 40); Kameradistanz ~87 < 160 → Emitter aktiv; `eclipsefx viewdist 12` falls
nötig). 15 s warten, Screenshot: cyan-grüne Funken-Säule, die über der
Blackstone-Spire aus dem Soul-Fire steigt.

**Screenshot C — Ghost-Wake unter `tick rate 2`**: zurück aufs Deck, an die Reling
neben einen Rower. `tick rate 2` → der 60-t-Zyklus dauert 30 s Echtzeit; auf den Catch
warten (Splash), Screenshot der Soul-Flecken-Linie, die achteraus (−X) vom Blatt
wegzieht + der einzelne Glow-Glint am Einstichpunkt. Danach `tick rate 20`.

**streakhold-Sequenz**: `execute as Dev run eclipsefx limbo streakhold on` (Command
braucht einen Spieler-Executor, `/dev photon test`-Präzedenz) → Chat-Feedback nennt die
Blickrichtung: ~17° steuerbord der Bug-Richtung (+X), ~55° hoch. Screenshot: statischer
grüner Streak (heller Kopf, ausgefadeter Schweif), beliebig lange fotografierbar. Dann
`execute as Dev run eclipsefx limbo streakhold off` + Screenshot derselben Blickrichtung:
Streak restlos weg. (Live-Schedule Ø ~1,6 min ist auf llvmpipe nicht abwartbar — genau
dafür existiert der Hold; die Sky-Uhr ist sekundenbasiert, `tick rate 2` streckt sie
nicht.)

**Chant/Bell-Sonden (Log-Abnahme, `run/logs/debug.log`)** — bei `tick rate 20`, auf dem
Deck (Crew in 24 Blöcken), ≥5 min sammeln:
- `rg -c "Limbo row chant note" run/logs/debug.log` → ~15/min (Zyklus 3 s, jeder 4.
  pausiert). Pitch-Folge deterministisch wiederholend: 0.5, 0.53, 0.5, (Pause), 0.5,
  0.445, 0.5, (Pause).
- `rg -c "Limbo rigging creak" run/logs/debug.log` → ~20/min (jeder Zyklus, Phase 30),
  alternierend `chain`/`wood`, nur ≤28 Blöcke vom Schiff.
- `rg "Limbo bell toll" run/logs/debug.log` → 1 Toll pro 2–4 min, Koordinaten 40–80
  Blöcke seitlich, y ≈ Waterline−12 (bei y=48 also y≈36).

**Guard-Gegenproben (⇒ 0 Fires)**:
- Hostile Crew: `eclipse boss ferryman summon` → `eclipse boss ferryman phase 2`
  (Crew-Rise) → 60–90 s warten → debug.log-Zeitfenster: 0 chant-/creak-Sonden (der
  `scanCrew`-Guard kurzschließt bei JEDEM hostilen Rower); läuft der Bell-Countdown im
  Fenster ab, erscheint stattdessen `Limbo bell toll suppressed (Ferryman in range)`.
  Danach `eclipse boss ferryman kill` → Sonden kehren zurück.
- Tilt: auf einer FRISCHEN Welt `eclipse start_event` — im TILT-Fenster (t=0 bis
  Submerge) 0 chant-/creak-Sonden (derselbe scanCrew-Kurzschluss über `isTilt()`; das
  Intro-Replay `/eclipsefx sequence intro …` hat KEINE Tilt-Phase, die beginnt erst bei
  ECLIPSE_ON — daher echtes start_event nötig; die hostile-Probe deckt denselben
  Code-Pfad billiger ab).

**reducedFx-Gegenprobe**: `run/config/eclipse-client.toml` → `reducedFx = true`
(NeoForge lädt Client-Configs bei Dateiänderung nach; alternativ Settings-Panel). Erwartung:
Chant/Creak-Kadenz halbiert (nur gerade Zyklen ⇒ ~7–8 bzw. ~10/min), Bell-Intervall 4–8 min,
Wake 2 Flecken ohne Glow-Glint, Motten-Intervall verdoppelt, Ember-Säulen und
Live-Streaks verschwinden komplett (Garnish-Clear; nur der explizite streakhold-Override
zeichnet weiter). Danach zurück auf `false`.

**Leak-Probe (Dimension-Wechsel)**: 60 s in Limbo stehen (Motten/Embers/Fog live) →
`execute in minecraft:overworld run tp Dev 0 200 0` → alle Limbo-Emitter/Sounds stoppen
(clearWindows-Seam inkl. `SpireEmbers.clear` + `LimboRowChant.reset`); 30 s warten:
debug.log zeigt KEINE chant/bell-Sonden mehr → `eclipse tp_limbo Dev` → normale Dichte,
keine Verdopplung (Windows starten leer, Bell-Countdown frisch). Hinweis: Sky-Streaks und
der Hold rendern nur ohne aktives Shaderpack (Iris-Guard des Sky-Passes, Bestand).

## 5. Nicht angefasst (Verbotszonen respektiert)

Team-A-/Team-B-Dateien, `limbo/GhostShipBuilder`/`LimboSeascape` (nur GELESEN für
Konstanten; `halfWidthAt`/`HALF_WIDTH` sind public API), `LimboHorizonShips.java` (nur
`hash01`-Konsum, wie `drawCoronalWisp` es bereits tut), `limbo.fsh`-Uniforms,
`StartEventCutscene`, Ferryman-Fight-Contracts, `PhotonBridge`/`PhotonFxRegistry`/
`FxCues`/`stormfx/*`/`ritual/*`, Lang-JSONs (Langdrop stattdessen), `UserFeedback.md`.
`sounds.json`/`EclipseSounds.java` blieben unverändert — alle Sounds sind Bestand
(Noteblock/Step-Sounds + registrierte `boss.ferryman_bell`), keine Audio-Generierung.
