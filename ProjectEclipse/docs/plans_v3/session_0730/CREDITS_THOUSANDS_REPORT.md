# CREDITS_THOUSANDS_REPORT — F-102 TEAM D „Credits-Tausende"

**Mission**: „Die Finale Scene bei den Credits muss noch krasser werden. Mehr Block Displays
ich will wirklich dass da hunderte bis tausende fliegen. […] Ich will dass man auch noch
sieht wie die Insel in der Mitte und der Altar zerspringen in tausende Teile und wie am
Himmel sich alles zusammenzieht und die Eclipse langsam verschwindet."

**Ergebnis in einem Satz**: Alle großen Display-Populationen der Credits hängen jetzt an
einer zentralen **Display-Budget-Leiter** (`CreditsDisplayBudget`, Tiers
`verify`/`standard`/`epic` — Config + `/dev credits tier`); der Insel-Shatter zersplittert
über Mehr-Schichten-Sampling in bis zu **~4.600 Teile** (EPIC), das Schwarzloch-Finale
peakt bei **~5.100 gleichzeitigen Displays** (EPIC), am Himmel ziehen **Sky-Drain-Ströme**
alles in das Loch und die Eclipse **dimmt als eigener Beat weg** (Intensity-Rückbau +
`credits5_skydrain`/`credits5_lastlight`-Veils + Maw-Refire-Stopp) — bei gestaffeltem
Spawn UND gestaffeltem Despawn, ohne einen einzigen Tausender-Tick.

---

## 1. PLAN — Akt-/Beat-Timeline und Ist-Counts (vor F-102)

`t` = Server-Ticks seit `CreditsSequence.begin()` (Konstanten in `CreditsSequence`).

| Akt / Beat | Ticks | Display-Counts VOR F-102 (fix, ein Tier) |
|---|---|---|
| Begin: Fade schwarz, Verstecken, Beach-Stamp | 0 | 0 |
| Shatter-Vantage (Spieler geparkt) | 40 | 0 |
| Vorriss (credits3_precrack) | 70 | 0 |
| **Insel+Altar-Shatter** (Drift bis 580) | 120–580 | 1.400 Samples + 420 Splitter = **1.820** @60/t |
| Shatter-Ende (Discard hinter Schwarz) | 620 | 1.820 → 0 in EINEM Tick |
| Helm-Shot (Steuerrad) | 640–860 | 1 |
| Whiteout → Portal → Epilog → Beach | 800–900 | 0 |
| **Formation-Backdrop** | 960–2.350 | **1.800** @50/t (fix) |
| Debris-Himmel (Flyer + Schatten-Pucks) | 1.020–2.350 | 288 + ~43 |
| Eclipse-Aufstieg (Shell + Corona) | 1.300–2.500 | 120 + 16 |
| Flyer/Formation-Ende | 2.370 | 2.131 → 0 in EINEM Tick |
| Burst (geschleudertes Debris) | 2.500–2.700 | 300 @25/t |
| White-Peak (alles discardet) | 2.700 | → 0 |
| Karten / Schwarz | 2.760–3.300 | 0 |
| Map-Effigy-Sampling hinter Schwarz | 3.400 | Spawn @30/t (+40/t Underside) |
| **Schwarzloch-Finale** (Tele 3.640, Reveal 3.720) | 3.640–5.020 | Akkretion **700** @48/t + Effigy **2.240** (1.300 Kruste + 160 Seams + 280 Shards + 500 Underside) = Peak **~2.940** |
| Finale-Dark → Titel → HOLD | 5.020–5.240 | HOLD-Beat: 2.940 → 0 in EINEM Tick |
| Hard-Cap (alle Arten) | — | 3.600 (statisch) |

Schwächen, die die Mission adressiert: fixe Counts (keine Verify/Epic-Skalierung), Insel
zersplittert nur in die Oberflächen-Schicht, KEIN „Himmel zieht sich zusammen"-Beat, die
Eclipse verschwindet nie lesbar (der Maw feuert bis zum Schnitt weiter), und drei Beats
discarden tausende Entities in einem einzigen Tick.

## 2. IDEEN je Schlüssel-Beat (3+ pro Beat, Wahl begründet)

