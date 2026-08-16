# EARLY Trailer — Audio-Stack (Musik + SFX)

Kompletter, **zu 100 % selbst synthetisierter** Audio-Stack für die beiden
EARLY-Produkt-Trailer. Keine fremden Samples, keine Loops, keine Libraries —
alles wird deterministisch aus einem einzigen Python-Skript (`generate_audio.py`,
numpy-Synthese) gerendert. ffmpeg wird nur für die AAC-Transcodes (`.m4a`)
verwendet.

## Lizenz / Nutzung

- Eigenproduktion dieses Projekts, keine Rechte Dritter enthalten.
  Frei verwendbar für alle EARLY-Trailer/-Cuts (inkl. TikTok/Social).
- Die Tracks sind als **Master-Timing-Basis** gedacht: Der Kunde kann später
  jeden lizenzierten Song drüberlegen — die Remotion-Compositions schneiden
  auf `beat_grid.json`, nicht auf die Audiodatei selbst. Solange BPM/Marker
  übernommen oder neu gemappt werden, bleibt der Schnitt frame-genau.

## Dateien

| Datei | Inhalt |
| --- | --- |
| `hype_track.wav` / `.m4a` | 50.4 s, **140 BPM**, EDM/Phonk-Hybrid (TikTok): 4/4-Kick, Off-Hats, Claps, rollender Mono-Sub, Pluck-Hook (a-Moll-Pentatonik), Cowbell-Layer im 2. Drop, Riser/Sweeps, Sidechain-Pumping |
| `clean_track.wav` / `.m4a` | 47.0 s, **105 BPM**, minimaler Apple-Stil: warme FM/Additiv-Klaviere mit Hammer-Transienten, softe Pads, dezenter Puls (Fingersnap + gefilterte Hats), Shimmer-Delay (Oktav-Echos) |
| `whoosh_1..3.wav` | Übergangs-Whooshes (auf / ab / auf-ab, 0.5–1.0 s, Stereo-Bewegung) |
| `impact_1..2.wav` | Tiefe Punch-Impacts mit Sub-Tail (1.5 s / 1.1 s) |
| `riser_short.wav` | 1.3 s Kurz-Riser (Noise-Sweep + Tonglide) für Schnitt-Anläufe |
| `fizz_open.wav` | Dose öffnen: Klick/Knack + Zisch + Sprudel-Blubbern (1.2 s) |
| `sparkle_pop.wav` | Pop + aufsteigende Sparkle-Arpeggio-Blips (0.5 s) |
| `ui_tick.wav` | Kurzer UI-Tick (0.2 s) |
| `beat_grid.json` | Pro Track: BPM, Sample-Rate, Dauer, Offset des ersten Beats, alle Beat-Zeiten (s), Marker; plus SFX-Dauern |

Technik: 48 kHz / 16 bit Stereo-WAV, Peak-normalisiert auf **−1.5 dBFS**,
Bass unter ~200 Hz mono, DC-frei, Fades an Start/Ende. `.m4a` = AAC 192 kbit/s.

## Marker (Sekunden, siehe `beat_grid.json`)

- `hype_track` (140 BPM, Beat 0 bei 0.0 s): `drop1` 6.857143 · `break` 20.571429 · `drop2` 27.428571 · `outro` 41.142857 · `end` 48.0 (Impact-Tail bis 50.4)
- `clean_track` (105 BPM, Beat 0 bei 0.0 s): `chorus` 9.142857 · `bridge` 27.428571 · `outro` 36.571429 · `end` 45.714286 (Ring-out bis 47.0)

## Regenerieren / Prüfen

```bash
python3 generate_audio.py            # rendert alles neu (deterministisch, fester Seed)
python3 generate_audio.py --verify   # QC: Peak/DC/RMS-Fenster/Dauern/JSON-Konsistenz/Bass-Mono
python3 generate_audio.py --checksums# sha256 aller Outputs (Byte-Determinismus)
```

Benötigt: Python ≥ 3.12, numpy, ffmpeg/ffprobe im PATH. Zwei Läufe erzeugen
byte-identische Dateien (auch die `.m4a`, dank `-bitexact`).
