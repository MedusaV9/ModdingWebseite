# POLISH4 — B6 Flash-HOLD + V6 Perf-Probe (Storm-Verifikations-Tooling)

**Auftrag:** STORM_MASS_PLAN B6 (Doppel-Flash-Zellen + Emissions-Adern) ist mit
`FLASH_TICKS = 7` (0,35 s) auf der llvmpipe-VM (Sekunden pro Frame) nicht fotografierbar
— es fehlte (1) ein Dev-HOLD-Schalter, der die Flashes einfrierbar/inspizierbar macht,
und (2) ein headless-tauglicher Anlauf für die **V6-Perf-Abnahme** (§6: Frametime je
Tier 2/1/0, fester Kamerapunkt).

**Datei-Besitz (exklusiv):** `stormfx/StormFlashDevHold.java` (NEU),
`stormfx/StormVolumeFx.java` (nur der Flash-Uniform-Block in `feedVolume`),
`cutscene/dev/FrameTimeProbe.java` (NEU), `cutscene/dev/FxDevCommands.java` (additiv:
zwei `storm`-Leaves + zwei Doc-Zeilen + Javadoc-Leaf-Liste),
`cutscene/dev/FxDevPayloads.java` (additiv: 2 Action-Konstanten),
`cutscene/dev/FxDevClient.java` (additiv: 2 Dispatch-Cases + Handler),
`docs/plans_v3/langdrop/POLISH4_FLASHHOLD.json` (NEU), dieser Report.
**Nicht angefasst:** `StormWeatherFx.java` (Scheduler/Serial/Licht/Interior-Beat laufen
unverändert — der HOLD ist ein reiner Uniform-Feed-Override), `storm_volume.fsh`
(**null Shader-Änderungen** — das Design forciert nur existierende Uniforms),
Photon-Tools, Entity-/Geo-Basen, Lang-JSONs (Keys via Langdrop, AGENTS-Regel).

---

## 1. Design

### 1.1 `/eclipsefx storm flashhold on [amount] | off` (B6-Sichtbarmachung)

- **Lane:** Server-Leaf im bestehenden `/eclipsefx storm`-Baum (Permission 3) →
  `FxDevPayloads.ACTION_STORM_FLASHHOLD` (arg `"on"/"off"`, value = amount) → Client
  (`FxDevClient`) → `StormFlashDevHold.set(...)`. Exakt das `post`/`sun debug`/
  `photon`-Muster: der Flash-Zustand ist client-seitig, also wird NUR der ausführende
  Client umgeschaltet — **kein Server-State, keine anderen Spieler betroffen**.
- **Wirkung (nur bei ON):** `StormVolumeFx.feedVolume` forciert **beide** B6-Slots:
  `FlashAmount = Flash2Amount = amount` (Default 1.0, Clamp 0.05–2.0) und ersetzt den
  per-Flash-Seed durch einen langsamen Zyklus
  `FlashSeed = (ticks/40) % 64` (+1 Seed-Schritt alle 2 s — jedes Adern-Muster ist in
  Ruhe inspizierbar, pausensicher über `StormFxClient.ticks()`).
- **Zell-Positionen bleiben ehrlich:** die gehaltenen Zellen nutzen die normalen
  per-Slot-Bearings/Lats des Schedulers (`innerFlashBearing/Lat`,
  `innerFlash2Bearing/Lat`), die zwischen Flashes im Slot stehen bleiben. Nur ein Slot,
  der noch NIE eine Zelle gepickt hat (erkennbar an `lat == 0` — echte Picks liegen
  immer in 0.15–0.70), fällt auf deterministische, **verschiedene** Fallback-Zellen
  zurück (Kamera-Bearing ∓/± 0.7 rad, lat 0.35 / 0.55 — dieselbe
  Kamera-Bearing-±-Spread-Logik wie der Scheduler selbst). Damit sind ab dem ersten
  gehaltenen Frame ZWEI getrennte Zellen sichtbar; sobald der weiterlaufende Scheduler
  echte Zellen pickt (Slot 1 nach ≤ 13 s, Slot 2 nach ≤ 17 s), springen die Positionen
  auf dessen normale Re-Rolls (alle ~5–17 s pro Slot — gewollt, man sieht verschiedene
  Zellpaare).
