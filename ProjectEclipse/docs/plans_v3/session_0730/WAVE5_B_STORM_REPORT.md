# WAVE5_B_STORM_REPORT — Team B „Der Sturm antwortet" (F-105)

> Hinweis Dateiname: das Team-Prompt nannte `WAVE5_TEAMB_REPORT.md`, der verbindliche
> Plan (§4, Datei-Ownership) nennt `WAVE5_B_STORM_REPORT.md` — bei Widerspruch gilt der
> Plan, daher dieser Name (konsistent mit `WAVE5_A_DEVHOLDS_BOSS_REPORT.md` /
> `WAVE5_C_ALTAR_RITUAL_REPORT.md`).

## 1. Was gebaut wurde (B1–B6)

| # | Deliverable | Dateien (Team-B-Ownership) |
|---|-------------|----------------------------|
| B1 | First-Breach-„Gulp": Edge-Detect auf `smoothedInterior` mit 0.5/0.3-Hysterese, `glitchPulseSafe(0.15, 10t)`, `EVENT_STORM_BURST` 1.2/0.5, Fog-Near-Pinch 6→2 über 10 t (Sinus-Envelope), Exhale 0.3/1.35 beim Verlassen | `stormfx/StormInteriorFx.java`, `stormfx/StormFxClient.java` (nur Sichtbarkeit `glitchPulseSafe` private→package-private) |
| B2 | Sturmtod-Schlucken: `LivingDeathEvent` (Spieler IM Registry-Sturm) → Corpse-Inhale (2 schrumpfende CLOUD-Ringe 6→2 über 10 t, gegenläufig rotierend, Inward-Drift), gedämpfter `EVENT_STORM_BURST` 0.6/0.7 am Corpse, gedämpfter Schrei (`PLAYER_HURT` 0.9/0.55) am projizierten Schalenpunkt für Außenstehende ≤96 Blöcke von der Schale, `EVENT_LIGHTNING_FAR` 0.7/0.85 dort 8 t später, 15 t-Regen-Surge ×1.6 innen via neues `FX_STORM_SURGE` | NEU `stormfx/StormDeathFx.java`; `network/fx/FxPayloads.java` (additive Id + Version-Bump `fx1`→`fx2` + Handler-Case); `veilfx/EclipseFxState.java` (Surge-Feld + 5 t-Release-Decay); `stormfx/StormInteriorFx.java` (Surge-Feed in den `RainAmount`-Pfad) |
| B3 | Tageslicht-Wand-Rim: `dayBoost = 1 − skyDarken/15` (vorhandene `daylight`-Variable) weitet das Churn-Band (Floor 0.45 → 0.30 bei vollem Tag) in Zylinder- UND Sphere-Schalen; äußere Additiv-Sphere-Schale (`s == 0`, non-endo) bekommt im oberen Dom-Drittel (`latFrac > 0.66`, smoothstep-Kante) `alpha × (1 + 0.5·dayBoost)`. KEINE neue Geometrie, kein Depth-Write | `stormfx/StormWallRenderer.java` |
| B4 | Glowmask-Atmung: neuer GeckoLib-Layer skaliert den Emissive-Alpha mit `0.6 + 0.8·interiorAmount()` — Basis-Pass mit `min(1, breath)`, Überschuss (>1.0) als zweiter additiver Emissive-Pass (Overdrive), gegated auf `!reducedFx` und `deathTime <= 0` | NEU `client/entity/fog/FogGlowBreathLayer.java`; `StormHoundRenderer`/`FogColossusRenderer`/`FogRevenantRenderer` (je 1 Zeile: `withGlowmask()` → `addRenderLayer(new FogGlowBreathLayer<>(this))`; W4-Stagger-Tell im Hound unangetastet) |
| B5 | Lair-Dread: (a) Server — `FogBankMarker.stampBankPillars` gewichtet die Pillar-Ring-Rauchdichte zum nächsten Beobachter (`×(1 + 0.35·cos(bearing−angle))`, probabilistisches Runden); (b) Client, protokollfrei — 16 t-Doppel-Thump (Haupt 0.30/0.70 + Echo 0.26/0.62 nach 6 t) im 30-Block-Kern bei `interiorAmount() > 0.6` | `entity/boss/fog/FogBankMarker.java` (Carve-out), `stormfx/StormFxClient.java` |
| B6 | Chest-Open-Reaktion: `PlayerContainerEvent.Open` auf Lair-Chests (Chest-Index aus `EclipseWorldgenState.fogSiteState().chests()`) → 2er-Arc-Volley (`FX_LIGHTNING_STRIKE` ×2, ±0.12 rad Spread) ankert am WALL-Punkt (Bearing-Projektion Chest→Schale, Sphere-Reach `√(r²−yOff²)`), `EVENT_LIGHTNING_FAR` 0.8/0.8, 30 % Revenant-Spawn 12–16 Blöcke via public Hook; one-shot Latch pro Chest pro Session | NEU `worldgen/fog/FogChestSting.java`; `entity/spawn/EventSpawnRules.java` (NEU public `trySpawnChestRevenant`, Caps + `SpawnGates.FOG_STORM` respektiert) |

