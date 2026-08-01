# WAVE5 Team A — Abnahme-Augen & Boss-Punktuation (F-105 A) — Report

Charter: `WAVE5_PLAN.md` §3. Mission: die zwei nicht-fotografierbaren Welle-4-Effekte
dauerhaft abnehmbar machen (A1 wakehold, A2 flickerhold), den Q2-Rest schließen (A3)
und den Bosskampf-Bogen um die drei fehlenden Punktuations-Beats ergänzen
(A4 Spotlight, A5 Crescendo, A6 Monument + Resonanz). Stretch A7 (`/eclipsefx holds`)
wurde mitgebaut.

**Status: A1–A7 implementiert. Gates grün** (compileJava + processResources
BUILD SUCCESSFUL, `fxlib validate --lint` 0 NEUE Findings, Generator-Doppellauf
byte-identisch — Belege in §4).

---

## 1. Erst-Verifikation (vor jeder Codezeile)

| Item | Beweis (Zustand vor dieser Welle) | Ergebnis |
|---|---|---|
| A1 wakehold | `rg -rn "wakehold" src/main/java` → 0 Treffer (deckt sich mit Plan §2 D-1) | OFFEN |
| A2 flickerhold | `rg -n "flickerhold" src/main/java` → 0; Blackout-Logik nur in `FogTyrantRenderer.EnrageGlowLayer.desperationBlackout()` | OFFEN |
| A3 hygiene-Zeile | `rg -n "hygiene" src/…/cutscene/dev/FxDevClient.java` → 0; `PhotonBridge.hygieneDirtyScrubs()/hygieneLinksRemoved()` public static vorhanden (nur READ) | OFFEN |
| A4 Spotlight | `rg -n "w5a-spotlight\|MarkSpotlight" src/main/java` → 0; Herald-Gaze telegrafiert nur opferprivat (Vignette+Heartbeat), Ferryman-Gaze nur Vignette+Bell | OFFEN |
| A5 Crescendo | `rg -n "w5a-crescendo\|Crescendo" src/main/java` → 0; `WARDEN_HEARTBEAT` nur im opferprivaten Herald-Gaze-Plumbing | OFFEN |
| A6 Monument | `rg -n "w5a-trophy\|TrophyMonument" src/main/java` → 0; `EclipseWorldState` kennt NUR `heraldDefeated`/`ferrymanDefeated` (Warden/Tyrant flaggenlos — siehe §3 A6) | OFFEN |
| A7 holds | `rg -n "\"holds\"" src/…/FxDevCommands.java` → 0; ACTION-Ids 12/13/14 in `FxDevPayloads` frei (höchste war 11) | OFFEN |

---

## 2. Was gebaut wurde (Dateien)

Nur Team-A-Ownership (§3-Matrix), additive Diffs mit `// WAVE5 (F-105 A)`-Hooks:

- `cutscene/dev/FxDevPayloads.java` — ACTION-Ids 12 (`ACTION_LIMBO_WAKEHOLD`),
  13 (`ACTION_TYRANT_FLICKERHOLD`), 14 (`ACTION_HOLDS_STATUS`).
- `cutscene/dev/FxDevCommands.java` — Leaves `limbo wakehold on|off`,
  `tyrant flickerhold on|off|blackout`, `holds`; drei Handbook-Doc-Einträge
  (Lang-Keys via Langdrop, s. u.).
- `cutscene/dev/FxDevClient.java` — Handler 12/13/14; A3-hygiene-Zeile in
  `photonStatus()`; streakhold-Spiegel `limboStreakHoldOn` (A7, `LimboSpecialEffects`
  hat keinen Getter und ist Team-B-Zone); Logout-Hygiene cleart wakehold +
  flickerhold + Spiegel.
- `client/entity/DeckhandRenderer.java` — A1-Hold (statisch, volatile), Hold-Branch in
  `preRender` NACH dem Live-Pfad, `spawnHeldWake` (10t-Throttle je Rower),
  `spawnGhostWake`-Overload mit explizitem `reduced`-Parameter.
- `entity/DeckhandEntity.java` — A1-Bookkeeping `clientWakeHoldFiredAt`/`clientWakeHoldCount`
  (getrennt vom Live-`clientSplashCycle`).
- `client/entity/fogboss/FogTyrantRenderer.java` — A2-Hold-Tristate (0=off/1=cadence/
  2=blackout), Hold-Branch am Kopf von `desperationBlackout()`, `HOLD_CADENCE_DARK_TICKS=20`.