### 2a. Insel+Altar-Zersplitterung
1. **GEWÄHLT — Mehr-Schichten-Strata-Sampling**: pro Säule zusätzlich bis zu 4 tiefere
   ECHTE Blöcke lesen (Wahrscheinlichkeit je Schicht aus dem Tier-Cap abgeleitet),
   VERIFY subsampelt stattdessen die Oberfläche. Vorteil: Block-Palette ist automatisch
   das echte Insel-/Altar-Material, skaliert 220 → 1.900 → 3.200 Samples ohne neue
   Choreo (die 3-Klassen-Muster + Impuls-Tumble + Core-Break bleiben unangetastet).
2. Voxel-Subdivision (jeder Block in 8 Achtel-Displays) — verworfen: verdoppelt+ die
   Entity-Zahl ohne neue Silhouette, Sub-Skalen flimmern auf llvmpipe, Identity-Overlay
   (Pixel-Perfekt-Start) ginge verloren.
3. Eigene „Nachbrösel"-Population (Sekundär-Splitter platzen von Brocken ab) —
   teilverworfen: der vorhandene Splitter-Schauer wird stattdessen über `splinterCap`
   mitskaliert (70/700/1.400); eine dritte Population brächte Choreo-Komplexität ohne
   eigenen Look.
4. Debris-Gürtel-Ring um die Insel — verworfen: liest sich als NEUES Objekt statt als
   „die Insel zerspringt".

### 2b. Schwarzloch-Verschlingen dichter
1. **GEWÄHLT — Akkretions-COUNT auf der Leiter** (180/900/1.600) + adaptiver
   `dopplerStride` (Helligkeits-Refresh-Budget bleibt über die Leiter flach) — mehr
   gleichzeitige Terrain-Spiralen, Recycling hält den Live-Count konstant.
2. **GEWÄHLT — Sky-Drain-Ströme** als ZWEITE Population (60/260/520, 8er-Ströme,
   eigene reine Pose-Funktion): hoch am Dom geboren, curlen einwärts und gießen sich
   ins Loch — erfüllt wörtlich „wie am Himmel sich alles zusammenzieht".
3. Zweite Disc-Ebene senkrecht (Polar-Ring) — verworfen: verdeckt die Jet-Achse der
   Map-Rip-Shreds und konkurriert mit der Effigy-Lesbarkeit.
4. Größere Cluster (6 → 12 Mitglieder) — verworfen: weniger Cluster = weniger
   Abriss-Events, die Gulp-Synchronisation (F-090) würde dünner.

### 2c. Map-Zerreißen (Effigy)
1. **GEWÄHLT — LOD-Basis-Steps je Tier** (10/16 → 6/10 → 5/9): feineres Gitter = mehr
   Zellen (420/1.300/1.700) über den vorhandenen „widen-until-fits"-Mechanismus, NULL
   Choreo-Änderung (Platten/Wellen/Jets arbeiten auf Zell-Listen beliebiger Dichte).
2. **GEWÄHLT — Pools je Tier** (Seams 60/160/220, Shards 80/280/420, Underside
   140/500/640) — die Riss-/Struktur-Dichte skaliert mit der Kruste mit.
3. Zweite Bedrock-Tiefenschicht — verworfen: hinter der ersten kaum sichtbar, kostet
   ~1.000 Displays für nichts.
4. Mehr Tektonik-Platten (40 → 64) — verworfen: `PLATE_COUNT` steckt in der
   F-093-verifizierten Voronoi-/Wellen-Choreo (verifizierte Beats nicht anfassen).

### 2d. Himmel-Kontraktion + Eclipse-Verschwinden (neuer Beat)
1. **GEWÄHLT — SPACE-Intensity-RÜCKBAU** als Spiegel der sechsstufigen Ergrauen-Kurve
   (`ECLIPSE_FADE_AT` 1140/1220/1290 nach Reveal, Intensitäten 0.8/0.45/0.12, lange
   überlappende Client-Ramps): Loch/Eclipse dimmt sichtbar weg — über den GESHIPPTEN
   `S2CCreditsSkyPayload` (kein Wire-Format-Touch).
2. **GEWÄHLT — Maw-Refire-Stopp** bei Reveal+1050: der ~340t-One-Shot stirbt genau aus,
   wenn der Fade den Himmel runternimmt (letzter lebender Maw ≈ 1240).