Langdrop: `docs/plans_v3/langdrop/WAVE5B.json` — bewusst LEER (en+de leere Objekte +
`_comment`): alle sechs Deliverables sind FX/Audio/Log-only, kein Player-facing Text.
Keine neuen `.fx`-Assets → fxlib-Gates nicht anwendbar; keine GLSL-Änderung (B2 nutzt
das bestehende `RainAmount`-Uniform, B3 ist reine Vertex-Farb-Arithmetik in Java).

## 2. Design-Entscheidungen

- **B1 — Teleports zählen nicht als Crossing**: der EVAL-4-M5-Snap (Kamera-Sprung
  > 32 Blöcke/Tick) re-seatet den Breach-Latch STUMM (`breachLatched = interior ≥ 0.5`
  ohne Sonde/FX). Ein `/tp` mitten in den Sturm ist kein „Eintauchen durch die Wand".
  Hysterese 0.5 enter / 0.3 exit — Schweben auf der Schwelle feuert nie doppelt.
- **B1 — `glitchPulseSafe` package-private statt public**: `StormInteriorFx` liegt im
  selben Package; kein neuer öffentlicher API-Punkt für einen Ein-Aufrufer-Fall.
- **B2 — `RainAmount`-Clamp-Vertrag gewahrt**: `storm_interior.fsh` clampt `RainAmount`
  auf [0,1]. Der Surge läuft deshalb als Multiplikator VOR dem Clamp durch
  `EclipseFxState.stormRainSurge()`: Nicht-Sphere-Interiors multiplizieren ihren
  Bestands-Regen ×1.6, Sphere-Interiors (ambienter Regen normal 0) bekommen den
  Surge-ÜBERSCHUSS (`interior·(mul−1)`) als Feed — sichtbarer Regenstoß ohne
  Shader-Änderung. 5 t-Release-Tail statt hartem Abriss.
- **B2 — positionale Sounds als direkte `ClientboundSoundPacket`s**: Schrei + Rumble
  gehen NUR an die betroffenen Außensteher (kein `level.playSound`-Broadcast — ein
  96-Block-Radius um die Schale wäre sonst dimension-weit hörbar). Der 8 t-Delay des
  Rumbles läuft über eine server-tick-getriebene Pending-Liste (Muster `StormReveal`),
  UUID-Lookup beim Feuern (Disconnect-sicher). Alles cleart in `ServerStoppedEvent`.
- **B2 — Sturm-Auswahl**: tiefster umschließender Registry-Sturm (max. Depth
  `1 − dist/radius`), nur `STATE_SPAWN`/`STATE_ACTIVE` — Sterben unter einem
  dissipierenden/explodierenden Sturm schluckt nicht.
- **B3 — Rim nur auf der Sphere-Außenschale**: der Alpha-Boost sitzt exklusiv auf
  `additive && !endo && s == 0` im oberen Drittel (`latFrac > 0.66`, smoothstep über
  ±0.08/0.10). Zylinder-Wände bekommen NUR das Churn-Widening: ihr Alpha ist ein
  linearer Höhen-Gradient, ein Top-Boost würde die F-101-`flashhold`-Fotoreferenzen
  verfälschen; Sphere-Domes sind die C8-Site-Stürme — dort zählt die Tages-Silhouette.
  KEINE neue Geometrie/Depth-Writes → Occluder-Falle (Plan §4) umgangen.
