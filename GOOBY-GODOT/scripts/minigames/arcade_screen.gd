class_name ArcadeScreen
extends Control
## Arcade-Grid: Cover-Kacheln aller Spiele (+ „Bald!“-Platzhalter). Die
## Cover der spielbaren Spiele sind via preload() COMPILE-ZEITIG geladen —
## der Web-Bug „alte Icons flackern beim Öffnen“ kann so nicht wiederkehren.
## Tap → Pregame → Host. HUD-Verdrahtung (W1c-API): der Home-Besitzer
## verbindet hud.action_pressed mit ArcadeScreen.handle_hud_action.
##
## FIX1 (P0 „Arcade sieht komisch/buggy aus, Cover ohne Smoothing“):
## - Cover-Kacheln filtern mit LINEAR_WITH_MIPMAPS (Import der Cover-PNGs
##   generiert jetzt Mipmaps) — kein Kanten-Flimmern beim Herunterskalieren.
## - Das Grid ist RESPONSIV: Spaltenzahl aus der verfügbaren Breite
##   (`grid_columns`, pure), Kacheln füllen die Zeile statt links zu kleben.
## - Safe-Area-Ränder + zentrale `UiScale`-Skalierung; kein Quer-Scrollen.

signal game_selected(game_id: String)
signal back_requested

## Compile-zeitige Cover (Konvention: res://assets/covers/<id>.png).
## Neue Spiele: Zeile ergänzen — ResourceLoader-Fallback unten fängt
## vergessene Einträge ab (lädt synchron, KEIN Flackern, nur langsamer).
## Auch „Bald!“-Kacheln (gobnom) preloaden: echtes Cover statt „?“-Karte.
const COVERS := {
	"teaParty": preload("res://assets/covers/teaParty.png"),
	"carrotCatch": preload("res://assets/covers/carrotCatch.png"),
	"gvz": preload("res://assets/covers/gvz.png"),
	"gobnom": preload("res://assets/covers/gobnom.png"),
}

const ROUTE_ARCADE := &"arcade"
const ROUTE_PREGAME := &"mg_pregame"
const ROUTE_HOST := &"mg_host"

const ROUTES := {
	ROUTE_ARCADE: "res://scripts/minigames/arcade_screen.tscn",
	ROUTE_PREGAME: "res://scripts/minigames/pregame.tscn",
	ROUTE_HOST: "res://scripts/minigames/minigame_host.tscn",
}

## FIX1-Grid-Geometrie (Design-px, skalieren mit dem UiScale-Faktor).
const TILE_MIN_WIDTH := 230.0
const TILE_HEIGHT := 240.0
const GRID_GAP := 16.0
const MIN_COLUMNS := 2
const MAX_COLUMNS := 5

## Tests: Navigation abschaltbar.
var auto_navigate := true

var _grid: GridContainer
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _back: Button


## Arcade-Routen am SceneRouter anmelden (idempotent). Der Home-Besitzer /
## Orchestrator ruft das einmal beim Boot (oder via handle_hud_action).
static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("register_routes"):
		return
	router.register_routes(ROUTES)


## EIN Verdrahtungspunkt für den HUD-Arcade-Button (W1c action_pressed):
##   hud.action_pressed.connect(ArcadeScreen.handle_hud_action)
## Liefert true, wenn die Action konsumiert wurde.
static func handle_hud_action(action: StringName) -> bool:
	if action != &"arcade":
		return false
	register_routes()
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE_ARCADE, {})
	return true


func _ready() -> void:
	# E14-P0: and_offsets — nur Anker setzen behält unter dem Router-Mount
	# das 0×0-Rect (Offsets werden aufs aktuelle Rect zurückgerechnet).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_build_ui()
	get_viewport().size_changed.connect(_apply_metrics)
	_apply_metrics()


## Spaltenzahl aus verfügbarer Breite (pure, FIX1-Test): so viele Kacheln
## mit Mindestbreite TILE_MIN_WIDTH×f passen nebeneinander, 2..5 Spalten.
static func grid_columns(avail_width: float, f: float) -> int:
	var tile := TILE_MIN_WIDTH * maxf(f, 0.01)
	var gap := GRID_GAP * maxf(f, 0.01)
	if avail_width <= 0.0:
		return MIN_COLUMNS
	var cols := int(floorf((avail_width + gap) / (tile + gap)))
	return clampi(cols, MIN_COLUMNS, MAX_COLUMNS)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_rows = VBoxContainer.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows.offset_left = 24.0
	_rows.offset_right = -24.0
	_rows.offset_top = 16.0
	_rows.offset_bottom = -16.0
	_rows.add_theme_constant_override("separation", 12)
	add_child(_rows)

	var header := HBoxContainer.new()
	_rows.add_child(header)
	_back = Button.new()
	_back.theme_type_variation = &"GhostButton"
	_back.text = I18nService.t("mg.arcade.back")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_on_back_pressed)
	header.add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.text = I18nService.t("mg.arcade.title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_title)
	var spacer := Control.new()
	spacer.custom_minimum_size = _back.get_combined_minimum_size()
	header.add_child(spacer)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# FIX1: nie quer scrollen — das Grid passt sich der Breite an; und
	# Touch-Deadzone, damit Wischen nicht sofort als Tile-Tap zählt.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 24
	_rows.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_scroll.add_child(_grid)
	# MG-3: all_games() statt GAMES — sonst fehlen alle per game.json-Manifest
	# entdeckten Spiele (W6-Registry) im Grid.
	var tiles: Array = []
	for game in MinigameRegistry.all_games():
		var tile := _build_tile(game)
		_grid.add_child(tile)
		tiles.append(tile)
	# FB3-Polish: Kacheln federn gestaffelt ein (Web-Stagger) statt zu ploppen.
	UiMotion.stagger_in(tiles, 0.03)


## Responsive Metriken (FIX1): Safe-Area-Ränder, UiScale-Faktor,
## Spaltenzahl aus der Breite — läuft bei Resize/Rotation erneut.
func _apply_metrics() -> void:
	if _rows == null or _grid == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var canvas := Vector2(vp.get_visible_rect().size)
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp)
	_rows.offset_left = float(insets["left"]) + 16.0
	_rows.offset_right = -float(insets["right"]) - 16.0
	_rows.offset_top = float(insets["top"]) + 12.0
	_rows.offset_bottom = -float(insets["bottom"]) - 12.0
	var gap := int(GRID_GAP * f)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	var avail := canvas.x - _rows.offset_left + _rows.offset_right
	_grid.columns = grid_columns(avail, f)
	# FB3: Touch-Floor auf BEIDEN Achsen + Schriften über die zentrale
	# Regel (vorher skalierte nur der Titel, Kachel-Labels blieben klein).
	var floor_px := maxf(
		HudLayoutLogic.touch_floor_canvas(canvas),
		float(AcTokens.TOUCH_FLOOR) * UiScale.touch_px_per_pt(get_viewport())
	)
	_back.custom_minimum_size = _back.custom_minimum_size.max(Vector2(floor_px, floor_px))
	ScreenShell.scale_fonts(self, f)
	for tile in _grid.get_children():
		(tile as Control).custom_minimum_size = Vector2(0.0, TILE_HEIGHT * f)