3. **GEWÄHLT — `credits5_skydrain`-Veil** (Streak-Fäden + Flüster-Haze vom 57–88er-Dom
   einwärts) alle 150t über Reveal+560..1220 + **`credits5_lastlight`** (EIN gedimmtes
   Abschieds-Flare + ausatmender Halo) bei Reveal+1270 — 30t vor dem Dark-Melt.
4. Shader-Umbau `black_hole.fsh` (Horizon-Shrink-Uniform) — VERWORFEN: der C5-Fix der
   glsl-Prozessor-NPE darf nicht riskiert werden, und der Intensity-Rückbau erreicht
   die identische Optik über den bestehenden, verifizierten Pfad. Der Shader wurde
   NICHT angefasst.
5. Beach-Eclipse-Sphere schrumpfen — verworfen: die Finale-Eclipse IST der Sky/Post-
   Pass, nicht die (längst discardete) Beach-Kugel; falscher Akt.

## 3. IMPLEMENTIERT

### 3a. Display-Budget-Leiter (`ritual/CreditsDisplayBudget.java`, NEU)
- `Tier`-Enum `VERIFY`/`STANDARD`/`EPIC` + immutabler `Snapshot`-Record (15 Werte:
  Hard-Cap, Shatter-Caps+Rate, Formation-Cap, Akkretion-Count+Rate, Sky-Drain-Count,
  Rip-Kruste/Pools/LOD-Steps).
- **Auswahl**: Common-Config `eclipse-credits-budget.toml` (`displayTier`, Default
  `standard`; Selbst-Registrierung nach `CreditsConfig`-Muster) ODER Laufzeit-Override
  `/dev credits tier <verify|standard|epic>` (Brigadier-Merge in den bestehenden
  `/dev credits`-Baum, `DevCommandDoc` `credits.tier` vor dem Registry-Freeze
  registriert; Doc-/Feedback-Keys via Langdrop `CREDITS3.json`).
- Der Tier wird bei `begin()` EINMAL gesnapshottet (deterministische Pose-Funktionen
  dürfen nie wechselnde Counts sehen); Wechsel wirken ab dem nächsten Start.
- Das Hard-Cap kommt jetzt AUS der Leiter (`capReached` liest
  `Run.budget.displayHardCap()`): 1.400 / 4.400 / 7.000.

### 3b. Insel+Altar-Shatter (`CreditsShatterAct`)
- Caps/Rate als Instanzfelder vom Snapshot; Mehr-Schichten-Sampling (bis 4 Strata,
  Keep-Wahrscheinlichkeit `clamp(density−(d−1))` mit `density = cap/700 − 1`); VERIFY
  subsampelt Nicht-Kern-Säulen per Hash — der Altar-Kern behält IMMER sein Herz (der
  `CORE_BREAK_TICK`-Flash braucht einen Körper).
- Splitter-Schauer skaliert mit (`min(splinterCap, samples/2)`).
- Pushes jetzt **phasen-gesliced**: `animate` läuft jeden Tick und schiebt 1/10 des
  Felds (jedes Fragment weiterhin alle 10t mit 10t-Interpolationsfenster — client-seitig
  identische Pfade, nur segment-phasenversetzt).

### 3c. Schwarzloch (`CreditsBlackHoleAct`)
- Akkretion `count`/`spawnPerTick` vom Snapshot, `dopplerStride` adaptiv
  (`max(4, count/200)` — ~200–225 Cache-Checks/Push über alle Tiers, NBT-Writes nur
  bei geänderten quantisierten Werten).
- **Sky-Drain-Ströme** (NEU): ab Akt-Tick 620 (= Reveal+540) spawnt die zweite
  Population aus der GETEILTEN Tick-Allowance (nie beide Populationen über Budget in
  einem Tick); 8er-Ströme auf 240–390t-Zyklen, Perlen-Stagger 11t, curlen einwärts,
  Stretch über die letzten 30 %, Grow-in/Drain/Wind-down-Envelopes + globales
  50t-Arm-in (mid-shot-Spawn poppt nie). Gleicher Tag, gleiche Discard-Pfade, gleiche
  Stateless-Pose-Gesetze; keine Doppler-/Heat-NBT-Kosten (dunkle Silhouetten by design).
- `spawnRemaining(actTick)` deckt beide Populationen.

