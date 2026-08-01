# WAVE3 — Neue Veil×Photon-Effekte (F-103 Team C)

Drei NEUE Cue-Familien (7 Assets), alle an BESTEHENDE Trigger gedockt, damit sie im
normalen Spielverlauf wirklich feuern. Generator: `tools/photon/wave3_fx.py` (fxlib,
UUID5-deterministisch — Doppel-Lauf byte-identisch verifiziert). Client-Rows:
`veilfx/Wave3FxRows.java` (selbstregistrierend via `@EventBusSubscriber`, MOD-Bus,
`FMLClientSetupEvent` — KEINE Registrier-Hookzeile nötig). Alle Rows sind
Photon-only-Garnish (`Mode.LAYER`, Quasar-Leg `null` — legal für NEUE Cues) und
one-shots (kein WINDOWED-Loop-Bookkeeping). `reducedFx` droppt alle drei — jeder
Moment wird bereits von seinen bestehenden Kanälen getragen (Zeremonie-Skript,
Chime+Toast, W8-Announcement).

Cue-Naming: beide Seiten leiten dieselbe `FxCues.cue("…")`-Id her
(CreditsSequence/CutsceneBeatFxRows-Präzedenz) — `FxCues.java` blieb unangetastet.

---

## Effekt 1 — Altar Purchase Bloom (`eclipse:fx/cue/wave3_altar_buy`)

**Design (1 Satz):** Der F-074 Kauf-Zeremonie-Auftakt bekommt eine kategorie-getönte
Photon-Blüte über der Altarkrone — violette Helix + goldene Bodenwelle (TEAM),
Schmiede-Funkenfächer + Schwebe-Orbit am Geschenk-Spot (GEAR), Rosen-Glut-Fontäne +
Glocken-Halos (HEART) — deren interne Burst-Ticks die Skript-Beats der Zeremonie
spiegeln.

**Trigger-Anbindung:** `economy/AltarBuyCeremony.beatOpening()` (der gemeinsame
t=0-Beat aller drei Kategorien, ~28t nach dem Kauf) sendet den Cue auf der
bestehenden `S2CFxEventPayload`-Lane (`FxPayloads.sendFxEvent`, `a` =
`Category.ordinal()` 0 TEAM / 1 GEAR / 2 HEART, Radius = `FX_RANGE` 48). Hook:
4 Zeilen + Kommentar, sonst nichts geändert.

**Frequenz-Gesetz:** SEQUENCE-Channel; die Zeremonie selbst kappt auf 8 parallele
Runs; Photons Same-Anchor-Dedup (default `allowMulti=false`) schluckt Kauf-Spam an
derselben Krone.

### Layer-Tabellen

`wave3_buy_team.fx` (Anker = Altarkrone):

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `team_helix` | 48 violette Motes, additive | rate 0.6 über 80t (= TEAM_SPIRAL_END_TICK) | Kreis r1.25 (Spiralradius des Skripts), 2.4 rad/s Orbit + 1.6 b/s Rise (4.0–5.6 Blöcke über 50–70t) | dunkelviolette Birth → SAC_VIOLET → SAC_HOT → SAC_VOID, HDR 1.45 |
| `team_wave_gold` | 2 Ring-Bursts | t=16 (20) + t=52 (14) = die FX_SHOCKWAVE-Ticks der Zeremonie | Kreis r1.5, radial +13 → 6.5 Blöcke in 50t (unter TEAM_RING_MAX_RADIUS 8) | GOLD_BIRTH → SAC_GOLD → SAC_GOLD_PALE, HDR 1.45 |
| `team_crown_glow` | 2 Soft-Glows 1.8–2.4 | Burst t=0, 30–40t | statisch, POP_SHRINK-Size | violett-weiße Blüte, dim |

`wave3_buy_gear.fx`:

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `gear_sparks` | 32 StretchedBillboard-Funken | Bursts t=0 (22) + t=4 (10) | 34°-Kegel, 2.8–4.4 b/s → 2.0–4.8 Blöcke in 14–22t | AMBER_BIRTH → ERA_CREAM → ERA_AMBER → ERA_EMBER, HDR 1.45 |
| `gear_gleam` | 30 Gold-Motes | rate 0.5 über 60t | Kreis r0.42, 0.9 b/s Rise = 1.35–2.0 Blöcke (GEAR_RISE_HEIGHT 1.35) | GOLD_BIRTH → SAC_GOLD_PALE → SAC_GOLD |
| `gear_orbit` | 10 Funken | Burst t=30 (= GEAR_RISE_END_TICK), Leben 24–30t (stirbt vor Flight-Beat 58) | Kreis r0.75 auf y+1.35, Orbit 3.4 rad/s | SAC_GOLD/ERA_CREAM, HDR 1.45 |

