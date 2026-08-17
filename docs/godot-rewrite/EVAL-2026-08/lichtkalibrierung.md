# Lichtkalibrierung (EVAL-2026-08, Lens B Befund 6 „Überbelichtung“)

Die globale Belichtungskette hat jetzt EINE Quelle:
`GOOBY-GODOT/scripts/world/licht_kalibrierung.gd` (`LichtKalibrierung`).
Welt-Agents setzen nur noch LOKALE Lichter — Tonemapper, Exposure,
Energie-Budgets und Außen-Nebel kommen aus dieser Referenz.

## Methode

- Mess-Skript: `GOOBY-GODOT/tests/tools/licht_messung.gd` — rendert die
  Referenz-Motive headless mit dem ECHTEN Renderer (`gl_compatibility`,
  1280×720) und misst pro Motiv:
  - mittlere Bild-Luma (BT.709 auf sRGB: `0.2126 R + 0.7152 G + 0.0722 B`),
  - 16-Bin-Histogramm (Anteile),
  - Clipping-Anteile (Luma ≥ 0.98 bzw. ≤ 0.02) in Prozent der Pixel.
- Aufruf (immer über flock + isoliertes Profil, eine Godot-Instanz):

  ```bash
  flock /tmp/gooby-godot.lock bash tools/ci/run_godot_isolated.sh \
    xvfb-run -a godot --path GOOBY-GODOT \
    --rendering-method gl_compatibility --rendering-driver opengl3 \
    --audio-driver Dummy \
    --script res://tests/tools/licht_messung.gd -- [vorher|nachher]
  ```

- Motive: Wohnzimmer + Bad (13 Uhr, echte Rig-Perspektive, Gooby geparkt),
  Garten 13/19.2/21.5 Uhr (Eval-03-Kamera), Stadt Straßenniveau (11 Uhr),
  Ranch-Panorama (11 Uhr). UI-Ebenen (inkl. Autoload-Toasts) sind während
  der Messung versteckt, die adaptive Qualitäts-Bremse ist aus.
- Wetter der Garten-Motive ist auf SONNE gepinnt (Himmel + Garten-WetterFx):
  der echte SoulWetter-Tagesplan ist pro Datum zufällig — ein Regen-Tag
  würde die Luma-Reihe unvergleichbar machen.
- Ausgabe: PNGs + `messwerte.json` unter
  `/tmp/gooby-godot/artifacts/LICHT/<phase>/`.
- HUD-Belege (iPhone-Leitformat 2340×1080 wie Eval-Shot 17) rendert
  `tests/tools/licht_hud_screens.gd` im echten Spiel-Boot.
- Nachher-Belege liegen unter `after-licht-garten/` (PNG, 256-Farben-
  quantisiert < 400 KB).

## Zielwerte

| Kennzahl | Ziel |
| --- | --- |
| Mittlere Luma am Tag | 0,45–0,55 |
| Clipping-Spitzen (Luma ≥ 0,98) | < 2 % der Pixel |
| Nacht-Luma (Spielbarkeit) | ≥ 0,12 |

Wächter: `LichtKalibrierung.im_zielfenster()` +
`tests/unit/test_licht_kalibrierung.gd`.

## Kalibrierte Kette (Endwerte)

| Parameter | Wert | Begründung |
| --- | --- | --- |
| Tonemapper | Filmic | rollt Spitzlichter weich ab; ACES entsättigt die Pastell-Palette, Linear clippt hart |
| `tonemap_white` | 1,35 | Cremewände landen in der Filmic-Schulter statt in der Clipping-Spitze |
| Exposure `innen` | 0,55 | Wohn-/Schlafzimmer/Küche |
| Exposure `innen_kuehl` | 0,33 | Bad (Weiß-auf-Weiß-Palette braucht deutlich weniger) |
| Exposure `draussen` | 0,36 | Garten (heller Himmel + Rasen dominieren) |
| Void-Dämpfung (`HINTERGRUND_DAEMPFUNG`) | 0,30 | BG_COLOR umgeht in `gl_compatibility` die Tonemap-Kette (gemessen: Bad-Motiv reagierte nicht auf Exposure) — der Innenraum-„Void“ wird deshalb direkt gedämpft |
| Energie-Budget Tag innen | Ambient 0,42 / Sonne 0,46 / Füll 0,30 | Summe hält Materialien unter der Filmic-Schulter |
| Energie-Budget Tag draußen | Ambient 0,36 / Sonne 0,72 | Sonne führt, Ambient stützt die Schattenseite |
| Außen-Nebel | exponentiell, Dichte 0,0085, `fog_sky_affect` 0 | bindet Fern-Kulissen an die Horizontfarbe des Himmels, ohne den Sky zu verwaschen |

Anwendung: RoomBase-Räume bauen ihre Kette über
`scripts/home/exterior/raum_licht.gd` (HomeLicht-Profil × LichtKalibrierung;
draußen echter `GoobyHimmel`-Shader als BG_SKY plus Nebel).

## Messwerte vorher → nachher

| Motiv | Luma vorher | Clip vorher | Luma nachher | Clip nachher |
| --- | --- | --- | --- | --- |
| Haus Wohnzimmer (Tag) | 0,748 | 8,60 % | **0,536** | 0,28 % |
| Haus Bad (Tag) | 0,852 | 23,93 % | **0,548** | 0,00 % |
| Garten (Tag) | 0,851 | 5,54 % | **0,544** | 0,00 % |
| Garten (Abend) | 0,501 | 0,00 % | 0,336 | 0,00 % |
| Garten (Nacht) | 0,221 | 0,00 % | 0,146 (≥ 0,12 ✓) | 0,00 % |
| Stadt (Tag) | 0,729 | 6,05 % | 0,745 | 8,53 % |
| Ranch-Panorama | 0,805 | 0,00 % | 0,846 | 0,78 % |

Hinweise zur Vorher-Messung: sie entstand vor der Kamera-/Gooby-Fixierung
des Mess-Skripts (Rahmenrauschen ±0,03 Luma) und vor dem Wetter-Pin —
die Abend-/Nacht-Zeile trägt daher einen Wetter-Vorbehalt (vorher lief
der Zufallsplan). Die Größenordnung der Verbesserung (−0,2 bis −0,3 Luma
am Tag, Clipping praktisch eliminiert) ist davon unberührt.

## Handover an Stadt-/Ranch-Agents

Stadt (`scripts/city/city_licht.gd`) und Ranch
(`scripts/ranch/welt/ranch_region_scene.gd`) bauen eigene Environments und
liegen AUSSERHALB der Schreib-Zone dieses Agents. Beide liegen weiterhin
über dem Zielfenster (Stadt 0,74 Luma / 8,5 % Clip; Ranch 0,85 Luma).
Erwartete Anpassung dort (je ~3 Zeilen):

```gdscript
LichtKalibrierung.anwenden(env, "draussen")  # Tonemap + Exposure
LichtKalibrierung.nebel_anwenden(env, horizont_farbe)  # optional
```

Danach `licht_messung.gd` erneut laufen lassen; Zielfenster wie oben.
