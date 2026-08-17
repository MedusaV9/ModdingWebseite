# ECLIPSE_WAVE_PLAN — Bug-/Verbesserungs-Wellen (Stand: WAVE10-Audit, 17.08.)

**Kontext.** PROJECT: ECLIPSE ist eine Minecraft-1.21.1/NeoForge-21.1.238-Server-Event-Mod
(„Eclipse-Core", ~1 290 Java-Dateien, 293 Photon-`.fx`, 101 Quasar-Emitter, 27 Veil-Post-
Pipelines, 155 GameTests). Die Polish-Wellen 1–9 (F-001…F-110/W9) haben die Befunde der
zwei Evaluationsrunden weitgehend abgearbeitet. Dieses Dokument ist das Ergebnis des
WAVE10-Audits: Build-System, Testinfrastruktur, Tool-Gates, offene Eval2-Reste und
frische Funde — als priorisierte Liste für die Wellen 10 (dieses Dokument = Welle 1
des neuen Zyklus), 11 und 12.

**Ausgangszustand (ehrlich gemessen, vor den WAVE10-Fixes):**

- `./gradlew build` — **grün** (4 m 47 s auf vorgewärmtem Cache).
- `./gradlew runGameTestServer` — **CRASH vor dem ersten Test**: `Missing test structure
  eclipse:gametest.empty` (P-01). Die 155 GameTests sind seit ihrer Einführung (P4-A1)
  noch nie headless gelaufen; AGENTS.md führte sie deshalb als „executable documentation".
- Nach dem Template-Fix: **19/155 Tests rot** in 4 Klassen (P-02…P-05), inklusive eines
  kompletten Server-Absturzes durch einen Payload-Send im Tick-Loop (P-02).
- `python3 tools/music/validate_oggs.py` — **rot** (12 Phantom-FAILs, P-06).
- `python3 scripts/p4_balance_check.py` — **AttributeError-Crash** (P-07).
- `python3 tools/photon/fxlib.py validate --lint` — grün (0 NEW, 23 grandfathered).
- `python3 tools/repass_cutscenes.py` — grün (10/10).
- Lang-Parität en_us == de_de == 2 875 Keys, 0 Lücken — grün.

---

## Priorisierte Liste (WAVE10 = in dieser Welle gefixt, W11/W12 = geplant)

### Kritisch / Hoch — WAVE10 (gefixt in dieser Welle)

