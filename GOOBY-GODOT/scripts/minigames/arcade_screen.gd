class_name ArcadeScreen
extends Control
## Arcade-Grid: Cover-Kacheln aller Spiele (+ „Bald!“-Platzhalter). Die
## Cover der spielbaren Spiele sind via preload() COMPILE-ZEITIG geladen —
## der Web-Bug „alte Icons flackern beim Öffnen“ kann so nicht wiederkehren.
## Tap → Pregame → Host. HUD-Verdrahtung (W1c-API): der Home-Besitzer
## verbindet hud.action_pressed mit ArcadeScreen.handle_hud_action.

signal game_selected(game_id: String)
signal back_requested

## Compile-zeitige Cover (Konvention: res://assets/covers/<id>.png).
## Neue Spiele: Zeile ergänzen — ResourceLoader-Fallback unten fängt
## vergessene Einträge ab (lädt synchron, KEIN Flackern, nur langsamer).
const COVERS := {
	"teaParty": preload("res://assets/covers/teaParty.png"),
	"carrotCatch": preload("res://assets/covers/carrotCatch.png"),
	"gvz": preload("res://assets/covers/gvz.png"),
}

const ROUTE_ARCADE := &"arcade"
const ROUTE_PREGAME := &"mg_pregame"
const ROUTE_HOST := &"mg_host"

const ROUTES := {
	ROUTE_ARCADE: "res://scripts/minigames/arcade_screen.tscn",
	ROUTE_PREGAME: "res://scripts/minigames/pregame.tscn",
	ROUTE_HOST: "res://scripts/minigames/minigame_host.tscn",
}

## Tests: Navigation abschaltbar.
var auto_navigate := true

var _grid: GridContainer


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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 24.0
	rows.offset_right = -24.0
	rows.offset_top = 16.0
	rows.offset_bottom = -16.0
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("mg.arcade.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mg.arcade.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = back.get_combined_minimum_size()
	header.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)
	for game in MinigameRegistry.GAMES:
		_grid.add_child(_build_tile(game))


func _build_tile(game: Dictionary) -> Control:
	var id: String = game["id"]
	var coming_soon: bool = game.get("coming_soon", false)
	var tile := Button.new()
	tile.name = "Tile_%s" % id
	tile.theme_type_variation = &"AcCard"
	tile.custom_minimum_size = Vector2(250, 240)
	tile.disabled = coming_soon
	if not coming_soon:
		tile.pressed.connect(_on_tile_pressed.bind(id))
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	content.add_child(label)
	return tile


func _build_cover(id: String, coming_soon: bool) -> Control:
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture: Texture2D = COVERS.get(id)
	if texture == null:
		# Fallback-Konvention: assets/covers/<id>.png — synchron geladen.
		var path := MinigameRegistry.cover_path(id)
		if ResourceLoader.exists(path):
			texture = load(path)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if coming_soon:
			rect.modulate = Color(0.6, 0.6, 0.6)
		frame.add_child(rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.87, 0.8, 0.72)
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(placeholder)
		var mark := Label.new()
		mark.text = "?"
		mark.theme_type_variation = &"TitleLabel"
		mark.set_anchors_preset(Control.PRESET_CENTER)
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
		badge.set_anchors_preset(Control.PRESET_CENTER)
		badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
		badge.grow_vertical = Control.GROW_DIRECTION_BOTH
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.rotation_degrees = -8.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(badge)
	return frame


func _on_tile_pressed(id: String) -> void:
	game_selected.emit(id)
	if not auto_navigate:
		return
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
	# Home gehört W2a — nur zurückreisen, wenn die Route schon existiert
	# (sonst würde goto einen Engine-ERROR loggen).
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
