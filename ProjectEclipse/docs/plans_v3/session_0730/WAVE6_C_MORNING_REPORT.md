# WAVE6 — Team C „Morgen-Meta & späte Aufsteher“ — Abschlussreport

Polish-Welle 6 (F-106), Team C. Alle Deliverables C1–C7 implementiert (C7-Stretch inklusive).
Kein `git add/commit/push`, keine Server-/Client-Neustarts, keine RCON-Kommandos ausgeführt.

---

## 1. Erst-Verifikationstabelle (rg vor jeder Codezeile)

| # | Behauptung aus dem Plan | Befund im Live-Tree | Ergebnis |
|---|---|---|---|
| V1 | `RealtimeDayService.runCatchUpNow` existiert | `progression/realtime/RealtimeDayService.java` (Startup-Hook `onServerStarted` → `runCatchUpNow`; quiet-Schleife mit `lastStep`-loud-Finale, `rollingOver`-Static-Muster vorhanden) | ✅ |
| V2 | `AwardsState.latestResolvedDay()` existiert | `awards/AwardsState.java` — `latestResolvedDay()`, dazu `resolved(int)`, `hasSeenReveal`, `markRevealSeen` | ✅ |
| V3 | `SundialPlaza.onDayChanged` existiert | `worldgen/structure/SundialPlaza.java` — `onDayChanged(MinecraftServer,int,int)`, aufgerufen NUR aus `DayScheduler.setDay` (Zeile 148, auch bei quiet) | ✅ |
| V4 | `handleOffering`-exactValue-Pfad | `ritual/AltarBlockEntity.handleOffering` → `OfferingService.acceptWithValue` liefert `OptionalInt exactValue`; ALTAR_BEAM-Send folgte NACH Swallow-Payloads; `offeringTellPitch(exactValue)`-Pfad separat | ✅ |
| V5 | Junk-Grenze = `exactValue == 0` | `OfferingRules.value`: `config.junk()`-Set ⇒ 0; Tier `junk` ⇒ Basis 0 (Default-Items: u. a. `minecraft:dirt`, `cobblestone`, `stick`) | ✅ |
| V6 | Offering-Interaktion: Arm + Confirm binnen 100t | `OFFERING_CONFIRM_WINDOW_TICKS = 100L`; Sneak-Rechtsklick armt (Actionbar `ritual.eclipse.offering.confirm` + OFFERING_ARMED-Säule), zweiter Klick binnen Fenster akzeptiert | ✅ |
| V7 | `AnnouncementOverlay`-Idle-Zustand ermittelbar | Felder `QUEUE`, `typewriter`, `sweepTicks`, `cardTicks`, `pendingDayLine` tragen den kompletten Präsentationszustand | ✅ |
| V8 | `ClientStateCache` (FROZEN) liefert `dayClockDay`/`questDay`/`questEntries` als lesbare Felder | öffentliche `volatile`-Felder; nur READ nötig, keine Änderung | ✅ |
| V9 | Quest-Kinds | `S2CQuestStatePayload.QuestEntry.kind`: 0=main, 1=side, 2=personal; Texte als en/de-Literale (R2) | ✅ |
| V10 | Actionbar `quest.eclipse.assigned` | `QuestEngine.ensurePlayer` (Personals-Erstzug), aufgerufen aus Login-Pfad UND aus dem Rebuild-Loop in `resolved()` | ✅ |
| V11 | Sounds | `EclipseSounds.UI_PAGE_TURN`, `UI_CAPTION_TICK`, `AWARD_STING` registriert; `UiSounds.pageTurn/typewriter/rouletteTick` vorhanden (Config-gegated) | ✅ |
| V12 | Quasar-Emitter | `S2CQuasarPayload.MAP_EXPAND_MATERIALIZE` als Konstante vorhanden (Bestands-Emitter) | ✅ |
| V13 | `BeamEmitter`-API | `emit(ServerLevel, BlockPos)` — ein Burst pro Aufruf, 512-Block-Empfängerkreis; „5-s-Säule“ = wiederholte Emits (Bestandsidiom: alle paar Ticks) | ✅ |
| V14 | `TimelineService.dayTitleKey` READ-only | `dayTitleKey(int, ServerPlayer)` — receiver-lokalisiert (Literal ODER generischer Lang-Key) | ✅ |
| V15 | Registrar-Muster | `BestiaryPayloads` NICHT am erwarteten Ort; identisches Muster in `network/credits/CreditsPayloads.java` (eigener MOD-Bus-Registrar, Consumer-Seams, dist-neutral) — als Vorlage verwendet | ✅ (Abweichung dokumentiert) |
| V16 | `/eclipse schedule next +2m` | `EclipseCommands` → `schedule next <spec greedy>` → `PhaseScheduler.scheduleNext` → `RealtimeMath.parseSpec` (`+NhNNm[NNs]`, absolute Formen) — `+2m` ist gültig | ✅ |
| V17 | `/dev phase`-Syntax | `dev phase status \| interval hours <n> \| interval minutes <1..10080> \| daily \| next` (perm 2); `next` = `RealtimeDayService.advancePhaseNow` (louder Einzeltag) | ✅ |
| V18 | `/eclipse-rt` | `arm \| disarm \| pause \| resume \| add <spec> \| set <spec> \| status`; `set` verlangt Zukunft (kein „Boundary in die Vergangenheit“-Trick — Catch-up-Abnahme braucht den Restart-Weg) | ✅ |
| V19 | Awards-Kommandos | `/eclipse-awards preview [day] \| resolve [day] \| send \| reroll [day]` (perm 2) | ✅ |
| V20 | Skill-XP-Kommando | `/dev xp add <amount> [player]` (perm 2, `SkillsApi.addXp`) | ✅ |
| V21 | DawnCeremony-Beats (read-only) | T+10 Sonnenpuls, T+20 Toll, **T+40 `AnnouncementService.onDayChanged`**, T+90 Offering, T+140 Goals, **T+200 Roulette-Send** | ✅ |
| V22 | Quiet-Tage | `DayScheduler`: quiet ⇒ KEIN `DawnCeremony.begin` ⇒ `AnnouncementService.onDayChanged` feuert bei Catch-up NUR am finalen (loud) Tag — Unlock-Keys akkumulieren im Diff | ✅ |

