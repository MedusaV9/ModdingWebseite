# MINECRAFT ECLIPSE — Trailer Sound-Design (30 s · 60 fps · 1800 Frames)

**Rolle:** Music-Supervision + Sound-Design für den 30-s-Game-Trailer (siehe `storyboard.md`, `motion_design.md`, `remotion_tech.md`).
**Quellmaterial:** Selbstproduzierte OGGs unter `src/main/resources/assets/eclipse/sounds/` (music/ + SFX-Ordner). Alle Werte unten stammen aus realer Analyse (ffprobe, `volumedetect`, `ebur128`-Momentary im 100-ms-Raster, Onset-Autokorrelation für Tempo-Gefühl) — nicht geschätzt.
**Ziel-Deliverable:** `trailer/public/audio/trailer_music.wav` (48 kHz stereo, −14 LUFS int., ≤ −1.5 dBTP) + `trailer_music.m4a` (AAC-Fallback) + konvertierte SFX-WAVs für Remotion.

Trailer-Struktur, an die sich die Musik anpasst:

| Phase | Zeit | Frames |
|---|---|---|
| Ruhe / Establishing | 0–5 s | 0–299 |
| Eskalation | 5–12 s | 300–719 |
| Drop-Montage (schnelle Cuts) | 12–24 s | 720–1439 |
| Schwarzes Loch + Endcard + Stille/Tail | 24–30 s | 1440–1799 |

---

## 1) Track-Steckbriefe (Top 5)

Messbasis: EBU-R128-Momentary (M, 400-ms-Fenster, alle 100 ms, pro Sekunde gemittelt), integrierte Loudness (I), Loudness Range (LRA), Sample-Peak. Tempo-Gefühl = stärkster Autokorrelations-Kandidat der Onset-Kurve (10-ms-Hop) — grob, kein exakter Beatgrid-Ersatz.

### 1.1 `day_final.ogg` — DER Trailer-Track ⭐

| Kennwert | Wert |
|---|---|
| Dauer | 127.4 s · 48 kHz stereo |
| Loudness | I = −16.0 LUFS · **LRA = 14.7 LU (dynamischster Track)** · Peak −1.3 dBFS |
| Tempo-Gefühl | ~154 BPM (bzw. Halftime ~77) im Epos-Teil |
| Charakter | Finaler-Tag-Hymne: mystisch-leerer Ambient-Start → treibendes Build → brachialer orchestraler Drop → episches Plateau → Breakdown |

Loudness-Verlauf (Momentary, Auszug):

```
  0–16 s : −47…−45 dB   ruhiger Ambient, fast leer (perfektes Establishing)
 17–18 s : Hit −34.7 → −21.9   erster Akzent
 18–29 s : −19…−26 dB   Build, wellenförmig ansteigend
 29 s    : −37.7 dB     PULL-BACK-DIP („Atem anhalten“ vor dem Drop)
 30–32 s : −19.0 → −11.6 → **−7.8 dB**   härtester Drop des gesamten Korpus
 32–85 s : −13…−17 dB   episches Plateau (lautestes 15-s-Fenster: 70–85 s @ −14.9)
 86–119 s: −20…−35 dB   Breakdown/Variation
120–127 s: Fade auf −66 dB
```

**Beste 30-s-Fenster:** (a) `0–32 s` roh — kompletter Bogen, aber Drop landet erst bei 30 s (zu spät für die Spec) → **editiert nutzen** (0–6.2 + 22.6–43.25, siehe §2); (b) `60–90 s` durchgehendes Epos ohne Bogen (nur als Bett für reine Action-Cuts).

### 1.2 `boss_herald.ogg` — Runner-up (spektakulärer eingebauter Silence-Drop)

| Kennwert | Wert |
|---|---|
| Dauer | 142.6 s · I = −16.0 LUFS · LRA 11.9 LU · Peak −1.5 dBFS |
| Tempo-Gefühl | ~94/188 BPM, hohe Onset-Dichte (3.3/s) — hektisch, treibend |
| Charakter | Boss-Hatz: startet sofort heiß (lautestes Fenster 5–20 s @ −14.2), Mittelteil-Break |

Kniff: `84–94 s` echte **Stille** (−50 → −86 dB), dann Re-Entry bei 94 s mit **+52 dB Sprung** — der brutalste „Abriss → Detonation“-Moment im Material. **Bestes 30-s-Fenster:** `84–114 s` (Stille → Explosion → Finale). Nicht als Haupttrack gewählt: der Drop läge bei ~10 s des Fensters, davor liegen 6 s Totenstille (wirkt im Trailer-Anfang wie ein Audiofehler) und der Anfang des Tracks hat kein Establishing.

