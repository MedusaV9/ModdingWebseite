class_name RanchExit
extends Node3D
## Stadtausfahrt zur Gooby Ranch (RANCH-1) — die EINZIGE Ranch-Datei in
## scripts/city/ (Ownership-Grenze; city_scene.gd gehört einem anderen
## Agenten). Selbstständiges Add-on: `RanchExit.install(city_scene)` in
## CityScene._ready einhängen (Handoff RANCH1-city-request.md), den Rest
## macht dieser Node — Ausfahrt-Stummel am Ostrand der Reihe-7-Straße,
## Schild „Zur Gooby Ranch — 8 km“, Näherungs-Prompt und Level-20-Gate.
##
## Duck-Typing: `karte`/`auto`/`game_state_override` sind injizierbar —
## Tests bauen den Node ohne komplette Stadt auf.

## Ausfahrt am Ostende der Reihe-7-Straße (city_map.json: reihen [.,.,7,.],
## reihen_spalten bis 13; der Stummel liegt auf Spalte 14 = Kartenrand).
const AUSFAHRT_TILE := Vector2i(7, 14)
const ZONE_RADIUS_M := 9.0
const HINWEIS_PAUSE_S := 6.0

var karte: Object
var auto: Node3D
var game_state_override: Object

var _prompt: PanelContainer
var _prompt_offen := false
var _toast: Node
var _hinweis_cooldown := 0.0


## Einhänge-Punkt für die Stadt (nach _baue_auto/_baue_hud aufrufen):
## liest karte/auto/GameState direkt von der CityScene (Duck-Typing).
static func install(city: Node3D) -> RanchExit:
	var exit := RanchExit.new()
	exit.name = "RanchExit"
	exit.karte = city.get("karte")
	exit.auto = city.get("auto")
	if city.has_method("game_state"):
		exit.game_state_override = city.game_state()
	city.add_child(exit)
	return exit


func _ready() -> void:
	_baue_ausfahrt()
	_baue_ui()


func _physics_process(delta: float) -> void:
	_hinweis_cooldown = maxf(0.0, _hinweis_cooldown - delta)
	_pruefe_zone()


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## Weltposition der Ausfahrt (Kartenrand der Reihe-7-Straße).
func ausfahrt_pos() -> Vector3:
	if karte != null and karte.has_method("tile_zu_welt"):
		return karte.tile_zu_welt(AUSFAHRT_TILE)
	return Vector3(140.0, 0.0, 30.0)


## Ist der Losfahren-Prompt gerade offen? (Tests)
func prompt_sichtbar() -> bool:
	return _prompt != null and _prompt.visible


## Steht das Spieler-Auto in der Ausfahrt-Zone?
func in_zone() -> bool:
	if auto == null:
		return false
	var ziel := ausfahrt_pos()
	var hier := Vector2(auto.position.x, auto.position.z)
	return hier.distance_to(Vector2(ziel.x, ziel.z)) <= ZONE_RADIUS_M


## ---------------------------------------------------------------- Aufbau


## Ausfahrt-Stummel (dunkle Fahrbahn-Platte) + Ranch-Schild am Straßenrand.
func _baue_ausfahrt() -> void:
	var pos := ausfahrt_pos()
	var platte := MeshInstance3D.new()
	platte.name = "AusfahrtPlatte"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(22.0, 12.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.4, 0.38)
	mesh.material = mat
	platte.mesh = mesh
	platte.position = Vector3(pos.x + 2.0, 0.06, pos.z)
	add_child(platte)
	var schild := Node3D.new()
	schild.name = "RanchSchild"
	schild.position = Vector3(pos.x - 4.0, 0.0, pos.z - 8.4)
	add_child(schild)
	var pfosten := MeshInstance3D.new()
	var pfosten_mesh := BoxMesh.new()
	pfosten_mesh.size = Vector3(0.22, 2.6, 0.22)
	var holz := StandardMaterial3D.new()
	holz.albedo_color = Color("#B58A5F")
	pfosten_mesh.material = holz
	pfosten.mesh = pfosten_mesh
	pfosten.position.y = 1.3
	schild.add_child(pfosten)
	var tafel := MeshInstance3D.new()
	var tafel_mesh := BoxMesh.new()
	tafel_mesh.size = Vector3(4.6, 1.5, 0.18)
	var creme := StandardMaterial3D.new()
	creme.albedo_color = Color("#F2E9DC")
	tafel_mesh.material = creme
	tafel.mesh = tafel_mesh
	tafel.position.y = 2.9
	schild.add_child(tafel)
	var text := Label3D.new()
	text.text = (
		"%s\n%s"
		% [
			I18nService.t("ranch.exit.schild_zeile1"),
			I18nService.t("ranch.exit.schild_zeile2", {"km": _schild_km()}),
		]
	)
	text.font_size = 96
	text.pixel_size = 0.01
	text.modulate = Color(0.24, 0.2, 0.16)
	text.position = Vector3(0.0, 2.9, 0.12)
	schild.add_child(text)


func _schild_km() -> int:
	return int(RanchWelt.welt_daten()["schild_km"])


func _baue_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RanchExitUi"
	add_child(layer)
	_prompt = PanelContainer.new()
	_prompt.theme = ThemeService.theme()
	_prompt.theme_type_variation = "AcCard"
	_prompt.visible = false
	_prompt.custom_minimum_size = Vector2(380.0, 0.0)
	_prompt.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 108
	)
	_prompt.grow_vertical = Control.GROW_DIRECTION_END
	layer.add_child(_prompt)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_prompt.add_child(box)
	var label := Label.new()
	label.text = I18nService.t("ranch.exit.prompt")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var los := Button.new()
	los.theme_type_variation = "PrimaryButton"
	los.text = I18nService.t("ranch.exit.losfahren")
	los.pressed.connect(_on_losfahren)
	box.add_child(los)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## ------------------------------------------------------------- Logik


func _pruefe_zone() -> void:
	var drin := in_zone()
	if drin == _prompt_offen:
		return
	if not drin:
		_prompt_offen = false
		_prompt.visible = false
		return
	_prompt_offen = true
	if RanchState.ist_freigeschaltet(game_state()):
		_prompt.visible = true
	elif _hinweis_cooldown <= 0.0:
		_hinweis_cooldown = HINWEIS_PAUSE_S
		var level := RanchKatalog.freischalt_level()
		_zeige_toast(I18nService.t("ranch.exit.gesperrt", {"level": level}))


## „Losfahren“: Level-Gate prüfen, dann ab auf die Landstraße.
func _on_losfahren() -> void:
	var gs := game_state()
	if not RanchState.ist_freigeschaltet(gs):
		_zeige_toast(
			I18nService.t("ranch.exit.gesperrt", {"level": RanchKatalog.freischalt_level()})
		)
		return
	if not RanchRouten.fahre_zur_ranch(get_tree()):
		_zeige_toast("(Route %s — Router fehlt)" % RanchRouten.ROUTE_FAHRT)


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)