---

## 2. Design-Entscheidungen

### C5-Transport: NEUES kompaktes Payload (kein `recap`-Flag) — **die zentrale Entscheidung**

`network/paper/MorningPaperPayloads.java` (C-eigener Registrar, `CreditsPayloads`-Muster, Versionsgruppe `paper1`) statt additivem `recap`-Flag auf `S2CAwardRevealPayload`. Begründung:

1. **Frozen-Zone-Konflikt:** Das Reveal-Payload läuft durch den eingefrorenen Hub (`EclipsePayloads.handleAwardReveal` → `ClientStateCache.awardRevealDay/awardCategories`). Ein `recap`-Flag müsste entweder den FROZEN Cache erweitern oder am Hub vorbei einen Zweit-Handler für denselben Typ registrieren — beides verletzt Welle-6-Gesetze bzw. NeoForge-Registrierungsregeln.
2. **Datenökonomie:** Die Recap-Karte braucht weder Kandidatenlisten noch Stat-/Reward-Zeilen — nur Tag, Award-Tag, Tagestitel und anonyme Gewinner-Rows (UUIDs). Die heutigen Dekrete liest der Client aus dem Quest-Cache, den der Login-Sync ohnehin füllt (`S2CQuestStatePayload` kommt bei jedem Login).
3. **Kontraktstabilität:** Das versionierte Reveal-Payload bleibt byte-identisch für alle anderen Sender/Empfänger; das FxPayloads-fx1→fx2-Bump-Idiom wäre nur nötig gewesen, wenn wir den bestehenden Typ angefasst hätten — haben wir nicht.