### 1.3 `boss_ferryman.ogg` — Runner-up (Plateau-Kraft)

| Kennwert | Wert |
|---|---|
| Dauer | 193.6 s · I = −16.1 LUFS · LRA 7.8 LU · Peak −1.3 dBFS |
| Tempo-Gefühl | ~122 BPM, gleichmäßig stampfend |
| Charakter | Fährmann-Brüter: 0–74 s dunkel-konstant (−17…−20), Stufe bei 75 s, dann gnadenloses Peak-Plateau 75–140 s (lautestes Fenster 95–110 s @ −13.6) |

**Bestes 30-s-Fenster:** `62–92 s` — „Ruhe“ 0–13, Stufe bei 13 s des Fensters, Plateau danach. Schwäche: die „Ruhe“ ist mit −18…−20 dB nie wirklich leise (LRA nur 7.8), kein mystisches Establishing, kein echter Einzel-Drop-Moment — eher Rampe als Detonation.

### 1.4 `eclipse_totality.ogg` — Titelgeber, gewählt als Sub-Tail-Spender

| Kennwert | Wert |
|---|---|
| Dauer | 135.0 s · I = −15.9 LUFS · LRA 7.3 LU · Peak −1.6 dBFS |
| Tempo-Gefühl | ~58 BPM — langsam, ritueller Puls |
| Charakter | Dunkler Ritual-Drone, gleichmäßige Dichte, Lull 60–72 s, stärkster Akt 99–122 s |

Kniff: das Outro `122–135 s` fällt von −21 über −41/−51 in echte Stille, mit einem **letzten einzelnen Sub-Puls bei 130–131 s (−44 dB)** — wie gemacht für den Endcard-Tail. **Beste 30-s-Fenster:** `92–122 s` (stärkster Abschnitt) bzw. `122–135 s` als Tail-Donor. Als Haupttrack zu flach (LRA 7.3, kein Drop).

### 1.5 `title_theme.ogg` — melodische Mod-ID, aber frontlastig

| Kennwert | Wert |
|---|---|
| Dauer | 149.6 s · I = −16.0 LUFS · LRA 14.5 LU · Peak −2.4 dBFS |
| Tempo-Gefühl | ~118 BPM |
| Charakter | Hauptthema: startet sofort mit voller Melodie (lautestes Fenster 36–51 s @ −13.7), Variationen mit Lulls 63–112 s, zweiter Höhepunkt 112–128 s, langer Decay 128–150 s |

**Beste 30-s-Fenster:** `22–52 s` (Hauptthema-Höhepunkt) oder `106–136 s` (zweiter Climax + natürlicher Ausklang). Kein Build-up-Bogen → als Haupttrack ungeeignet, aber Kandidat für spätere Longform-Videos (Feature-Showcase).

### Kurzbegründung, warum die übrigen 10 rausfielen

`boss_fog_tyrant` (Plateau erst bei 132–147 s, kein Bogen) · `boss_rift_warden` (heiß ab Sek. 2, LRA-Profil flach) · `expansion_theme` (Peak schon bei 13–28 s, danach abfallend) · `fog_storm`/`intro_storm` (solide Riser-Betten, ~140/171 BPM, aber Peaks schwächer als day_final und kein Drop-Moment; `intro_storm` bleibt Storyboard-Alternative für Akt II) · `kill_contract` (Peak 24–39 s, zu kurzer Bogen) · `limbo_ambience` (Ambient, Peak erst bei 157 s) · `victory_theme` (kein Rise >6 dB — konstant feierlich, falsche Emotion) · `wand_awakening` (nur 50.6 s, leise, med. −23.9) · `xbox_nostalgia` (nostalgisch-hell, tonal falsch für den Trailer).

---

## 2) ENTSCHEIDUNG: Haupttrack + Schnittkonzept

**Haupttrack: `day_final.ogg`** (Segmente A+B) **+ `eclipse_totality.ogg` Outro als Sub-Tail** (Segment C).

