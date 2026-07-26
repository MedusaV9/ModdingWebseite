class_name RanchRegionScene
extends Node3D
## Die offene Ranch-Region (RW-1): EINE zusammenhängende Welt aus neun
## Zonen (RanchKarte) ohne Ladebildschirme — Gelände-Chunks (RanchTerrain),
## Zonen-Deko (RanchZonenDeko, per Abstand gestreamt), deterministisches
## Wetter (RanchWetterController), Wildtiere (RanchWildtiere) und der freie
## Reiter (RanchWeltReiter). Entdeckte Zonen landen additiv im Save
## (`ranch.welt`), der Wetter-Seed in `ranch.wetter`.
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau;
## `receive_params({"spawn_zone": "see"})` setzt den Startpunkt.
## Tests injizieren `game_state_override` VOR add_child.

signal ready_for_reveal
## Andock-Punkt für andere Agents (s. RW1-welt-api.md): feuert beim
## Betreten einer neuen Zone (Zonen-Id aus RanchKarte, "" = freies Land).
signal zone_gewechselt(zone_id: String)

## Deko-Gruppen einer Zone verschwinden ab diesem Abstand zum Zonen-Rect.
const STREAM_ABSTAND_M := 520.0

var game_state_override: Object
## Tests/Screenshots erzwingen Uhrzeit (< 0 = Systemzeit) + Wetterlage.
var stunde_override := -1.0
var wetter_override := ""
## -1 = Setting (city.lebenReduziert), 0/1 = erzwungen (Tests).
var leben_reduziert_override := -1

var reiter: RanchWeltReiter
var wetter: RanchWetterController
var wildtiere: RanchWildtiere

var _spawn_zone := "hof"
var _deko_gruppen: Dictionary = {}
var _windrad_rotor: Node3D
var _env: Environment
var _sonne: DirectionalLight3D
var _terrain: RanchTerrain
var _bach_punkte: Array[Vector2] = []
var _toast: Node
var _hud_zone: Label
var _hud_status: Label
var _stream_timer := 0.0


func _ready() -> void:
	var gs := game_state()
	_baue_licht()
	_terrain = RanchTerrain.new()
	_terrain.baue_chunks(self)
	_terrain.baue_wege(self)
	_terrain.baue_wasser(self)
	var deko := RanchZonenDeko.new(RanchKarte.seed_wert())
	_deko_gruppen = deko.baue(self)
	_windrad_rotor = deko.windrad_rotor
	wetter = RanchWetterController.new()
	wetter.name = "Wetter"
	wetter.seed_wert = RanchWeltState.wetter_seed(gs)
	wetter.datum = RanchWetter.datum_heute()
	wetter.wetter_override = wetter_override
	add_child(wetter)
	wetter.einrichten(_env, _sonne, _terrain.terrain_material, deko.gras_material)
	wildtiere = RanchWildtiere.new()
	wildtiere.name = "Wildtiere"
	add_child(wildtiere)
	wildtiere.einrichten(_leben_reduziert(), RanchKarte.seed_wert())
	_merke_bach()
	_baue_reiter()
	_baue_hud()
	ready_for_reveal.emit()


func _process(delta: float) -> void:
	if _windrad_rotor != null:
		_windrad_rotor.rotation.z += delta * 0.9
	var stunde := _stunde()
	wetter.tick(delta, stunde, reiter.position)
	wetter.set_bach_naehe(clampf(1.0 - _bach_abstand() / 55.0, 0.0, 1.0))
	wildtiere.tick(delta, stunde, str(wetter.zustand["typ"]), reiter.position)
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.5
		_streame_zonen()
		_zeige_status(stunde)


## Router-Params (W1a-Contract).
func receive_params(params: Dictionary) -> void:
	var zone := str(params.get("spawn_zone", "hof"))
	if not RanchKarte.zone(zone).is_empty():
		_spawn_zone = zone


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## ---------------------------------------------------------------- Aufbau


func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


func _leben_reduziert() -> bool:
	if leben_reduziert_override >= 0:
		return leben_reduziert_override == 1
	var gs := game_state()
	return gs != null and bool(gs.get_value("city.lebenReduziert", false))