`wave3_buy_heart.fx`:

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `heart_fountain` | 45 Rosen-Embers | rate 0.5 über 90t (= HEART_FOUNTAIN_END_TICK) | 15°-Kegel, 1.5–2.1 b/s → 3.5–7.3 Blöcke Steigen | ROSE_BIRTH → GLI_MAGENTA → SAC_HOT-Kern, HDR 1.45 |
| `heart_bells` | 3×12 Halo-Pulse | Bursts t=24/44/64 (= HEART_BELL_TICKS, je ein Chime) | Kreis r0.7 auf y+1.5, radial +6.8 → 3 Blöcke in 44t | rosa Blüte → SAC_VOID Fade |
| `heart_glow` | 2+1 dim Glows 2.2–3.0 | Bursts t=0 (2) + t=60 (1) | statisch, Peak-Alpha 0.4 | Rosen-Wärme unter den Skript-Säulen |

**RCON-Test (Optik einzeln):**

```
dev photon test "eclipse:wave3_buy_team" <x> <y> <z>
dev photon test "eclipse:wave3_buy_gear" <x> <y> <z>
dev photon test "eclipse:wave3_buy_heart" <x> <y> <z>
```

**Live-Trigger-Test:** einen Shard-Shop-Kauf am Altar tätigen — die Blüte startet
mit dem Zeremonie-Auftakt (Beam + Chime) an der Krone; TEAM-Kauf zeigt die Gold-Welle
synchron zu den zwei Screen-Shockwaves.

**Erwartete Optik:** ~5 s Blüte direkt über der Altarkrone, in der Kategoriefarbe;
kein Ersatz, sondern Schicht ÜBER den bestehenden Quasar/Vanilla-Beats (LAYER).

---

## Effekt 2 — Vein-Clear Jackpot (`eclipse:fx/cue/wave3_vein_jackpot`)

**Design (1 Satz):** Der Moment, in dem der LETZTE Block einer getrackten Erzader
bricht, bekommt einen kompakten Funken-Jackpot am schließenden Block — warm
(amber-gold) für rotdominante Erze, kühl (cyan-arc) für blaudominante, skaliert mit
der Adergröße.

