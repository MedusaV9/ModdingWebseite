# Cosmetics-Overlays (Kosmetik-Welle 3)

Echte Shop-Kosmetik mit sichtbarer Wirkung am Affen/Podium — Renderer ist
`client/shared/meta-avatar.ts` (`schmueckePuppen`), Katalog `shared/meta.ts`.
Die Dateien hier sind die EINZIGE Quelle der Grafiken: der Client lädt sie
build-zeitlich per Vite `?raw` und injiziert nur den Inhalt des Wurzel-`<svg>`
in die Puppen (Werkzeuge wie `tools/art/cosmetics-probe.mts` lesen dieselben
Dateien per `fs`).

## Datei-Konventionen

- **Kopf-Overlays** (`hut-*.svg`) + **Gesichts-Overlays** (`gesicht-*.svg`):
  volle Puppen-viewBox `0 0 240 320`, gezeichnet im STANDARD-Kopfraum von
  Don Bananas (Kopf-Mitte 120/94, r 44, Augen ≈ 104/136 auf y 82, Nase y 100,
  Mund y 112, Hut-Zone y 10–60). ACHTUNG: Die Puppen teilen die Kopf-Position
  NICHT (Kiki tief, Oma vorgebeugt, Paule winzig) — der Renderer mappt die
  Overlays per `KOPF_ANKER`-Tabelle (translate + scale) auf jede Puppe
  (Details: `assets/img/monkeys/README.md`). Kopf-Overlays docken im
  `#accessoire`-Slot an (Standard-Hut wird dabei per CSS ausgeblendet),
  Gesichts-Overlays direkt im `#kopf` — beide nicken/schütteln also mit.
- **Fell-Pattern-Kacheln** (`fell-*.svg`): kleine, NAHTLOS kachelbare Tiles
  (viewBox = Kachelmaß). Basis-Rect nutzt `var(--fell, …)`, damit Farb-Swaps
  (Palette, Leopard/Neon/Spezies) durchs Muster scheinen. Der Renderer packt
  den Tile-Inhalt in ein `<pattern>` mit Instanz-eindeutiger Id und überschreibt
  `.fell`-fill/`.fell-s`-stroke (Details: `assets/img/monkeys/README.md`).
  Nahtlos-Regeln: Formen bleiben komplett im Tile ODER angeschnittene Formen
  wiederholen sich um genau eine Kachelbreite/-höhe versetzt.
- **Podium-Deko** (`podium-girlande.svg`): eigenes Seitenverhältnis, wird als
  absolut positioniertes Element ÜBER den Podest-Slot gelegt (kein Puppen-Teil).

## Animations-Klassen (CSS liegt in meta-avatar.ts, nie in den Dateien!)

`<style>`-Blöcke in injizierten Overlays würden dokumentweit leaken — deshalb
tragen animierte Teile nur KLASSEN, die zugehörigen Keyframes liefert der
Renderer (inkl. `prefers-reduced-motion`-Bremse):

| Klasse | Datei | Wirkung |
|---|---|---|
| `mm-propeller` | hut-propeller | Rotor-Flip-Drehung |
| `mm-heiligenschein` | hut-heiligenschein | sanftes Auf-und-ab-Schweben |
| `mm-partyhut-konfetti` | hut-partyhut | Konfetti-Flattern an der Spitze |
| `mm-kaugummi` | gesicht-kaugummi | dezentes Blasen-Pulsieren |

Ausnahme: `fell-goldglitzer` funkelt per SMIL-`<animate>` IN der Kachel
(pattern-Inhalt ist für CSS-Animationen unzuverlässig; ohne SMIL bleibt
statischer Glitzer — kein Bruch).

## Neue Items ergänzen

1. SVG hier ablegen (Konventionen oben, Outlines `#1A1208`, Breiten 2–5).
2. Katalog-Eintrag in `shared/meta.ts` (`SHOP_ITEMS`, `visuell: true`).
3. In `meta-avatar.ts` registrieren (`HUT_OVERLAYS`/`GESICHT_OVERLAYS`/
   `FELL_MUSTER`/…) — der Renderer-Abdeckungs-Test in
   `client/shared/meta-avatar.test.ts` schlägt sonst fehl.
4. Stilprobe neu rendern: `npx tsx tools/art/cosmetics-probe.mts`.