- `entity/boss/HeraldEntity.java` — A4-Spotlight in `tickGaze` (20t), A5-Crescendo in
  `tickFight`, A6-Monument in `shatter()` + geteilter Placement-Walk
  `placeMonumentBlock` (public static, Host für alle vier Tode).
- `entity/boss/FerrymanEntity.java` — A4-Spotlight im Gaze-Tick (20t), A5-Crescendo in
  `tickFight`, A6-Soul-Laterne am Heck beim finalen Bell-Toll.
- `entity/boss/rift/RiftWardenEntity.java` — A5-Crescendo + verdoppelte Wand-Kadenz an
  der `particleWall`-Callsite, A6-Monument in `implode()`.
- `entity/boss/fog/FogTyrantEntity.java` — A5-Crescendo + verdoppelte Wand-Kadenz an
  der `particleWall`-Callsite, A6-Monument am Removal-Keyframe.
- NEU `veilfx/Wave5BossFxRows.java` — vier WINDOWED-Loop-Rows + `TrophyWisp`-Fenster
  (Hysterese 28/36, Retry 40t, reducedFx-Release, Dimension-Gates je Boss).
- NEU `tools/photon/wave5_boss_fx.py` + `assets/eclipse/fx/wave5_trophy_wisp.{fx,fxproj}`.
- NEU `docs/plans_v3/langdrop/WAVE5A.json` — 3 Doc-Keys en+de paritätisch
  (`dev.eclipse.doc.fx.limbo.wakehold` / `…fx.tyrant.flickerhold` / `…fx.holds`).
  `merge_langdrops.py` NICHT gelaufen (zentraler Merge in der Abnahme).

`RiftAnchor.java`/`FogTyrantArena.java` blieben unangetastet — die A5-Wand-Verdopplung
sitzt per Plan §3 an den Callsites (`this.tickCount % wallInterval` statt `% 8`).

---

## 3. Umsetzung + Design-Entscheidungen je Item

### A1 `/eclipsefx limbo wakehold on|off` (ACTION 12)

- **Mechanik**: Client-Hold statisch im `DeckhandRenderer` (flashhold-Präzedenz).
  Solange ON, feuert JEDER sichtbare (= gerenderte) Rower in `preRender` throttled alle
  10t Level-Zeit Splash (3× `SPLASH`) + Ghost-Wake an seinem gemessenen Blatt-Tip nach —
  anker-UNABHÄNGIG (läuft auch, wenn `clientRowResetAt` noch `Long.MIN_VALUE` ist, der
  C2-R2-Anker also noch nicht gegriffen hat).
- **Einziger Konsument / restlose Restauration** (Akzeptanzkriterium): der Hold-Branch
  liegt ADDITIV hinter dem unveränderten Live-Pfad und hält sein eigenes Bookkeeping
  (`clientWakeHoldFiredAt/-Count`) — der Live-Dedup-Zustand `clientSplashCycle` wird nie
  berührt, `off` hinterlässt null Residuen, `[c2-splash]` läuft unverändert weiter.
- **reducedFx-Override**: `spawnGhostWake`-Overload mit `reduced=false` — voller
  Fleck-Count auch unter reducedFx (expliziter Operator-Override, streakhold-Präzedenz);
  der Live-Pfad ruft den bestehenden Einstieg mit `EclipseClientConfig.reducedFx()` auf.
- **Sonde**: `[w5a-wakehold] rower <id> re-fired: gameTime <t> count <n>` (DEBUG, ≤1/10t
  je Rower). Logout cleart den Hold (`FxDevClient.onLoggingOut`).

### A2 `/eclipsefx tyrant flickerhold on|off|blackout` (ACTION 13)

- **Mechanik**: Tristate-Hold statisch im `FogTyrantRenderer`. Hold-Branch am KOPF von
  `desperationBlackout()`: `blackout` ⇒ konstant `true` (Emissive-Pass dauerhaft dunkel,
  Krone/Auge/Core aus — fotografierbar), `on` ⇒ gestreckte 20t-an/20t-aus-Kadenz über
  `floorMod(gameTime, 40) < 20` (llvmpipe-fangbar), phasen-unabhängig und auch unter
  reducedFx wirksam (Operator-Override).
- **Bit-identische Restauration**: `off` fällt durch in den unveränderten Live-Zweig
  (Phase-3-Gate, `isCoreLit`, `deathTime`, reducedFx-Standdown, GameTime-Hash-Schedule) —
  am Live-Code wurde keine Zeile verändert, der Hold-Branch ist der einzige Konsument.
- **Sonde**: `[w5a-flickerhold] hold <alt> -> <neu> (0=off 1=cadence 2=blackout)` loggt
  jeden Zustandswechsel. Logout cleart.