- **Der Scheduler läuft ungebremst weiter:** `StormWeatherFx` ist unangetastet — Serial,
  Punktlicht-Budget, Interior-Beat, W-A/W-C/W-D-Verträge verhalten sich exakt wie ohne
  HOLD (echte 7-Tick-Flashes fallen während des Holds schlicht mit den forcierten
  Werten zusammen). Der HOLD ist ausschließlich ein Override der fünf
  Flash-Uniform-Zuweisungen im Volume-Feed.
- **Hygiene:** Logout löscht den Hold (`ClientPlayerNetworkEvent.LoggingOut`, das
  `FxDevClient`-Override-Muster).

### 1.2 `/eclipsefx storm perfprobe [seconds]` (V6-Anlauf)

Kein brauchbarer Frametime-Zugriff existierte im Repo (`rg "frameTime|fps"
src/main/java` → nur Kommentar-Treffer), F3-Screenshot-Parsing ist auf llvmpipe
unzuverlässig → eigene Mini-Sonde `FrameTimeProbe`:

- Sampelt `Minecraft.getFrameTimeNs()` (Dauer der Render-Phase des Frames, OHNE
  Framerate-Limiter-Wartezeit — genau die Kostengröße für V6) einmal pro gerendertem
  Frame via `RenderFrameEvent.Post` (NeoForge, feuert exakt 1×/Frame). Da der Wert
  beim Post-Event noch den VORHERIGEN Frame trägt, wird das erste Event nach dem Start
  übersprungen (kein Pre-Probe-Frame in der Stichprobe).
- Nach Ablauf des Wall-Clock-Fensters (2–120 s, Default 10): Report mit Frame-Anzahl,
  **min/avg/p95/max** Frametime (ms) und fps-Schätzung in den Chat des Operators UND
  ins Client-Log (`EclipseMod.LOGGER`, grepbar: `"V6 perfprobe"`), inklusive des
  A/B-Kontexts: `stormVolumeQuality`-Tier, ist `eclipse:storm_volume` im Veil-Manager
  live, Flashhold-Status.
- Inaktiv kostet die Sonde einen statischen boolean-Read pro Frame; Sample-Puffer
  (max. 120 s × 1000 fps Longs) wird nach dem Report freigegeben; Logout bricht ab.

### 1.3 Doku-Registry + Lang

`FxDevCommands.registerDocs` additiv um `fx.storm.flashhold` und `fx.storm.perfprobe`
erweitert (DevCommandRegistry → `/dev help` / Handbook / `/dev docs export`). Die zwei
`dev.eclipse.doc.*`-Keys liegen als Langdrop in
`docs/plans_v3/langdrop/POLISH4_FLASHHOLD.json` (en+de) — Lang-JSONs werden per
AGENTS-Regel nie direkt editiert; bis zum Integrator-Merge zeigt das Handbook die
rohen Keys (kosmetisch, kein Build-Gate).

---

## 2. Idle-Regel-Beweis (flashhold off ⇒ bit-identische Frames)

Statische Argumentation über alle geänderten Produktionspfade:

1. **Schalterzustand.** `StormFlashDevHold.active` ist `private static volatile
   boolean`, initial `false`. Einzige Schreiber: `set(...)` (erreichbar NUR über den
   Dev-Payload `ACTION_STORM_FLASHHOLD`, den ausschließlich `/eclipsefx storm
   flashhold` versendet) und der Logout-Handler (schreibt `false`). In jeder Session
   ohne diesen Befehl ist `active == false`; nach `flashhold off` ebenfalls.