### 3d. Map-Rip (`CreditsMapRipAct`)
- `cellCap`/`seamPool`/`shardPool`/`undersidePool`/`stepNear`/`stepFar` vom Snapshot;
  Seam-Arrays dynamisch alloziert; LOD-Widening startet auf den Tier-Steps.
- Choreo (Fronten, Platten, Wellen, Jets, Deep-Rip) unverändert — nur Dichte.

### 3e. Sequenz (`CreditsSequence`)
- Budget-Snapshot in `Run`, an alle `prepare()` durchgereicht; Formation-Cap wird
  SEQUENZ-SEITIG gegated (Batches stoppen nach `ceil(cap/rate)` Aufrufen — VERIFY 300
  von 1.800; `CreditsFormationAct` selbst nur um `discardInto` ergänzt).
- **Gestaffelter Despawn** (NEU): `DISCARD_QUEUE` + `drainDiscardQueue()` am Tick-Anfang
  (max **150 Discards/t**, läuft auch ohne Run weiter); Acts übergeben per
  `discardInto(sink)`. Scripted-Pfade gestaffelt: Shatter-Ende (620, hinter Schwarz),
  Formation-Ende (2.370, auf Scale-Floor geschrumpft), HOLD-Beat (5.240, hinter
  Schwarz). Abort-Pfade (`skip`/`endEvent`/`forceClearNow`) **flushen sofort**;
  `ServerStopped` leert die Queue (Disk-Strays fängt der Join-Sweep).
- **Eclipse-Verschwinden**: Fade-Steps (1140/1220/1290 → 0.8/0.45/0.12, Ramps
  100/90/120), Maw-Refire-Stopp bei Reveal+1050, `credits5_skydrain`-Cue alle 150t über
  Reveal+560..1220, `credits5_lastlight` + leiser END_PORTAL_SPAWN-Klang bei
  Reveal+1270.
- **Push-Dephasierung**: Schwarzloch-Pushes auf Halb-Stride-Offset — Akkretions- und
  Effigy-Welle schieben NIE im selben Tick (Reveal−Tele = 80 ≡ 0 mod 10, vorher wären
  es EPIC ~5.1k NBT-Writes in einem Tick gewesen).
- FX-only-Replay `BLACKHOLE` um die F-102-Beats ergänzt (Skydrain-Sample @360,
  Intensity-Rückbau @440, Lastlight @520 — Parität fürs Rehearsal).

### 3f. Photon (`tools/photon/credits5_fx.py`, NEU) + Rows
- `credits5_skydrain.fx`: Streak-Fäden (StretchedBillboard, radial −45 Blöcke/Leben,
  0.17-rad/s-Curl, Margin gegen den r=0-Flip) + Flüster-Haze (BLEND_ALPHA, 8–12 Blöcke
  einwärts). `credits5_lastlight.fx`: 2 gedimmte Zentral-Flares + 24er-Halo (7 Blöcke
  AUSatmend) + 10 finale Ember.
- Alle House-Laws ab Werk: Einheiten rückgerechnet (linear ×0.05/t, radial ×0.01/t),
  dunkle Birth-Tints, HDR ≤ 1.45 hue-erhaltend, `random_gradient` auf allen echten
  Populationen, `arc_mode` = fxlib-Default „Random" (nie „Uniform").
- Rows in `veilfx/CreditsFinaleFxRows.java` (Photon-only, Quasar-Leg `null` — der Beat
  liest auch ohne Photon über Displays + Sky-Fade).
- **Main-Agent**: nach dem Checkout einmal `/photon_client clear_client_fx_cache`
  ausführen (Client-FX-Cache kennt die neuen Assets sonst nicht).

### 3g. Langdrop (`docs/plans_v3/langdrop/CREDITS3.json`, NEU)
`dev.eclipse.doc.credits.tier`, `dev.eclipse.credits.tier_current`,
`dev.eclipse.credits.tier_set` (en+de). Lang-JSONs wurden NICHT direkt angefasst —
der Merge läuft wie üblich über `python3 tools/merge_langdrops.py` (idempotent; bitte
vom Main-Agent mit den anderen Team-Drops zusammen fahren).

## 4. Akt-Tabelle — Counts vorher/nachher je Tier