| # | Befund | Dateien | Status |
|---|---|---|---|
| P-01 | **GameTest-Suite nie lauffähig: Template-ID `gametest.empty` mappt literal auf `structure/gametest.empty.nbt`, geshippt ist `structure/gametest/empty.nbt`** — GameTestServer crasht vor Test 1; alle 155 Tests betroffen. Fix: ID auf `gametest/empty`. | `gametest/GameTestSupport.java` (EMPTY_TEMPLATE), `data/eclipse/structure/gametest/empty.nbt` | ✅ WAVE10 |
| P-02 | **Mock-Player ohne Payload-Channels: jeder `PacketDistributor.sendToPlayer(mock, …)` wirft `UnsupportedOperationException`** — 16 Tests rot (`day_state`/`day_clock`-Sends), und der `UnlockSync.onServerTick`-Broadcast an einen liegengebliebenen Mock **crashte den ganzen GameTestServer** (Exception im Tick-Loop). Fix: NeoForges offizielles `NetworkRegistry.configureMockConnection` beim Mock-Spawn. | `gametest/GameTestSupport.java`, Beweis: `UnlockSync.java:107`-Stacktrace im Baseline-Log | ✅ WAVE10 |
| P-03 | **Test-Drift `spawnProtectionUsesSanctumQuery`: prüfte die alte r=18-Sanctum-Zone, Produktion ist seit plans_v5 B10/ALTARFIX2 absichtlich die breite r=71-Zone** — „outside"-Probe bei r=22 lag mitten in der echten Zone. Fix: Probe hinter `spawnRadius(server)`. | `gametest/restrictions/RestrictionGametests.java`, Semantik: `worldgen/structure/SanctumProtection.java` | ✅ WAVE10 |
| P-04 | **Test-Bug `placedBlockNaturalCheck`: setzte Bit 0 der Section (= lokale Ecke (0,0,0)) statt des Block-Index der Testposition** — konnte auf zufälligen GameTest-Pads nie bestehen. Fix: Produktions-Schreibpfad `PlacedBlockTracker.markPlaced`. | `gametest/buffs/TimedBuffGameTests.java`, `analytics/PlacedBlockTracker.java` | ✅ WAVE10 |
| P-05 | **2 Xbox-Tests erwarten Datapack-Dimensionen, aber GameTestServer bootet NUR die flache Test-Overworld** (auch `eclipse:limbo` fehlt dort — gleiche Warnung im Log). Kein Produktionsbug (TU-Welten seit F-028 live verifiziert). Fix: dokumentierter Umgebungs-Skip; Vollprüfung bleibt unter `runServer`s `/test`. | `gametest/xboxevent/XboxEraWorldGameTests.java` | ✅ WAVE10 |
| P-06 | **`validate_oggs.py` permanent rot: `minecraft:`-Namespace-Zeilen (`music.xbox_era` → C418-Tracks aus Mojangs Asset-Index) wurden in den Eclipse-Asset-Baum aufgelöst** — 12 Phantom-„missing file"-FAILs; das AGENTS.md-Pflicht-Gate war wertlos (rote Gates trainieren Ignorieren). Fix: Fremd-Namespaces überspringen (Regel aus `MusicAssetValidationTest`). | `tools/music/validate_oggs.py:102` | ✅ WAVE10 |
| P-07 | **`p4_balance_check.py` crasht: v5-Config-Migration wickelte `milestones.json` in `{configVersion, _comment, milestones}`, der Checker iteriert das Dict (Strings statt Objekte) → `AttributeError`, der NICHT im Catch-Tupel steht und das ganze Gate tötet.** Dazu 3 weitere Drift-Schichten: Trigger-Whitelist ohne `touch_altar`/`visit_dimension` (echte `TriggerType`-Einträge), Advancement-i18n gegen den historischen WB-CONTENT-Langdrop statt der gemergten Lang-Dateien, P4-Ära-Zahlen-Envelopes (24–28 Knoten / C(12)≈2650) die das seit F-036 akzeptierte Live-Design (60 Knoten, C(12)=19935) dauerhaft rot stellten. Fix: v5-Shape, Enum als Source-of-Truth, Ship-Lang, Re-Baseline auf Live-Werte. | `scripts/p4_balance_check.py` (Z. 317, 477 ff., TRIGGER_IDS, validate_advancements, validate_skills) | ✅ WAVE10 |
| P-08 | **Backrooms-Exit ohne Heightmap-Gate (EVAL2-C P-2, F-109/W5-B6-Void-Klasse):** `exitToAnchor` vertraut `getHeight()` ungeprüft — auf ungeladenem Chunk kommt `minBuildHeight` (−176) zurück = Void-Säulen-Teleport. Heute implizit durch Spawn-Chunks gedeckt; bricht mit `spawnChunkRadius=0` oder verlegtem Altar. Fix: Sentinel-Gate + Fallback auf Anchor/World-Spawn. | `backrooms/BackroomsEventService.java:554` | ✅ WAVE10 |

### Mittel — WAVE10 (gefixt in dieser Welle)

