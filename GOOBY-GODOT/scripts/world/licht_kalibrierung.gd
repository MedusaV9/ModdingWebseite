class_name LichtKalibrierung
extends RefCounted
## DIE globale Belichtungs-Referenz aller GOOBY-Welten (EVAL-2026-08 Lens B,
## Befund 6 „Überbelichtung wäscht Materialien aus“). EINE Quelle für
## Tonemapper, Exposure und Energie-Budgets — Welt-Agents setzen nur noch
## LOKALE Lichter; die Kette hier ist kalibriert gegen die Zielwerte aus
## docs/godot-rewrite/EVAL-2026-08/lichtkalibrierung.md:
##
##   - mittlere Bild-Luma (BT.709 auf sRGB) am Tag: 0.45–0.55,
##   - Clipping-Spitzen (Luma ≥ 0.98): < 2 % der Pixel,
##   - Nacht darf dunkler sein, aber nie unter 0.12 (Spielbarkeit).
##
## Gemessen wird mit tests/tools/licht_messung.gd (Durchschnitts-Luma +
## 16-Bin-Histogramm pro Referenz-Motiv, headless über gl_compatibility).
## PURE + headless-testbar (tests/unit/test_licht_kalibrierung.gd).

## Zielfenster der Tages-Luma (Dokumentation + Testwächter).
const ZIEL_LUMA_MIN := 0.45
const ZIEL_LUMA_MAX := 0.55
const ZIEL_CLIP_PROZENT := 2.0
const NACHT_LUMA_MIN := 0.12

## EIN Tonemapper fürs ganze Spiel: Filmic rollt Spitzlichter weich ab
## (ACES entsättigt die Pastell-Palette zu stark, Linear clippt hart).
const TONEMAP_MODE := Environment.TONE_MAPPER_FILMIC
## Weißpunkt > 1 gibt der Filmic-Kurve Luft, bevor sie abrollt — helle
## Cremewände landen im Schulter-Bereich statt in der Clipping-Spitze.
const TONEMAP_WEISS := 1.35

## Exposure je Kontext — kalibriert gegen die Referenz-Motive (Werte in
## lichtkalibrierung.md; Bad braucht wegen Weiß-auf-Weiß-Palette weniger).
const EXPOSURE := {
	"innen": 0.55,
	"innen_kuehl": 0.33,
	"draussen": 0.36,
}

## BG_COLOR umgeht im gl_compatibility-Renderer die Tonemap-Kette
## (gemessen: das Bad-Motiv reagierte praktisch NICHT auf Exposure-
## Änderungen — der Void dominiert dort das Bild). Der Innenraum-„Void“
## wird deshalb HIER gedämpft, damit er zur belichteten Szene passt.
const HINTERGRUND_DAEMPFUNG := 0.3

## Energie-Budget (Ambient + Sonne + Füll) — die Summe hält Materialien
## unterhalb der Filmic-Schulter. Werte sind BASIS für Tag; Tageszeit-Lerps
## leben in den Welt-Profilen (HomeLicht etc.).
const BUDGET_AMBIENT_TAG := 0.42
const BUDGET_SONNE_TAG := 0.46
const BUDGET_FUELL_TAG := 0.3
const BUDGET_DRAUSSEN_AMBIENT_TAG := 0.36
const BUDGET_DRAUSSEN_SONNE_TAG := 0.72

## Nebelschleier der Außen-Horizonte: exponentiell, schont die Sky-Farbe
## (fog_sky_affect 0) und taucht Fern-Kulissen in die Horizontfarbe.
const NEBEL_DICHTE_DRAUSSEN := 0.0085


## Kontext eines Raums/Orts → Exposure-Wert der Kette.
static func exposure(kontext: String) -> float:
	return float(EXPOSURE.get(kontext, EXPOSURE["innen"]))


## Tonemap-Kette auf ein Environment anwenden (der EINE Ort, an dem
## tonemap_mode/exposure/white gesetzt werden — Welt-Szenen rufen das).
static func anwenden(env: Environment, kontext: String) -> void:
	env.tonemap_mode = TONEMAP_MODE
	env.tonemap_white = TONEMAP_WEISS
	env.tonemap_exposure = exposure(kontext)


## Void-Hintergrundfarbe der Innenräume (Profil-Pastell → gedämpft).
static func hintergrund(farbe: Color) -> Color:
	return farbe.darkened(HINTERGRUND_DAEMPFUNG)


## Fertiges Environment für einen Kontext (Ambient-Quelle Farbe; Aufrufer
## setzt Hintergrund + Ambient-Farbe/-Energie aus seinem Profil).
static func environment(kontext: String) -> Environment:
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	anwenden(env, kontext)
	return env


## Außen-Nebel auf ein Environment legen (Horizontfarbe = Dunstfarbe des
## Himmels) — der Schleier bindet Fern-Kulissen an den Himmel.
static func nebel_anwenden(env: Environment, horizont: Color) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = NEBEL_DICHTE_DRAUSSEN
	env.fog_light_color = horizont
	env.fog_sky_affect = 0.0


## Liegt eine Tages-Messung im Zielfenster? (Wächter für Mess-Workflows.)
static func im_zielfenster(mittel_luma: float, clip_prozent: float) -> bool:
	if clip_prozent >= ZIEL_CLIP_PROZENT:
		return false
	return mittel_luma >= ZIEL_LUMA_MIN and mittel_luma <= ZIEL_LUMA_MAX