### A3 hygiene-Zeile (Q2-Closeout)

Eine Zeile in `FxDevClient.photonStatus()`: `hygiene: scrubs=<n> links=<n>` über die
vorhandenen public Accessors `PhotonBridge.hygieneDirtyScrubs()/hygieneLinksRemoved()`.
`PhotonBridge.java` byte-unangetastet; `FxDevClient` ist Client-Klasse ⇒ kein
Dist-Crash-Risiko auf dem Dedicated Server (das W4-Streichungs-Problem).

### A4 Marked-Player-Spotlight

Dünne END_ROD-Säule (9 Partikel, ~2 Blöcke) serverseitig am Gaze-Opfer, alle 20t, für
ALLE sichtbar (das Mark selbst bleibt opferprivat) — Hooks: `HeraldEntity.tickGaze`
(Charge-Fenster, `gazeChargeTimer % 20`) und Ferryman-Gaze-Tick (`gazeTicksLeft % 20`,
ganze Mark-Dauer — der Ferryman-Mark ist ein Jagd-Fenster, kein Charge). END_ROD lebt
~1 s und wird sekündlich nachgefüttert ⇒ statisch fotografierbar. Sonde
`[w5a-spotlight] <victim> <boss>` (max. 1 Zeile/s, Kadenz = Throttle).

### A5 Sub-10%-HP-Herzschlag-Crescendo (alle 4 Bosse)

- Unter 10 % HP hört JEDER lebende Participant den `WARDEN_HEARTBEAT` (private
  Sound-Packets — Herald über sein bestehendes `sendPrivateHeartbeat`-Plumbing, jetzt
  ausgefächert; die anderen drei mit identischem Packet-Idiom 1.2F/0.8F).
- Kadenz HP-gestaffelt: ≤10 % → 30t, ≤6,66 % → 20t, ≤3,33 % → 12t. Throttle über
  `lastCrescendoTick`-Marke (das `DEFLECT_CUE_INTERVAL_TICKS`-Muster), transient.
- Arena-Wand-Kadenz im selben Fenster verdoppelt (8t → 4t) an den
  `RiftAnchor.particleWall`/`FogTyrantArena.particleWall`-Callsites (visual-only,
  gleiche Partikel-Budget-Größe pro Call). Herald/Ferryman haben keine Partikel-Wand —
  dort trägt der Heartbeat allein (Plan §3: Wand nur Warden/Tyrant).
- Hook-Punkt einheitlich direkt nach den Reset-/Wipe-Checks in `tickFight` ⇒ feuert auch
  während Stagger-/Rooted-Fenstern (genau dann ist das Kill-Window offen), nie während
  Reset/Wipe. Sonde `[w5a-crescendo] <boss> hp=<f> cadence=<t>` (1 Zeile/Puls).

### A6 Trophäen-Monument + Resonanz

- **Blöcke/Orte** (Plan §3): Herald Amethyst-Cluster am Dais-Zentrum (`shatter()`),
  Rift-Warden Obsidian+End-Rod am Ring-Zentrum (`implode()`), Tyrant Lightning-Rod am
  Lair-Zentrum (Removal-Keyframe, NACH dem Reward-Chest-Walk), Ferryman Soul-Laterne am
  Heck `(STERN_X, deckY+1, 0)` beim finalen Bell-Toll — schiffs-relativ deterministisch,
  übersteht `restoreShip` (sweept nur Wasser).
- **Genau-eins-Garantie**: geteilter Placement-Walk `HeraldEntity.placeMonumentBlock`
  (public static; alle vier Tode — sämtlich Team-A-Dateien — teilen ihn): erst
  Dedup-Scan über den 5er-Kandidatenring `{0,0},{±2,0},{0,±2}` (steht das Monument
  irgendwo im Ring ⇒ Skip mit Log), dann erste Air-Zelle mit `canSurvive` (Support-
  Check). Der Ring existiert, weil Heralds Dais-Zentrum auf der Altar-Achse liegt und
  der Tyrant-Chest im Einzelfall die Mitte nehmen kann.
- **Flag-Gates**: Herald/Ferryman gaten auf die `EclipseWorldState`-Defeat-Flags (in
  `die()` gesetzt, das Monument kommt später im Skript ⇒ Gate erfüllt). **Design-
  Entscheidung**: Warden/Tyrant HABEN keine Defeat-Flags (per rg verifiziert, §1), und
  `EclipseWorldState` ist keine Team-A-Datei — deren Dedup ist deshalb rein räumlich
  (Kandidatenring-Scan), was die Genau-eins-Semantik am selben Ort identisch erfüllt
  (Vault-/Lair-Kämpfe sind per-Site; ein Kill an einem ANDEREN Ort hinterlässt bewusst
  ein eigenes Monument).