2. **`feedVolume` (die einzige geänderte Produktionsfunktion).** Jede Änderung ist auf
   `hold == true` gegated:
   - `flash`/`flash2` werden mit den **unveränderten Original-Ausdrücken** berechnet
     (`state == ACTIVE ? innerFlash[2]Amount : 0`); der Override ist ein nachgelagertes
     `if (hold) flash = …` — bei `hold == false` toter Code.
   - Die Positions-Zweige lesen Bearing/Lat mit den Original-Aufrufen; der
     Fallback-Override steht in `if (hold && latFrac <= 0.0F)` — bei `hold == false`
     toter Code. Gate-Schwelle (`> 0.01F`), Anker-Formel und Else-Zweig (Zentrum)
     sind zeichenidentisch zum Vorzustand.
   - `FlashSeed` wird als Ternary gefüttert: bei `hold == false` ist der gefütterte
     Wert der Original-Ausdruck `StormWeatherFx.innerFlashSerial() % 64` (identische
     Auswertung, identischer int→float-Pfad).
   ⇒ Für `hold == false` produziert jede der fünf Flash-Uniform-Zuweisungen Wert für
   Wert dieselbe Berechnung wie vor dem Patch — **kein Uniform kann abweichen**.
3. **Kein weiterer Leser/Seiteneffekt.** `StormFlashDevHold` wird nur von
   `StormVolumeFx.feedVolume` (gated), `FxDevClient` (Set) und `FrameTimeProbe`
   (Status-String im Report) referenziert. `StormWeatherFx.java` und
   `storm_volume.fsh` sind byte-unverändert (`git diff` leer für beide).
4. **`FrameTimeProbe` inaktiv** = ein volatiler boolean-Read im Frame-Event, keinerlei
   Render-/Uniform-Wirkung. Die zwei neuen Payload-Actions sind additive
   Diskriminatoren auf dem bestehenden optionalen Dev-Kanal (Codec unverändert; alte
   Clients loggen unbekannte Actions als Warnung — Dev-only-Wire-Contract laut
   `FxDevPayloads`-Javadoc).

---

## 3. Validierung

- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (2 Warnungen sind der vorbestehende `EventBusSubscriber.Bus`-
  Deprecation-Hinweis in `FxDevPayloads`, nicht von diesem Patch).
- RCON-Umgebung geprüft: `python3 tools/rcon/rcon.py "list"` → Spieler `Dev` online;
  Befehlsform `execute as Dev run eclipsefx …` validiert (mit `post list`, harmlos).
- Die NEUEN Befehle existieren erst nach Server+Client-Neustart (laufende Instanzen
  tragen den alten Code) — In-Game-Abnahme siehe §4, wird vom Main-Agent gefahren.

---

## 4. Verifikations-Skript für den Main-Agent (NACH Neustart von Server + Client)

Voraussetzung: Dedicated Server + Client mit dem neuen Build, Spieler `Dev` verbunden
(Client auf DISPLAY :1). Alle Befehle vom Repo-Root.

### 4.1 B6 Flash-HOLD (Sichtprüfung)

```bash
# 1. Position merken (cx cy cz aus der Antwort ablesen):
python3 tools/rcon/rcon.py "data get entity Dev Pos"

# 2. Kugel-Sturm r=48 h=96 an der Spielerposition spawnen:
python3 tools/rcon/rcon.py "execute as Dev at Dev run eclipsefx storm add 48 96 sphere"

# 3. ≥ 5 s warten (STATE_SPAWN 80 Ticks -> ACTIVE; Flash-Scheduler gated auf ACTIVE).

# 4. Kamera VOR die Wand stellen (75 > r=48 => ~27 Bloecke ausserhalb der Schale,
#    innerhalb FLASH_RANGE 160 / Volume-Range), Blick auf den Sturm:
python3 tools/rcon/rcon.py "tp Dev <cx+75> <cy+15> <cz> facing <cx> <cy+25> <cz>"

# 5. HOLD an (Default-Amount 1.0):
python3 tools/rcon/rcon.py "execute as Dev run eclipsefx storm flashhold on"
```

**Erwartung Chat:** RCON-seitig `[eclipsefx] storm flashhold ON (amount 1.00) → your
client …`; im CLIENT-Chat grün `storm flashhold ON — both B6 cells held at 1.00, vein
seed cycles every 2 s (volume feed only; scheduler untouched)`.

**Erwartung Screenshot(s)** (llvmpipe: 20–40 s pro Frame einplanen, Fenster klein):

- **ZWEI** violette Emissions-Glimmzellen (Flash-Farbe `vec3(0.70, 0.58, 1.00)`) IN
  der Wolkenmasse auf der kameranahen Wandseite, auf unterschiedlichen Bearings und
  Höhen (Zellen sitzen bei 0.92·r; Höhen 15–70 % bzw. Fallback 35 %/55 %).