**Trigger-Anbindung:** `drama/MiningFeelService.onNaturalOreMined()`, der bestehende
`scan.present() == 1`-Zweig (Two-Note-Payoff + „Vein cleared"-Toast) sendet den Cue
(`a` = `scan.total()`, `b` = `oreColor(state)` — dasselbe gepackte 24-bit-RGB, das
der Ore-Proc-Sparkle-Seam schon prägt; exakt im Float). Hook: 5 Zeilen + Kommentar.
Client-Leg buckelt `b` (rot ≥ blau → warm, sonst cool — Photon kann nicht runtime-
tinten) und skaliert `clamp(0.75 + 0.045·a, 0.85, 1.3)`.

**Frequenz-Gesetz:** BURST-Channel; natürlich ratenbegrenzt (pro Fire muss eine
komplette Ader abgebaut sein), trotzdem der häufigste WAVE3-Cue — deshalb das
schlankste Asset der Welle (33 Sprites gesamt).

### Layer-Tabelle (`wave3_vein_jackpot_{warm,cool}.fx`, geteiltes Skelett)

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `*_sparks` | 20 StretchedBillboard-Streaks | Burst t=0 | Kugel r0.45 (breite Schale 0.6), 2.6–4.0 b/s → 2.0–4.8 Blöcke in 15–24t | warm: AMBER→SAC_GOLD/ERA_CREAM · cool: CYAN_BIRTH→GLI_CYAN/STM_ARC, HDR 1.45 |
| `*_flash` | 1 Hot-Core 1.5–1.9 | Burst t=0, 10–14t | statisch, POP_SHRINK | das „Ding!" — Peak-Alpha 0.85 |
| `*_ring` | 12 Horizontal-Motes | Burst t=2 | Kreis r0.5, radial +6.9 → 2.2 Blöcke in 32t | flacher Münz-Ring in Variantenfarbe |

**RCON-Test:**

```
dev photon test "eclipse:wave3_vein_jackpot_warm" <x> <y> <z>
dev photon test "eclipse:wave3_vein_jackpot_cool" <x> <y> <z>
```

**Live-Trigger-Test:** eine mehrblöckige Erzader (≥2 Blöcke, z. B. Eisen) komplett
abbauen — beim letzten Block poppt der Jackpot mittig am Block, zeitgleich mit dem
Amethyst-Chime; Eisen/Gold/Redstone/Kupfer/Kohle → warm, Lapis/Diamant/Emerald →
cool. Größere Adern poppen sichtbar größer.

**Erwartete Optik:** ~1.5 s kompakter Spark-Pop + flacher Ring + kurzer Blitz; klein
genug, um bei Serien-Clears nie zu ermüden.

---

## Effekt 3 — Night Omen (`eclipse:fx/cue/wave3_night_omen`)

**Design (1 Satz):** Beim Einsetzen einer Pale/Umbral Night steigt an den Füßen
JEDES Spielers ein persönliches Omen auf — Pale: elfenbeinfarbene Motes, die aus
einem Geisterschleier aufsteigen; Umbral: ein Reverse-Gulp aus violetten Motes, die
unter einem kriechenden Nachtnebel in den Boden gezogen werden.

**Trigger-Anbindung:** `entity/EclipseSpawner.announceNightEvent()` (der eine Ort,
durch den Nightfall-Roll UND `/eclipse event set` laufen; wird nie mit `none`
aufgerufen) sendet pro Online-Spieler einen persönlichen Cue auf der
`FxPayloads.sendFxEventTo`-Lane (`a` = 1 umbral / 0 pale) — die
CUE_DAWN_TOLL/Seal-Brand-Personal-Ceremony-Präzedenz: ein Range-Broadcast würde bei
gruppierten Spielern N×N Kopien stapeln. Hook: 6 Zeilen + Kommentar.

**Frequenz-Gesetz:** SEQUENCE-Channel; maximal einmal pro Nacht, genau eine Kopie
pro Client (personal lane).

### Layer-Tabellen

`wave3_omen_pale.fx` (Anker = Spielerfüße beim Send):

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `pale_motes` | 32 Elfenbein-Motes, Peak-Alpha 0.38 | rate 0.32 über 100t | Kreis r1.7 (breite Schale), 0.55 b/s Rise → 1.9–2.5 Blöcke | PALE_BIRTH → STM_ARC → SAC_HOT → ERA_SHADOW |
| `pale_halo` | 16 Ring-Motes | Burst t=10 | Kreis r0.9 auf y+1.25, radial +5.8 → 3.5 Blöcke in 60t | kalter Atem-Ring, dim |
| `pale_veil` | 3 Alpha-Smoke-Sheets 2.6–3.6 | Burst t=0, 70–90t | 0.25 b/s Drift nach oben | Whisper-Alpha 0.12, DISTANCE-sortiert, near-black Birth |

`wave3_omen_umbral.fx`:

| Emitter | Layer | Timing | Bewegung | Farben |
| --- | --- | --- | --- | --- |
| `umbral_gulp` | 38 violette Motes | Bursts t=0 (22) + t=22 (16) | Brusthöhen-Ring r2.6 (Kreis, keine Kugel — Kugelschale würde ⅓ der Births unterirdisch verschwenden), radial −2.2 → 1.5 Blöcke einwärts (Worst-Case-Tod bei r~0.45, sicher vor dem r=0-Flip) + 0.55 b/s Sink in den Boden | GLI_DEAD → COR_VIOLET → COR_INK, HDR 1.45 |
| `umbral_fog` | 7 Fog-Sheets 2.2–3.2 | Bursts t=0 (4) + t=30 (3), 80–105t | Bodenring r1.1, radial +2.4 → 2.5 Blöcke auswärts | Whisper-Alpha 0.14, DISTANCE-sortiert, near-black violett |
| `umbral_rise` | 12 dim Halo-Motes | Burst t=6 | Kreis r0.95, 0.5 b/s Rise → Knöchel→Brust | „es sieht dich an"-Linie, Peak-Alpha 0.35 |

**RCON-Test (Optik einzeln):**

```
dev photon test "eclipse:wave3_omen_pale" <x> <y> <z>
dev photon test "eclipse:wave3_omen_umbral" <x> <y> <z>
```

**Live-Trigger-Test (empfohlen):**

```
eclipse event set pale
eclipse event set umbral
```

— beides ruft `announceNightEvent` auf; das Omen startet an den eigenen Füßen
zeitgleich mit dem W8-Typewriter-Overlay. (Zurücksetzen: `eclipse event set none` —
feuert kein Omen.)

**Erwartete Optik:** ~5 s leiser, persönlicher Boden-Moment ums eigene Standfeld;
Pale liest sich als kaltes Aufatmen (aufsteigend, silbrig), Umbral als Schlucken
(einwärts/abwärts, violett-schwarz). Bewusst Whisper-Level — das Announcement
schreit, das Omen flüstert.

---

## Haus-Gesetze / Selbst-Iteration

- **Stacking-Law V2.1:** alle Ramps starten mit Alpha 0 aus DUNKLEN Birth-Tints
  (`*_BIRTH`-Paletten, Haze aus near-black `DUST_BIRTH_*`); Schalen breit
  (thickness 0.2–0.6); Counts getrimmt (größtes Asset 102 max Sprites, Jackpot 37).
- **Radial-Flip-Margin:** einziger Inward-Pull (`umbral_gulp`) in der Iteration von
  Kugel auf Brusthöhen-Ring umgebaut — Worst-Case-Tod jetzt r~0.45 statt r~0.06
  (Bounce-Gefahr), und keine unterirdischen Births mehr.
- **Prewarm/CullBox:** alles one-shots (kein Prewarm nötig); trotzdem trägt JEDER
  Emitter eine CullBox (credits5-Konvention; die 120t-Heart-Blüte liegt nahe der
  LINT-CULL-LONGSHOT-Grenze).
- **HDR ≤ 1.45:** alle Additive über den `hdr()`-Clamp (Peak exakt 1.45, Hue-Ratio
  erhalten); Alpha-Sheets ohne HDR + `vertex_sorting="DISTANCE"`.
- **Enums:** nur fxlib-validierte Strings (Billboard/StretchedBillboard/Horizontal,
  arc_mode default Random) — fxlib wirft beim Authoring.
- **UUID5-Determinismus:** Doppel-Lauf des Generators via `md5sum -c` byte-identisch
  bestätigt (alle 14 Dateien OK).
- **Binary-Blob-Gesetz:** `.fxproj`-Sibling neben jeder `.fx` committet.
- **Paletten:** alle Stops an FX-STYLE-GUIDE-§1-Tokens verankert — die 7 Assets
  erzeugen 0 LINT-PALETTE-Advisories (Flotten-Advisory-Zahl unverändert 149).

## Gates

| Gate | Ergebnis |
| --- | --- |
| `python3 tools/photon/fxlib.py validate --lint` | `284 file(s), 0 NEW error/warn, 27 grandfathered, 149 advisory info` — Bestand exakt unverändert |
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | `BUILD SUCCESSFUL` |
| Generator-Doppellauf | byte-identisch (UUID5) |
| Server/Client-Starts, RCON | keine (Main-Agent testet live) |

## Ownership-Bilanz

Neue Files: `tools/photon/wave3_fx.py`, `veilfx/Wave3FxRows.java`, 7×
`assets/eclipse/fx/wave3_*.fx` + 7× `.fxproj`, dieser Report. Fremde Files, minimal:
`AltarBuyCeremony.java` (+4 Zeilen in `beatOpening`), `MiningFeelService.java`
(+5 Zeilen im Vein-Clear-Zweig), `EclipseSpawner.java` (+6 Zeilen am Ende von
`announceNightEvent`) — alle drei klar `WAVE3 (F-103 C)`-kommentiert, keine Zeile
außerhalb der Hook-Stellen. Verbotene Zonen (PhotonBridge, worldgen/stage, ritual,
CreditsFinaleFxRows, credits5_fx.py, UserFeedback.md): unangetastet.
