class_name PanelSheetLayout
extends RefCounted
## FIX1 — PURE Sheet-Geometrie (headless testbar): Sheets erscheinen als
## zentriertes Blatt über einer Abdunkelung, statt vollflächig ALLES zu
## überdecken (P0 „Interface nimmt den ganzen Platz ein / überschneidet“).
## Regeln:
## - Breite: höchstens MAX_WIDTH×Faktor, nie breiter als der sichere Bereich
##   minus Seitenränder — das HUD bleibt daneben/darüber sichtbar.
## - Höhe: wächst mit dem Inhalt, ist aber auf MAX_HEIGHT_SHARE des sicheren
##   Bereichs gedeckelt UND lässt oben TOP_RESERVE für die HUD-Statuszeile
##   frei; mehr Inhalt scrollt (Patchnotes-Fix).
## - Position: horizontal zentriert, unten mit BOTTOM_GAP über dem
##   Home-Indicator (Safe-Area-Klemmung).

## Seitenrand (Design-px, wird mit dem UiScale-Faktor multipliziert).
const MARGIN := 24.0
## Abstand zur Unterkante (zusätzlich zum Safe-Area-Inset).
const BOTTOM_GAP := 16.0
## Maximale Sheet-Breite in Design-px (Web-Referenz: Karten ≤ 720).
const MAX_WIDTH := 720.0
## Oben freigehaltener Streifen (HUD-Statuszeile bleibt sichtbar).
const TOP_RESERVE := 96.0
## Höhen-Deckel als Anteil des sicheren Bereichs.
const MAX_HEIGHT_SHARE := 0.78


## Nutzbare Sheet-Breite.
static func sheet_width(canvas: Vector2, insets: Dictionary, f: float) -> float:
	var avail := canvas.x - float(insets["left"]) - float(insets["right"]) - 2.0 * MARGIN * f
	return minf(MAX_WIDTH * f, maxf(avail, 0.0))


## Höhen-Deckel für das ganze Sheet (inkl. Titel/Chrome).
static func max_sheet_height(canvas: Vector2, insets: Dictionary, f: float) -> float:
	var safe_h := canvas.y - float(insets["top"]) - float(insets["bottom"])
	var cap := safe_h * MAX_HEIGHT_SHARE
	var with_reserve := safe_h - TOP_RESERVE * f - BOTTOM_GAP * f
	return maxf(minf(cap, with_reserve), 0.0)


## Finale Sheet-Geometrie: `desired_h` = gewünschte Gesamthöhe (Inhalt +
## Chrome); wird auf den Deckel geklemmt. Ergebnis liegt IMMER im sicheren
## Bereich (Notch/Home-Indicator).
static func sheet_rect(canvas: Vector2, insets: Dictionary, f: float, desired_h: float) -> Rect2:
	var width := sheet_width(canvas, insets, f)
	var height := clampf(desired_h, 0.0, max_sheet_height(canvas, insets, f))
	var safe_left := float(insets["left"])
	var safe_right := canvas.x - float(insets["right"])
	var x := safe_left + ((safe_right - safe_left) - width) / 2.0
	var y := canvas.y - float(insets["bottom"]) - BOTTOM_GAP * f - height
	return Rect2(x, y, width, height)
