extends RefCounted
## Präsentations-Schicht des Minigolfs (G5 P29, Audit B §miniGolf). Reines
## VIEW-Gefühl nach dem delivery_rush_feel-Muster — keine Spielzahl wird
## angefasst:
##   - Putt-Pitch: die Schlagkraft wird HÖRBAR (vorher ±3 %, ein Ass-Putt
##     klang wie ein Zärtel-Putt; Sfx-Id bleibt mg_good).
##   - Endton-Wahl (M8): Endlos endet immer über das Über-Par-Limit
##     (mg_lose), die 6-Bahnen-Runde feiert jeden gepunkteten Lauf.
##   - Flash-Band (M7) + Ziel-Banner auf Milchglas-Plate — die draw-Helfer
##     malen auf dem übergebenen CanvasItem des Spiels.

const Logic := preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd")

## Banner-Tinte/-Kontur auf der Milchglas-Plate (M7).
const INK := Color(0.32, 0.24, 0.28)
const RIM := Color(1.0, 0.99, 0.94, 0.85)

var _banner_plate := StyleBoxFlat.new()


## Putt-Pitch (PUR für Tests) — wächst mit der Schlagkraft, ein voller
## Schlag klingt hell, ein Zärtel-Putt tief (semantische Reihe 0,9–1,4
## innerhalb des Grammatik-Bereichs 0,9–1,6).
static func putt_pitch(power: float) -> float:
	return 0.9 + 0.5 * clampf(power / float(Logic.GOLF["MAX_POWER"]), 0.0, 1.0)


## Endton-Wahl (PUR für Tests, M8): Endlos endet immer über das Über-Par-
## Limit (mg_lose), die 6-Bahnen-Runde feiert jeden gepunkteten Lauf.
static func end_sfx_for(endless: bool, score_now: int) -> String:
	return "mg_lose" if endless or score_now <= 0 else "mg_win"


## M7: Gold auf hellem Grün war verwaschen — der Flash sitzt jetzt wie bei
## goalieGooby auf einem dunklen Band und skaliert mit `ui`.
func draw_flash(canvas: CanvasItem, text: String, flash: float, view: Vector2, ui: float) -> void:
	if flash <= 0.0 or text.is_empty():
		return
	var alpha := clampf(flash * 1.4, 0.0, 1.0)
	var y := view.y * 0.2
	canvas.draw_rect(
		Rect2(0.0, y - 30.0 * ui, view.x, 44.0 * ui), Color(0.1, 0.15, 0.1, 0.45 * alpha)
	)
	canvas.draw_string(
		ThemeService.font(800),
		Vector2(0.0, y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view.x,
		int(32.0 * ui),
		Color(0.99, 0.86, 0.45, alpha)
	)


## M1/M7: Ziel-Banner mittig auf Milchglas-Plate mit Kontur; lange
## Übersetzungen brechen um (carrot_catch-Muster).
func draw_banner(canvas: CanvasItem, text: String, t: float, view: Vector2, ui: float) -> void:
	if t <= 0.0 or text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(t * 1.4, 0.0, 1.0)
	var fs := int(26.0 * ui)
	var w := minf(view.x * 0.92, 460.0 * ui)
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	var top := view.y * 0.32
	var pad := Vector2(18.0, 10.0) * ui
	_banner_plate.set_corner_radius_all(int(12.0 * ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	canvas.draw_style_box(
		_banner_plate, Rect2(Vector2((view.x - size.x) * 0.5, top) - pad, size + pad * 2.0)
	)
	var at := Vector2((view.x - w) * 0.5, top + font.get_ascent(fs))
	canvas.draw_multiline_string_outline(
		font,
		at,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		fs,
		-1,
		int(5.0 * ui),
		Color(RIM, RIM.a * alpha)
	)
	canvas.draw_multiline_string(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, Color(INK, alpha)
	)