- **B3 — EVAL-4-M4 (Occluder-Hysterese)**: bereits obsolet — `OCCLUDER_SEGMENTS` ist
  im Bestand fix 48 (kein LOD-Stepping mehr), keine Hysterese nötig. Nichts geändert.
- **B4 — Overdrive als Zweit-Pass statt HDR-Farbe**: GeckoLib-Farb-Ints clampen bei 255;
  „heller als voll" geht im additiven Emissive-RenderType nur über einen zweiten
  Draw. Der Basis-Atem (0.6…1.0) bleibt auch bei `reducedFx` aktiv (kostenneutral,
  ein Pass wie Bestand), NUR der Overdrive-Zweitpass ist gegated — Entscheidung wie
  vom Plan gefordert hier dokumentiert. Sterbende Mobs (`deathTime > 0`) überspringen
  den Overdrive, damit der W4-A2-Death-Dissolve-Alpha-Fade nicht überstrahlt wird.
  Im `StormHoundRenderer` wurde AUSSCHLIESSLICH die Glowmask-Layer-Zeile ersetzt.
- **B5 — `cos` statt `sin` (dokumentierte Plan-Abweichung)**: `sin(bearing−angle)`
  peakt 90° NEBEN dem Beobachter; die Intention „Rauch lehnt sich zum Spieler" braucht
  `cos(bearing−angle)` (Peak bei Ausrichtung). Budget bleibt im Mittel exakt: Gewicht
  integriert über den Ring zu 1.0, probabilistisches Runden statt Truncation.
- **B5 — separate Lair-Felder** (`nextLairThumpTick`/`lairEchoTick`) statt Reuse der
  Approach-Dread-Felder: `tickApproachDread` bailt bei `interiorAmount() ≥ 0.1` und
  cleart dabei sein Echo — ein geteiltes Feld hätte das Lair-Echo gefressen. Außerhalb
  Kern/Gate übernimmt nahtlos wieder die §1-Approach-Leiter.
