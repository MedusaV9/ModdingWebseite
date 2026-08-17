class_name GhostHuntHud
extends RefCounted
## HUD/Banner der Geisterjagd (G5/P31-Split, Muster gvz_hud.gd): Zeit-/
## Ketten-Label, Hinweis und das Ereignisband wohnen jetzt hier — ghost_hunt.gd
## stand am 1000-Zeilen-Limit. Reine PRÄSENTATION: der Helfer liest den
## Sim-State nur über `view.state` und zeichnet auf die Szene (view).
## Neu gegenüber dem alten Band (Audit A §2.10 / G4-Politur):
## — M9/Q5: alle Pixelmaße skalieren mit `view._ui` (Kurzkante/390),
##   die Hinweis-Breite hängt am Viewport statt an fixen 340 px.
## — Q3: der Hinweis blendet nach ~6 s Spielzeit aus (G2-Muster).
## — M7: Banner als Creme-Plate mit Kontur-Text statt rohem draw_string
##   auf dunklem Vollbreiten-Band (pancake_tower-Muster).

## Q3: Hinweis-Standzeit (s Spielzeit, tickt erst nach dem Intro) + Fade.
const HINT_FADE_AT := 6.0
const HINT_FADE_SEC := 1.5
## Standzeit des Ereignisbands (wie das alte `_banner_t = 1.4`).
const BANNER_SEC := 1.4

## Die Spielszene (ghost_hunt.gd) — bewusst untypisiert (kein class_name
## dort; ein Preload wäre zirkulär). Liefert view_size, landscape, _ui, state.
var view

var score_label: Label
var chain_label: Label
var hint_label: Label

## Ereignisband-Zustand (Buh-Welle, Attrappe, Aufsammler, Intro-Ziel).
var banner_text := ""
var banner_t := 0.0
## Q3: gesehene Spielzeit des Hinweises (tickt erst nach dem Intro).
var hint_seen := 0.0

var _plate := StyleBoxFlat.new()


func _init(game_view: Node2D) -> void:
	view = game_view
	_plate.set_corner_radius_all(12)


## Labels bauen und an die Szene hängen (einmal aus setup()).
func build() -> void:
	score_label = Label.new()
	score_label.theme_type_variation = &"HeadlineLabel"
	view.add_child(score_label)
	chain_label = Label.new()
	chain_label.theme_type_variation = &"CaptionLabel"
	view.add_child(chain_label)
	hint_label = Label.new()
	hint_label.theme_type_variation = &"SoftLabel"
	hint_label.text = I18nService.t("mg.ghostHunt.hint")
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(hint_label)
	# Die Dämmerungskulisse ist dunkel — die Theme-Schriftfarben sind es auch.
	score_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	chain_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	hint_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.95))
	for label: Label in [score_label, chain_label, hint_label]:
		label.add_theme_color_override("font_outline_color", Color(0.09, 0.06, 0.14, 0.9))
		label.add_theme_constant_override("outline_size", 6)
	update()


## M9/Q5: HUD aus dem Viewport-Rect stellen — alle Maße skalieren mit _ui,
## die Hinweis-Breite hängt an vp.x statt an fixen 340 px (Audit A QF-2).
func layout() -> void:
	if score_label == null:
		return
	var ui := float(view._ui)
	var vp: Vector2 = view.get_viewport_rect().size
	score_label.position = Vector2(16.0, 10.0) * ui
	score_label.add_theme_font_size_override("font_size", int(34.0 * ui))
	chain_label.position = Vector2(16.0, 48.0) * ui
	chain_label.add_theme_font_size_override("font_size", int(15.0 * ui))
	var hint_w := minf(vp.x - 32.0 * ui, 360.0 * ui)
	var font_size := int(20.0 * ui)
	hint_label.add_theme_font_size_override("font_size", font_size)
	var font := hint_label.get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, hint_w, font_size
	)
	var box := Vector2(hint_w, text_size.y + 6.0 * ui)
	hint_label.position = Vector2((vp.x - box.x) * 0.5, vp.y - box.y - 10.0 * ui)
	hint_label.size = box
	for label: Label in [score_label, chain_label, hint_label]:
		label.add_theme_constant_override("outline_size", int(6.0 * ui))


## Jeden Frame: Banner-Uhr runter, Hinweis-Uhr hoch (nur im Spielbetrieb —
## im Intro-Beat steht der Hinweis, damit die Lesezeit nicht wegtickt).
func tick(delta: float, gameplay: bool) -> void:
	banner_t = maxf(0.0, banner_t - delta)
	if gameplay:
		hint_seen += delta


func show_banner(text: String, sec := BANNER_SEC) -> void:
	banner_text = text
	banner_t = sec


## Label-Texte aus dem Sim-State (Zeit/Entwischt + Ketten-/Netz-/Laternen-
## Pillen) und der Q3-Hinweis-Fade.
func update() -> void:
	var state: Dictionary = view.state
	var tune: Dictionary = state["tune"]
	if bool(tune["ENDLESS"]):
		score_label.text = I18nService.t(
			"mg.ghostHunt.escapes",
			{"n": int(state["escapedWaves"]), "max": int(tune["ENDLESS_ESCAPE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(state["t"]))))
		score_label.text = I18nService.t("mg.game.time", {"sec": left})
	var parts: Array[String] = []
	if int(state["chain"]) > 1:
		parts.append(I18nService.t("mg.ghostHunt.chainPill", {"n": int(state["chain"])}))
	if int(state["netLeft"]) > 0:
		parts.append(I18nService.t("mg.ghostHunt.netPill", {"n": int(state["netLeft"])}))
	if float(state["lanternT"]) > 0.0:
		parts.append(
			I18nService.t("mg.ghostHunt.lanternPill", {"n": int(ceil(float(state["lanternT"])))})
		)
	chain_label.text = "  ".join(parts)
	hint_label.modulate.a = hint_alpha()


## Q3: der Hinweis steht die ersten Sekunden und blendet dann aus — der
## Friedhof gehört danach ganz den Geistern.
func hint_alpha() -> float:
	return clampf(1.0 - (hint_seen - HINT_FADE_AT) / HINT_FADE_SEC, 0.0, 1.0)


## Ereignisband mittig mit Creme-Plate und Kontur (M7, pancake_tower-Muster);
## lange Übersetzungen brechen um. Trägt Intro-Ziel UND Ereignis-Meldungen.
func draw_banner() -> void:
	if banner_t <= 0.0 or banner_text.is_empty():
		return
	var ui := float(view._ui)
	var vp: Vector2 = view.view_size
	var font: Font = ThemeService.font(800)
	var alpha := clampf(banner_t / 0.4, 0.0, 1.0)
	var font_size := int(maxf(22.0, 26.0 * ui))
	var w := minf(vp.x * 0.92, 460.0 * ui)
	var text_size := font.get_multiline_string_size(
		banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top: float = vp.y * (0.2 if bool(view.landscape) else 0.24)
	var pad := Vector2(18.0, 10.0) * ui
	_plate.set_corner_radius_all(int(12.0 * ui))
	_plate.bg_color = Color(1.0, 0.99, 0.94, 0.78 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	view.draw_style_box(_plate, Rect2(plate_pos, text_size + pad * 2.0))
	# Nacht-Tinte + heller Saum: lesbar auf Mondhimmel UND Kürbisschein.
	var ink := Color(0.3, 0.22, 0.34, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	view.draw_multiline_string_outline(
		font, at, banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * ui), rim
	)
	view.draw_multiline_string(
		font, at, banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink
	)
