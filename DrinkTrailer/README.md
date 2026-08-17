# EARLY DrinkTrailer

Zwei komplette Produkt-Trailer-Stile für den EARLY Sparkling Vitamin Drink
([drinkearly.com](https://drinkearly.com)) — jeweils als TikTok- (9:16, 1080x1920)
und Querformat-Version (16:9, 1920x1080), 30 fps.

## Fertige Trailer (`trailers/`)

| Datei | Stil | Format | Länge |
| --- | --- | --- | --- |
| `early_hype_tiktok_9x16.mp4` | Overedited TikTok/IG (Beat-Cuts, Glitch, RGB-Split, Sticker) | 1080x1920 | 48 s |
| `early_hype_landscape_16x9.mp4` | Overedited, eigenständiges 16:9-Layout (Split-Screens) | 1920x1080 | 48 s |
| `early_clean_tiktok_9x16.mp4` | Apple-Style minimal (Creme, Typo, Farbfeld-Kapitel) | 1080x1920 | 42 s |
| `early_clean_landscape_16x9.mp4` | Apple-Style, eigenständiges 16:9-Layout | 1920x1080 | 42 s |

## Aufbau

- `assets/images/` — 15 KI-generierte Produkt-/Lifestyle-Shots (Hero, Splash,
  Macro, Underwater, Lineup, Lifestyle, Minimal-Float) in 9:16 und 16:9.
- `assets/blender/` — parametrische 3D-Dose (`build_can.py`, Blender 4.0 / Cycles)
  plus deterministischer Label-Generator (`gen_labels.py`, PIL) für alle drei
  Sorten (WEISSER PFIRSICH / GRAPEFRUIT / ZITRONE-MINZE).
- `assets/renders/` — Blender-Ausgaben: 6 Sorten-Stills, Trio-Still,
  360°-Turntable (`early_turntable_peach_9x16.mp4`) und Slow-Dolly
  (`early_dolly_peach_16x9.mp4`).
- `assets/music/` — komplett eigenproduzierter Audio-Stack
  (`generate_audio.py`, numpy + ffmpeg, deterministisch): `hype_track`
  (140 BPM EDM, Drops bei 6.86 s / 27.43 s), `clean_track` (105 BPM, minimal),
  9 SFX (Whooshes, Impacts, Riser, Dosen-Fizz, Sparkle, UI-Tick) und
  `beat_grid.json` als frame-genaue Timing-Basis. Frei ersetzbar durch einen
  lizenzierten Song — die Schnitte hängen am Beat-Grid.
- `assets/fonts/` — Inter, Space Grotesk, Bebas Neue (alle OFL, Lizenz beiliegend).
- `remotion/` — Remotion-4-Projekt mit vier Compositions
  (`EarlyHypeTikTok`, `EarlyHypeLandscape`, `EarlyCleanTikTok`,
  `EarlyCleanLandscape`), geteilten Motion-Primitives (KenBurns, Glitch,
  Shake, SpeedRamp, TypeReveal, BubbleField, Grain u. a.) und Beat-Sync-Helfern.

## Trailer neu rendern

```bash
cd DrinkTrailer/remotion
source ~/.nvm/nvm.sh
npm install            # synct Assets automatisch nach public/
npm run render:all     # rendert alle vier MP4s nach ../trailers/
# einzeln:
npx remotion render EarlyHypeTikTok ../trailers/early_hype_tiktok_9x16.mp4 --codec=h264 --crf=18 --timeout=600000
```

3D-Renders reproduzieren:

```bash
cd DrinkTrailer/assets/blender
python3 gen_labels.py                 # Label-PNGs (deterministisch)
blender -b -P build_can.py -- --shot stills      # Sorten-/Trio-Stills
blender -b -P build_can.py -- --shot turntable   # 72-Frame-360°-Loop
blender -b -P build_can.py -- --shot dolly       # 48-Frame-Kamerafahrt
```

Audio reproduzieren/prüfen: `python3 assets/music/generate_audio.py [--verify]`.

## Hinweise

- Alle Inhalte (Bilder, 3D, Musik, SFX) sind eigenproduziert; keine fremden
  Samples/Assets. Markentexte entsprechen der EARLY-Website
  („SPARKLING VITAMIN DRINK", „HYDRATION WITH BENEFITS", isotonisch,
  kalorienarm, Vitamine + Elektrolyte).
- TikTok-Versionen halten die untere ~20%-Zone frei (Caption-/UI-Safe-Zone).
