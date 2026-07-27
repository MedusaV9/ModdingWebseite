# GOOBY 5.0 — Godot-Update-Trailer

Offizieller Trailer zum Godot-Engine-Update: **1920×1080, 60 fps, ~54,6 s**,
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
- `public/audio/glitter_blast_cut54.m4a` — Musik, fertig geschnitten (54,6 s)
- `public/img/icon.png`, `public/img/key_artwork_gooby_ranch.webp`,
  `public/img/logo_gooby_ranch_frei.webp`,
  `public/fonts/baloo2-latin-var.woff2` — Branding/Key-Art (Ranch-Artwork
  aus `GOOBY-GODOT/assets/ranch/artwork/`)

## Aufbau (Sekunden-Fahrplan)

Der Schnitt liegt auf dem Beat („Glitter Blast“, 100 BPM → 1 Beat = 36
Frames; Kapitelwechsel auf Taktgrenzen). Fahrplan siehe Kommentar in
`src/Trailer.tsx`:
Titelkarte → wiederhergestellter Original-Gooby (Showcase) →
Zuhause mit echten Möbeln/Baumodus/**Gestalten-Modus** → GOUHBUS/Garderobe
(92 Teile) → Stadt (Panorama/Tag/Nacht) → Minispiel-Montage („36
Minispiele“, Beat-Schnitte inkl. Hochkant-Triptychon) → Multiplayer-Besuch
→ **Kapitel-Karte GOOBY RANCH** (Key-Artwork + Logo) → Überlandfahrt →
Hof mit Pferden → freies Reiten → **Bergmassiv mit Hängebrücke + Bergsee**
→ Neue-Zonen-Montage (Lavendelwiese, Nebelmoor, Turmruine, Muschelbucht,
Apfelgarten, Kornfeld) → 7 Wetterlagen & Tageszeiten → Dorf Hufingen
(Quests & NPCs) → Turnier-Springen (Liga) → Multiplayer-Ausritt →
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
zusammen ≈ 2–3 h, unter Last entsprechend länger).

Verfügbare Clip-Treiber: `GOOBY-GODOT/tools/capture/clips/*.gd`
(Minigames als `mg_*`, Stadt `city_*`, Haus `home_*` inkl. `home_style`
für den Gestalten-Modus, Ranch `ranch`, `ranch_fahrt`, `ranch_ride`,
`ranch_berge`, `ranch_zonen`, `ranch_comp`, `ranch_dorf`, `ranch_wetter`,
`ranch_mp`, dazu `showcase`, `wardrobe`, `ikea`, `visit`, `cutscene`).
Die Minigame-Treiber pushen Touch-Events direkt in den SubViewport des
MinigameHost (Fenster-Events erreichen dessen `_unhandled_input` nicht).
Trailer-Regie-Detail: Der lokale `RanchWeltReiter` zeigt selbst keinen
Gooby im Sattel (nur Mitspieler sehen einen via `RmpRemoteRider`) — die
Reit-Treiber setzen deshalb über `clip_driver.gooby_in_den_sattel()` einen
sichtbaren Gooby samt Sattel aufs Pferd (reine Aufnahme-Regie).

Zweites Regie-Detail: Der MinigameHost rendert das Spiel in ein
Teilrechteck des Fensters (außenrum Host-Chrome mit Sterne-Zähler und
Pause-Knopf). Im Trailer soll das SPIEL das Bild füllen — `Trailer.tsx`
schneidet deshalb per `sourceRect` (`MG_RECT`, quer) bzw. dem Karten-Crop
in `TrioScene.tsx` (hochkant) auf die per Einzelbild vermessene
Spiel-Canvas zu. Ändert sich das Host-Layout, Rechtecke neu vermessen.

## Musik-Lizenz

Siehe `CREDITS.md` (Kevin MacLeod, CC BY 4.0 — Namensnennung ist im
Outro des Trailers eingeblendet).