| Akt / Population | vorher (fix) | VERIFY | STANDARD | EPIC |
|---|---|---|---|---|
| Shatter: Samples + Splitter | 1.400 + 420 = **1.820** | 220 + 70 = **290** | 1.900 + 700 = **2.600** | 3.200 + 1.400 = **4.600** |
| Shatter Spawn/t | 60 | 40 | 64 | 80 |
| Formation-Backdrop | 1.800 | **300** | 1.800 | 1.800 |
| Flyer + Schatten (unverändert) | 288 + ~43 | 288 + ~43 | 288 + ~43 | 288 + ~43 |
| Eclipse Shell/Corona/Burst (unverändert) | 120/16/300 | 120/16/300 | 120/16/300 | 120/16/300 |
| Akkretion (recycelt) | 700 | **180** | **900** | **1.600** |
| Sky-Drain-Ströme (NEU) | — | **60** | **260** | **520** |
| Akkretion+Drain Spawn/t (geteilt) | 48 | 40 | 56 | 80 |
| Effigy: Kruste + Seams + Shards + Underside | 1.300+160+280+500 = **2.240** | 420+60+80+140 = **700** | **2.240** | 1.700+220+420+640 = **2.980** |
| Effigy-LOD-Steps (nah/fern) | 6/10 | 10/16 | 6/10 | 5/9 |
| **Finale-Peak gleichzeitig** | **~2.940** | **~940** | **~3.400** | **~5.100** |
| **Beach-Peak gleichzeitig** | ~2.270 | ~770 | ~2.270 | ~2.270 |
| **Hard-Cap (Leiter)** | 3.600 | **1.400** | **4.400** | **7.000** |
| Despawn | 1-Tick-Massen-Discard | 150/t Queue | 150/t Queue | 150/t Queue |

## 5. Selbst-Iterationen (harte Eigenkritik)

### Iteration 1 — „Tick-Budget wirklich gerechnet?"
**Fund 1**: Die Akte schoben ihr GESAMTES Feld auf jedem Stride-Tick — EPIC-Shatter wären
4.600 Transform-NBT-Writes in EINEM Tick alle 10t gewesen (Amortisierung ist kein
Spike-Argument). → Shatter-Pushes phasen-gesliced (≈460/t stetig, jedes Fragment behält
sein 10t-Fenster).
**Fund 2**: Reveal−Tele = 80 ≡ 0 (mod 10) — Akkretions- UND Effigy-Welle wären auf DEN
SELBEN Ticks gelandet (EPIC ≈ 5.100 Writes/Tick). → Schwarzloch-Pushes auf
Halb-Stride-Offset: EPIC-Worst-Case jetzt ~2.980/Tick (Effigy-Welle allein) — auf dem
Niveau des VOR F-102 ausgelieferten Spikes (~2.940), Verify ~700.
**Budget-Rechnung (Transform-Writes/Tick, Worst-Window)**:
- Shatter: V 29/t · S 260/t · E 460/t (stetig, gesliced) + Spawn 40–80/t solange offen.
- Beach: Formation 1.800/14 ≈ 129/t (V: 22/t) + Flyer 288/4 = 72/t + Eclipse 136/10.
- Finale: Effigy-Welle (alle 10t) V 700 / S 2.240 / E 2.980; Schwarzloch-Welle
  (dephasiert, alle 10t) V 240 / S 1.160 / E 2.120; Doppler ~200–225 Checks/Push
  (edge-triggered Writes); Heat-/State-Swaps nur an Crossing-Kanten.
- Removal: konstant ≤150 Discards/t (EPIC-HOLD ≈ 34 Ticks Abbau hinter Schwarz).
**Fund 3**: Audit-Zahlen im Budget-Javadoc waren falsch (Shatter-EPIC 3.9k statt 4.6k,
Beach-Peaks überzählt) → korrigiert.

### Iteration 2 — „Leak-Pfade? Pop-Artefakte? Verify praktikabel?"
**Fund 1 (Optik)**: Sky-Drain spawnt MID-SHOT (sichtbar) mit gehashten Zyklus-Phasen —
ein Member bei q=0.5 wäre auf voller Skala mitten im Himmel aufgepoppt. → globales
50t-Arm-in-Envelope (deterministisch, stateless).
**Fund 2 (Removal-Regel)**: Formation-Ende discardete 1.800 Displays in einem Tick
(Alt-Verhalten, verletzt die F-102-Regel). → `discardInto` in `CreditsFormationAct`
(einzige Änderung dort) + Queue-Pfad; `discard()` bleibt der Abort-Pfad.
**Leak-Audit** (alle Pfade durchgespielt):
- Join-Sweep deckt ALLE Tags (Wheel/Flyer/Shatter/Formation/BlackHole[+Drains]/MapRip);
  Drains tragen den BlackHole-Tag.
