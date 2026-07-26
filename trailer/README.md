# GOOBY 5.0 — Godot-Update-Trailer

Offizieller Trailer zum Godot-Engine-Update: **1920×1080, 60 fps, ~44 s**,
gebaut mit [Remotion](https://remotion.dev). Finales Video:
`GOOBY-5.0-Godot-Update-Trailer.mp4` (in diesem Ordner).

## Neu rendern

```bash
cd trailer
npm ci
npx remotion render Trailer GOOBY-5.0-Godot-Update-Trailer.mp4
```

Codec/CRF stehen in `remotion.config.ts` (H.264, **CRF 16**, PNG-Frames —
kein verlustiges JPEG-Zwischenformat). Vorschau/Studio: `npm run dev`
(Remotion Studio auf localhost:3000).

Alle Zutaten liegen in `public/`:

- `public/clips/*.mp4` — die Gameplay-Aufnahmen (siehe unten)
- `public/audio/glitter_blast_cut.m4a` — Musik, fertig geschnitten (44,4 s)
- `public/img/icon.png`, `public/fonts/baloo2-latin-var.woff2` — Branding

## Aufbau (Sekunden-Fahrplan)

Der Schnitt liegt auf dem Beat („Glitter Blast“, 100 BPM → 1 Beat = 36
Frames). Fahrplan siehe Kommentar in `src/Trailer.tsx`:
Titelkarte → 3D-Gooby → Zuhause/Baumodus → GOUHBUS/Garderobe →
Stadt (Panorama/Tag/Nacht) → Minispiel-Montage (Beat-Schnitte, inkl.
Hochkant-Triptychon) → Multiplayer-Besuch → **Ranch-Update-Block**
(Hof mit Pferden → freies Reiten in der offenen Region → Wetter- und
Tageszeiten-Zeitraffer → Reit-Dorf Hufingen → Turnier-Springen) →
Outro mit Feature-Chips und Musik-Credit.

## Gameplay-Clips neu aufnehmen

Die Clips entstehen **direkt aus dem Godot-Projekt** (keine Standbilder):
`GOOBY-GODOT/tools/capture/` enthält eine Capture-Bühne, die echte
Spielszenen mountet, Eingaben injiziert (Tippen/Wischen/Tasten bzw. die
eingebauten Autoplay-Bots) und im Movie-Maker-Modus mit fester
60-fps-Schrittweite aufzeichnet:

```bash
# einzelner Clip: PNG-Einzelbilder nach $OUT_DIR/<name>/ (Default trailer/captures)
GOOBY-GODOT/tools/capture/record.sh <clip-name> 1920x1080 30

# alle Clips klein probeweise (MJPEG-AVI + Kontrollbilder nach trailer/probe/)
GOOBY-GODOT/tools/capture/probe_all.sh showcase city_day mg_toy_racer ...

# finale Aufnahmen inkl. PNG→MP4-Encode nach public/clips/
GOOBY-GODOT/tools/capture/finals.sh            # alle Trailer-Clips
GOOBY-GODOT/tools/capture/finals.sh mg_gvz     # einzelne neu aufnehmen
```

### Qualitäts-Kette (WICHTIG — so bleibt der Trailer scharf)

Das „pixelig“-Feedback zum ersten Trailer kam aus der Aufnahme-Kette
(960×540-Aufnahme → 2×-Lanczos-Upscale → doppelte H.264-Kompression).
Die Kette ist jetzt durchgehend verlustarm — beim Neu-Aufnehmen NICHT
wieder absenken:

1. **Native Zielauflösung aufnehmen:** quer **1920×1080**, hochkant
   **720×1280** (`finals.sh`, per `LAND_RES`/`PORTRAIT_RES` übersteuerbar
   — z. B. 2560×1440 als Zoom-Reserve, kostet unter llvmpipe ~1,8× Zeit).
   Niemals kleiner aufnehmen und hochskalieren.
2. **Godot-Qualität wird erzwungen:** `clip_driver.gd` setzt beim Start
   `graphics.preset=hoch` (volle 3D-Skalierung, Schatten-Atlas 4096,
   Glow an) **plus MSAA 4×** — auch auf den Minigame-SubViewport
   (`_mg_base.gd`). Das Auto-Profil würde sonst je nach xvfb-Umgebung
   herunterstufen; MSAA war früher fürs Capture hart deaktiviert.
3. **Verlustfreies Zwischenformat:** Movie-Maker schreibt PNG-Einzelbilder
   (kein MJPEG mehr), `finals.sh` encodiert daraus H.264 **CRF 14**
   `preset slow` (visuell transparent, Chrome-kompatibel für Remotion).
4. **Ein einziger End-Encode:** Remotion rendert PNG-Frames und encodiert
   final H.264 **CRF 16** (`remotion.config.ts`) — kein weiteres
   Umkodieren dahinter.

Movie-Maker rendert offline (feste Schrittweite) — die Aufnahme darf
beliebig langsam sein, unter llvmpipe sind ~1–3 fps normal (alle Clips
zusammen ≈ 2–3 h).

Verfügbare Clip-Treiber: `GOOBY-GODOT/tools/capture/clips/*.gd`
(Minigames als `mg_*`, Stadt `city_*`, Haus `home_*`, Ranch `ranch`,
`ranch_ride`, `ranch_comp`, `ranch_dorf`, `ranch_wetter`, dazu
`showcase`, `wardrobe`, `ikea`, `visit`, `cutscene`). Die Minigame-Treiber
pushen Touch-Events direkt in den SubViewport des MinigameHost
(Fenster-Events erreichen dessen `_unhandled_input` nicht).

## Musik-Lizenz

Siehe `CREDITS.md` (Kevin MacLeod, CC BY 4.0 — Namensnennung ist im
Outro des Trailers eingeblendet).
