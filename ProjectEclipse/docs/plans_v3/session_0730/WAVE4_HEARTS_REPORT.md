# WAVE4 Team B — Herz-, Tod- & Revive-Emotionsbogen (F-104, IDEA-13)

Scope: B1(R3) Revive-Relight, B2(R5) Kill-Transfer-Reverse-Burst, B3(R7) Deck-Revive-Feier,
B4(R8) Last-Heart-Hush, B5(R9) Witnessed-Loss-Anker, B6(R10) Ghost-Phantom-Pulse,
B7(R6) Ghost-Grade-Pre-Warm, Q1 Untertitel-Langdrop. Ideensammlung:
`docs/plans_v3/ideas_wave4/IDEA-13_death.md`.

## 1. Erst-Verifikation (vor jeder Codezeile)

| Item | Befund | Beweis-Kommando (vor der Änderung 0 Treffer im relevanten Code) |
|---|---|---|
| B1 (R3) | OFFEN | `rg -n "beginRelight" src/main/java` → nichts in `hearts/` (nur unverwandte `relight*`-Worldgen-Treffer) |
| B2 (R5) | OFFEN | `rg -n "gained\|triggerGained" src/main/java/dev/projecteclipse/eclipse/{hearts,network,lives}` → 0 relevante Treffer; `S2CHeartBurstPayload` trug nur `heartIndex` |
| B3 (R7) | OFFEN | `rg -n "HEART_BURST" src/main/java/dev/projecteclipse/eclipse/lives/DeathFlowHooks.java` → 0 |
| B4 (R8) | OFFEN | `rg -n "hush\|0.7F" src/main/java/dev/projecteclipse/eclipse/hearts/client/HeartBurstOverlay.java` → 0 |
| B5 (R9) | OFFEN | `rg -n "Quasar\|HEART_BURST" src/main/java/dev/projecteclipse/eclipse/drama/WitnessedLossService.java` → 0 |
| B6 (R10) | OFFEN | `rg -n "phantom\|throb\|300" src/main/java/dev/projecteclipse/eclipse/client/death/GhostHeartsLayer.java` → 0 |
| B7 (R6) | **OFFEN** (nicht gestrichen) | `rg -n "sendGhostState" src/main/java/dev/projecteclipse/eclipse/lives/DeathFlowHooks.java` → Zeilen 179/366/430 = Respawn-/Revive-/Login-Pfad; im `onLivingDeath` (Death-Screen-Zeitpunkt) fehlte der Send |
| Q1 | OFFEN | `rg -n "goal_stamp\|skill_unlock\|toggle_settle" src/main/resources/assets/eclipse/lang/*.json` → 0; Client-Log: 3× `Missing subtitle translation` ERRORs (latest.log Zeilen 177/180/182) |
| R1/R2/R4 | FERTIG, nicht angefasst | `PurpleHeartsLayer`-Grundbogen, Burst-Queue, `S2CRitualVigilPayload`/Vigil-Fill existieren; ebenso `EclipseDeathScreen`/`DeathScreenSwap`, `ritual/ReviveRitual` |

## 2. Umsetzung je Item

### B1 (R3) — Revive-Relight
`GhostHeartsLayer.beginReviveBurst` merkt sich jetzt `heartsRestored`; der BURST-Exit
(BURST → IDLE, also echte Revives) ruft `PurpleHeartsLayer.beginRelight(hearts)` auf.
Dort neue rein-clientseitige Choreographie: zurückkehrende Herzen bleiben dunkle Sockets
und füllen sich links→rechts im 4-Tick-Stagger, jedes landet als 3-Tick-Weißblitz
(Blink-Sprite-Familie, `FULL_BLINKING`/`HALF_BLINKING`) mit leisem Amethyst-Chime
(Volume 0.3, Pitch steigend 1.05 + 0.08/Slot). Tick-getrieben (eigener
`ClientTickEvent.Post`-Driver nach `HeartBurstOverlay`-Konvention: Reset ohne Level,
Freeze bei Pause), kein Protokoll-Change; No-op bei `purpleHearts=false`.