- Queue: `skip`/`endEvent`/`forceClearNow` flushen sofort; `ServerStopped` leert
  in-memory; Disk-Strays fängt der Join-Sweep (F-084-Muster). Gequeue­te Displays
  bleiben bis zum echten Discard in `LIVE_DISPLAYS` → das Hard-Cap zählt sie korrekt.
- `beatWhitePeak`-Belt-and-Braces (`shatter.discard()` etc.) bleiben — nach
  `discardInto` sind die Act-Listen leer, die Aufrufe sind No-ops.
- Queue-Timing kollidiert nie mit Spawns: Shatter-Queue (EPIC 4.600/150 ≈ 31t) ist vor
  dem Wheel-Spawn (t=640) leer bzw. weit unter Cap; Formation-Queue (12t) leer vor dem
  Burst (2.500); HOLD-Queue läuft hinter gehaltenem Schwarz.
**Verify-Praktikabilität**: 290 Shatter-Fragmente spawnen in 8 Ticks, Effigy 700 hinter
dem Post-Card-Schwarz, Peak 940 « Cap 1.400; alle Populationen einzeln per Tag zählbar
(RCON-Skript unten); llvmpipe-Worst-Tick ≈ 700 Transform-Writes.

## 6. Gates

| Gate | Ergebnis |
|---|---|
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** (einzige Warnungen: die haus-übliche `EventBusSubscriber.Bus.MOD`-Deprecation, identisch zu `CreditsConfig`) |
| `python3 tools/photon/fxlib.py validate --lint` | **277 file(s), 0 NEW error/warn** (27 grandfathered, 149 advisory — unverändert); credits5-Assets: **0 Findings** |
| glslang | n/a — **Shader NICHT angefasst** (bewusst, siehe Idee 2d.4; kein Regressionsrisiko für den C5-NPE-Fix) |

## 7. Verifikations-Skript für den Main-Agent

**Vorbereitung** (einmalig):
1. Client: `/photon_client clear_client_fx_cache` (neue credits5-Assets).
2. Lang-Merge (optional fürs `/dev help`-Cosmetic): `python3 tools/merge_langdrops.py`.

**Verify-Tier setzen** (eine der beiden Varianten):
- Laufzeit (empfohlen): `/dev credits tier verify` → Feedback „Credits-Display-Stufe
  überschrieben: verify …". Kontrolle: `/dev credits tier` (bare) zeigt die aktive Stufe.
- Persistent: in `config/eclipse-credits-budget.toml` → `displayTier = "verify"`.

**Start**: `/dev credits start` (Log-Zeile prüfen:
`CreditsSequence: display-budget tier VERIFY (hard cap 1400)`).

**Screenshot-/Zähl-Plan** (t = Ticks seit Start; RCON zählt via
`/execute if entity @e[type=minecraft:block_display,tag=<TAG>]` — die Erfolgsmeldung
nennt die Matched-Anzahl):