- **B6 — Anchor NIE am Spieler**: Bearing wird vom CHEST (nicht vom Spieler) auf die
  Schale projiziert; degenerierter Fall (Chest exakt im Zentrum) bekommt ein
  Zufalls-Bearing. Re-Open still über `STUNG_CHESTS`-Set (Session-Latch, cleart in
  `ServerStoppedEvent` — bewusst NICHT persistiert: „once per session" laut Charter).
- **B6 — Spawn über `EventSpawnRules`-Hook**: `trySpawnChestRevenant` nutzt dieselben
  Caps (global + Site) und `SpawnGates.FOG_STORM` wie die Bestands-Spawns; Peaceful
  und Cap-Überlauf loggen und spawnen still nicht (Arc + Rumble feuern trotzdem).

## 3. Erst-Verifikationstabelle

| Prüfpunkt | Methode | Ergebnis |
|-----------|---------|----------|
| Compile-Gate | `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | BUILD SUCCESSFUL |
| B1 genau 1 enter pro Crossing | Code-Review: Latch-Flanken (`!latched && ≥0.5` / `latched && <0.3`), Snap re-seatet stumm | PASS (Log-Beweis → Drehbuch S1) |
| B1 Fog-Pinch 6→2/10 t | Sinus-Envelope über `breachTicks`, `Math.min` gegen Bestands-Near (nie weiter als Bestand) | PASS |
| B2 Sonden-Lanes corpse/outside/inside | drei `[w5b-swallow]`-Sonden vorhanden, outside loggt Schalenpunkt-Koordinaten | PASS (Live → Drehbuch S2) |
| B2 `FxPayloads` additiv | Diff: nur neue Id + Handler-Case + Version-String `fx2` | PASS |
| B2 `EclipseFxState` additiv | Diff: 2 Felder + 2 Methoden + `clearAll`-Reset | PASS |
| B3 keine neue Depth-Geometrie | Diff: nur Farb-/Alpha-Arithmetik in bestehenden Emit-Schleifen, Vertex-Zahl unverändert | PASS |
| B3 Nacht unverändert | `daylight = 0` ⇒ churnFloor 0.45 (Bestand), Rim-Faktor ×1.0 — byte-identische Nacht-Arithmetik | PASS |
| B4 nur Emissive-Pass im Hound | Diff `StormHoundRenderer`: einzig die Glowmask-Zeile; Stagger-Tell-Block unberührt | PASS |
| B5 Kadenz nur im Kern | Gates `centerDist ≤ 30` UND `interior > 0.6` UND Sturm nicht dissipate/explode | PASS (Live → Drehbuch S5) |
| B5 Partikelbudget | Erwartungswert Ring-Summe = Bestand (`Σ cos = 0` über vollen Ring) | PASS |
| B6 one-shot + Wall-Anchor | Latch-Set + Bearing-Projektion vom Chest; Sonde loggt Wall-Koordinaten | PASS (Live → Drehbuch S6) |
| Ownership | `git status`: ausschließlich Team-B-Dateien angefasst (10 modifiziert + 4 neu + Report) | PASS |
| Langdrop | `WAVE5B.json` python-json-valide, en+de leer + Begründungs-Kommentar | PASS |

## 4. RCON-Abnahme-Drehbuch (für den Hauptagenten)

Vorbedingungen: dedizierter Server + llvmpipe-Client laufen (NICHT neu starten),
Spieler `Dev` verbunden, Sonden-Greps auf `run/logs/debug.log`. DEBUG-Level ist im
Bestand aktiv (`[w5b-*]`-Sonden sind `LOGGER.debug` wie `[c2-splash]`/`[w4a-whiff]`).

**S0 — Sturm-Lanes kennen (wichtig!):**
- `execute as Dev at Dev run eclipsefx storm add 24 sphere` erzeugt einen NUR-CLIENT-Sturm
  (Payload, kein `StormRegistry`-Eintrag) → reicht für B1/B3/B4/B5-Heartbeat.
- B2/B6 (+ B5-Pillars) brauchen einen ECHTEN Registry-Sturm mit Site/Chests:
  `eclipse-worldgen structures list` → pending Site-Id wählen →
  `eclipse-worldgen structures place <siteId>` (materialisiert Grove + Chests, Reveal
  läuft, Sphere-Dome steht nach ≤ 40 t Poll + Reveal-Choreo). Kontrolle: `dev status`
  zeigt die Sturm-Zahl. Steht schon eine aktive Site, direkt die nutzen.

**S1 — B1 Breach (exakt 1 enter pro Crossing):**
1. Dev-Sturm oder Site-Sturm; Dev per EINEM großen `/tp` ≥ 40 Blöcke außerhalb der
   Wand setzen (Sprung > 32 Blöcke = stummer M5-Snap, armiert den Latch sauber).
2. Dann in Schritten ≤ 24 Blöcke durch die Wand teleportieren (oder fliegen), drinnen
   ~3 s stehen, wieder raus, wieder rein (rein/raus/rein).
3. `rg "\[w5b-breach\]" run/logs/debug.log` → GENAU 2× `enter` + 1× `exit`, keine
   Doppel-Fires beim Verweilen. Sichtprobe optional (Pinch ist 10 t).

**S2 — B2 Swallow (`damage Dev 1000`):**
1. Site-Sturm aus S0, Dev hineinstellen (Registry-Sturm!), dann `damage Dev 1000`.
2. `rg "\[w5b-swallow\]" run/logs/debug.log` → `corpse`-Zeile (Pos + Storm-Id/Radius)
   und `inside surge x1.6 for 15t`-Zeile. Respawn normal, keine neuen WARN.
3. Outside-Lane braucht einen ZWEITEN Spieler ≤ 96 Blöcke außerhalb der Schale
   (die Lane iteriert `level.players()` minus Innenstehende). Ohne zweiten Client:
   Plausibilität der Schalen-Projektion aus der corpse-Zeile rechnen
   (|shell − center| ≈ radius); mit zweitem Client: dessen `outside listener=`-Zeile
   loggt den Schalenpunkt direkt.
4. Sichtprobe innen (optional, `tick rate 2` dehnt die 10 t-Inhale-Ringe): zwei
   CLOUD-Ringe ziehen sich über der Leiche zusammen.

**S3 — B3 Tageslicht-Rim (Fotopunkte):**
1. `time set noon` → Screenshot der Site-Dome-Wand aus ~40 Blöcken: obere Dom-Kante
   deutlich heller/silhouettiert, Churn-Grauvarianz breiter.
2. `time set midnight` → Screenshot: Nacht-Optik unverändert (Referenz
   STORM_MASS_PLAN-S-Serie). `eclipsefx storm flashhold on` (F-101-Fotopfad) bleibt intakt.

**S4 — B4 Glowmask-Atmung:**
1. `summon eclipse:storm_hound` AUSSEN (interior≈0 → Atem-Faktor 0.6) → Screenshot.
2. Hound in den Sturm tp'en, Kamera mit hinein (interior≈1 → Faktor 1.4, Overdrive-
   Zweitpass) → Screenshot: `glow_spine` deutlich heller. Gegenprobe `reducedFx on`:
   Basis-Atem bleibt, Overdrive aus (dokumentierte Entscheidung §2).

**S5 — B5 Lair-Dread:**
1. Dev ins Sturm-ZENTRUM (< 30 Blöcke, interior > 0.6 — bei Sphere-Dome zentral stehen).
2. `rg "\[w5b-lairdread\]" run/logs/debug.log` → `cadence=16`-Zeilen im 16 t-Takt
   (hörbar: Doppel-Thump). > 30 Blöcke raus → Zeilen stoppen, §1-Approach-Leiter läuft.
3. Pillars (Site-Sturm): am Fog-Bank-Ring Foto — Rauchsäulen zur Spielerseite dichter
   (kein Log; ±35 %-Dichte-Bias, Foto von zwei Gegenseiten vergleichen).

**S6 — B6 Chest-Sting:**
1. Site aus S0 mit platzierten Chests; eine Lair-Chest öffnen.
2. `rg "\[w5b-chest\]" run/logs/debug.log` → genau 1 Zeile (site, pos, revenant=bool,
   wall=(x,y,z) — Wall-Koordinaten ≈ auf der Schale, NIE die Spielerposition).
   Chest schließen + erneut öffnen → KEINE neue Zeile (one-shot Latch).
3. 10× öffnen (verschiedene Chests) → `revenant=true`-Quote ≈ 30 %;
   `rg "chest-sting" run/logs/debug.log` zeigt Cap-Bails (`EventSpawnRules`), Caps nie
   überschritten.

**Grep-Sammelblock:**
```
rg "\[w5b-breach\]"    run/logs/debug.log
rg "\[w5b-swallow\]"   run/logs/debug.log
rg "\[w5b-lairdread\]" run/logs/debug.log
rg "\[w5b-chest\]"     run/logs/debug.log
rg "chest-sting"       run/logs/debug.log   # EventSpawnRules Cap-/Spawn-Log
```

## 5. Gates

- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (inkl. paralleler Team-A/C-Stände im Worktree).
- Keine neuen `.fx`/Resources → fxlib-Lint/Doppellauf/`processResources` nicht berührt.
- Keine GLSL-Änderungen → kein `glslangValidator`-Lauf nötig.
- `FxPayloads`/`EclipseFxState`-Diffs additiv (Plan-Gate erfüllt, siehe §3).

## 6. Offene Punkte / Übergaben

- B2-Outside-Schrei-Lane live nur mit zweitem Client vollständig abnehmbar (§4 S2.3).
- B5-Pillar-Lean ist bewusst sondenfrei (Partikel-Pfad, kein Log-Budget) — Abnahme
  fotobasiert.
- `reducedFx`-Entscheidung B4 (Basis-Atem ungegated, Overdrive gegated) steht in §2 —
  falls die Abnahme den Basis-Atem auch gaten will: Ein-Zeilen-Änderung im Layer.