### C1: Client-Render in `DecreesCard` (nicht im AwardsOverlay-Summary-Craft)

Ein eigenes self-subscribed Layer (`client/awards/DecreesCard.java`) rendert BEIDE Karten (Dekrete + Morning Paper) mit einer Phasenmaschine (TYPE → FLIP → HOLD → FADE). Trigger C1: `dayClockDay`-Flip mid-session (Grace 100t wie AwardsOverlay) armt „warte auf Quest-Sync“; sobald `questDay` nachzieht, wird die Karte aus `questEntries` gebaut (mains kind==0 typewriten, personals kind==2 mit UI_PAGE_TURN-Flip). Arm-Timeout 200t (Quest-Engine still ⇒ keine Karte, kein Deadlock).

### C1-Server: Actionbar-Degradierung über den Rebuild-Kontext

`QuestEngine.resolved()` unterscheidet jetzt DAY-Flip-Rebuilds (`current != null && current.day != day`) von Boot-/Config-/Unlock-Rebuilds: nur beim Day-Flip wird `ensurePlayer(..., announceAssigned=false)` gerufen — dort übernimmt die DecreesCard. Login (und Boot/Config-Fälle, die client-seitig KEINEN `dayClockDay`-Flip erzeugen) behalten die Actionbar als Fallback.

### C2: Azyklisches Gate-Netz

`AnnouncementOverlay.isIdle()` ist das EINE neue Cross-Overlay-Gate. Abhängigkeitskette: DecreesCard wartet auf {Letterbox, isIdle, CenterStage}; AwardsOverlay wartet auf {Letterbox, isIdle, `DecreesCard.liveOrArmed()`, CenterStage}. Kein Rückkanal DecreesCard→AwardsOverlay ⇒ kein Deadlock; der Morgen liest deterministisch Tages-Karte → Dekrete → Roulette. Der AWARD_STING spielt client-seitig am INTRO-Beat (Ende des 40t-Pre-Beats); der Server-Sting in `sendRevealNow` bleibt als Ankunfts-Cue (1-Kommentar-Note gesetzt).

### C3: Ein-Animation-Invariante + Bestands-identische Writes

Genau EINE laufende Wander-Animation; ein neuer `onDayChanged` (Catch-up-Burst!) flusht die alte erst instant zu ihrem Endzustand. Jeder Einzel-Write ist byte-identisch zum Bestandspfad (`groundMix`/`POLISHED_BASALT`), die Animation verteilt sie nur über die Zeit (16 Steps × 2t ≈ 30t: Erase innen→außen, Place außen→innen). Chunk-Entladung mid-run ⇒ Instant-Flush ohne FX (Boot-Order-Gesetz: keine Sync-Loads für Flavor). Marker-Restore schreibt den KANONISCHEN Zustand (selbstheilend statt Snapshot).

### C4: Statisches Fenster statt try/finally

`RealtimeDayService.CatchUpWindow(fromDay, toDay)` wird NACH der Catch-up-Schleife gesetzt (nur bei ≥2 Tagen) und von `AnnouncementService.onDayChanged` ~2 s später (DawnCeremony T+40) per `consumeCatchUpWindow()` einmalig abgeholt — try/finally scheidet aus, weil der Konsument asynchron NACH `runCatchUpNow` läuft (exakt das `rollingOver`-Idiom, Reset in `onServerStopped`). Digest = EIN unlock-Sweep (Subtitle per `ServerLang` gebacken) + Key-Liste 1× im Chat (Keys ohne Lang-Zeile humanisiert wie im Client-Renderer). Queue-Cap-sicher: statt Key-Parade genau 1 Sweep.

### C6: Nur die Junk-Grenze, nie der Tier