Begründung: `day_final` enthält den kompletten geforderten Bogen nativ in einem Take — inklusive Pull-back-Dip direkt vor dem härtesten Drop des gesamten Korpus (M −7.8 dB). Nur die Proportionen stimmen nicht (17 s Intro, Drop bei 30 s) → ein einziger Crossfade innerhalb desselben Tracks (gleiche Tonart, gleiches Klangbild, unhörbar im Ambient-/Build-Material) staucht das Intro. `eclipse_totality` liefert mit seinem Outro-Sub-Puls den Tail unter der Endcard — die 2-Track-Kombi bleibt dadurch risikofrei (kein Tempo-/Key-Clash, der Tail ist praktisch tonloses Sub-Material). Das 5-Track-Chaining aus dem Storyboard (`eclipse_totality → intro_storm → boss_ferryman → day_final → title_theme`) ist in 30 s musikalisch nicht sauber machbar (4 Übergänge à ~1 s Crossfade = hörbares Patchwork); die Storyboard-Cues werden stattdessen von SFX-Spots übernommen (§3).

### Schnittkonzept (Quell-Zeitfenster → Trailer-Zeit)

| Seg | Quelle | Quell-Fenster | Trailer-Zeit | Inhalt |
|---|---|---|---|---|
| A | `day_final` | **0.00–6.20 s** | 0.00–6.20 s | nativer Fade-in + leerer Ambient (−47…−40 dB) = Ruhe/Establishing |
| ⤬ | Crossfade | 0.8 s (tri/tri) | 5.40–6.20 s | im Ambient/Build unhörbar (beide Seiten texturell) |
| B | `day_final` | **22.60–43.25 s** | 5.40–26.05 s | Build (−22…−19) → Pull-back-Dip Quell-29 s @ **Trailer 11.8 s** → Drop-Impact Quell-30.2 s @ **Trailer 13.0 s** → Peak −7.8 dB @ 14.6 s → Epos bis 26 s |
| ✂ | Hard-Cut (Abriss) | afade 0.05 s | **26.00 s** | Musik reißt exakt auf Schwarzes-Loch-Schlussbild ab |
| C | `eclipse_totality` | **128.20–134.20 s** | 26.00–29.25 s | Lowpass 120 Hz, +9 dB: Sub-Puls (Quell-130 s) landet @ **Trailer 27.8 s**, Fade-out 28.2–29.25 s |
| — | Stille | — | 29.25–30.00 s | letzte 45 Frames digital still (apad auf exakt 30.000 s) |

Mapping für Trailer-Zeit t ≥ 5.4 s: `Quellzeit(day_final) = 22.6 + (t − 5.4)`.

**Verifiziert** (ebur128-Momentary des gerenderten Mixes, pro Sekunde): `0:−76 … 5:−35` (Ruhe) · `6:−22 … 11:−20` (Eskalation) · `12:−33` (Dip) · `13:−14 → 14:−8.1 → 15:−7.7` (Drop) · `16–25:−12…−22` (Epos) · `26:−47` (Abriss) · `27:−63` · `28:−37` (Sub-Puls) · `29:−40` → Stille. Ergebnis: **I = −14.2 LUFS, True Peak −1.5 dBFS, LRA 17 LU.**

**Anpassungs-Variante (Storyboard-Drop bei Frame 900 = 15.0 s):** Das Storyboard legt den Drop auf Frame 900 mit Schwarzbild 894–899. Dafür nur Segment B früher schneiden: `atrim=20.6:45.25` statt `22.6:43.25` — Dip landet dann bei 13.8 s, Impact exakt bei 15.0 s, Abriss bleibt bei 26.0 s. Alle übrigen Parameter unverändert; SFX-Frames aus §3 um +120 schieben (Riser/Drop-Gruppe).

### Exakte ffmpeg-Kommandos (Kern)

```bash
# Pass 0 — 30-s-Bett bauen (unnormalisiert):
ffmpeg -y \
  -i "$SND/music/day_final.ogg" -i "$SND/music/day_final.ogg" -i "$SND/music/eclipse_totality.ogg" \
  -filter_complex "\
[0:a]atrim=0:6.2,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.5[a];\
[1:a]atrim=22.6:43.25,asetpts=PTS-STARTPTS[b];\
[a][b]acrossfade=d=0.8:c1=tri:c2=tri[ab];\
[ab]afade=t=out:st=25.96:d=0.05[abx];\
[2:a]atrim=128.2:134.2,asetpts=PTS-STARTPTS,lowpass=f=120,volume=9dB,\
afade=t=in:st=0:d=0.08,afade=t=out:st=2.2:d=1.05,adelay=26000|26000[tail];\
[abx][tail]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[mix];\
[mix]apad=whole_dur=30,atrim=0:30,asetpts=PTS-STARTPTS[raw]" \
  -map "[raw]" -ar 48000 -ac 2 -c:a pcm_s16le /tmp/trailer_audio/mix_raw.wav

# Pass 1 — Loudness messen (Werte in Variablen parsen, siehe §5):
ffmpeg -i /tmp/trailer_audio/mix_raw.wav \
  -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null -

# Pass 2 — linear auf −14 LUFS / −1.5 dBTP (WAV 48 kHz stereo für Remotion):
ffmpeg -y -i /tmp/trailer_audio/mix_raw.wav \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:\
measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/trailer_music.wav"

# AAC-Fallback:
ffmpeg -y -i "$OUT/trailer_music.wav" -c:a aac -b:a 256k "$OUT/trailer_music.m4a"
```