- **Sonde**: `[w5a-trophy] <boss>: <block> placed at <x, y, z>` bzw. `…already stands…`
  / `…placement skipped (air-check)` — INFO (einmaliges Lifecycle-Event im Stil der
  umgebenden Death-Logs; landet in debug.log UND latest.log, die Koordinaten füttern
  den `execute if block`-Check).
- **Resonanz (optional, gebaut)**: `wave5_trophy_wisp` — EIN geteiltes Asset (fxlib-
  Generator `tools/photon/wave5_boss_fx.py`, uuid5-deterministisch, `.fxproj`-Sibling),
  zwei Emitter (Wisp-Orbit + Atem-Halo, ≤8 live Partikel), GLI-Palette, dunkle
  Birth-Tints (V2.1), HDR ≤ 1.45, CullBox, looping + prewarm 70. VIER Loop-Rows/Anchor-
  Ids (`FxCues.cue("wave5_trophy_<boss>")`, beidseitig re-deriviert — `FxCues.java`
  unangetastet), weil `ensureLoop` genau EINEN Loop je logischer Id verwaltet.
  Die Tode publizieren den Anker via `FxAnchors.set` (FROZEN-API, nur benutzt) auf dem
  Cap-Block; `Wave5BossFxRows.TrophyWisp` fenstert die Loops (Hysterese 28/36, Retry
  40t nach `NetherPitPlume`-Muster, `reducedFx` skippt komplett, Quasar-Leg `null` —
  legal für NEUE Cues, Baseline ist das Monument selbst). **Scope-Ehrlichkeit**:
  `FxAnchors` ist transient und dimensionslos ⇒ der Wisp ist ein Server-Session-Schmuck
  über dem PERSISTENTEN Block, und jedes Fenster gatet zusätzlich auf die Boss-Dimension
  (Ferryman: Limbo/Arena; die drei anderen: Overworld), damit ein Limbo-Anker nie bei
  gleichen Koordinaten im Overworld geistert.

### A7 `/eclipsefx holds` (ACTION 14, Stretch)

Reine Lese-Übersicht der vier Holds im Client-Chat: flashhold via vorhandenem
`StormFlashDevHold`-Getter (Team-B-Datei, NUR gelesen), wakehold/flickerhold via eigener
Getter, streakhold via `FxDevClient`-eigenem Spiegel (`LimboSpecialEffects` hat keinen
Getter und gehört Team B — Spiegel wird bei `limboStreakHold`-Kommandos und Logout
synchron gehalten). Abnahme-Protokoll §7 nutzt das Kommando als Hold-Restprüfung.

---

## 4. Gate-Belege

| Gate | Ergebnis |
|---|---|
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** (einzige Warnungen: das vorbestehende `EventBusSubscriber.Bus`-Deprecation-Muster, das auch `FxPayloads`/`SmallCueFxRows` tragen) |
| `… processResources --offline` | **BUILD SUCCESSFUL** |
| `python3 tools/photon/fxlib.py validate --lint` | `lint: 289 file(s), 0 NEW error/warn, 27 grandfathered, 149 advisory info` — **0 NEUE Findings** (auch kein neues LINT-PALETTE: Wisp sitzt auf GLI-Tokens) |
| Doppellauf byte-identisch | 2× `python3 tools/photon/wave5_boss_fx.py` ⇒ sha256 `.fx` `ed16bc81…` und `.fxproj` `b7db58b0…` beide Läufe identisch |
| `.fxproj`-Sibling | committed (`wave5_trophy_wisp.fxproj`) |
| Langdrop | `WAVE5A.json` en+de paritätisch (3 Keys), python-json-valide; NICHT gemerged |

---

## 5. RCON-Abnahme-Drehbuch (Hauptagent, llvmpipe)

Vorbedingungen: frische Client-JVM (F-103), Spieler `Dev` eingeloggt, Rower stehen auf
dem Geisterschiff in Limbo, nach `.fx`-Merge einmal `/photon_client clear_client_fx_cache`
+ `F3+T`. Sonden-Greps laufen auf `run/logs/debug.log`. Nach jedem Block: `tick rate 20`
restaurieren, Mobs aufräumen, am Ende `execute as Dev run eclipsefx holds` (alles off).