Bei `exactValue == 0`: ALTAR_BEAM wird geskippt, stattdessen SMOKE-Puffs + FIRE_EXTINGUISH (Pitch 0.6F). Swallow-Flug, PORTAL-Partikel und beide Accept-Chimes (inkl. `offeringTellPitch`-Privat-Tell) bleiben unangetastet — der Rauch verrät ausschließlich die Junk-Grenze.

### C7: gameTime-Envelope

Der „+n“-Chip lebt 12 GAME-Ticks (`level.getGameTime()` + partial), nicht 12 Client-Ticks — bei `/tick rate 2` streckt er sich auf ~6 s Realzeit (fotografierbar). Gains während der Envelope summieren in EINEN Chip; reducedFx armt ihn nie. Zusatzsonde `[w6c-xpchip] delta=<n>` (w6c-Präfix-konform; C7 hatte keine Plansonde).

---

## 3. Gate-Belege

```
$ cd /workspace/ProjectEclipse && flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain
BUILD SUCCESSFUL in 1s
2 actionable tasks: 1 executed, 1 up-to-date

$ flock /tmp/gradle.lock ./gradlew processResources --offline --console=plain
BUILD SUCCESSFUL in 576ms
```

Klassen-Nachweis (alle neuen Typen im Build-Output):
`DecreesCard.class` (+ `$Card`/`$Mode`/`$Phase`), `MorningPaperPayloads.class` (+ `$S2CMorningPaperPayload`/`$WinnerRow`), `SundialPlaza$Animation.class` — jeweils neuer als die Quelldateien.

Ressourcen wurden NICHT angefasst (Langdrop ist doc-only unter `docs/plans_v3/langdrop/WAVE6C.json`); `processResources` lief als Beleg dennoch grün.

---

## 4. RCON-Abnahme-Drehbuch

**Voraussetzungen:** Dev-Server mit DEBUG-Logging für `dev.projecteclipse` (alle `[w6c-*]`-Sonden sind `LOGGER.debug`), 1–2 Testclients, `reducedFx=false` in `config/eclipse-client.toml` (Gegentests siehe unten). Der Langdrop `WAVE6C.json` sollte vor der Abnahme in die Lang-Dateien gemerged sein, sonst rendern die neuen Keys literal (erwartetes Fallback-Verhalten, kein Fehler).

**Wichtig zu `/tick rate 2`:** Client-Overlays (C1-Typewriter, C2-Pre-Beat) ticken auf der 20-Hz-CLIENT-Uhr und werden durch die Server-Tickrate NICHT verlangsamt. `/tick rate 2` streckt dagegen C3 (Server-Task-Schedule), C6-Confirm-Fenster (100 Server-Ticks ⇒ ~50 s) und C7 (gameTime-Envelope) — dort liegen die Foto-Punkte.

### A) C1 + C2 — Rollover-Morgen (Client A online)

```
/eclipse-awards resolve            # stellt sicher, dass ein Reveal für den Vortag existiert
/dev phase next                    # louder Einzeltages-Rollover
```

Erwartete Reihenfolge auf Client A: Tages-Nummernkarte/Sweep → **DecreesCard** (Mains einzeln typewriten, dann Personals mit Page-Turn-Flips) → **40t-Dim-Curtain** mit Roulette-Tick-Count-in → AWARD_STING am INTRO-Beat → Roulette.

Erwartete Sonden (Client-Log A):
```
[w6c-decrees] day=<d> mains=<n> personal=<n>
[w6c-curtain] waited=<t>t          # t > 0, da Sweep + Dekrete vorher liefen
```

Foto-Punkte: (1) halbgetypte Main-Zeile, (2) einfliegender Personal-Flip, (3) halbtransparenter Pre-Beat-Veil OHNE Kartenrahmen, (4) INTRO-Panel-Fade unter vollem Veil.
Zusatztests: Sneak während TYPE ⇒ fertige Liste; Sneak in HOLD ⇒ dismiss. `reducedFx=true` + erneuter `/dev phase next` ⇒ fertige Liste sofort, längerer Hold, keine Count-in-Blips (Dim + Sting bleiben).