Der komplette kopierbare Block inkl. Variablen-Parsing und SFX-Konvertierung steht in §5. Zweipass-`loudnorm` mit `linear=true` ist Pflicht — der Single-Pass-Modus arbeitet dynamisch und pumpt den Abriss/Tail wieder hoch.

---

## 3) SFX-Spotting-Liste

`ls`-Befund der SFX-Ordner: `ambient/` (gazer_whisper 4.0 s, limbo_loop 10.0 s) · `award/` (sting) · `boss/` (ferryman_ambient 3.2 s, ferryman_bell 2.9 s, herald_ambient 2.6 s, herald_telegraph 0.8 s) · `event/` (border_glitch 1.44 s, emerge 3.6 s, submerge 3.7 s) · `offering/` (accept) · `ritual/` (extract) · `skill/` (levelup, proc) · `ui/` (heart_shatter 1.3 s, hover, page_turn, tab, typewriter, unlock_sting 0.55 s).

⚠ **Duplikat-Befund (md5-identisch):** `award/sting.ogg` = `event/submerge.ogg` = `offering/accept.ogg` = `ritual/extract.ogg` = `skill/levelup.ogg` = `skill/proc.ogg` — es gibt nur EINE dieser Klangdateien; unten wird stellvertretend `event/submerge.ogg` referenziert.

Hüllkurven-Analyse der Kandidaten: `emerge` = 2.5-s-**Riser** (−119 → −34 dB kontinuierlich steigend, dann Plateau) · `submerge` = schneller Attack + langer −35-dB-Sustain (**Down-Boom**) · `border_glitch` = Sofort-Attack, sägender Sustain (**Glitch-Stutter**) · `ferryman_bell` = Glockenschlag, **Attack erst bei +0.14 s** nach Dateistart · `herald_telegraph` = 0.8-s-Sofort-Impact (lautester SFX, Peak −10.9 dB) · `heart_shatter` = Splitter-Impact (Attack ~+0.15 s).

Pfad-Präfix `$SND` = `/home/ubuntu/project-eclipse/ProjectEclipse/src/main/resources/assets/eclipse/sounds`.
Beat-Raster Montage: Drop-Impact = Frame 780; Epos ≈ 154 BPM → 1 Beat ≈ 23.4 Frames, Montage-Hits auf 8-Beat-Raster (780 + n·187) — Positionen beim Feinschnitt ±2 Frames nach Gehör verifizieren.

| # | Frame @60fps | Zeit | Datei (exakt) | Zweck | Gain rel. |
|---|---|---|---|---|---|
| 1 | 40 | 0.67 s | `$SND/event/submerge.ogg` → `sfx_sub_boom.wav` (Lowpass-Variante) | Erster Sub-Impuls unter Text „Sieben Tage.“ (S01, Storyboard-Cue) | −16 dB |
| 2 | 150 | 2.50 s | `$SND/boss/ferryman_bell.ogg` | Ferne Glocke auf S02-Cut „Die Insel“ (Attack landet ~Frame 158 auf Text) | −10 dB |
| 3 | 300 | 5.00 s | `$SND/boss/herald_telegraph.ogg` | Cut-Impact: Beginn Eskalation / erster harter Szenenschnitt (S03) | −6 dB |
| 4 | 480 | 8.00 s | `$SND/event/border_glitch.ogg` | Glitch-Stutter auf Glitch-Wipe (RGB-Split-Übergang) | −8 dB |
| 5 | 627 | 10.45 s | `$SND/event/emerge.ogg` | Riser in den Drop — Plateau erreicht exakt Frame 780 | −4 dB |
| 6 | 780 | 13.00 s | `$SND/ui/heart_shatter.ogg` | Drop-Impact-Layer: Shatter verstärkt den Musik-Hit | −3 dB |
| 7 | 967 | 16.12 s | `$SND/boss/herald_telegraph.ogg` | Montage-Hit auf Boss-Cut (8-Beat-Raster) | −6 dB |
| 8 | 1154 | 19.23 s | `$SND/event/border_glitch.ogg` | Zweiter Glitch-Stutter auf Schnellschnitt (16-Beat) | −8 dB |
| 9 | 1560 | 26.00 s | `$SND/event/submerge.ogg` → `sfx_sub_boom.wav` (voll) | **Endcard-Boom/Sub-Drop** exakt auf Abriss + Schwarzbild | 0 dB |
| 10 | 1620 | 27.00 s | `$SND/ui/unlock_sting.ogg` | Leiser Ping auf Titel-Reveal „MINECRAFT ECLIPSE“ | −10 dB |

