class_name UiScale
extends RefCounted
## FIX1 — DIE zentrale UI-Skalierungs-Regel (P0 „UI ist meist falsch
## skaliert“). Ursache: das Projekt-Stretch (Basis 1280×720, canvas_items +
## expand) hält die kurze Canvas-Kante bei 720 px — auf einem iPhone werden
## Design-Pixel damit PHYSISCH nur ~0,55–0,6× so groß wie in der
## Web-Referenz (CSS-px ≈ iOS-Punkte). Zwei pure Regeln, beide an die
## KURZE Kante gekoppelt:
##
## - `for_canvas(canvas)`: Canvas-Kurzkante / 720 — greift in Hochkant
##   (Canvas-Kurzkante ≥ 1280) und ersetzt die alte, nur fürs HUD gedachte
##   `HudLayoutLogic.portrait_scale`-Heuristik als gemeinsame Basis.
## - `physical_factor(canvas, fenster_px, screen_scale)`: Canvas-Kurzkante /
##   (physische Kurzkante in PUNKTEN) — greift auf Retina-Geräten auch in
##   Querformat (z. B. iPhone 1792×828 @2×: 720/414 ≈ 1,74).
##
## `for_viewport()` kombiniert beide (max) und ist headless-sicher: ohne
## echten DisplayServer bleibt der physische Anteil 1,0. Panels/HUD/Screens
## multiplizieren ihre Schriften und festen Pixelwerte mit diesem Faktor.

## Design-Basis: kurze Kante des 1280×720-Referenz-Canvas.
const BASE_SHORT_EDGE := 720.0
const MIN_FACTOR := 1.0
## Deckel gegen Absurd-Werte (kleine Fenster, kaputte DPI-Reports).
const MAX_CANVAS_FACTOR := 2.6
const MAX_PHYSICAL_FACTOR := 3.0
## Tippflächen sind ein PHYSISCHES Minimum (44 pt) — ihr px/pt-Faktor darf
## deshalb höher liegen als der Design-Deckel MAX_PHYSICAL_FACTOR (iPhone
## hoch: 1280 Canvas-px / 393 pt ≈ 3,26).
const MAX_TOUCH_FACTOR := 4.0
## Safe-Area-Insets werden pro Achse gedeckelt (echte Notches liegen bei
## ≤ ~8 % — schützt vor kaputten get_display_safe_area()-Werten, z. B.
## wenn das Fenster größer als der (virtuelle) Screen ist).
const MAX_INSET_SHARE := 0.15

## Tests/Screenshot-Sim: erzwingt einen screen_scale (0 = DisplayServer).
static var screen_scale_override := 0.0
## FB3-Audit/Tests: GLOBALE Notch-Simulation — Safe-Area-Rect in
## CANVAS-Koordinaten (Rect2() = aus). Ein per-Aufruf-Override gewinnt;
## damit prüfen Audit-Läufe ALLE Screens gegen dieselbe simulierte Notch,
## ohne dass jeder Screen ein eigenes Override-Feld braucht.
static var insets_override := Rect2()
## RW-7 (Settings §4.3): Benutzerfaktoren aus AppSettings — der QualityService
## setzt sie beim Boot und bei jeder Änderung (display.ui_scale /
## display.text_scale / display.safe_area_extra). Defaults = neutrale 1.0/0.
static var user_factor := 1.0
static var text_factor := 1.0
static var extra_inset := 0.0


## Kurze CANVAS-Kante gegen die 720er-Design-Basis (pure, headless testbar).
static func for_canvas(canvas_size: Vector2) -> float:
	var short_edge := minf(canvas_size.x, canvas_size.y)
	if short_edge <= 0.0:
		return MIN_FACTOR
	return clampf(short_edge / BASE_SHORT_EDGE, MIN_FACTOR, MAX_CANVAS_FACTOR)


## Physischer Faktor: wieviel Canvas-px braucht 1 Design-px, damit er
## PHYSISCH so groß ist wie 1 Punkt der Web-Referenz (pure).
static func physical_factor(canvas_size: Vector2, window_px: Vector2, screen_scale: float) -> float:
	if screen_scale <= 0.0 or window_px.x <= 0.0 or window_px.y <= 0.0:
		return MIN_FACTOR
	var points_short := minf(window_px.x, window_px.y) / screen_scale
	if points_short <= 0.0:
		return MIN_FACTOR
	var canvas_short := minf(canvas_size.x, canvas_size.y)
	return clampf(canvas_short / points_short, MIN_FACTOR, MAX_PHYSICAL_FACTOR)


## Kombinierte Regel für einen echten Viewport (headless-sicher).
## RW-7: multipliziert den Benutzerfaktor (display.ui_scale) hinein —
## gedeckelt, damit 130 % auf großen Canvases nichts sprengt.
static func for_viewport(viewport: Viewport) -> float:
	if viewport == null:
		return MIN_FACTOR
	var canvas := Vector2(viewport.get_visible_rect().size)
	var factor := for_canvas(canvas)
	var scale := _screen_scale()
	if scale > 0.0:
		factor = maxf(factor, physical_factor(canvas, _window_px(viewport), scale))
	return clampf(factor * clampf(user_factor, 0.7, 1.6), 0.5, MAX_PHYSICAL_FACTOR)


