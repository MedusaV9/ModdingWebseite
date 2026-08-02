# EVAL2-A — Veil-Domäne (Evaluations-Runde 2, Team A)

**Scope:** Alle 101 Quasar-Emitter-JSONs (`assets/eclipse/quasar/emitters/`), 27 Pinwheel-Post-Pipelines
+ 55 Shader-Programme (`assets/eclipse/pinwheel/`), Führungscode (`stormfx/`, `veilfx/` inkl. `rift/`,
`border/client/`, `LimboAmbience`, Night/Umbral/Totality, Trophäen-/Altar-Loops), Konsistenz Code↔Assets,
Lebenszyklen, FxBudget. **Methode:** statisch, read-only; JSON-Parse-Scans über den Gesamtbestand,
Datei-Lektüre der Führungsklassen, Bytecode-Verifikation gegen `veil-neoforge-1.21.1-4.3.0.jar`
(Gradle-Cache, `javap -p -c`). Kein Gradle, keine Code-Änderung, kein Live-Client.

**Referenzstand:** `EMITTER_AUDIT_F107_CLASS.md` §1–§10 (F-107/F-108-Fixes inkl. E3-Wisp-Regeneration,
§9-face_velocity-Fix, §10-Godfinger-Clearance), `F109_SOFTBORDER_RESPAWN_REPORT.md`, WAVE5/6-Reports.

---

## 1. Noten-Tabelle

| Unterbereich | Note | Ein-Satz-Begründung |
|---|---:|---|
| Emitter-Hygiene | **8/10** | 99/101 Emitter sauber nach der F-108-Kur — aber ein ÜBERSEHENER Offender derselben Defektklasse (`arm_wisps`: ungedämpfter `veil:vortex` 0.9/t², das F-108-Audit scannte nur `veil:wind`), plus ein Server-Cue auf ein nicht existierendes Emitter-JSON (`containment_bounce`) und ein Waisen-JSON (`roulette_flare`). |
| Shader (Pinwheel) | **8/10** | Alle 27 Post-Pipelines und 55 Programme strukturell konsistent, Uniform-Feeds vollständig — mit EINER toten Pipeline: `resonance_shimmer` hat kein Programm-Definitions-JSON und kann nie rendern (Bytecode-Beweis §2/C1). |
| Führungscode-Lebenszyklen | **9/10** | Alle 12 `spawnManaged`-Führungen und alle Loop-Fenster haben verifizierte Release-Pfade (Dimension-Wechsel, Storm-/Boss-Ende, `reducedFx`, Logout); `QuasarSpawner`/`PhotonFxRegistry`-Disconnect-Sweeps sauber; FxBudget-Kanäle konsequent. |
| Kamera-Robustheit | **7/10** | Godfinger-Clearance (§10.2) ist vorbildlich umgesetzt und verifiziert — aber `StormFxClient.tickWisps` hat exakt dieselbe Lücke ungefixt (Wandquerung in den Vortex-Sturm ohne Release), und der Outrunner-Spawn streut designbedingt durch die Kameraposition ohne Ausschlusszone. |
| Beat-Sichtbarkeit (llvmpipe) | **7/10** | Nur zwei Emitter liegen unter der additiven Crush-Schwelle (~0.12): `limbo_motes` (0.05, dokumentiert absichtlich) und `storm_godfinger` (0.1) — Letzterer trägt den „Auge/Zentrum"-Orientierungsbeat im Sphären-Sturm und ist laut §10.6-Live-Learning bei Dämmerung/Nacht de facto unsichtbar; ungefixt. |

**Gesamteindruck:** Die Polish-Wellen 2–8 haben die F-107/F-108-Klasse im Wind-Pfad und die
Lebenszyklus-Disziplin nahezu vollständig durchgesetzt. Die verbliebenen Befunde sind Rand-Instanzen
derselben, bereits gelösten Problemklassen (Vortex statt Wind; Wisps statt Godfinger) plus zwei
Asset-Wiring-Löcher, die statisch nie auffallen konnten.

