class_name HomeEntry
extends Node
## Zuhause-Einstieg (W2a HOUSE): registriert die Raum-Routen am W1a-Router,
## zeigt bei frischen Saves das W1c-Onboarding und lädt danach das
## Wohnzimmer. Dazu W1c-HUD (Bau-Button → Baumodus des aktuellen Raums) und
## Live-Werte aus dem W1d-GameState.
##
## main.gd (W1a) soll diese Szene statt des Platzhalter-Homes instanzieren —
## Request: /tmp/gooby-godot/handoffs/W2a-boot-request.md.

const START_ROOM := "living"

var _router: Node
var _gs: Node
var _hud: Hud
var _toasts: ToastLayer

@onready var _world: Node3D = $World
@onready var _ui_layer: CanvasLayer = $UiLayer


func _ready() -> void:
	HomeState.register_slice()
	# W3-Integration (Orchestrator): Content-Slices + Routen aller Screens.
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	_router = get_node_or_null("/root/SceneRouter")
	_gs = get_node_or_null("/root/GameState")
	if _router != null:
		_router.register_routes(RoomDefs.route_table())
		_router.set_mount_point(_world)
		CityScene.register_routes(_router)
	ArcadeScreen.register_routes()
	AlbumScreen.register_routes()
	SocialScreen.register_routes()
	VisitScene.register_routes()
	BattleshipScene.register_routes()
	_build_hud()
	if _router != null and _router.has_signal("travel_finished"):
		_router.travel_finished.connect(_on_travel_finished)
	_roll_random_event()
	if _gs != null and not bool(_gs.get_value("onboarding.done", false)):
		_show_onboarding()
	else:
		_start_home()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_roll_random_event()


func _roll_random_event() -> void:
	if _gs == null:
		return
	var defs := RandomEventEngine.defs_from_registry()
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var uhr := Time.get_datetime_dict_from_system()
	var minuten: int = int(uhr["hour"]) * 60 + int(uhr["minute"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	RandomEventEngine.roll_on_start(_gs, defs, now_ms, minuten, rng)


func _on_travel_finished(_target: Variant = null) -> void:
	var room := _current_room()
	if room == null:
		return
	# W3d-Hooks: Bad-Suite/Geschichten-Stunde + aktives Random-Event pro Raum.
	InteractablesHost.attach_to(room)
	EventRunner.attach_to(room)


func _build_hud() -> void:
	_hud = (load("res://scripts/ui/hud.tscn") as PackedScene).instantiate()
	_hud.visible = false
	_ui_layer.add_child(_hud)
	_toasts = ToastLayer.new()
	_toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_toasts)
	_hud.action_pressed.connect(_on_hud_action)
	if _gs == null:
		return
	_gs.coins_changed.connect(func(coins: int) -> void: _hud.set_coins(coins))
	_gs.stats_changed.connect(_on_stats_changed)
	_gs.level_changed.connect(func(level: int, ratio: float) -> void: _hud.set_level(level, ratio))
	_hud.set_coins(int(_gs.get_value("economy.coins", 0)))
	_on_stats_changed(_gs.get_value("gooby.stats", {}))
	_hud.set_level(int(_gs.get_value("progression.level", 1)), _gs.xp_ratio())


func _on_stats_changed(stats: Dictionary) -> void:
	(
		_hud
		. set_stats(
			{
				"hunger": float(stats.get("hunger", 80.0)),
				"energie": float(stats.get("energy", 90.0)),
				"hygiene": float(stats.get("hygiene", 85.0)),
				"spass": float(stats.get("fun", 70.0)),
			}
		)
	)


func _on_hud_action(action: StringName) -> void:
	if action == &"bau":
		var room := _current_room()
		if room != null:
			room.open_build_mode()
		return
	if ArcadeScreen.handle_hud_action(action):
		return
	if AlbumScreen.handle_hud_action(action):
		return
	if GooberandoApp.handle_hud_action(action, self, _gs):
		return
	if action == &"reise" and _router != null:
		_router.goto(CityScene.ROUTE_CITY)
		return
	if action == &"profil" and _router != null:
		# M1: der Profil-Knopf öffnet den Social-Screen (Freunde/Besuche/Pal);
		# der volle Profil-Rework ist W4/M2 (GODOT-PLAN Backlog).
		_router.goto(SocialScreen.ROUTE)
		return
	_toasts.show_toast(I18nService.t("home.aktion_bald"))


func _current_room() -> RoomBase:
	if _router == null:
		return null
	return _router.get_current_scene() as RoomBase


func _show_onboarding() -> void:
	var flow: OnboardingFlow = (
		(load("res://scripts/ui/onboarding/onboarding_flow.tscn") as PackedScene).instantiate()
	)
	_ui_layer.add_child(flow)
	flow.completed.connect(
		func(profile: Dictionary) -> void:
			if _gs != null:
				_gs.apply_onboarding_profile(profile)
			flow.queue_free()
			_start_home()
	)


func _start_home() -> void:
	_hud.visible = true
	if _router != null:
		_router.goto(RoomDefs.route_target(START_ROOM))