- Jede Zelle zeigt **aderige Filament-Struktur** (helle Stränge/dunkle Lücken im
  ~9/R-Muster), KEIN glatter radialer Bulb — das ist der B6-Vein-Term.
- Zweiter Screenshot ≥ 2 s später: Adern-Muster gewechselt (Seed-Schritt), beide
  Zellen weiter an. Positions-Sprünge alle ~5–17 s sind die normalen
  Scheduler-Re-Picks (gewollt).
- Direkt nach dem Einschalten (bevor beide Slots je geflasht haben) stehen die Zellen
  auf den Fallbacks Kamera-Bearing ∓/± 0.7 rad — auch dann bereits zwei getrennte
  Zellen.

```bash
# 6. Optional Intensitaets-Check (Glimmen halbiert):
python3 tools/rcon/rcon.py "execute as Dev run eclipsefx storm flashhold on 0.5"

# 7. HOLD aus — Idle-Regel-Sichtpruefung: Dauerglimmen verschwindet, nur noch die
#    seltenen 0,35-s-Live-Flashes (auf llvmpipe praktisch nie im Frame):
python3 tools/rcon/rcon.py "execute as Dev run eclipsefx storm flashhold off"
```

### 4.2 V6 Perf-Probe (Tier-A/B, relative llvmpipe-Zahlen)

Fester Kamerapunkt = Position aus Schritt 4 (S4-artig: dichtes Band füllt das Bild).

```bash
# Tier 2 (Config-Default):
python3 tools/rcon/rcon.py "execute as Dev run eclipsefx storm perfprobe 60"
# 70 s warten, dann Report lesen (Client-Chat im Screenshot ODER Client-Log):
rg "V6 perfprobe" run/logs/latest.log | tail -1
```

**Erwartung:** Zeile der Form `V6 perfprobe: N frames — frametime min a / avg b /
p95 c / max d ms (≈e fps render-bound) | stormVolumeQuality=2, storm_volume pipeline
ACTIVE, flashhold off`. Auf llvmpipe liefern 60 s ggf. nur eine Handvoll Frames —
dann Fenster auf 120 s erhöhen; p95≈max ist bei kleinen N normal.

Dann Tier-Wechsel via Client-Config (NeoForge hot-reloaded TOML-Änderungen, kein
Neustart): in `run/config/eclipse-client.toml` `stormVolumeQuality = 1` setzen →
perfprobe 60 wiederholen → `= 0` → wiederholen → **`= 2` zurücksetzen**. Erwartete
Ordnung im dichten Band: avg(Tier 0) < avg(Tier 1) < avg(Tier 2) (24/40/64
Basis-Steps). Die absoluten V6-Schwellen (Tier 2 ≤ +20 %, Tier 0 ≤ +5 % **gegen den
Vor-B-Paket-Baseline-Build**) sind auf dieser VM nicht abnehmbar (kein
Baseline-Build, llvmpipe-Rauschen) — die Probe liefert die relativen Tier-Zahlen und
ist das fertige Werkzeug für die Messung auf echter GPU.

### 4.3 Aufräumen

```bash
python3 tools/rcon/rcon.py "execute as Dev at Dev run eclipsefx storm remove"
```

---

## 5. Selbstkritik / Grenzen

- Der HOLD zeigt die Zellen mit Dauer-Envelope 1.0 — die echte 7-Tick-Attack/Release-
  Kurve (smoothstep 40/60) bleibt nur im Live-Betrieb sichtbar; für die B6-Abnahme
  (zwei Zellen + Adern) ist das irrelevant, für Timing-Gefühl nicht ersetzbar.
- `FxDevPayloads`/`FxDevClient` waren nicht in der Besitz-Liste, sind aber die
  Dev-Lane, die die Aufgabe explizit als Muster benennt — beide nur additiv erweitert
  (2 Konstanten, 2 Cases + 1 Handler, 1 Import).
- Die perfprobe-fps-Schätzung ist render-bound (ohne Limiter-Wartezeit) und
  überschätzt damit die Wall-Clock-fps — für V6 (Kostenvergleich) ist genau das die
  richtige Metrik, im Report so beschriftet.