### B2 (R5) — Kill-Transfer-Reverse-Burst
Neues `S2CHeartBurstFxPayload(int heartIndex, boolean gained)` in
`network/hearts/HeartsPayloads` (id `eclipse:hearts/burst_fx`), Version-Group-Bump
`w4hearts1` → `w4hearts2` nach Bestandsmuster; das Legacy-`eclipse:heart_burst` in
`EclipsePayloads` Gruppe "2" bleibt unangetastet (Duplicate-Id-Regel).
`LifecycleEvents`-Kill-Zweig (STEAL): nach jedem `LivesApi.add(killer, +1)` (Basis-Steal
und Umbral-Blade-Bonus) geht `sendHeartBurstFx(killer, LivesApi.get(killer)-1, true)`
raus, plus INFO-Logzeile als Abnahme-Sonde. Client: `HeartBurstOverlay.triggerGained`
spielt die identische Pure-Function-Timeline zeitlich GESPIEGELT (`t = 17 - time`) —
Sparks falten sich ein, Shards konvergieren auf den Slot, Cracks verheilen, das Herz
settelt mit Ganz-Herz-Flash; keine rote Vignette, Cue = Unlock-Sting bei 0.7 Pitch
(die Geist-Burst-Familie) statt Glass-Crack. Queue-Einträge tragen jetzt
`gained`/`hush`-Flags, Stagger/Kapazität unverändert.

### B3 (R7) — Deck-Revive-Feier
`DeathFlowHooks.tickShipFlow` case `REVIVE_BURST`: bei `stageTicks % 8 == 0 && <= 40`
(Ticks 8/16/24/32/40 = exakt 5, synchron zu den fünf 8-Tick-gestaggerten HUD-Bursts)
ein `S2CQuasarPayload(HEART_BURST, playerPos + (0, 1.2, 0))` an ALLE Spieler in Limbo —
der Wiederbelebte und jeder Geist an Bord sehen die fünf aufsteigenden Violettbursts.
Bestehender One-Shot-Emitter, 5 Spawns über 2 s = im IMPACT-Budget.

### B4 (R8) — Last-Heart-Hush
`HeartBurstOverlay.trigger` entscheidet zur Trigger-Zeit: `ClientStateCache.lives == 1`
→ Hush-Eintrag. Variante: keine Spark-Pops, Shards fallen fast senkrecht
(vx×0.18, vy×0.30, Gravity 0.10→0.24, Drag 0.028→0.055/Tick, Floor 0.55→0.35),
Burst-Start-Vignette hält 6 statt 2 Ticks (3×), Crack-Cue auf 0.7 Pitch.
`reducedFx` bleibt unkonsultiert (gated wie bisher nur Heartbeat/Pulse, nie den Burst).

### B5 (R9) — Witnessed-Loss-Anker
`WitnessedLossService.onHeartLost`: in der bestehenden 24-Block-Zeugen-Schleife
zusätzlich ein `S2CQuasarPayload(HEART_BURST, victimPos + (0, 1, 0))` pro Zeuge
(Payload einmal gebaut, nie ans Opfer — dessen Burst replayt beim Respawn über der
Hotbar). Gleiche Schleife, ein Payload mehr, kein neuer Radius.

### B6 (R10) — Ghost-Phantom-Pulse
`GhostHeartsLayer`, GHOST-Modus: alle 300 Ticks wirft das Herz
`(modeTicks/300) % 5` einen Alpha-Throb 0.62 → 0.78 → 0.62 über 12 Ticks
(Sinus-Halbwelle, partialTick-geglättet) plus EINEN gedämpften Warden-Beat
(Pitch 0.5, Volume 0.25 — deutlich unter dem 1–2-Leben-Dread-Loop). Throb + Beat
komplett gated hinter `heartbeatSound()` UND `!reducedFx()` (Auftragswortlaut).
Erster Puls bewusst erst bei modeTicks ≥ 300 (kein Throb im Fade-in).

### B7 (R6) — Ghost-Grade-Pre-Warm (war OFFEN, jetzt implementiert)
`DeathFlowHooks.onLivingDeath` (LOW, nach `BanService.ban`): bei `flow.ghost` sofort
`FxPayloads.sendGhostState(victim, true)` — `EclipseFxState` blendet die Grade über
~30 t ein, während `HOLD_TICKS_GHOST` (40 t) den Button gated; "Als Geist erwachen"
landet damit in einer bereits gegradeten Welt. Der Respawn-Send bleibt als
idempotenter Refresh.

### Q1 — Untertitel-Langdrop
`docs/plans_v3/langdrop/WAVE4B.json`: die 3 fehlenden `subtitles.eclipse.ui.*`-Keys
(goal_stamp/skill_unlock/toggle_settle) + 2 Keys für den neuen Dev-Trigger
(`dev.eclipse.doc.lives.burst`, `dev.eclipse.lives.burst.ok`), en+de. Merge-Lauf:
`python3 tools/langmerge/merge_langdrops.py WAVE4B.json` →
**`merged: en_us +5, de_de +5; totals en=2854 de=2854` / `parity OK`**.
Lang-JSONs NICHT von Hand editiert (Diff = exakt die 5 Keys pro Datei).