| # | Befund | Dateien | Status |
|---|---|---|---|
| P-09 | **Dragon-Bossbar hält Disconnect-Leichen bis Kampfende (EVAL2-C P-4):** der Sweep prüfte nur `player.level() != level`, was für tote Referenzen false bleibt. Fix: `hasDisconnected()`-Leg im bestehenden Sweep (Haus-Muster `MinigameService.onPlayerLoggedOut`). | `worldgen/end/EclipseDragonFight.java:734` | ✅ WAVE10 |
| P-10 | **PortalKey `unlock_turn` 25°-Body-Ruck (letzter offener EVAL2-C-P-1-Eintrag):** W9-C hat Sentinel/Revenant/SoulWisp nachgezogen, den Portal-Key aber ausgelassen. Fix: 2-t-Blend via `actionTransitionTicks` (SoulWisp-Idiom); Molang-Präzession unberührt. | `ferryman/finale/PortalKeyEntity.java` | ✅ WAVE10 |
| P-11 | **StormApproach-Runner durch die Kamera (EVAL2-A P3, F-107-Klingen-Klasse):** Side-Scatter ±7 ohne Ausschlusszone — bei |side|<~1.5 zieht ein 2.4-Block-Quad exakt durch die Near-Plane. Fix: |side| auf ≥1.5 aufrunden, Vorzeichen bleibt (Inhale-Lesart erhalten). | `stormfx/StormApproachFx.java:202` | ✅ WAVE10 |
| P-12 | **Waisen-Emitter `roulette_flare.json` (EVAL2-A P2):** Screen-Space-Ersatz rendert längst in Code (`AwardsOverlay`), das World-Space-JSON shippte trotzdem. Fix: gelöscht + 3 Javadoc-Stellen auf „retired" umformuliert. (`a0_shader_proof.fx` bleibt BEWUSST: generator-eigen — Löschen bräche das W9-B-gen-diff-Gate — und via `/dev photon test` erreichbarer A0-Proof.) | `assets/eclipse/quasar/emitters/roulette_flare.json`, `client/awards/AwardsOverlay.java` | ✅ WAVE10 |

### Welle 11 (nächste Welle — konkret geplant)

| # | Befund | Dateien |
|---|---|---|
| P-13 | **Lint-Baseline-Burndown Runde 2:** 23 grandfathered Verstöße (`LINT-LINEAR-CURVE`/`LINT-ALPHA-NOSORT`/1× `LINT-SUBEM-FAT`); W9-B hat die 4 `boss/tyrant_*` abgebaut. Nächste Kandidaten nach Sichtbarkeit: `intro_burst_ring` (3), `portal_draw_in` (5), `totality_diamond_ring` (5), `storm_cloud_belt` (3× ALPHA-NOSORT). Pro Eintrag Kurve → 2-Segment-Ease bzw. `sortMode`, dann Sichtprüfung. | `tools/photon/lint_baseline.txt`, zugehörige Generatoren |
| P-14 | **7 GeckoLib-Items auf nacktem Hard-0-`AnimationController` (EVAL2-C P-6):** aktuell messbar pop-frei authoriert, aber jede NEUE Anim erbt still Hard-0 am POLISH2-Policy-Punkt vorbei. Mechanischer Swap auf `EclipseActionController` (bit-identisch, reine Zukunftssicherung). | `wand/EclipseWandItem.java:89`, `ritual/ReviveSigilItem.java:99`, `ritual/StormHeartItem.java:92`, `ritual/HeraldsLureItem.java:87`, `economy/UmbralBladeItem.java:60`, `economy/UmbralPickItem.java:71`, `economy/FerrymanTollItem.java:74` |
| P-15 | **Totes `strength`-Feld in 15 `veil:wind`-Blöcken (EVAL2-A P6):** Veil 4.3.0 ignoriert es nachweislich (F-107-Bytecode-Beweis); beim nächsten Tuning ist Verwechslung programmiert. Feld entfernen; dabei prüfen, ob ein Generator die JSONs besitzt (sonst gen-diff-Konflikt wie bei P-12). | u. a. `quasar/emitters/storm_godfinger.json:62` |
| P-16 | **`beat_credits_afterglow`-Stacking-Guard nur implizit (EVAL2-B P-5):** einziger Neubestands-Emitter, der das V2.1-Gesetz allein über Shape-Streuung erfüllt (Birth-Tint 0.93-Luminanz!) — Shape-Verengung erzeugt sofort einen Weiß-Blob. Guard-Kommentar in den Beats-Generator + optional Birth-Stop ≤0.6. | `tools/photon/beats_fx.py` (o. ä.), `assets/eclipse/fx/beat_credits_afterglow.fx` |
| P-17 | **GameTest-Harness-Härtung:** (a) `runGameTestServer` in AGENTS.md/README als Pflicht-Gate dokumentieren (WAVE10 erledigt den Doku-Teil), (b) CI-Empfehlung: Suite auf jedem Push, (c) die 2 Xbox-Skips per dediziertem `runServer`-`/test`-Protokoll gegenprüfen, (d) Login-Sync-„recoverable"-ERRORs für Mock-Player entrauschen (kosmetisch, Log-Hygiene). | `.github/workflows/` (neu), `gametest/`, `AGENTS.md` |
| P-18 | **Balance-Gate Feinschliff:** Re-Baseline-Werte (P-07) gegen die Java-Default-Tabellen statt gegen `run/config` prüfen (der `--strict`-Pfad existiert schon), damit das Gate auch auf frischen VMs ohne Dev-Weltzustand läuft; `validate_source_shape` deckt heute nur einen Teil. | `scripts/p4_balance_check.py`, `progression/goals/GoalConfig.java`, `skills/` |