### B) C3 — Sundial-Wanderung (Spieler ≤64 Blöcke am Sanctum-Altar)

```
/tick rate 2
/eclipse day set <aktueller Tag + 1>
```

Erwartet: Erase-Schritte wandern auswärts, Place-Schritte einwärts (bei rate 2: 1 Schritt/s), pro Placement Basalt-Puff (`map_expand_materialize`) + UI_CAPTION_TICK mit steigendem Pitch (≤24 Blöcke), Finale gilded Marker-Flash + Beam-Säule (100 Server-Ticks ⇒ ~50 s bei rate 2).

```
[w6c-sundial] animated=true steps=16
```

Fallback-Gegentest: `/tp @s ~1000 ~ ~`, dann `/eclipse day set <+1>` ⇒ Instant-Pfad:
```
[w6c-sundial] animated=false steps=0
```
Danach `/tick rate 20`.

### C) C4 — Catch-up-Digest (Restart durch den Hauptagenten/Operator — Team C startet nichts neu)

```
/dev phase interval minutes 1
/eclipse-rt arm
/eclipse-rt status                 # Boundary notieren
```

Dann: **Server stoppen, ≥3 Minuten warten, Server starten** (`/eclipse-rt set` in die Vergangenheit ist bewusst unmöglich — der Restart-Weg ist der einzige echte Catch-up-Pfad).

Erwartet im Server-Log beim Start: 2× „catch-up … (quiet)“ + 1 louder Finaltag; ~2 s nach dem letzten Rollover (DawnCeremony T+40):
```
[w6c-digest] days=<x>..<y> unlocks=<n>
```
Client: EIN violett/unlock-Digest-Sweep („Tage x–y vergangen — n Siegel geöffnet“) statt Key-Parade; bei n>0 zusätzlich EINE Chat-Zeile mit der vollen, lokalisierten Key-Liste. Foto: Digest-Sweep + Chat-Zeile in einem Frame.

### D) C5 — Morning Paper (Client B offline während des Rollovers)

1. Client B ausloggen. 2. `/dev phase next` (Client A erlebt den normalen Morgen). 3. Client B einloggen.

Erwartet Server-Log:
```
[w6c-paper] player=<Name B> day=<d>
```
Client B: KEINE Roulette-Show (Late-Join-Grace), stattdessen nach ~8 s Settle die kompakte Morgenblatt-Karte: Tagestitel, „Ehrungen von Tag d−1“ (Gewinner-Rows — „DU“/„YOU“ nur beim eigenen Sieg, sonst Glitch-Shimmer), darunter die heutigen Dekrete. Foto: fertige Paper-Karte.

### E) C6 — Junk-Sniff (Interaktion: Sneak-Rechtsklick-Arm + Confirm binnen 100t!)

Client A hält **`minecraft:dirt`** (unverzaubert, unbenannt):
1. Sneak-Rechtsklick auf den Altar ⇒ Confirm-Actionbar + „Armed“-Säule.
2. Zweiter Sneak-Rechtsklick binnen 100 Server-Ticks (bei `/tick rate 2`: ~50 s Zeit — Foto-freundlich) ⇒ Item-Swallow-Flug + PORTAL-Partikel + Accept-Chimes, **KEIN Beam**, stattdessen Rauchwolke + Fire-Extinguish (tief, 0.6F).

```
[w6c-sniff] item=minecraft:dirt
```

Gegentest mit `minecraft:diamond` (nächster Tag oder zweiter Spieler — 1 Offering/Tag!): Beam wie gehabt, keine Sniff-Sonde. Foto: Rauch-Altar vs. Beam-Altar.

### F) C7 — XP-Chip