---

## 2. Befunde

### CRITICAL

**C1 — `resonance_shimmer`-Post-Pipeline ist tot: Programm-Definitions-JSON fehlt.**
- **Dateien:** `assets/eclipse/pinwheel/post/resonance_shimmer.json` (Stage referenziert
  `"shader": "eclipse:resonance_shimmer"`), `assets/eclipse/pinwheel/shaders/program/resonance_shimmer.fsh`
  (existiert, 53 Zeilen, fertig implementiert) — **`shaders/program/resonance_shimmer.json` existiert NICHT**
  (alle 26 anderen Pipelines haben ihre Definition, z. B. `echo_grade.json` = `{"vertex": "veil:blit_screen",
  "fragment": "eclipse:echo_grade"}`).
- **Failure-Mechanismus (Bytecode-verifiziert):** Veils `ShaderManager.prepare` lädt Programme
  AUSSCHLIESSLICH über den Definition-Lister (`getShaderDefinitionLister` → `.json`-Dateien); ein nacktes
  `.fsh` wird nie zu einem Programm. `BlitPostStage.apply` → `ShaderManager.getShader(id)` liefert `null`
  → `Logger.warn` und die Stage zeichnet nichts. Die WOAH-04-§4.6-Pipeline (Kristall-Schlag-Schimmern,
  Finale-Peak 0.6) ist registriert (`ResonanceFieldFx.java:121–123`), gefüttert (`feedShimmer`,
  `ResonanceFieldFx.java:170–172`) und **rendert nie**. `FX_CENSUS_WAVE13.md` führt sie als „fertig" —
  der Bruch ist rein statisch unsichtbar, zur Laufzeit nur eine Warn-Zeile.
- **Fix (1 Datei, 4 Zeilen):** `pinwheel/shaders/program/resonance_shimmer.json` mit
  `{"vertex": "veil:blit_screen", "fragment": "eclipse:resonance_shimmer"}` anlegen (exakt das
  `echo_grade`-Muster). Danach Live-Sichtung eines Kristall-Schlags.

### HIGH

**H1 — `arm_wisps`: ungedämpfter `veil:vortex` — übersehener F-108-Klasse-Offender.**
- **Datei:** `quasar/emitters/arm_wisps.json` (Modul-Block Z. 72–87: `strength: 0.9`, `range: 2.0`,
  `local_position: true`, Achse/Zentrum (0,1,0)); **kein `veil:drag`-Modul**; Lifetime bis 30 t;
  `veil:trail` (Länge 10) am Partikel. Spawner: `ArmParticles.java:46` (Dauer-Loop, entity-attached, an
  JEDEM sichtbaren Artefakt-Träger) und `TheOtherEntity.java:254 ff.` (Dawn-Despawn-Burst).
