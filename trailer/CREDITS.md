# Trailer-Credits

## Musik

- **Titel:** „Glitter Blast“
- **Künstler:** Kevin MacLeod ([incompetech.com](https://incompetech.com))
- **Quelle:** <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Glitter%20Blast.mp3>
- **Lizenz:** [Creative Commons: By Attribution 4.0](https://creativecommons.org/licenses/by/4.0/)
- **Namensnennung (wie von Incompetech vorgegeben):**

  > "Glitter Blast" Kevin MacLeod (incompetech.com)
  > Licensed under Creative Commons: By Attribution 4.0 License
  > http://creativecommons.org/licenses/by/4.0/

  Die Namensnennung ist zusätzlich im Trailer-Abspann (Outro) eingeblendet.
- **Bearbeitung:** Für die Fassung v3 auf 57,6 s (96 Beats) gekürzt
  (Start beim Downbeat bei 2,25 s, 2,2 s Fade-out ab 55,4 s), Loudness auf
  ca. −14 LUFS normalisiert (ffmpeg `loudnorm`). Tempo: 100 BPM (per
  Spektralfluss-Analyse bestätigt: 100,01 BPM) → bei 60 fps liegt jeder
  Beat auf exakt 36 Frames; alle Schnitte des Trailers sitzen auf
  Beat-Vielfachen. Der Track wurde für die neue Fassung erneut bewusst
  BEIBEHALTEN: exakt 100 BPM (verlustfreies Beat-Grid), durchgehend hohe
  Energie für die Montagen, Lizenz bereits sauber attribuiert — die
  Ranch-Wendung wird visuell (Kapitel-Karte + Flash auf Taktgrenze)
  markiert, da der Track keinen musikalischen Break besitzt. Geprüfte
  CC0/CC-BY-Alternativen boten kein sauberes 100-BPM-Grid in dieser
  Energie — der Wechsel hätte nur den Beat-Schnitt gekostet.

## Schrift

- **Baloo 2** (Variable Font) — SIL Open Font License 1.1
  (liegt im Spiel unter `GOOBY-GODOT/assets/fonts/`, OFL.txt daneben).

## Bildmaterial

- Alle Gameplay-Clips wurden mit den Skripten unter
  `GOOBY-GODOT/tools/capture/` direkt aus dem Godot-Projekt aufgenommen
  (Movie-Maker-Modus, feste 60-fps-Schrittweite, echte Spielszenen mit
  skripteten Eingaben; für v3 komplett neu aufgenommen — inkl. der neuen
  Clips `emotion`, `haus_garten` und `funkelpark`). Aufnahme-Einstellungen:
  native 1920×1080 (hochkant 720×1280), Godot-Grafikpreset „hoch“
  (inkl. Post-FX-Stufe „hoch“: Vignette, Tageszeit-Tönung, Bloom) + MSAA 4×
  erzwungen, PNG-Einzelbilder als verlustfreies Zwischenformat, H.264 CRF 14
  als Remotion-Quellmaterial, finaler Export H.264 CRF 16 (Details: README,
  „Qualitäts-Kette“). App-Icon und Farbwelt stammen aus dem GOOBY-Projekt
  selbst.
- Kapitel-Karte „GOOBY RANCH“: Key-Artwork und Holzschild-Logo aus
  `GOOBY-GODOT/assets/ranch/artwork/` (`key_artwork_gooby_ranch.webp`,
  `logo_gooby_ranch_frei.webp`) — projekteigenes Artwork.
