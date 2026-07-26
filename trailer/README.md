# GOOBY 5.0 — Godot-Update-Trailer

Offizieller Trailer zum Godot-Engine-Update: **1920×1080, 60 fps, ~37 s**,
gebaut mit [Remotion](https://remotion.dev). Finales Video:
`GOOBY-5.0-Godot-Update-Trailer.mp4` (in diesem Ordner).

## Neu rendern

```bash
cd trailer
npm ci
npx remotion render Trailer GOOBY-5.0-Godot-Update-Trailer.mp4 --codec h264 --crf 20
```

Vorschau/Studio: `npm run dev` (Remotion Studio auf localhost:3000).

Alle Zutaten liegen in `public/`:

- `public/clips/*.mp4` — die Gameplay-Aufnahmen (siehe unten)
- `public/audio/glitter_blast_cut.m4a` — Musik, fertig geschnitten
- `public/img/icon.png`, `public/fonts/baloo2-latin-var.woff2` — Branding

## Aufbau (Sekunden-Fahrplan)

Der Schnitt liegt auf dem Beat („Glitter Blast“, 100 BPM → 1 Beat = 36
Frames). Fahrplan siehe Kommentar in `src/Trailer.tsx`:
Titelkarte → 3D-Gooby → Zuhause/Baumodus → GOUHBUS/Garderobe →
Stadt (Panorama/Tag/Nacht) → Minispiel-Montage (Beat-Schnitte, inkl.
Hochkant-Triptychon) → Multiplayer-Besuch → Ranch-Teaser → Outro mit
Feature-Chips und Musik-Credit.

## Gameplay-Clips neu aufnehmen

Die Clips entstehen **direkt aus dem Godot-Projekt** (keine Standbilder):
`GOOBY-GODOT/tools/capture/` enthält eine Capture-Bühne, die echte
Spielszenen mountet, Eingaben injiziert (Tippen/Wischen/Tasten bzw. die
eingebauten Autoplay-Bots) und im Movie-Maker-Modus mit fester
60-fps-Schrittweite aufzeichnet:

```bash
# einzelner Clip (schreibt <name>.avi nach $OUT_DIR, Default trailer/captures)
GOOBY-GODOT/tools/capture/record.sh <clip-name> 960x540 30

# alle Clips klein probeweise (Kontrollbilder nach trailer/probe/)
GOOBY-GODOT/tools/capture/probe_all.sh showcase city_day mg_toy_racer ...

# finale Aufnahmen inkl. AVI→MP4-Konvertierung nach public/clips/
GOOBY-GODOT/tools/capture/finals.sh            # alle Trailer-Clips
GOOBY-GODOT/tools/capture/finals.sh mg_gvz     # einzelne neu aufnehmen
```

Verfügbare Clip-Treiber: `GOOBY-GODOT/tools/capture/clips/*.gd`
(Minigames als `mg_*`, Stadt `city_*`, Haus `home_*`, dazu `showcase`,
`wardrobe`, `ikea`, `visit`, `ranch`, `cutscene`). Die Minigame-Treiber
pushen Touch-Events direkt in den SubViewport des MinigameHost
(Fenster-Events erreichen dessen `_unhandled_input` nicht).

## Musik-Lizenz

Siehe `CREDITS.md` (Kevin MacLeod, CC BY 4.0 — Namensnennung ist im
Outro des Trailers eingeblendet).