### Abnahme-Werkzeug — `/dev lives burst` (neu, DevLivesCommands)
`/dev lives burst <player> <slot> <loss|gain|witness>` replayt eine Burst-FX-Spur ohne
Leben anzufassen: `loss` = Hotbar-Shatter (Hush greift automatisch bei 1 Leben),
`gain` = R5-Reverse-Burst, `witness` = der R9-Welt-Anker-Quasar an den Spieler selbst
(exakt das Zeugen-Payload) — macht Killer-/Zeugen-Pfade ohne zweiten echten Client
sichtbar. Registriert im `DevCommandRegistry` (Danger SAFE, Perm 2), Audit-Zeile inkl.

## 3. Gate-Belege

1. `cd /workspace/ProjectEclipse && flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain`
   → **BUILD SUCCESSFUL** (mehrfach, zuletzt nach finalem Stand; `2 actionable tasks: 1 executed`).
2. Langdrop-Merge: `merged: en_us +5, de_de +5; totals en=2854 de=2854` + `parity OK`.
3. Kein Reformat fremder Zeilen (Diffs additiv/lokal, Nachbarstil, Timelines tick-basiert);
   keine Photon-Assets angefasst — alles läuft über bestehende Quasar-/Payload-Lanes.

## 4. RCON-Abnahme-Drehbuch (Hauptagent)

Voraussetzung: Server + Client laufen, `<P>` = Name des Testspielers,
RCON = `python3 tools/rcon/rcon.py "<cmd>"`. **WICHTIG: Frische JVM!** Server UND Client
müssen NACH diesem Commit gestartet worden sein (Pre-Fix-Bytecode-Falle, siehe
F-103-Learnings). llvmpipe: vor visuellen Checks `tick rate 2` (10×-Streckung), Fenster
klein halten, 20–40 s Waits.

### Schritt 0 — Q1-Beweis (Client-Boot)
Nach frischem Client-Start:
`rg "Missing subtitle translation" run/logs/latest.log` → darf die drei
`eclipse:ui.goal_stamp|skill_unlock|toggle_settle`-Zeilen NICHT mehr enthalten
(vorher 3× ERROR).

### Schritt 1 — B4 Last-Heart-Hush (zuerst, braucht 1 Leben)
1. `dev lives give <P> -4` (5 → 1 Leben; Herz-Row zeigt 1 lila Herz).
2. `tick rate 2`, dann `dev lives burst <P> 0 loss`.
3. Erwartetes Bild: Herz-Slot 0 zerbricht OHNE weiße/violette Spark-Pops; Shards fallen
   fast senkrecht nach unten (kein Fächer); rote Rand-Vignette hält sichtbar länger
   (6 Ticks = ~3 s bei rate 2). Danach übernimmt der bestehende 1-Leben-Puls.
4. Kontrast-Referenz: `dev lives give <P> +4` (zurück auf 5), `dev lives burst <P> 2 loss`
   → normaler Fächer-Burst MIT Sparks, kurze Vignette.

### Schritt 2 — B2 Reverse-Burst (Dev-Spur + echter Kill-Zweig)
1. `dev lives burst <P> 3 gain` (bei `tick rate 2`).
2. Erwartetes Bild: über Slot 3 konvergieren Shards/Sparks von außen auf das Herz,
   Cracks verheilen, Ganz-Herz-Flash am Ende; KEINE rote Vignette; Unlock-Sting statt
   Crack (Audio auf der VM eh stumm — visuell abnehmen).
3. Echter Kill-Zweig (Server-Logik): erfordert Killer UND Opfer als `ServerPlayer` —
   ohne zweiten Client nicht auslösbar (Mob-Killer nimmt den PvE-Pfad ohne Transfer).
   Beleg stattdessen: die Dev-Spur oben nutzt exakt denselben Payload/Handler; der
   Server-Sender sitzt 1 Zeile hinter dem bestehenden `LivesApi.add(killer, +1)`.
   Log-Sonde für spätere 2-Spieler-Sessions:
   `rg "Kill transfer reverse burst sent" run/logs/latest.log`.

