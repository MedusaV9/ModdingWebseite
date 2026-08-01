# GOOBY 5.1 — Godot-Update-Trailer

Offizieller Trailer zum Godot-Engine-Update: **1920×1080, 60 fps, 62,4 s**,
gebaut mit [Remotion](https://remotion.dev). Finales Video:
`GOOBY-5.1-Godot-Trailer.mp4` (in diesem Ordner — Aufnahme NACH dem
W16/G4-UI-Rework, Storyboard v4). Die Vorfassung
`GOOBY-5.0-Godot-Update-Trailer.mp4` (57,6 s, Vor-W14-UI) bleibt als
Referenz daneben liegen.

## Neu rendern

```bash
cd trailer
npm ci
npx remotion render Trailer GOOBY-5.1-Godot-Trailer.mp4   # = npm run render
```

Codec/CRF stehen in `remotion.config.ts` (H.264, **CRF 16**, PNG-Frames —
kein verlustiges JPEG-Zwischenformat). Vorschau/Studio: `npm run dev`
(Remotion Studio auf localhost:3000).

Alle Zutaten liegen in `public/`:

- `public/clips/*.mp4` — die Gameplay-Aufnahmen (siehe unten)
- `public/audio/glitter_blast_cut624.m4a` — Musik, fertig geschnitten
  (62,4 s; die alte 57,6-s-Fassung `glitter_blast_cut576.m4a` bleibt
  für den v3-Stand liegen)
- `public/img/icon.png`, `public/img/key_artwork_gooby_ranch.webp`,
  `public/img/logo_gooby_ranch_frei.webp`,
  `public/fonts/baloo2-latin-var.woff2` — Branding/Key-Art (Ranch-Artwork
  aus `GOOBY-GODOT/assets/ranch/artwork/`)

## Aufbau (Sekunden-Fahrplan)

Der Schnitt liegt auf dem Beat („Glitter Blast“, 100 BPM → 1 Beat = 36
Frames; 104 Beats = 62,4 s). Fahrplan siehe Kommentar in
`src/Trailer.tsx`:
**Boot-Cover** (Möhren-Ladebalken + Kreis-Wipe ins Wohnzimmer) →
Titelkarte → wiederhergestellter Original-Gooby (Showcase, Fell-Look) →
**Emotions-Nahaufnahme** (Schreck + Verliebtheit mit Symbol, Regie-Zoom) →
Zuhause mit echten Möbeln → **Kühlschrank 2.0** (Regal-Grid + Mampf) →
Baumodus/**Gestalten-Modus** → **Haus im Garten** (HAUS-SICHT) →
GOUHBUS/Garderobe (93 Teile) → Stadt (Panorama/Tag/Nacht) →
**eigener Marktstand** → **Funkelpark** (Tor-Totale + Achterbahn-POV) →
Minispiel-Montage („38 Minispiele“, Beat-Schnitte inkl.
Hochkant-Triptychon) → Multiplayer-Besuch → **Urlaubs-Besuch am Strand**
→ **Kapitel-Karte GOOBY RANCH** (Key-Artwork + Logo) → Überlandfahrt →
Hof mit Pferden → freies Reiten → **Bergmassiv mit Hängebrücke + Bergsee**
→ Neue-Zonen-Montage (Lavendelwiese, Nebelmoor, Turmruine, Muschelbucht,
Apfelgarten, Kornfeld) → 7 Wetterlagen & Tageszeiten → Dorf Hufingen
(Quests & NPCs) → Turnier-Springen (Liga) → Multiplayer-Ausritt →
Outro mit Feature-Chips und Musik-Credit.

Zahlen-Stand W16: die Labels sagen **38 Minispiele** (MinigameRegistry:
4 feste Einträge + 34 `game.json`-Manifeste) und **93 Kosmetik-Teile**
(CosmeticsCatalog: 30 Hüte, 17 Brillen, 18 Hals, 14 Rücken, 14 Felle);
seit G5 auch im Outro-Chip (vorher stand dort noch „36“).

## Storyboard v4 (umgesetzt in `GOOBY-5.1-Godot-Trailer.mp4`)

**Vier neue Kapitel** (Treiber liegen bereit, s. u.): `boot_cover`
(Boot-Cover-Ladebildschirm mit Möhren-Ladebalken — der „neuer Look ab
Sekunde 1“-Beweis), `fuettern` (Kühlschrank 2.0: Regal-Grid + Mampf-Sequenz
mit Verliebtheit), `markt` (eigener Wochenmarkt-Stand mit Verkaufs-Replay)
und `urlaub` (Urlaubs-Besuch am Strand: Tap-Spots, Statisten, Souvenir).

**Länge:** 96 → **104 Beats = 62,4 s** (Raster 100 BPM bleibt). Musik
(erledigt, G5): `public/audio/glitter_blast_cut624.m4a` — gleiches Rezept
wie v3 (Start am Downbeat 2,25 s im Original, loudnorm −14 LUFS, 2,2 s
Fade-out ab 60,2 s), `TRAILER_DURATION` steht auf `104 * BEAT`.
Gegenfinanzierung der +8 Beats: Titelkarte 4→2 (das Boot-Cover trägt
jetzt den Marken-Moment; TitleCard-Federn dafür vorgezogen),
Emotion-Herz-Slot 2→1, Baumodus 2 Slots→1 Slot à 3, Funkelpark-POV 3→2.

Beat-Plan (1 Beat = 0,6 s; NEU = neues Kapitel):

| Beats | Zeit (s) | Inhalt |
|---|---|---|
| 0–2 | 0,0–1,2 | NEU `boot_cover` I: Cover-Artwork, Möhren-Balken füllt sich |
| 2–4 | 1,2–2,4 | NEU `boot_cover` II: Kreis-Wipe öffnet ins Wohnzimmer (Flash) |
| 4–6 | 2,4–3,6 | Titelkarte „GOOBY 5.0“ (gekürzt) |
| 6–10 | 3,6–6,0 | `showcase` — „Alles neu — und ganz der Alte!“ |
| 10–12 | 6,0–7,2 | `emotion` Schreck |
| 12–13 | 7,2–7,8 | `emotion` Herz (gekürzt) |
| 13–16 | 7,8–9,6 | `home_room` — Zuhause mit echten Möbeln |
| 16–19 | 9,6–11,4 | NEU `fuettern` — „Neu: Kühlschrank 2.0 — Mampf-Zeit!“ |
| 19–22 | 11,4–13,2 | `home_build` (1 Slot statt 2) |
| 22–25 | 13,2–15,0 | `home_style` — Gestalten-Modus |
| 25–28 | 15,0–16,8 | `haus_garten` — Haus im Garten |
| 28–30 | 16,8–18,0 | `ikea` — GOUHBUS |
| 30–33 | 18,0–19,8 | `wardrobe` — „93 Kosmetik-Teile“ |
| 33–35 | 19,8–21,0 | `city_overview` |
| 35–38 | 21,0–22,8 | `city_day` |
| 38–40 | 22,8–24,0 | `city_night` |
| 40–43 | 24,0–25,8 | NEU `markt` — „Neu: dein eigener Marktstand“ |
| 43–47 | 25,8–28,2 | `funkelpark` Totale 2 + POV 2 |
| 47–59 | 28,2–35,4 | Minispiel-Montage 6×2 — „38 Minispiele“ |
| 59–61 | 35,4–36,6 | `visit` — Multiplayer-Besuch |
| 61–64 | 36,6–38,4 | NEU `urlaub` — „Neu: Besuch Gooby im Urlaub!“ |
| 64–67 | 38,4–40,2 | Kapitel-Karte GOOBY RANCH |
| 67–70 | 40,2–42,0 | `ranch_fahrt` |
| 70–73 | 42,0–43,8 | `ranch` |
| 73–76 | 43,8–45,6 | `ranch_ride` |
| 76–80 | 45,6–48,0 | `ranch_berge` Brücke 2 + See 2 |
| 80–86 | 48,0–51,6 | Zonen-Montage 6×1 |
| 86–89 | 51,6–53,4 | `ranch_wetter` |
| 89–92 | 53,4–55,2 | `ranch_dorf` |
| 92–95 | 55,2–57,0 | `ranch_comp` |
| 95–98 | 57,0–58,8 | `ranch_mp` |
| 98–104 | 58,8–62,4 | Outro (Feature-Chips + Logo + Credit) |

**Umsetzung (G5/P27, alle Schritte erledigt):** T0 (G3/P12): Zahlen-Fixes,
Storyboard, die 4 neuen Treiber, `finals.sh`-Liste. T1: `MG_RECT` und
TrioScene-Crop nach dem G4-Letterbox-Umbau per Bewegungs-Differenz neu
vermessen — Canvas quer 1632×756 @ (0,188), hochkant 472×1028 @ (124,60),
praktisch unverändert zu v3; Treiber-Selektoren (`ikea`, `wardrobe`,
`home_style`) liefen unverändert durch. T2: Probe-Pass über die neuen
und die Risiko-Clips; Befunde → drei Treiber-Fixes (nur Aufnahme-Regie):
`markt` bekam eine Kino-Kamera auf den Eigenstand (die Ort-Kamera zeigte
viel leeren Himmel) + späteres Sheet-Öffnen, `markt`/`urlaub` blenden den
„Raus“-Knopf aus, `mg_gvz` läuft 16 s statt 12 s mit nur EINEM Schützen
pro Bahn und dichterem Spawn-Plan (mit voller Abwehr starben alle Zombies
unsichtbar rechts außerhalb des MG_RECT-Cover-Crops; `startFrom` darum
850). T3: `finals.sh` komplett (34 Clips, ≈3 h auf 4 Kernen, Log im
G5-Report) → Musik-Neuschnitt → Remotion-Endrender.
`public/clips/` ist NICHT im Repo — für den v4-Render wurden ALLE Clips
neu aufgenommen, auch die unveränderten.

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

### Einzelbild-Kontrolle (v3, dokumentiert)

Vor dem Endrender wurden aus den fertigen `public/clips/*.mp4` über 20
Einzelbilder in 100 % (native 1080p, teils zusätzliche 100 %-Crops)
geprüft — pro Reviewer-Befund mindestens ein Beleg-Frame im gewählten
`startFrom`-Fenster:

- **Kornfeld** (`ranch_zonen` ~F1000): echte Ährenbüschel, im Wind geneigt
  — keine „schwebenden Pfeile“.
- **Wasser** (`ranch_berge` ~F700): Wellenringe, Tiefenverlauf,
  Schaumsaum am Ufer.
- **Hufe** (`ranch` ~F594, `ranch_comp` ~F600): Bodenkontakt bzw. sauberer
  Sprungbogen ohne Clipping durch Planken/Stangen.
- **Regen** (`ranch_wetter` ~F300): mehrschichtige Tropfen +
  Aufschlagringe.
- **Ortsschilder** (`city_day` ~F400): mitwachsende Billboards, lesbar.
- **Fell-Look** (`showcase` ~F120, 100 %-Crop): Korn, Flaum-Silhouette,
  warmer Lichtsaum.
- **Emotionen** (`emotion` F56–128/F330–402): Schreck-„!“ und Herz-Symbol
  über dem Kopf inkl. Regie-Zoom.
- **Haus im Garten** (`haus_garten` ~F400): Haus mit Dach im gewählten
  Stil, Gooby winkt vor der Tür.
- **Funkelpark** (`funkelpark` F36/F500+): lesbares Torschild bzw.
  Looping-POV.
- Alle 30 Fenster gegen die tatsächliche Framezahl der Clips geprüft
  (kein Fenster läuft über das Clip-Ende hinaus → keine Schwarzframes).

Verfügbare Clip-Treiber: `GOOBY-GODOT/tools/capture/clips/*.gd`
(Minigames als `mg_*`, Stadt `city_*`, Haus `home_*` inkl. `home_style`
für den Gestalten-Modus, Ranch `ranch`, `ranch_fahrt`, `ranch_ride`,
`ranch_berge`, `ranch_zonen`, `ranch_comp`, `ranch_dorf`, `ranch_wetter`,
`ranch_mp`, dazu `showcase`, `wardrobe`, `ikea`, `visit`, `cutscene` —
und neu: `emotion` (FEEL-AC-Nahaufnahme mit Schreck/Verliebtheit inkl.
MomentRegie-Zoom), `haus_garten` (HAUS-SICHT: das eigene Haus im Garten)
und `funkelpark` (Tor-Totale + Achterbahn-POV; Boarding/Lift werden per
deterministischem `simuliere()`-Vorlauf übersprungen)).
Storyboard-v4-Treiber (W16/T0): `boot_cover` (Möhren-Ladebalken über der
CLIP-Zeit + `oeffne()`-Kreis-Wipe ins Wohnzimmer; fasst `main.gd` NICHT
an), `fuettern` (Kühlschrank-Regal-Grid; die Mampf-Beats werden vom
Treiber in Movie-Zeit nachgespielt, weil FuetterSequenz/`walk_to` über
die Wanduhr takten — s. u.), `urlaub` (Strand-Besuch; Kamera-Push-in
läuft bewusst über die ORT-Kamera, damit die per `unproject_position`
platzierten Muschel-Tap-Spots zur renderenden Kamera passen) und `markt`
(Eigenstand: bestückt mit dem Zeitstempel des LETZTEN Samstags 7:00 —
Status „fertig“, das deterministische Verkaufs-Replay startet sofort).
WICHTIG für Treiber-Autoren: `GoobyHome.walk_to()` hat ein WANDUHR-Timeout
(`Time.get_ticks_msec`) — im Movie-Maker (1–6 fps Wandzeit) bricht das
Läufe nach wenigen Frames ab. In Treibern stattdessen
`gooby.call("_start_walking", ziel)` benutzen (ohne Timeout).
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