func _baue_licht() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "Umgebung"
	_env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	# Lehre aus den Minigame-Bühnen (_3db_stage): reines Himmel-Ambient +
	# Linear/Filmic brennt helle Pastellflächen zu Weiß aus. Warmes Farb-
	# Ambient (Wetter-Controller färbt es je Tageszeit) + ACES mit gesenkter
	# Belichtung hält Wiese/Feldweg satt, ohne die Szene milchig zu machen.
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.88, 0.9, 0.86)
	_env.ambient_light_sky_contribution = 0.35
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_white = 1.7
	_env.tonemap_exposure = 0.62
	env_node.environment = _env
	add_child(env_node)
	_sonne = DirectionalLight3D.new()
	_sonne.name = "Sonne"
	_sonne.shadow_enabled = true
	_sonne.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sonne.directional_shadow_max_distance = 190.0
	add_child(_sonne)


func _merke_bach() -> void:
	for paar: Array in RanchKarte.karte()["bach"]["punkte"]:
		_bach_punkte.append(Vector2(float(paar[0]), float(paar[1])))


func _bach_abstand() -> float:
	var p := Vector2(reiter.position.x, reiter.position.z)
	var best := INF
	for punkt in _bach_punkte:
		best = minf(best, p.distance_to(punkt))
	return best


func _baue_reiter() -> void:
	reiter = RanchWeltReiter.new()
	reiter.name = "Reiter"
	add_child(reiter)
	var spawn := RanchKarte.spawn_punkt(_spawn_zone)
	reiter.springe_zu(spawn, PI if spawn.z > 0.0 else 0.0)
	reiter.zone_gewechselt.connect(_on_zone_gewechselt)


func _baue_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	var hud := Control.new()
	hud.name = "RegionHud"
	hud.theme = ThemeService.theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_hud_zone = Label.new()
	_hud_zone.theme_type_variation = "TitleLabel"
	_hud_zone.text = I18nService.t("rwelt.titel")
	_hud_zone.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18
	)
	hud.add_child(_hud_zone)
	_hud_status = Label.new()
	_hud_status.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16
	)
	hud.add_child(_hud_status)
	var hof := Button.new()
	hof.theme_type_variation = "GhostButton"
	hof.text = I18nService.t("rwelt.hud.zur_ranch")
	hof.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	hof.pressed.connect(_on_zum_hof)
	hud.add_child(hof)
	var galopp := Button.new()
	galopp.theme_type_variation = "PrimaryButton"
	galopp.toggle_mode = true
	galopp.text = I18nService.t("ranch.hof.pferde_galopp")
	galopp.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24
	)
	galopp.toggled.connect(func(an: bool) -> void: reiter.galopp = an)
	hud.add_child(galopp)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## ---------------------------------------------------------------- Laufzeit


## Deko-Streaming: Zonen-Gruppen außerhalb des Abstands schlafen (kein
## Ladebildschirm — nur Sichtbarkeit; Karte + Gelände bleiben immer da).
func _streame_zonen() -> void:
	var p := Vector2(reiter.position.x, reiter.position.z)
	for zone_id: String in _deko_gruppen:
		var rect := RanchKarte.zone_rect(RanchKarte.zone(zone_id))
		var naechster := Vector2(
			clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y)
		)
		(_deko_gruppen[zone_id] as Node3D).visible = (p.distance_to(naechster) < STREAM_ABSTAND_M)


func _zeige_status(stunde: float) -> void:
	var zone_id := reiter.aktuelle_zone()
	if zone_id.is_empty():
		zone_id = "frei"
	_hud_zone.text = I18nService.t("rwelt.zone.%s" % zone_id)
	var wetter_text := I18nService.t(str(wetter.zustand["name_key"]))
	if bool(wetter.zustand["regenbogen"]):
		wetter_text = I18nService.t("rwelt.wetter.regenbogen")
	_hud_status.text = (
		"%02d:%02d  ·  %s" % [int(stunde), int(fmod(stunde, 1.0) * 60.0), wetter_text]
	)


func _on_zone_gewechselt(zone_id: String) -> void:
	zone_gewechselt.emit(zone_id)
	if RanchWeltState.entdecke_zone(game_state(), zone_id):
		var zonen_name := I18nService.t("rwelt.zone.%s" % zone_id)
		_zeige_toast(I18nService.t("rwelt.entdeckt", {"zone": zonen_name}))


func _on_zum_hof() -> void:
	RanchRouten.fahre_zum_hof(get_tree())


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)