func _build_tile(game: Dictionary) -> Control:
	var id: String = game["id"]
	var coming_soon: bool = game.get("coming_soon", false)
	var tile := Button.new()
	tile.name = "Tile_%s" % id
	# E7-P0-3: FIX-As Button-taugliche Karten-Variation. `AcCard` ist eine
	# PanelContainer-Variation — auf einem Button fiel sie still auf die
	# Pill-Basis zurück (Radius 999 → weiße Ellipsen).
	tile.theme_type_variation = &"AcCardButton"
	# FIX1: Kacheln füllen die Zeile (Spaltenzahl macht _apply_metrics) —
	# feste Höhe, Breite kommt vom Grid.
	tile.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.disabled = coming_soon
	if not coming_soon:
		tile.pressed.connect(_on_tile_pressed.bind(id))
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10.0
	content.offset_right = -10.0
	content.offset_top = 10.0
	content.offset_bottom = -10.0
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(content)
	var cover := _build_cover(id, coming_soon)
	content.add_child(cover)
	var label := Label.new()
	label.text = I18nService.t(str(game.get("title_key", id)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# FIX1: lange Titel werden mit „…“ gekürzt statt hart abgeschnitten.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(label)
	return tile


## Dieselbe Textur-Instanz für Kachel UND LoadingVeil-Cover-Karte
## (W4/POLISH-17: kein Doppel-Load, kein Flackern).
static func cover_texture(id: String) -> Texture2D:
	var texture: Texture2D = COVERS.get(id)
	if texture == null:
		# Fallback-Konvention: assets/covers/<id>.png — synchron geladen.
		var path := MinigameRegistry.cover_path(id)
		if ResourceLoader.exists(path):
			texture = load(path)
	return texture


func _build_cover(id: String, coming_soon: bool) -> Control:
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := cover_texture(id)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# FIX1 „kein Smoothing“: Cover werden stark herunterskaliert —
		# ohne Mipmaps flimmern die Kanten (Import generiert sie jetzt).
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if coming_soon:
			rect.modulate = Color(0.6, 0.6, 0.6)
		frame.add_child(rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.87, 0.8, 0.72)
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(placeholder)
		var mark := Label.new()
		mark.text = "?"
		mark.theme_type_variation = &"TitleLabel"
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
		mark.grow_vertical = Control.GROW_DIRECTION_BOTH
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(mark)
	if coming_soon:
		var badge := Label.new()
		badge.text = I18nService.t("mg.arcade.coming_soon")
		badge.theme_type_variation = &"HeadlineLabel"
		badge.add_theme_color_override("font_color", Color(0.95, 0.45, 0.66))
		badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
		badge.grow_vertical = Control.GROW_DIRECTION_BOTH
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.rotation_degrees = -8.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(badge)
	return frame


func _on_tile_pressed(id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	game_selected.emit(id)
	if not auto_navigate:
		return
	# Veil-Kontext für die ganze Kette Arcade→Pregame→Host: Cover-Karte mit
	# Titel + Tipps statt Standard-Gooby (W4/POLISH-3+17). Der Hint räumt
	# sich beim nächsten Nicht-Minigame-Ziel selbst auf.
	var game := MinigameRegistry.get_game(id)
	var hint := {
		"game_id": id,
		"title": I18nService.t(str(game.get("title_key", id))),
		"cover": cover_texture(id),
		"targets": [ROUTE_PREGAME, ROUTE_HOST],
	}
	LoadingVeil.set_travel_hint(hint)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(ROUTE_PREGAME, {"game_id": id})


func _on_back_pressed() -> void:
	back_requested.emit()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	# FIX1: EIN gemeinsamer Zurück-Pfad — erst Panel-Stack/History im Router
	# (handle_back_request), sonst der &"home"-Alias (löst auf den zuletzt
	# besuchten Raum auf). Guard bleibt: ohne Home-Route kein Engine-ERROR.
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