| Zeitpunkt | Screenshot / Erwartete Optik | RCON-Count (VERIFY) |
|---|---|---|
| t≈70–120 (~3–6 s) | Insel-Seams GLÜHEN violett (Vorriss), dann Break-Flash + Himmel-Kollaps | — |
| t≈300 (~15 s) | Insel + Altar in Brocken/Splittern auseinandertreibend, 3 Größenklassen lesbar | `tag=eclipse_credits_shatter` → **290** |
| t≈630 (~31 s) | hinter Schwarz: Queue-Abbau | Shatter-Count fällt ~150/t auf **0** |
| t≈1.200 (~60 s) | Beach: Sonnenaufgang, Formations-Bänder + Debris-Himmel | `tag=eclipse_credits_formation` → **300**; `tag=eclipse_credits_flyer` → **288** (+~43 Schatten-Pucks im selben Tag) |
| t≈3.700 (~185 s) | Post-Card-Schwarz: Effigy fertig gebaut | `tag=eclipse_credits_maprip` → **≈700** (Pools inkl.) |
| t≈3.900 (~195 s) | Reveal: Schwarzloch frisst die Map, Akkretions-Spiralen | `tag=eclipse_credits_blackhole` → **180** |
| t≈4.400 (~220 s) | **F-102-Beat**: Sky-Drain-Fäden gießen sich vom Himmel ins Loch (Displays + credits5_skydrain-Veil) | `tag=eclipse_credits_blackhole` → **240** (180 + 60 Drains) |
| t≈4.900–5.010 (~247 s) | **F-102-Beat**: Himmel/Post dimmt sichtbar ZURÜCK (Eclipse verschwindet), Maw feuert nicht mehr nach, ein letztes gedimmtes Flare (lastlight) | — |
| t≈5.250 (~263 s) | HOLD hinter Schwarz | alle Tags fallen ~150/t auf **0**; danach `/dev end_event` |

**Schnell-Rehearsal ohne Full-Run**: `/eclipsefx sequence credits BLACKHOLE` spielt den
Finale-Beat FX-only inkl. der neuen F-102-Cues (Skydrain @t360, Intensity-Rückbau @440,
Lastlight @520) — keine Displays, kein Teleport.

**Abbruch-Sicherheit prüfen** (Leak-Gate): mitten im Shatter (t≈300)
`/dev end_event` → `/execute if entity @e[type=minecraft:block_display]` muss außer
Fremd-Displays **0** Credits-Displays melden (Sofort-Flush).

**Standard/Epic danach**: `/dev credits tier standard` bzw. `epic` und Neustart des
Runs — gleiche Zählpunkte, erwartete Counts aus der Akt-Tabelle (§4).

## 8. Commits (lokal, kein Push)

Siehe `git log` auf `cursor/project-eclipse` — Commit
`feat(f102-creditsthousands): …` enthält AUSSCHLIESSLICH:
`ritual/CreditsSequence.java`, `ritual/CreditsShatterAct.java`,
`ritual/CreditsBlackHoleAct.java`, `ritual/CreditsMapRipAct.java`,
`ritual/CreditsFormationAct.java` (nur `discardInto`),
`ritual/CreditsDisplayBudget.java` (neu), `veilfx/CreditsFinaleFxRows.java`,
`tools/photon/credits5_fx.py` (neu), `assets/eclipse/fx/credits5_*.fx/.fxproj` (neu),
`docs/plans_v3/langdrop/CREDITS3.json` (neu), dieser Report.

## 9. Offene Risiken

1. **EPIC ist unverprobtes Live-Terrain**: ~5.100 gleichzeitige Displays sind
   client-seitig Render-Last (Server-seitig budgetiert). EPIC ist bewusst NICHT der
   Default; Standard (3.400 Peak) liegt nahe am verprobten V3-Niveau (2.940).
2. **Effigy-Welle bleibt ein 10t-Burst** (EPIC ~2.980 Writes auf ihren Stride-Ticks):
   `CreditsMapRipAct.animate` hat Cross-Listen-Caches; ein Phasen-Slicing dort wäre die
   nächste Ausbaustufe, wurde aber wegen Regressionsrisiko in der F-093-verifizierten
   Choreo NICHT gemacht (Spike ≤ Alt-Niveau durch die Dephasierung).
3. **Sky-Drain-Photon-Veil vs. Kamera**: der 57–88er-Dom umschließt den FX-Anker; die
   nächste Dom-Kante kommt der Kamera (~110 Blöcke vorm Anker) auf ~22 Blöcke nah —
   identische Geometrie wie die Display-Ströme, aber auf llvmpipe im Verify-Run einmal
   gegenprüfen, dass keine Haze-Quads störend VOR der Kamera aufziehen.
4. **Langdrop noch nicht gemerged**: bis `merge_langdrops.py` läuft, zeigt
   `/dev credits tier` rohe Lang-Keys im Feedback (rein kosmetisch).
5. **Tier-Wechsel mid-run** wirkt erst ab dem nächsten `begin()` (bewusst — Snapshot-
   Invariante); ein laufender Run muss für einen Tier-Vergleich per `/dev end_event`
   beendet und neu gestartet werden.
