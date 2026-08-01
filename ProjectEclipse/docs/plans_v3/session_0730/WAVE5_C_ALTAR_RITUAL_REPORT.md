# WAVE5 Morgen-Liturgie & Altar-Seele — Team-C-Report (F-105, Polish-Welle 5)

Team C „Morgen-Liturgie & Altar-Seele" — Implementierungsreport. Alle Items aus
`WAVE5_PLAN.md` §5 (IDEA-09 #4, IDEA-12 #4–#10, IDEA-16 #6, IDEA-05 #4), inkl. beider
Stretch-Items C7/C8. Erst-Verifikation gegen den Tree vor der ersten eigenen Codezeile.

## 1. Erst-Verifikations-Tabelle

| Item | Befund | Beweis-Kommando (vor Implementierung) |
|---|---|---|
| C1 Last Call | OFFEN | `rg -rn "lastcall\|last_call" src/main/java` → 0; `rg -n "hasOfferedToday" offering/OfferingService.java` → public Helper vorhanden; `rg -n "HUSH_WINDOW\|60_000" client/drama/LastMinuteHush.java` → Duck-Fenster beginnt T-60 s ⇒ T-90 s ist kollisionsfrei (Plan-Ausweichposition bestätigt) |
| C2 Armed-Spannungssäule | OFFEN, Plan-Delta | `ls src/main/resources/assets/eclipse/quasar/emitters/ \| rg offering` → leer; **`rg -n "handleHeartSacrifice" ritual/AltarBlockEntity.java` → 0** — der im Plan genannte zweite Arm-Branch wurde in ALTARFIX2 entfernt, das Armen lebt heute NUR in `handleOffering` (⇒ ein Send-Punkt statt zwei; §3) |
| C3 Verdict-Blüte | OFFEN | `rg -n "crown\|verdict" src/main/java/dev/projecteclipse/eclipse/offering/OfferingService.java` → 0 (die Plan-Fußnote bestätigt: `sig/crown_verdict` ist die Boss-Kill-Signatur, der Offering-Verdikt hatte keine physische Antwort) |
| C4 Chime-Leiter | OFFEN | `rg -n "AMETHYST_BLOCK_CHIME" ritual/AltarBlockEntity.java` → fixer Pitch `0.8F` in `handleMilestoneDeposit` |
| C5 Puls + Atem | OFFEN | `rg -n "pulse" client/AltarAberration.java` → 0; `BREATH_HZ` fix 0.3, Amplitude fix ±10 %; `rg -n "altarLevel" client/ClientStateCache.java` → synced Feld vorhanden (READ-only-Zugriff möglich) |
| C6 Phase-Shatter | OFFEN | `rg -n "shatter\|notch\|phase" client/hud/BossbarSkin.java` → 0 relevante Treffer (nur Damage-Flash/Ghost); `getPhase()` ist NICHT client-synced ⇒ Detektion über den lerped Progress (§3) |
| C7 Shard-Arpeggio | OFFEN | `rg -rn "arpeggio" src/main/java` → 0; Deposit-Chime fix `1.2F` in `ShardEconomy.deposit` |
| C8 Lub-Dub | OFFEN | `rg -n "PULSE_AMPLITUDE" client/hud/DayTimerLayer.java` → Single-Pop `easeOutCubic(f)` |
| Infrastruktur | DONE — nicht angefasst | `S2CCaptionPayload` (STYLE_WHISPER), `S2CQuasarPayload` (+ `ALTAR_BEAM`-Konstante), `BeamEmitter.emit`, `EclipseWorldState.getSanctumAltarPos()`, `EclipseSounds.OFFERING_ACCEPT` alle vorhanden — keine fremde Datei musste geändert werden |

## 2. Was gebaut wurde

### C1 — Last Call am Altar (`RealtimeDayService`, IDEA-09 #4)

Neuer Block im 1-s-Clock-Poll von `onServerTick` (`tickLastCall`, VOR dem
FIRE_CHECK-Gating): Stage-Flags `lastCall10mFired`/`lastCall90sFired` + Flicker-Cursor
`lastCallFlickerIndex`, alle drei in `onDayApplied` (jede Boundary, bedingungslos) UND in
`onServerStopped` zurückgesetzt. T-10 min und T-90 s senden je einmal pro Tag an jeden
Online-Spieler mit `!OfferingService.hasOfferedToday(player)` eine PRIVATE
Whisper-Caption (`S2CCaptionPayload`, 70 t, `STYLE_WHISPER`) + gedämpfte Glocke
(`playNotifySound(BELL_BLOCK, BLOCKS, 0.4F, 0.6F)`). Strikt anonym: kein Broadcast, keine
Namen außer in der DEBUG-Sonde. Guards: `armed && !paused && boundary > 0`; die
90-s-Stage latcht die 10-m-Stage mit (Boundary, die INNERHALB von T-10 m gesetzt wird,
springt direkt zur späten Stage; Rückwärts-Shifts können die frühe nie nachholen). In der
letzten Minute flackert der Sanctum-Beam: 4 Marken (55/40/25/10 s), max. 1 Emit pro
1-s-Poll, `BeamEmitter.emit(server.overworld(), sanctumPos)` mit Null-Guard für
Pre-Intro-Welten. Sonden: `[w5c-lastcall] stage=<10m|90s> player=<name>` und
`[w5c-lastcall] flicker <i>/4 at <pos>`. Captions als Langdrop
`docs/plans_v3/langdrop/WAVE5C.json` (en+de paritätisch, `merge_langdrops.py` NICHT
gelaufen — zentraler Merge).

### C2 — Armed-Offering-Spannungssäule (`offering_armed.json` + `AltarBlockEntity`, IDEA-12 #6)

Neues Text-Asset `assets/eclipse/quasar/emitters/offering_armed.json` (Hand-Edit nach dem
House-Schema von `altar_beam.json`): one-shot (`loop: false`), `max_lifetime: 100` ==
`OFFERING_CONFIRM_WINDOW_TICKS`, enge `veil:cylinder`-Säule (0.26×1.4), rate 4 × count 2
(~50 Motes über 5 s — spärlich, „ein Beam, der die Luft anhält"), Partikel-Lifetime 45 t,
langsamer Auftrieb (speed 0.03, sanfter Up-Push mit Drag). V2.1-Stacking-Law: dunkle
Birth-Tint `#1D0A33` → Peak `#5B1E99` (Alpha max. 0.55) → fast-schwarzer Death `#120722`.
Im Arm-Branch von `handleOffering` (nach dem Resonate-Sound) ein einziges
`S2CQuasarPayload(OFFERING_ARMED, Altar-Mitte +0.7)` an die 64-Block-Lane — dieselbe
Distribution wie der Accept-Beam. Kein Cleanup-Bookkeeping: verfallenes Fenster ⇒ Emitter
läuft aus ohne Residuum; Confirm ⇒ Accept-Beam übernimmt sichtbar.

### C3 — Dawn-Verdict-Blüte (`OfferingService`, IDEA-12 #10)

`resolveDay` unterscheidet jetzt explizit den frischen Pfad: `boolean fresh =
state.putResolved(result)` — NUR `fresh == true` feuert `fireVerdictBloom` (die
idempotenten Re-Entry-/Repair-Pfade können die Zeremonie nie wiederholen). Die Blüte:
Sonde `[w5c-verdict] winners=<n> day=<d>` IMMER (auch bei 0 — das ist die
Duplikat-bleibt-dunkel-Abnahme), bei Gewinnern 3× `BeamEmitter.emit` am Sanctum-Altar
über ~40 t (Statics `bloomEmitsLeft`/`bloomCountdownTicks`/`bloomPos`, getrieben von
einem neuen `ServerTickEvent.Post`-Handler — idle = 1 int-Vergleich; Reset in
`onServerStopped`; Null-Guard Sanctum). Jeder ONLINE-Gewinner hört privat
`OFFERING_ACCEPT` bei Pitch 1.3F (`playNotifySound` — Split-Chime-Gesetz, nichts leakt an
Dritte).

### C4 — Milestone-Chime-Leiter (`AltarBlockEntity.handleMilestoneDeposit`, IDEA-12 #5)

Receipt-Chime-Pitch `0.7F + 0.5F * (updated / (float) match.count())` statt fix 0.8F —
erster Beitrag ≈ 0.7+, letzter genau 1.2, monoton steigend (`updated ≤ count` per
Konstruktion, `consumed` ist oben geclampt). `completeMilestone` behält seinen eigenen
End-Portal-Sting als Leiter-Spitze. Sonde `[w5c-chime] pitch=<f> progress=<u>/<c>
item=<id>` (Audio ist auf der VM stumm — der Log ist die Abnahme).

### C5 — Aberrations-Puls + Level-Atem (`AltarAberration`, `QuasarSpawner`, `AltarBlock`, IDEA-12 #4 + #9)

**Puls**: neues statisches `AltarAberration.pulse(float)` — +0.20, linearer Decay über
15 t, published als `min(MAX_STRENGTH, eased + pulse)` (der frozen
Single-Uniform-Contract sieht nie eine neue Decke) und NUR innerhalb der Zone
(`eased > 0.001`) — ein 512-Block-ALTAR_BEAM darf ohne Zonen-Kontext keine Screens
flashen. `reducedFx` skippt den Puls komplett. Trigger client-lokal:
`QuasarSpawner.spawnOrFallback` notified bei Emitter-Id `ALTAR_BEAM` VOR den
Budget-/Garnish-Gates (ein budget-gedroppter Beam ist trotzdem passiert). Sonde
`[w5c-abpulse]` nur auf der steigenden Flanke (Ritual-Salven fluten das Log nicht).
**Shard-Banking**: der Deposit-Branch von `AltarBlock.onSneakRightClick` sendet jetzt
dasselbe `S2CQuasarPayload(ALTAR_BEAM…)` an die 64-Block-Lane — Banking bekommt Beam +
Puls. **Atem**: `feedPost`-Frequenz `0.3 + 0.03·altarLevel` Hz, via
`Math.round(x*100)/100` auf 0.01 Hz gesnappt — jede Frequenz vollendet ganzzahlige Zyklen
pro 100-s-Wrap, der Seam-Beweis des Bestands hält. Amplitude ±10 % + 0.8 %/Level, Cap
±14 % (Plan-Decke; Worst-Case-Feed 0.884 < intendierte Grenze). `ClientStateCache.altarLevel`
wird NUR gelesen. Sonde `[w5c-breath] hz=<f> amp=<f> level=<n>` einmal pro Hz-Änderung.

### C6 — Bossbar-Phase-Break-Shatter (`BossbarSkin`, IDEA-16 #6)

Rein client-detektiert, 0 Netzwerk: im BESTEHENDEN Damage-Drop-Branch von
`onBossEventProgress` (nur dort — Heals/Aufwärts-Progress können physisch nie
triggern) prüft `crossedPhaseNotch(prev, actual)` den Abwärts-Kreuz über 2/3, 1/2, 1/3;
nur für `THEME_BOSS` (zählende Goal-/Ritual-Bars stroben nicht durch ihre Brüche), nur
ohne `reducedFx`. Der Break spikt den BESTEHENDEN `glowAlpha`-Parameter weißglühend
(1.0 → 0 über 10 t) und lässt 6–8 fallende 2×2-px-Fragmente ab der Notch-Position
regnen (12 t, deterministische Pseudo-Randomness gehasht aus der Start-Tick-Zahl,
ballistisch mit 90 px/s² auf Sekunden-Äquivalent `ticks/20`). **Timing-Entscheidung**:
anders als der restliche Wall-Clock-Juice der Skin läuft die Shatter-Envelope auf
`level.getGameTime()` + `event.getPartialTick().getGameTimeDeltaPartialTick(false)` —
bei `tick rate 2` dehnen sich die 10 t auf ~5 s Echtzeit (die Fotopunkte der Abnahme),
und im Pause-Menü friert der Burst ein statt wegzulaufen. State: 2 Felder in `BarState`
(`shatterStartGameTime`, Idle-Sentinel `Long.MIN_VALUE`, + `shatterNotch`). Sonde
`[w5c-barshatter] theme=boss notch=<f>` genau 1× pro Break (Client-Log).

### C7 (Stretch) — Shard-Bank-Arpeggio (`ShardEconomy.deposit`, IDEA-12 #8)

Der fixe 1.2F-Receipt-Chime wird eine steigende Leiter: `min(1 + amount/8, 6)` Noten,
alle 3 t eine, Pitch linear 1.2 → 1.8 über die Queue (1 Note ⇒ exakt der alte
Einzel-Chime bei 1.2 — Deposits von 1–7 Shards klingen unverändert). Map
`ARPEGGIO<UUID, Arpeggio>` wird am Anfang von `onServerTick` VOR dem 20-t-Gate gedraint
(idle = 1 `isEmpty()`), Offline-Spieler droppen ihre Queue, Clear im bestehenden
`onServerStopped`. Sonde `[w5c-arpeggio] player=<n> amount=<a> notes=<k>`.

### C8 (Stretch) — Day-Timer-Lub-Dub (`DayTimerLayer`, IDEA-05 #4)

Der Single-Pop der finalen 10 s wird ein Herzschlag: voller Pop an der Sekundengrenze
(`lub`, easeOutCubic über f 1.0→0.55) + 55-%-Echo-Pop bei f=0.55 (`dub`), kombiniert per
`max()` (Envelopes stapeln nie, Amplituden-Decke unverändert). Alle Bestands-Gates
(reducedFx/paused/zeroHold/Spool-Scissors) unangetastet.

## 3. Design-Entscheidungen

1. **C2 gilt nur für `handleOffering`**: der Plan nennt `handleHeartSacrifice` als
   zweiten Arm-Branch, aber ALTARFIX2 hat die Methode entfernt (Erst-Verifikation §1) —
   es existiert genau EIN Arm-Punkt. Additiv dort eingehängt, keine Rekonstruktion.
2. **C6 auf gameTime statt Wall-Clock**: die Skin animiert sonst auf `Util.getMillis()`,
   aber die Abnahme fotografiert bei `tick rate 2` — eine 500-ms-Envelope wäre dort
   unfotografierbar kurz geblieben. `CustomizeGuiOverlayEvent` führt den `DeltaTracker`
   mit (`getPartialTick()`), also skaliert der Shatter sauber sub-tick-glatt mit der
   Tick-Rate; der übrige Bestand (Flash/Ghost/Scan) blieb unangetastet Wall-Clock.
3. **C6 Detektion über lerped Progress statt `getPhase()`**: Boss-Phase ist nicht
   client-synced; der Progress-Kreuz über 2/3–1/3 ist die netzwerkfreie Plan-Variante
   („oder"), deckt alle 4 Boss-Themes in dieser einen Datei.
4. **C1 T-90 s statt T-60 s** (Plan-Vorgabe verifiziert): `LastMinuteHush` duckt Audio ab
   T-60 s — die Glocke bei T-90 s bleibt hörbar. Die 90-s-Stage latcht die 10-m-Stage.
5. **C3 nur auf dem frischen `putResolved`-Pfad**: Doppel-Resolutions (Catch-up, Repair,
   Gametests) können die Blüte nicht wiederholen; die Sonde loggt trotzdem jede
   Resolution (winners=0-Abnahme gratis).
6. **C5 Puls zonen-gebunden + Rising-Edge-Log**: Wiederbelebungs-/Level-Up-Rituale senden
   minutenlang ALTAR_BEAMs — ohne Zonen-Gate würde der halbe Server flashen, ohne
   Edge-Gate entstünden > 1000 Log-Zeilen pro Ritual.
7. **Kein `.fx`-Asset nötig**: C2 ist ein Quasar-JSON (Text-Asset, Hand-Edit legal);
   die fxlib-Gates greifen nicht. CullBox ist ein Photon-`.fx`-Konzept — das
   Quasar-House-Schema hat kein solches Feld (mit Bestands-Emittern abgeglichen).

## 4. Gates

| Gate | Ergebnis |
|---|---|
| `flock /tmp/gradle.lock ./gradlew compileJava --offline` | **BUILD SUCCESSFUL** (finaler Lauf, ganzer Tree). Zwischenläufe waren ROT durch Team-A-Zwischenstände (`cutscene/dev/FxDevClient.java` 16×, dann `entity/boss/fog/FogTyrantEntity.java` 2× — alles Team-A-Verbotszone, 0 Fehler in Team-C-Dateien zu jedem Zeitpunkt) |
| `./gradlew processResources --offline` | **BUILD SUCCESSFUL** — `offering_armed.json` liegt im Build-Output |
| JSON-Validierung | `python3 -m json.tool` GRÜN für `offering_armed.json` + `WAVE5C.json` |
| Langdrop | NUR `docs/plans_v3/langdrop/WAVE5C.json`, en+de paritätisch (2 Keys je Sprache); lang-JSONs des Mods NICHT angefasst, `merge_langdrops.py` NICHT gelaufen |
| Diff-Hygiene | Additiv, jede Stelle mit `// WAVE5 (F-105 C)` markiert, 0 fremde Zeilen reformatiert, 0 Schreibzugriffe außerhalb der Ownership |

## 5. RCON-Abnahme-Drehbuch

Sonden-Greps: Server-Sonden (`w5c-lastcall`, `w5c-verdict`, `w5c-chime`, `w5c-arpeggio`)
in `run/logs/debug.log`; Client-Sonden (`w5c-abpulse`, `w5c-breath`, `w5c-barshatter`) im
debug.log des llvmpipe-Clients. Captions erscheinen bis zum zentralen Langdrop-Merge als
Raw-Keys — für die Abnahme irrelevant (die Sonde zählt).

```
# --- C1 Last Call (Dev OHNE Offering) --------------------------------------
/eclipse schedule next +11m
#   nach ~1 min:  grep -c "w5c-lastcall] stage=10m" run/logs/debug.log   -> +1 (genau 1x)
#   nach ~9.5 min: grep -c "w5c-lastcall] stage=90s" run/logs/debug.log  -> +1
#   letzte Minute: grep "w5c-lastcall] flicker" run/logs/debug.log       -> 4 Zeilen; Screenshot Beam-Flicker
#   Boundary feuert -> onDayApplied resettet; naechster Tag armt frisch
# --- C1 Gegenprobe (Dev MIT Offering): erst Offering machen (siehe C2), dann
/eclipse schedule next +11m
#   -> KEINE neuen stage=-Zeilen fuer diesen Spieler (Flicker laeuft trotzdem)

# --- C2 Spannungssaeule (Fotopunkt) -----------------------------------------
/tick rate 2
#   In-game: Offering-Item sneak-right-click auf den Altar (1. Klick = armen)
#   -> dunkle #5B1E99-Saeule steht ~50 s Echtzeit (100 t) ueber dem Stein: Screenshot
#   Fenster verfallen lassen -> Saeule fadet ohne Residuum
#   2. Klick (Confirm) -> Accept-Beam ersetzt sie sichtbar
/tick rate 20

# --- C3 Verdict-Bluete -------------------------------------------------------
#   Dev macht ein Offering (arm + confirm), dann:
/dev phase next
#   grep "w5c-verdict" run/logs/debug.log -> winners=1; bei tick rate 2: 3 Beam-Salven
#   ueber ~20 s Echtzeit fotografieren. Duplikat-Tag (2 Spieler, gleicher Wert):
#   winners=0 und KEIN Beam (dunkel = korrekt)

# --- C4 Chime-Leiter ---------------------------------------------------------
#   Milestone-Item aus run/config/eclipse/milestones.json geben, z.B.:
/give Dev <milestone_item> 64
#   wiederholt (non-sneak) deponieren, dann:
#   grep "w5c-chime" run/logs/debug.log -> pitch strikt monoton 0.7x -> 1.2
#   (completeMilestone-Sting = Leiter-Spitze)

# --- C5 Puls + Atem ----------------------------------------------------------
/give Dev eclipse:umbral_shard 32
#   sneak-right-click Altar (Shard-Bank) -> Client-Log: grep "w5c-abpulse"
#   Screenshot-Paar Peak/Idle bei /tick rate 2 (Screen-Space-subtil, sonst Log-Abnahme)
/eclipse altar set 3
#   Client-Log: grep "w5c-breath" -> hz=0.39 (0.3 + 0.03*3, 0.01-gesnappt)
#   reducedFx-Gegenprobe: Client-Config reducedFx=true -> kein w5c-abpulse, Atem flach

# --- C6 Phase-Shatter (Fotopunkt) ---------------------------------------------
#   Boss mit Boss-Bossbar summonen (z.B. Fog Tyrant), dann HP ueber 2/3 druecken:
/damage <boss-uuid-selector> 40 minecraft:generic
/tick rate 2
#   Client-Log: grep "w5c-barshatter" -> theme=boss notch=0.6666667, genau 1x
#   Glut-Spike + Fragmente laufen ~5 s Echtzeit (10 t Glow / 12 t Fragmente): Screenshot
#   Gegenprobe: Boss heilen/Progress steigt -> keine neue Sonde

# --- C7 Arpeggio ---------------------------------------------------------------
#   32 Shards banken (siehe C5) -> grep "w5c-arpeggio" -> amount=32 notes=5;
#   1 Shard banken -> notes=1 (Legacy-Einzelchime)

# --- C8 Lub-Dub ----------------------------------------------------------------
/eclipse schedule next +30s
#   HUD-Day-Timer in den finalen 10 s beobachten: Doppel-Puls je Sekunde (visuell)
```