## Canvas-px pro physischem PUNKT — Grundlage für Tippflächen-Minima
## (44 pt × diesen Faktor). Bewusst NICHT mit MAX_PHYSICAL_FACTOR gedeckelt:
## der Design-Deckel darf Schriften begrenzen, aber kein physisches
## Tippflächen-Minimum unterschreiten. Headless-sicher (Fallback 1,0).
static func touch_px_per_pt(viewport: Viewport) -> float:
	if viewport == null:
		return MIN_FACTOR
	var scale := _screen_scale()
	if scale <= 0.0:
		return MIN_FACTOR
	var window_px := _window_px(viewport)
	if window_px.x <= 0.0 or window_px.y <= 0.0:
		return MIN_FACTOR
	var points_short := minf(window_px.x, window_px.y) / scale
	if points_short <= 0.0:
		return MIN_FACTOR
	var canvas := Vector2(viewport.get_visible_rect().size)
	var canvas_short := minf(canvas.x, canvas.y)
	return clampf(canvas_short / points_short, MIN_FACTOR, MAX_TOUCH_FACTOR)


## Screen-Scale: Override (Tests) > DisplayServer (nicht headless) > 0.
static func _screen_scale() -> float:
	if screen_scale_override > 0.0:
		return screen_scale_override
	if DisplayServer.get_name() != "headless":
		return DisplayServer.screen_get_scale()
	return 0.0


## Fenstergröße in px — headless liefert der DisplayServer (0,0), dann
## zählt die Window-Größe des Viewports (Tests setzen root.size).
static func _window_px(viewport: Viewport) -> Vector2:
	var window_px := Vector2(DisplayServer.window_get_size())
	if window_px.x > 0.0 and window_px.y > 0.0:
		return window_px
	var win := viewport.get_window()
	if win != null:
		return Vector2(win.size)
	return Vector2.ZERO


## RW-7: Faktor für SCHRIFTEN — UI-Faktor × Textgrößen-Faktor
## (display.text_scale). Screens nutzen ihn für font_size-Overrides.
static func font_scale(viewport: Viewport) -> float:
	return for_viewport(viewport) * clampf(text_factor, 1.0, 1.5)


## Safe-Area-Insets in CANVAS-Koordinaten für einen echten Viewport:
## Override (Tests/Notch-Simulation) > DisplayServer > 0 (Desktop/Headless).
## Deckelt jede Seite auf MAX_INSET_SHARE der Achse (Robustheit, s. o.).
## RW-7: `extra_inset` (display.safe_area_extra, 0–24 px Feinjustierung)
## wird auf JEDE Seite addiert, bevor gedeckelt wird.
static func safe_insets_canvas(viewport: Viewport, override := Rect2()) -> Dictionary:
	var canvas := Vector2(viewport.get_visible_rect().size)
	if override != Rect2():
		return clamp_insets(_plus_extra(HudLayoutLogic.safe_insets(canvas, override)), canvas)
	if insets_override != Rect2():
		return clamp_insets(
			_plus_extra(HudLayoutLogic.safe_insets(canvas, insets_override)), canvas
		)
	if DisplayServer.get_name() == "headless":
		return clamp_insets(
			_plus_extra(HudLayoutLogic.safe_insets(canvas, Rect2(Vector2.ZERO, canvas))), canvas
		)
	var win_size := Vector2(DisplayServer.window_get_size())
	var win_pos := Vector2(DisplayServer.window_get_position())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var local := Rect2(safe.position - win_pos, safe.size).intersection(
		Rect2(Vector2.ZERO, win_size)
	)
	var raw := HudLayoutLogic.safe_insets(win_size, local)
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return clamp_insets(_plus_extra(raw), canvas)
	var fx := canvas.x / win_size.x
	var fy := canvas.y / win_size.y
	var scaled := {
		"left": float(raw["left"]) * fx,
		"top": float(raw["top"]) * fy,
		"right": float(raw["right"]) * fx,
		"bottom": float(raw["bottom"]) * fy,
	}
	return clamp_insets(_plus_extra(scaled), canvas)


## Benutzer-Feinjustierung auf alle Seiten addieren (pure).
static func _plus_extra(insets: Dictionary) -> Dictionary:
	var extra := clampf(extra_inset, 0.0, 24.0)
	if extra <= 0.0:
		return insets
	return {
		"left": float(insets.get("left", 0.0)) + extra,
		"top": float(insets.get("top", 0.0)) + extra,
		"right": float(insets.get("right", 0.0)) + extra,
		"bottom": float(insets.get("bottom", 0.0)) + extra,
	}


## Insets pro Seite auf MAX_INSET_SHARE der jeweiligen Achse deckeln (pure).
static func clamp_insets(insets: Dictionary, canvas_size: Vector2) -> Dictionary:
	var max_x := canvas_size.x * MAX_INSET_SHARE
	var max_y := canvas_size.y * MAX_INSET_SHARE
	return {
		"left": clampf(float(insets.get("left", 0.0)), 0.0, max_x),
		"top": clampf(float(insets.get("top", 0.0)), 0.0, max_y),
		"right": clampf(float(insets.get("right", 0.0)), 0.0, max_x),
		"bottom": clampf(float(insets.get("bottom", 0.0)), 0.0, max_y),
	}