**A1 wakehold** (zuerst — Werkzeug für alles Weitere):
```
eclipse tp_limbo Dev                        # aufs Geisterschiff, Kamera auf die Ruderbank
execute as Dev run eclipsefx limbo wakehold on
tick rate 2                                 # Fotopunkt: Soul-Driftlinie + Splash an >=1 Ruderblatt (binnen 30 s)
rg -c "\[w5a-wakehold\]" run/logs/debug.log # 2x im Abstand ~30 s: Zahl wächst
execute as Dev run eclipsefx limbo wakehold off
rg -c "\[w5a-wakehold\]" run/logs/debug.log # 60 s warten: Zahl friert ein
rg -c "\[c2-splash\]" run/logs/debug.log    # wächst weiter (Live-60t-Pfad unangetastet — Akzeptanzkriterium)
```

**A2 flickerhold**:
```
summon eclipse:fog_tyrant ~10 ~ ~
execute as Dev run eclipsefx tyrant flickerhold blackout   # Foto: Krone/Auge/Core DUNKEL
execute as Dev run eclipsefx tyrant flickerhold on         # tick rate 2: 20t-an/aus-Wechsel fangbar
execute as Dev run eclipsefx tyrant flickerhold off        # Foto: Glow zurück
rg "\[w5a-flickerhold\]" run/logs/latest.log               # Client-Log: jeder Wechsel geloggt
# Gegenprobe: Phase 1 + hold off => kein Flicker (W4-Verhalten erhalten)
```

**A3 hygiene**: `execute as Dev at Dev run dev photon status` → Chat enthält
`hygiene: scrubs=<n> links=<n>` (gesund 0/0); Dedicated-Boot blieb crash-frei.

**A4 Spotlight**: Herald am Altar summonen (bzw. `eclipse:ferryman`), P3 abwarten bzw.
per `damage` drücken, Gaze abwarten →
`rg "\[w5a-spotlight\]" run/logs/debug.log` ≥1; Foto: statische END_ROD-Säule über `Dev`.

**A5 Crescendo** (je Boss, exemplarisch Tyrant):
```
data get entity @e[type=eclipse:fog_tyrant,limit=1] Health
damage @e[type=eclipse:fog_tyrant,limit=1] <auf ~9%/6%/3% druecken>
rg "\[w5a-crescendo\] tyrant" run/logs/debug.log   # Kadenz 30->20->12t via Zeitstempel-Deltas
# Fotopaar Arena-Wand vor/nach dem 10%-Fenster: sichtbar dichter (8t->4t)
```

**A6 Monument** (je Boss töten, dann):
```
rg "\[w5a-trophy\]" run/logs/debug.log             # liefert die exakten <x y z> je Boss
execute if block <x y z> minecraft:amethyst_cluster   # Herald  => pass
execute if block <x y z> minecraft:end_rod            # Warden-Cap (Obsidian darunter) => pass
execute if block <x y z> minecraft:lightning_rod      # Tyrant  => pass
execute if block <x y z> minecraft:soul_lantern       # Ferryman (Heck) => pass
# Re-Summon + Re-Kill => rg zeigt "already stands", if block weiterhin GENAU EIN pass
# Wisp: nah ans Monument (<28 Bloecke) => leiser Orbit+Halo; reducedFx on => Loop weg
```

**A7 holds**: `execute as Dev run eclipsefx holds` → vier Zeilen
flashhold/streakhold/wakehold/flickerhold mit aktuellem Zustand; nach Relog alles off.

## A6 Re-Kill-Dedup — Live-Abnahme-Fund + Fix

**Fund (Live-Abnahme, dedicated):** Tyrant-Re-Kill stapelte einen ZWEITEN Lightning Rod —
`if block` pass bei (110,80,100) UND (110,81,100), kein "already stands"-Log. Der re-summonte
Tyrant stand AUF dem alten Rod, sein snapToFloor-Center lag dadurch bei y=81 statt y=80.

**Root Cause:** Der Dedup-Scan in `HeraldEntity.placeMonumentBlock` prüfte je Ring-Kandidat
NUR die exakte center-Y-Ebene; ein Alt-Monument ±1..2 Blöcke darüber/darunter war unsichtbar.

**Fix (F-105):** Der Dedup-Scan prüft je Ring-Kandidat jetzt ein vertikales Band y-2..y+2
(y+1/+2 deckt Boss-steht-auf-Monument, y-1/-2 Boden-/Dais-Varianz). Log-Zeile und
Rückgabevertrag (BlockPos stehend/frisch, null ohne Kandidat) unverändert.

**Placement-Phase unverändert:** Frische Monumente entstehen weiterhin nur auf center-Y der
Ring-Kandidaten — das Band weitet nur die Sichtbarkeit des Dedup, nicht die Platzierungsorte;
der Warden-End-Rod-Cap (separater Block über dem Obsidian) bleibt vom Dedup unberührt.