Optionale Extras (wenn Luft ist): `$SND/ambient/gazer_whisper.ogg` @ Frame 30 (−12 dB, Flüster-Creep unterm Establishing) · dritter `herald_telegraph`-Hit @ Frame 1341 (24-Beat, letzter Montage-Hit vor dem Finale) · `ui/typewriter.ogg` (0.05 s) pro Buchstabe bei Text-Pops.

---

## 4) Misch-Regeln

### 4.1 Musik-Volume-Envelope (Remotion `volume`-Callback, Frame → 0..1, linear interpolierbar)

Abriss und Sub-Tail sind bereits ins WAV gebacken — die Envelope regelt nur Gesamtpegel + Ducking:

| Frame | Vol | Grund |
|---|---|---|
| 0 | 0.00 | Fade-in aus Schwarz |
| 45 | 0.85 | Intro-Level erreicht (Material ist nativ leise) |
| 300 | 0.90 | Eskalation beginnt |
| 620 | 0.90 | — |
| 700 | 0.80 | Platz für den Riser (#5) |
| 775 | 0.55 | Duck unter Drop-Impact (#6) |
| 800 | 1.00 | Slam — volle Montage |
| 962 | 1.00 | — |
| 972 | 0.80 | Duck Montage-Hit (#7) |
| 992 | 1.00 | Release |
| 1149 | 1.00 | — |
| 1159 | 0.80 | Duck Glitch (#8) |
| 1179 | 1.00 | Release |
| 1755 | 1.00 | gebackener Tail läuft aus (Fade endet 29.25 s) |
| 1800 | 0.00 | Safety-Fade auf Kompositionsende |

```ts
// Remotion:
const musicVolume = (f: number) => interpolate(f,
  [0, 45, 300, 620, 700, 775, 800, 962, 972, 992, 1149, 1159, 1179, 1755, 1800],
  [0, 0.85, 0.9, 0.9, 0.8, 0.55, 1, 1, 0.8, 1, 1, 0.8, 1, 1, 0],
  { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
```

### 4.2 Ducking-Regel (generisch für jeden SFX-Hit)

- Duck-Beginn **5 Frames vor** SFX-Attack (Achtung Offsets: `ferryman_bell` +8 Frames, `heart_shatter` +9 Frames Attack-Verzögerung in der Datei).
- Duck-Tiefe: −6 dB (×0.55) beim Drop-Impact, sonst −2 dB (×0.8).
- Release: linear über **20–25 Frames** zurück auf Ausgangswert.
- Nie zwei Ducks überlappen lassen — bei Hit-Abstand < 30 Frames nur den lauteren Hit ducken.

### 4.3 Endcard & Silence-Tail

- Frame 1560 (26.0 s): Musik-Abriss ist im WAV (Fade 25.96–26.01 s). In Remotion NICHT zusätzlich schneiden — nur `sfx_sub_boom.wav` (#9) auf exakt Frame 1560 legen.
- Frames 1560–1755: nur gebackener Sub-Puls (27.8 s) + Boom-Tail des SFX. Kein weiteres Element außer #10 (Ping, −10 dB).
- **Frames ~1755–1800 (letzte 45 Frames): digitale Stille bzw. auslaufender Sub-Rumble unterhalb −60 dB** — im WAV garantiert (Fade endet 29.25 s, danach apad-Stille). Kein Safety-Problem beim Loop/Replay auf Social Media.
- SFX-Spuren generell: keine eigene Normalisierung nötig (Gains aus §3 relativ zum −14-LUFS-Bett); `sfx_sub_boom.wav` ist vorprozessiert (Lowpass 90 Hz, +10 dB, Limiter −1.5 dBTP).

---

## 5) Vorbereitungs-Kommandos (kopierbarer Bash-Block — getestet)

```bash
#!/usr/bin/env bash
set -euo pipefail

SND=/home/ubuntu/project-eclipse/ProjectEclipse/src/main/resources/assets/eclipse/sounds
OUT=/home/ubuntu/project-eclipse/trailer/public/audio
TMP=/tmp/trailer_audio
mkdir -p "$OUT" "$TMP"

# ── 1) 30-s-Musikbett (day_final-Bogen + eclipse_totality-Sub-Tail), unnormalisiert ──
ffmpeg -y \
  -i "$SND/music/day_final.ogg" -i "$SND/music/day_final.ogg" -i "$SND/music/eclipse_totality.ogg" \
  -filter_complex "\
[0:a]atrim=0:6.2,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.5[a];\
[1:a]atrim=22.6:43.25,asetpts=PTS-STARTPTS[b];\
[a][b]acrossfade=d=0.8:c1=tri:c2=tri[ab];\
[ab]afade=t=out:st=25.96:d=0.05[abx];\
[2:a]atrim=128.2:134.2,asetpts=PTS-STARTPTS,lowpass=f=120,volume=9dB,\
afade=t=in:st=0:d=0.08,afade=t=out:st=2.2:d=1.05,adelay=26000|26000[tail];\
[abx][tail]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[mix];\
[mix]apad=whole_dur=30,atrim=0:30,asetpts=PTS-STARTPTS[raw]" \
  -map "[raw]" -ar 48000 -ac 2 -c:a pcm_s16le "$TMP/mix_raw.wav"

# ── 2) Loudnorm Pass 1: messen ──
ffmpeg -hide_banner -nostats -i "$TMP/mix_raw.wav" \
  -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
  | tail -n 14 > "$TMP/loudnorm.json"
I=$(grep  -oP '"input_i"\s*:\s*"\K[-0-9.]+'      "$TMP/loudnorm.json")
TP=$(grep -oP '"input_tp"\s*:\s*"\K[-0-9.]+'     "$TMP/loudnorm.json")
LRA=$(grep -oP '"input_lra"\s*:\s*"\K[-0-9.]+'   "$TMP/loudnorm.json")
TH=$(grep -oP '"input_thresh"\s*:\s*"\K[-0-9.]+' "$TMP/loudnorm.json")
OFF=$(grep -oP '"target_offset"\s*:\s*"\K[-0-9.]+' "$TMP/loudnorm.json")

# ── 3) Loudnorm Pass 2: linear auf -14 LUFS / -1.5 dBTP → Remotion-Master (WAV 48k stereo) ──
ffmpeg -y -i "$TMP/mix_raw.wav" \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:\
measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/trailer_music.wav"

# ── 4) AAC-Fallback ──
ffmpeg -y -i "$OUT/trailer_music.wav" -c:a aac -b:a 256k "$OUT/trailer_music.m4a"

# ── 5) SFX konvertieren (48 kHz stereo WAV für Remotion) ──
for spec in \
  "boss/ferryman_bell:sfx_bell" \
  "boss/herald_telegraph:sfx_impact" \
  "event/border_glitch:sfx_glitch" \
  "event/emerge:sfx_riser" \
  "ui/heart_shatter:sfx_shatter" \
  "ui/unlock_sting:sfx_unlock" \
  "ambient/gazer_whisper:sfx_whisper" ; do
  ffmpeg -y -i "$SND/${spec%%:*}.ogg" -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/${spec##*:}.wav"
done

# ── 6) Endcard-Sub-Boom (submerge → Lowpass 90 Hz, +10 dB, Limiter -1.5 dBTP) ──
ffmpeg -y -i "$SND/event/submerge.ogg" \
  -af "lowpass=f=90,volume=10dB,alimiter=limit=0.84:level=false" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/sfx_sub_boom.wav"

# ── 7) Verifikation ──
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/trailer_music.wav"  # → 30.000000
ffmpeg -hide_banner -nostats -i "$OUT/trailer_music.wav" -af ebur128=peak=true -f null - 2>&1 | tail -8
# Erwartung: I ≈ -14.0…-14.2 LUFS, True Peak -1.5 dBFS
```

Pipeline verifiziert (Testlauf nach `/tmp`): Dauer exakt 30.000 s · I = −14.2 LUFS · TP = −1.5 dBFS · Momentary-Bogen wie in §2 tabelliert.