```
/tick rate 2
/dev xp add 25
```

Erwartet: „+25“ steigt vom rechten Balkenende auf und blendet über 12 GAME-Ticks (~6 s Realzeit bei rate 2) aus. Foto: Chip auf halber Höhe.
```
[w6c-xpchip] delta=25
```
Gegentest `reducedFx=true` ⇒ kein Chip. Danach `/tick rate 20`.

---

## 5. Angefasste/neue Dateien (vollständig)

**Neu (C-owned):**
- `src/main/java/dev/projecteclipse/eclipse/client/awards/DecreesCard.java` (C1 + C5-Client)
- `src/main/java/dev/projecteclipse/eclipse/network/paper/MorningPaperPayloads.java` (C5-Transport)
- `docs/plans_v3/langdrop/WAVE6C.json` (en+de paritätisch: 3 gui.decrees/paper-Blöcke, 3 digest-Keys)
- `docs/plans_v3/session_0730/WAVE6_C_MORNING_REPORT.md` (dieser Report)

**Geändert (C-owned laut Plan §5):**
- `src/main/java/dev/projecteclipse/eclipse/client/hud/AnnouncementOverlay.java` (C2: `isIdle()`)
- `src/main/java/dev/projecteclipse/eclipse/client/awards/AwardsOverlay.java` (C2: PREBEAT-Phase, Gates, Client-Sting, Sonde)
- `src/main/java/dev/projecteclipse/eclipse/progression/goals/QuestEngine.java` (C1: Actionbar-Degradierung)
- `src/main/java/dev/projecteclipse/eclipse/awards/AwardService.java` (C5: Paper-Send im Login-Pfad + Sonde; C2: Kommentar-Note in `sendRevealNow`)
- `src/main/java/dev/projecteclipse/eclipse/worldgen/structure/SundialPlaza.java` (C3: Task-Schedule-Animation + Fallback + Sonde)
- `src/main/java/dev/projecteclipse/eclipse/progression/realtime/RealtimeDayService.java` (C4: CatchUpWindow-Handoff)
- `src/main/java/dev/projecteclipse/eclipse/timeline/AnnouncementService.java` (C4: Digest-Sweep + Chat-Liste + Sonde)
- `src/main/java/dev/projecteclipse/eclipse/ritual/AltarBlockEntity.java` (C6: Junk-Sniff + Sonde)
- `src/main/java/dev/projecteclipse/eclipse/client/skills/SkillXpBarLayer.java` (C7: Chip + Sonde)

**Nicht angefasst (Verbotszonen respektiert):** `DayScheduler`, `DawnCeremony`, `EclipseGuiLayers` (FROZEN — DecreesCard self-subscribed), `ClientStateCache` (FROZEN — nur READ), `OfferingService` (nur lesen), `BeamEmitter` (nur API-Aufruf), sämtliche Team-A-/Team-B-Dateien, lang-Dateien (nur Langdrop).

---

## 6. Sonden-Übersicht

| Sonde | Ort | Seite |
|---|---|---|
| `[w6c-decrees] day=<d> mains=<n> personal=<n>` | `DecreesCard.maybeStart` | Client |
| `[w6c-curtain] waited=<t>t` | `AwardsOverlay.maybeStart` | Client |
| `[w6c-sundial] animated=<b> steps=<n>` | `SundialPlaza.onDayChanged` | Server |
| `[w6c-digest] days=<x>..<y> unlocks=<n>` | `AnnouncementService.announceCatchUpDigest` | Server |
| `[w6c-paper] player=<n> day=<d>` | `AwardService.onPlayerLoggedIn` | Server |
| `[w6c-sniff] item=<id>` | `AltarBlockEntity.handleOffering` | Server |
| `[w6c-xpchip] delta=<n>` (Zusatz, C7 ohne Plansonde) | `SkillXpBarLayer.onClientTick` | Client |