- **Failure-Mechanismus (Bytecode-verifiziert):** `VortexForceModule.applyForce` addiert pro Tick einen
  Tangential-Vektor der Länge `strength` auf die Velocity (`normalize(radial⊥).cross(axis).mul(strength)`
  → `velocity.add`), `QuasarParticle.tick` integriert `position += velocity` pro Tick ohne dt — d. h.
  0.9 Blöcke/Tick² Beschleunigung solange |Δ| < 2. Ein Partikel verlässt den 2-Block-Range nach ~2 Ticks
  mit ~1.8–2.7 B/t (36–54 B/s) und fliegt dann UNGEBREMST (kein Drag) die restlichen ~25 t ballistisch —
  40–60 Blöcke weit, mit 10-Punkt-Trail: „Leuchtspurgeschosse" vom Artefakt-Träger, dieselbe Anatomie wie
  `ferry_lantern_swarm` vor dem §3.3-Fix (24 B/s). Das F-108-Audit hat das nicht gesehen, weil sein
  Offender-Kriterium nur `wind_speed` scannte — `veil:vortex`/`veil:point_force` sind aber dieselbe
  ungedämpfte Per-Tick-Kraft-Familie. **Bestands-Scan: `arm_wisps` ist der EINZIGE Kraft-Modul-Emitter
  ohne Drag** (33 weitere Vortex-/PointForce-/Attractor-Instanzen haben alle `veil:drag` 0.01–0.3 —
  bei Drag-Semantik „Retention" ist 0.01–0.3 STARKE Dämpfung, alles gutmütig).
- **Fix (JSON-only, konservativ):** `strength` 0.9 → ~0.1 **und** `veil:drag` ~0.9 ergänzen
  (Muster `limbo_moths`: vortex 0.05 + drag; `glyph_greet`: 0.5 + drag 0.9). Ziel-Look: enge
  Orbit-Wisps um den Arm statt Streaks; Live-Sichtung am Artefakt-Träger.

**H2 — `containment_bounce`: Server-Cue auf nicht existierendes Emitter-JSON.**
- **Datei:** `progression/ContainmentService.java:45–46` deklariert
  `eclipse:containment_bounce` („P2 registers this Quasar emitter; fallback particles apply until then")
  und sendet ihn bei jedem Containment-Bounce als `S2CQuasarPayload` (Z. 187). Es gibt **kein**
  `quasar/emitters/containment_bounce.json` — der Client läuft in `QuasarSpawner.spawnOrFallback` →
  unknown-id-Warn (einmalig) → generischer 8-Partikel-END_ROD/PORTAL-Vanilla-Burst.
- **Failure-Mechanismus:** Kein Crash, aber der Weltrand-Bounce (ein wiederkehrender Gameplay-Beat) spielt
  permanent den Notfall-Fallback statt eines komponierten Effekts; das im Javadoc versprochene P2-Asset
  wurde nie geliefert. Einziger fehlender Emitter unter allen 10 `S2CQuasarPayload`-Konstanten,
  allen FxCues-Quasar-Legs und allen `*_EMITTER`-Konstanten (Scan über `src/main/java`).
- **Fix:** `containment_bounce.json` anlegen (nächste Verwandte: `unlock_burst`-Anatomie — Hemisphäre,
  kurzer additiver Puls, Tint `#B98CFF` passend zu `ContainmentService.HINT_COLOR`) oder den Javadoc-
  Vertrag explizit auf „Vanilla-Fallback ist final" ändern.

**H3 — `StormFxClient.tickWisps`: fehlende Kamera-Clearance — dieselbe Lücke, die §10.2 beim Godfinger geschlossen hat.**
- **Datei:** `stormfx/StormFxClient.java:714–751` (`tickWisps`): ≤3 `vortex_wisp`-Loop-Emitter
  (`MAX_WISPS=3`, Z. 97) orbitieren den Vortex-Sturm auf `storm.radius + 1.0` (Z. 725) mit
  0.0175 rad/t (≈10 B/s Tangential bei r≈28) und werden per `setPosition` geführt. Es gibt Releases für
  DISSIPATE/Sichtbarkeit/Tier (Z. 715–722), aber **keinen Kamera-Abstands-Release** — anders als
  `StormInteriorFx.tickGodFingers` (Release <6, Re-Engage >9, `StormInteriorFx.java:762–781`).
- **Failure-Mechanismus:** Das Betreten eines Vortex-Sturms IST eine Wandquerung durch den
  Wisp-Orbit-Ring (Shell+1). `vortex_wisp`-Quads sind bis 2.1 Half-Edge (4.2 Blöcke Kante, 16×16-Wisp,
  nicht-additiv α 0.42) und die vom vorbeiziehenden Emitter zurückgelassenen Partikel (Life 65 t, quasi
  ortsfest: wind 0.03 + drag 0.05) hängen genau in der Querungszone — Kamera-Durchflug erzeugt
  Near-Plane-Schnittkanten einer 4-Block-Violett-Fläche, die F-107-Klingen-Klasse. Motion-/Fog-maskiert
  und kurz, aber bei jedem Sturm-Eintritt reproduzierbar möglich.
- **Fix (~15 Zeilen Java):** das §10.2-Hysterese-Paar in `tickWisps` übernehmen: Wisp-Slot released,
  wenn die Ring-Sollposition horizontal <6 Blöcke an der Kamera liegt, Re-Engage >9; `wispAngle` läuft
  weiter (Godfinger-Muster, kein Ruckeln). Emitter-JSON unangetastet.

### POLISH

**P1 — `storm_godfinger` nachts unter der llvmpipe-Sichtbarkeitsschwelle (Beat-Sichtbarkeit).**
`quasar/emitters/storm_godfinger.json` α-Peak 0.1 additiv (Z. 85–102) unter dem verdunkelnden
`storm_interior`-Grade; §10.6 dokumentiert als Test-Learning („Interieur-Grade crusht die additiven
Schächte bei Dämmerung/Nacht unter die llvmpipe-Sichtbarkeit"), aber nicht gefixt. Der Godfinger ist der
einzige Orientierungs-Marker Richtung Sturm-Auge (EyeDim-Zone). Vorschlag: α-Peak 0.1 → 0.14–0.16 ODER
Java-seitig `veil:color`-unabhängige Nacht-Kompensation ist nicht möglich — daher pragmatisch α anheben
und bei Tages-Abnahme gegenprüfen (die 3.2er-Quads mit 64×256-Soft-Textur vertragen das ohne
Kanten-Risiko, Kriterium 3 bleibt unterschritten, weil Textur-Peak 0.55 die Effektiv-α dämpft).

**P2 — `roulette_flare.json` ist ein Waisen-Emitter (dokumentiert bewusst unbenutzt).**
`AwardsOverlay.java:125/691–693/734–736` erklärt, warum der World-Space-Emitter hinter dem Fixed-Overlay
unbrauchbar ist (Screen-Space-Ersatz in Code). Das JSON bleibt aber im Ship-Bestand und taucht in
Dev-Vorschlagslisten auf. Vorschlag: JSON löschen und die Javadoc-Erwähnungen auf „ehemals" umformulieren
— oder als bewusstes Archiv einzeilig im JSON kommentieren lassen (Quasar-JSONs können kein `_comment`?
→ dann löschen; 1 Datei, 0 Risiko).

**P3 — `StormApproachFx`-Runner ohne Kamera-Ausschlusszone im Side-Scatter.**
`StormApproachFx.java:202–208`: Runner starten 3.6–8.4 Blöcke HINTER dem Spieler mit ±7 Blöcken
Seitenstreuung und rasen mit 13 B/s durch/nahe der Kameraposition zur Wand („der Sturm inhaliert dich" —
Design-Absicht). Bei |side| < ~1 zieht ein 2.4-Block-Quad (nicht-additiv α 0.5) exakt durch die Near-Plane.
Vorschlag: `side` unter ±1.5 auf ±1.5 aufrunden (Vorzeichen behalten) — die Inhale-Lesart bleibt, der
Durch-die-Kamera-Fall verschwindet; 3 Zeilen.

**P4 — `a0_shader_proof.fx` ist das einzige wirklich verwaiste Photon-Asset.**
Binär-Scan aller 293 `.fx` (inkl. Kompositions-Querverweise) + Java-Strings: nur `a0_shader_proof`
referenziert nichts und wird nicht referenziert (A0-Foundation-Proof, `A0_SHADER_FOUNDATION.md`).
Vorschlag: löschen oder in `tools/` verschieben — Ship-Assets sauber halten.

**P5 — E2-Watchlist unverändert offen; stärkster Kandidat `totality_diamond_glint`.**
Die fünf F-108-Grenzfälle (Quad 1.1–2.1 auf Haus-Wisps) bestehen weiter; seit E3 sind die Wisps 16×16 mit
Rand-α 0, was die Quad-Kanten-Komponente entschärft, NICHT aber die Nearest-Texel-Rechtecke auf großen
Quads. `totality_diamond_glint` (Quad 1.6, additiv, α-Peak 1.0, `AtmospherePhotonFxRows`) ist die
höchste Energie-Kombination der Liste — beim Totality-Peak zentral im Blick. Vorschlag: Sprite auf
`flash_soft.png` umstellen (fertiges Gegenmittel, §6/E2-Rezept), Rest der Liste weiter nur beobachten.

**P6 — Kosmetik: totes `strength`-Feld in `veil:wind`-Blöcken.**
15 Wind-Module tragen weiter `"strength": 0.2–0.5`, das Veil 4.3.0 nachweislich ignoriert (F-107-Teil-2-
Beweis; z. B. `storm_godfinger.json` Z. 62). Verwechslungsgefahr beim nächsten Tuning — Feld entfernen
oder pro Datei einen Kommentar-Workaround via Feldname vermeiden; reine Hygiene, keine Laufzeitwirkung.

---

## 3. Top-5 Polish-Kandidaten für die nächste Welle (Impact/Aufwand)

| # | Kandidat | Impact | Aufwand |
|---|---|---|---|
| 1 | **C1**: `pinwheel/shaders/program/resonance_shimmer.json` anlegen (4 Zeilen, `echo_grade`-Muster) — schaltet ein fertiges, bereits gefüttertes WOAH-04-Feature frei | hoch | minimal |
| 2 | **H1**: `arm_wisps`-Vortex-Kur (strength 0.9→~0.1, +drag ~0.9) — beendet 40-Block-Leuchtspuren an jedem Artefakt-Träger | hoch | minimal (JSON) |
| 3 | **H2**: `containment_bounce.json` anlegen (`unlock_burst`-Anatomie, Tint #B98CFF) — ersetzt den Vanilla-Notfallburst eines wiederkehrenden Beats | mittel-hoch | klein (Asset) |
| 4 | **H3**: Kamera-Clearance in `StormFxClient.tickWisps` (§10.2-Hysterese-Muster übernehmen) | mittel | klein (~15 Zeilen Java) |
| 5 | **P1+P5**: Sichtbarkeits-/Kanten-Paket — `storm_godfinger` α 0.1→0.15 (Nacht-Crush) + `totality_diamond_glint` auf `flash_soft.png` | mittel | minimal (2 JSONs) |

---

## 4. GEPRÜFT und für GUT befunden (nicht doppelt prüfen)

**Emitter-Bestand (101 JSONs, vollständiger Parse-Scan):**
- **Wind-Audit (Prüfmuster 1):** KEINE neuen ungedämpften `veil:wind`-Fälle. Nur `limbo_fog` (0.0003)
  und `storm_rain_sheet` (0.001) ohne Drag — beide dokumentiert-absichtlich (§3.2-Muster), Drift ≤1.1 bzw.
  ≤0.17 Blöcke. Alle 13 Wind+Drag-Paare: Terminal ≤0.96 B/s außer `cutscene_veil` 3.6 B/s (E1, absichtliche
  Streaks). Alle 7 F-108-Fixes sind im Bestand verifiziert wirksam (Werte stimmen mit §3/§5 überein).
- **Kraft-Module jenseits Wind:** alle 16 `veil:vortex`-, 12 `veil:point_force`-, 6 `veil:point_attractor`-
  Instanzen einzeln geprüft — **alle außer `arm_wisps` (H1) haben `veil:drag`** und sind mit
  Retention-Semantik (Drag 0.01–0.3 = starke Dämpfung) gutmütig.
- **face_velocity-Muster (Prüfmuster 4):** §9-Musterscan reproduziert. `storm_godfinger` steht korrekt auf
  `face_velocity:false`/`stretch 0.0`; `storm_rain_sheet` bewusst true (echter Fall-Effekt, kein Drag).
  Genau die vier dokumentierten Nebenbefund-Emitter kombinieren face_velocity+drag≥0.9 (`boss_slam`,
  `cutscene_veil`, `altar_reveal_burst`, `roulette_flare`) — kleine One-Shot-Quads ≤0.36, weiterhin
  Beobachten-Verdikt. KEINE neuen Kandidaten. **Java-seitig existieren keine direkt gebauten Emitter:**
  einzig `QuasarSpawner` berührt `ParticleSystemManager`/`createEmitter` (rg-verifiziert) — alles datengetrieben.
- **Texturen:** Haus-Wisps sind wie in §8 versprochen 16×16 (PNG-Header-Scan) mit dediziertem Soft-Satz
  (`limbo_fog_soft` 128², `limbo_fogbank_soft` 128×64, `flash_soft`/`dust_wall_soft` 128², `ring_soft`/
  `border_glitch` 256², `storm_godfinger_shaft` 64×256). **Alle 22 Partikel-Texturen sind referenziert** —
  die 9 scheinbaren Waisen (`crt_glow_2x2`, `dome_faint`, `hand_reach`, `nether_plume_atlas`, `petal_soft`,
  `square_4x4`, `star_2x2`, `storm_puff_atlas`, `wand_ember_atlas`) stecken binär in Photon-`.fx`
  (gzip-Scan aller 293 Kompositionen).
- **llvmpipe-Crush-Scan (Prüfmuster 5):** nur `limbo_motes` (0.05 — absichtlicher F-107-Teil-4-Cap, Death-
  Screen seit §7 über `death_ash` 0.28 entkoppelt) und `storm_godfinger` (0.1 — P1) liegen additiv ≤0.12.
  `sig_crown_verdict_halo` (Peak 0.85, Auslauf 0.28) trägt seinen S-MAX-Punch weiterhin über der Schwelle.

**Code↔Asset-Konsistenz:**
- Alle 10 `S2CQuasarPayload`-Konstanten, alle FxCues-Quasar-Legs und alle `*_EMITTER`-Konstanten zeigen auf
  existierende JSONs — einzige Ausnahme `containment_bounce` (H2). 100/101 Emitter sind aus Java referenziert —
  einziger Waise `roulette_flare` (P2, dokumentierte Design-Entscheidung).
- Photon: alle `fx("…")`-Referenzen lösen auf (Verdachtsfälle `boss/…`, `sig/…` liegen in Unterordnern;
  `FxPayloads.fx()` ist ein Cue-Namespace, kein Asset-Pfad; `boss_summon_beacon_<n>` dynamisch konstruiert);
  einziges verwaistes `.fx` ist `a0_shader_proof` (P4).
- Pinwheel: alle 27 Post-JSONs → alle Stage-Shader haben Programmdefinitionen AUSSER `resonance_shimmer`
  (C1); alle 55 Programm-JSONs → `.fsh` vorhanden; `storm_volume` (2-Stage + Half-Res-Framebuffer + Sampler)
  strukturell korrekt; `glitch_<id>`-Familie wird dynamisch aus `GlitchZoneEffects` konstruiert (kein Waise).
- **Uniform-Feeds:** Scripted Abgleich aller Nicht-Sampler-Uniforms aller 55 `.fsh` gegen `getUniform("…")`
  in `src/main/java` — vollständig gedeckt (`rift_volume`s `Rift0/1*` über dynamische Namen in
  `RiftVolumeFx.feedRift`, verifiziert).

**Führungscode / Lebenszyklen (alle Dateien gelesen):**
- `QuasarSpawner`: BROKEN/WARNED-Sets, ATTACHED-Map mit `prune()`, Logout-Sweep, Budget-vor-Spawn-Gesetz,
  reducedFx-Garnish-Shed — Referenzqualität. `FxBudget`: Kanäle/Fenster/Tier-Logik konsistent; STORM für
  Sturm-Loops, AMBIENT für Ambience-Fenster, SEQUENCE für Skripte, BURST für One-Shots — stichprobenhaft
  über alle Spawn-Stellen bestätigt.
- `LimboAmbience`: 4 Fenster + SpireEmbers mit Live-Caps, `clear()` auf Dimension-Wechsel/Logout/reducedFx;
  Clearance-Mathe der FOG-/FOGBANK-Ringe (≥5.4/≥7.9 Blöcke) nachgerechnet und schlüssig. *Dokumentierte
  Rest-Exposition:* die Garantie gilt zur Spawn-Zeit — ein kreativ FLIEGENDER Spieler kann eine Fog-Sheet
  binnen ihrer 4-s-Lebenszeit erreichen; im Ruder-Schiff-Normalspiel irrelevant, weiche nicht-additive
  Textur macht den Durchflug zum Haze-Puls. Kein Handlungsbedarf.
- `StormInteriorFx`: Godfinger-Clearance §10.2 exakt wie dokumentiert im Code (Release <6 / Re-Engage >9,
  Winkel läuft weiter, `removeEmitter` tötet Alt-Quads mit); RainSheets Spawn-Distanz ≥2.0 bei Quad ≤0.8 ✓;
  `reset()` deckt level-null/Clone/Logout, `clearRain`+`clearGodFingers` inklusive. `StormFxClient`:
  Wisp-/CrownHalo-/Churn-Releases auf DISSIPATE/Sichtbarkeit/Range/Tier ✓ (bis auf H3-Kamera-Lücke);
  `StormApproachFx`: Runner-Absorb/MaxTicks/Clear auf Logout+Clone+level-null ✓.
- `RiftFx` (sparkEmitter/motesEmitter/inhaleEmitter je Rift, `removeEmitters` beim Schließen, `clearAll`
  auf Logout), `RiftDrawIn`, `RiftVolumeFx` (reiner Uniform-Feeder) ✓. `AltarIdleMotes` (Overworld-Gate,
  Hysterese 64/72, reducedFx-Release) ✓. `SanctumLightfall`, `ShipDoorGlow`, `EclipseDeathScreen.removed()`
  (death_ash), `HurtSparks` (expireTick), `OfferingSwallowFx` (finishFlight) ✓.
- `PhotonFxRegistry`: ensureLoop/releaseLoop mit prune, REPLACE-Retire, Disconnect-Sweep ✓; Fenster-Besitzer
  `TrophyWisp` (4 Boss-Trophäen: Dimension-Gates, 28/36-Hysterese, reducedFx/Logout) und `DungeonMawIdle`
  (Anchor-Tabelle, Unlock-Gate, Re-Anchor = Release+Ensure) ✓. `EndStaticFx`/`TotalityPeakFx`/
  `UmbralVeinsFx`: Logout-Resets vorhanden ✓.
- `BorderFxRenderer`: Shard-/Glitch-Bursts sind ring-gepinnt (SoftBorder-Pushback hält die Kamera vom Ring;
  harte Blocky-Optik ist dort Design), `resetThrottles` gegen gameTime-Restart ✓; `FirstContactSeam` nur
  One-Shots. `SignatureCompositions`: `sig_crown_verdict_halo` als One-Shot +3.5Y über dem Anker mit
  256er-Soft-Ring — kein Clearance-Fall; Step-Scheduler cleart auf Unload/Logout ✓.

**Shader-Stichproben:** `storm_interior.fsh` (EyeDim/WallBand/BandFlow-Verkabelung, definierte
smoothstep-Richtungen, Depth am gewobbelten UV gesampelt), `limbo.fsh`-Feeder-Seite (InvViewProj-Disziplin,
NaN-Guards, Uniform-Parkwerte), `resonance_shimmer.fsh` (Implementierung fertig und budget-konform — nur
die Definition fehlt, C1). Keine weiteren strukturellen Auffälligkeiten.

---

*EVAL2-A, statisches Audit ohne Live-Client — Live-Verifikation der Fixes C1/H1/H3 braucht je eine
kurze Sichtung (Kristall-Schlag im Resonanzfeld, Artefakt-Träger, Vortex-Sturm-Eintritt).*