### Welle 12 (Backlog, bewertet)

| # | Befund | Dateien |
|---|---|---|
| P-19 | **Woah-Audio-Beds G-2 (seit F-095 „ready-to-generate"):** 3 dedizierte Beds; Specs+Prompts fixiert, blockiert allein durch fehlenden `TREBLO_API_KEY` in der Umgebung. Sobald der Key als Secret verfügbar ist: generieren, `validate_oggs` (jetzt grünes Gate!), einbauen. | `tools/music/treblo_generate.py`, `docs/plans_v3/…` (G-2-Spec) |
| P-20 | **`storm_godfinger`-Nacht-Sichtbarkeit nachmessen:** W9-A hob α auf 0.15 — die §10.6-Dämmerungs-Crush-Bedingung ist seitdem nie live gegengeprüft worden (llvmpipe-Abnahme steht aus). | `quasar/emitters/storm_godfinger.json`, Abnahme per `runClient` |
| P-21 | **Kamera-Clearance-Klasse systematisch schließen:** nach Godfinger (W8), Wisps (W9-A) und Approach-Runnern (WAVE10 P-11) bleiben die dokumentierten Rest-Expositionen: `LimboAmbience`-Fog-Sheets bei Kreativ-Flug (EVAL2-A „kein Handlungsbedarf" — re-evaluieren), `BorderFxRenderer`-Ring-Bursts (Design). Einmalige Sweep-Checkliste, dann Klasse für erledigt erklären. | `veilfx/LimboAmbience.java`, `border/client/BorderFxRenderer.java` |
| P-22 | **EMI-„Can't send EMI packet"-Warn pro Mock/Vanilla-Join** (Baseline-Log): harmlos, aber pro Join eine Zeile; prüfen ob die EMI-Plugin-Registrierung einen `hasChannel`-Guard verdient. | `integration/emi/` (Eclipse-EMI-Plugin) |
| P-23 | **`run/server.properties`-Regenerations-Falle** (AGENTS.md-Gotcha): nach Wipe fehlen RCON/allow-flight silently. Ein `/dev doctor`-Check (oder Boot-Warn), der die 3 kritischen Properties prüft und loggt, macht die Falle selbstdiagnostizierend. | `devtools/dev/` (neuer Doctor-Check), `AGENTS.md` |
| P-24 | **`xbox_staging/` im Repo-Root** (35 MB?) gehört vermutlich nicht ins Repo bzw. nicht auf diesen Branch — klären ob Alt-Artefakt der Xbox-Welten-Pipeline; ggf. in Git-LFS/`.gitignore`. | `xbox_staging/` (Repo-Root, außerhalb ProjectEclipse) |

---

## Testinfrastruktur-Referenz (nach WAVE10)

- **`./gradlew build`** — kompiliert strict; Pflicht vor jedem Push (unverändert).
- **`./gradlew runGameTestServer`** — bootet den headless GameTest-Server und führt alle
  155 `@GameTest`s aus; Exit ≠ 0 bei jedem Required-Fail. Seit WAVE10 lauffähig und grün;
  2 dokumentierte Umgebungs-Skips (Xbox-Dimensionen, P-05). Neue Server-Features bitte mit
  GameTest ausstatten — die Harness (`GameTestSupport`) kann Mock-Player MIT
  Payload-Channels, Day-Set, Codec-Roundtrips und Death-Counter.
- **Python-Gates** (alle grün seit WAVE10): `tools/photon/fxlib.py validate --lint`
  (+ `--gen-diff`), `tools/repass_cutscenes.py`, `tools/music/validate_oggs.py`,
  `scripts/p4_balance_check.py` (braucht `run/config/eclipse` ODER läuft im
  Source-Shape-Modus).
- **Live-Verifikation** — unverändert `runServer` + RCON bzw. `runClient` (llvmpipe).