### Schritt 3 — B7 Pre-Warm + B6 Phantom-Pulse (Geist machen)
1. `tick rate 20` (Normaltempo), dann `dev lives give <P> -5` → 0 Leben, Ban, Ghost-Flow.
2. B7-Bild: schon WÄHREND der Geist-Death-Screen steht (vor Klick auf "Als Geist
   erwachen") gradet die Welt hinter dem Screen violett/entsättigt ein — nicht erst
   nach dem Respawn-Klick. (Der Send läuft im Death-Event; Screenshot des Death-Screens
   mit bereits gegradetem Hintergrund.)
3. Respawn klicken → Limbo-Deck, Ghost-Row (5 cracked Hearts + GEIST-Tag).
4. B6-Bild: bei Normaltempo ~15 s warten (Puls bei modeTicks 300), dann `tick rate 2`
   NICHT nötig — besser: direkt nach dem Respawn `tick rate 2` setzen, dann kommt der
   erste Puls nach ~2:30 min und der Throb dauert ~6 s: Herz #1 der Crack-Reihe hellt
   sichtbar auf (0.62 → 0.78) und dimmt zurück. Screenshot im Hellpunkt.
   Gate-Check: `reducedFx=true` ODER `heartbeatSound=false` in den Settings → kein Throb.
5. B5-Sichtprobe (Proxy): `dev lives burst <P> 0 witness` → EIN world-space
   Herz-Burst-Quasar (violette Partikel-Fontäne) am Spieler — exakt das Payload, das
   Zeugen im 24-Block-Radius beim echten Herzverlust bekommen (echter Multi-Client-Pfad
   ist eine unveränderte Schleife um den bestehenden Vignette+Crack-Send; Zeugen-Setup
   ohne zweiten Client nicht fahrbar, Mob als Killer erzeugt keine Zeugen-Ausnahme —
   der Ausschluss gilt nur dem Opfer).

### Schritt 4 — B1 Relight + B3 Deck-Feier (Revive)
1. Als Geist (aus Schritt 3), `tick rate 2` gesetzt lassen, dann `dev lives give <P> +1`.
2. Log-Sonde: `rg "Revive celebration started" run/logs/latest.log` → 1 Zeile.
3. Erwartetes Bild (eine Sequenz, am besten Video/Screenshot-Serie):
   a. Deck-Teleport, die 5 Ghost-Hearts bersten einzeln (8-Tick-Stagger, bestehend);
   b. **B3**: synchron dazu steigen 5 world-space Violettbursts am Spieler auf
      (Ticks 8/16/24/32/40 der REVIVE_BURST-Stage) — auch aus Sicht eines zweiten
      Geists an Bord, falls vorhanden;
   c. **B1**: nach dem letzten Ghost-Burst snapped die echte Row NICHT — der Slot
      bleibt einen Beat dunkel (Container ohne Füllung), dann Weißblitz (3 Ticks) und
      das lila Herz settelt (bei 1 wiederhergestelltem Leben genau 1 Herz; Chime pro
      Herz, auf der VM stumm).
4. Danach öffnet die Tür wie gehabt (Flow unverändert; Hard-Caps ungetestet lassen).

### Log-Sonden (gesammelt)
- `rg "Missing subtitle translation" run/logs/latest.log` → 0 eclipse-ui-Treffer (Q1)
- `rg "Kill transfer reverse burst sent" run/logs/latest.log` (B2-Serverzweig)
- `rg "Revive celebration started" run/logs/latest.log` (Revive-Flow-Start, bestehend)
- `rg "\[DEV AUDIT\].*heart burst" run/logs/latest.log` (Dev-Trigger-Audit)

### tick-rate-Hinweise
`tick rate 2` für: Hush-Shards/Vignette (S1), Reverse-Burst (S2), Relight-Stagger +
Deck-Echos (S4), Phantom-Throb (S3.4 — Puls-PERIODE dann aber 2:30 min, einplanen).
Normal-Rate reicht für: Q1-Logcheck, B7-Grade (eased über 30 t hinter 40-t-Hold).

## 5. Grenzen / bewusst nicht gemacht

- Kein zweiter echter Client verfügbar: B2-Server-Kill-Zweig und B5-Multi-Client-Pfad
  sind per Code-Review + identischer Dev-Payload-Spur belegt (s. Drehbuch S2/S3.5).
- `HeartsService`, `ritual/*`, `EclipseSounds`/`sounds.json`, Lang-JSONs (direkt),
  Team-A-/Team-C-Zonen: unangetastet. Kein neues Photon-Asset (nur bestehende
  Quasar-/Payload-Lanes) → FX-Gates n/a.
