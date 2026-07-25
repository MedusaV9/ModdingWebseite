class_name BattleshipScene
extends Node3D
## Schiffe versenken am Brettspieltisch (W3c VISIT): First-Person am Tisch —
## eigenes Brett liegt unten (Setup per Tap: Schiff antippen = drehen,
## „Neu würfeln“ = neue deterministische Flotte), das Gegner-Brett steht
## aufrecht (Tap = Schuss). BEIDE Goobys sitzen links/rechts am Tisch
## (W1b sit-Clip) und reagieren: Treffer → celebrate/sad, Warten → Grimassen
## alle ~10 s. Emote-Rad (4 Emotes) + Tomate (1×/Runde, Server erzwingt):
## Wurf-Bogen von Gooby zu Gooby, Splat auf der „Kamera“ des Getroffenen
## (TomatoOverlay, rutscht ~4 s ab). Turn-Relay macht BoardSession.

const ROUTE := &"social/battleship"
const ROUTES := {ROUTE: "res://scripts/social/boardgame/battleship_scene.tscn"}
const GRIMACE_SEC := 10.0
const GRIMACES: Array[String] = ["dizzy", "sleepy", "angry", "sad"]

## Tests/Screenshots: SocialServices-Instanz injizieren statt /root-Lookup.
var services_override: Node = null

var my_board_view: BoardDisplay
var opp_board_view: BoardDisplay
var my_gooby: RemoteGooby
var opp_gooby: RemoteGooby
var wheel: EmoteWheel
var overlay: TomatoOverlay
var toast: ToastLayer

var _services: Node = null
var _session: BoardSession
var _phase := "setup"  # setup -> play -> over
var _fleet: Array[Dictionary] = []
var _reroll_count := 0
var _locked := false
var _turn_label: Label
var _setup_box: HBoxContainer
var _tomato_button: Button
var _grimace_accum := 0.0
var _rng := RandomNumberGenerator.new()


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	_services = services_override
	if _services == null:
		_services = SocialServices.get_or_create(self)
	_session = _services.board if _services != null else null
	_build_world()
	_build_hud()
	_wire_session()
	_start_setup()


func session() -> BoardSession:
	return _session


func _process(delta: float) -> void:
	if _phase != "play" or _session == null or _session.my_turn():
		_grimace_accum = 0.0
		return
	_grimace_accum += delta
	if _grimace_accum >= GRIMACE_SEC:
		_grimace_accum = 0.0
		my_gooby.rig.set_emotion(GRIMACES[_rng.randi_range(0, GRIMACES.size() - 1)])
		my_gooby.rig.play_clip("idle_lookaround")


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#F6E3C5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.84)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(8.0, 0.1, 8.0)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = _flat(Color("#C9A36B"))
	floor_mesh.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mesh)

	# Der Brettspieltisch (W2a-Katalog-Item folgt — Catalog-Request offen).
	var table := MeshInstance3D.new()
	var table_box := BoxMesh.new()
	table_box.size = Vector3(2.2, 0.08, 1.4)
	table.mesh = table_box
	table.material_override = _flat(Color(0.52, 0.36, 0.22))
	table.position = Vector3(0.0, 0.72, 0.0)
	add_child(table)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.08, 0.72, 0.08)
			leg.mesh = leg_box
			leg.material_override = _flat(Color(0.42, 0.28, 0.17))
			leg.position = Vector3(sx * 1.0, 0.36, sz * 0.6)
			add_child(leg)

	my_board_view = BoardDisplay.new()
	my_board_view.name = "MyBoard"
	my_board_view.position = Vector3(0.0, 0.77, 0.28)
	add_child(my_board_view)
	my_board_view.cell_tapped.connect(_on_my_board_tapped)

	opp_board_view = BoardDisplay.new()
	opp_board_view.name = "OppBoard"
	opp_board_view.position = Vector3(0.0, 1.3, -0.62)
	opp_board_view.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	add_child(opp_board_view)
	opp_board_view.cell_tapped.connect(_on_opp_board_tapped)

	my_gooby = _make_seated_gooby(Vector3(-1.45, 0.0, 0.0), PI / 2.0)
	opp_gooby = _make_seated_gooby(Vector3(1.45, 0.0, 0.0), -PI / 2.0)
	if _session != null:
		opp_gooby.set_display_name(_session.opponent_gooby_name)
		my_gooby.set_display_name(_my_gooby_name())

	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.position = Vector3(0.0, 1.5, 1.55)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -0.4))


func _make_seated_gooby(pos: Vector3, yaw: float) -> RemoteGooby:
	var gooby := RemoteGooby.new()
	add_child(gooby)
	gooby.position = pos
	gooby.rig.rotation.y = yaw
	gooby.rig.play_clip("sit")
	var stool := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 0.5)
	stool.mesh = box
	stool.material_override = _flat(Color(0.62, 0.45, 0.3))
	stool.position = Vector3(0.0, 0.15, 0.0)
	gooby.add_child(stool)
	gooby.rig.position.y = 0.3
	return gooby


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	_turn_label = Label.new()
	_turn_label.theme_type_variation = &"TitleLabel"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_turn_label.offset_top = 12.0
	root.add_child(_turn_label)

	var leave := Button.new()
	leave.theme_type_variation = &"GhostButton"
	leave.text = I18nService.t("board.leave")
	leave.position = Vector2(16.0, 12.0)
	leave.pressed.connect(_on_leave_pressed)
	root.add_child(leave)

	_setup_box = HBoxContainer.new()
	_setup_box.add_theme_constant_override("separation", 8)
	_setup_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_setup_box.offset_bottom = -18.0
	_setup_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_setup_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_setup_box)
	var reroll := Button.new()
	reroll.theme_type_variation = &"GhostButton"
	reroll.text = I18nService.t("board.setup.reroll")
	reroll.pressed.connect(_on_reroll_pressed)
	_setup_box.add_child(reroll)
	var ready_btn := Button.new()
	ready_btn.theme_type_variation = &"PrimaryButton"
	ready_btn.text = I18nService.t("board.setup.ready")
	ready_btn.pressed.connect(_on_ready_pressed)
	_setup_box.add_child(ready_btn)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.offset_right = -16.0
	actions.offset_bottom = -18.0
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(actions)
	var emote_btn := Button.new()
	emote_btn.theme_type_variation = &"BtnTeal"
	emote_btn.text = I18nService.t("board.emote.button")
	emote_btn.pressed.connect(func() -> void: wheel.toggle())
	actions.add_child(emote_btn)
	_tomato_button = Button.new()
	_tomato_button.theme_type_variation = &"AccentButton"
	_tomato_button.text = I18nService.t("board.tomato.button")
	_tomato_button.pressed.connect(_on_tomato_pressed)
	actions.add_child(_tomato_button)

	wheel = EmoteWheel.new()
	wheel.set_anchors_preset(Control.PRESET_CENTER)
	wheel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wheel.grow_vertical = Control.GROW_DIRECTION_BOTH
	wheel.emote_picked.connect(_on_emote_picked)
	root.add_child(wheel)

	overlay = TomatoOverlay.new()
	root.add_child(overlay)
	toast = ToastLayer.new()
	root.add_child(toast)
	# ToastLayer setzt in _ready nur die Anker — kommt er in einen bereits
	# gelayouteten Parent, bleibt sein Rect leer → hier explizit aufziehen.
	toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _wire_session() -> void:
	if _session == null:
		return
	_session.opponent_shot.connect(_on_opponent_shot)
	_session.shot_result.connect(_on_shot_result)
	_session.opponent_emote.connect(_on_opponent_emote)
	_session.tomato_incoming.connect(_on_tomato_incoming)
	_session.tomato_rejected.connect(_on_tomato_rejected)
	_session.game_over.connect(_on_game_over)
	_session.game_resumed.connect(_on_game_resumed)
	_session.opponent_forfeit.connect(_on_opponent_forfeit)


# ── Setup-Phase ──────────────────────────────────────────────────────────────


func _start_setup() -> void:
	_phase = "setup"
	if _session != null and _session.board != null and _session.board.is_ready():
		# Rejoin/Resume: Brett steht schon.
		_fleet.assign(_session.board.ships)
		_enter_play()
		return
	if _session != null:
		_fleet = _session.default_fleet()
	else:
		_fleet = BattleshipLogic.auto_fleet(20260725)
	my_board_view.show_fleet(_fleet)
	_turn_label.text = I18nService.t("board.setup.title")


func _on_reroll_pressed() -> void:
	if _phase != "setup" or _locked:
		return
	_reroll_count += 1
	var seed_base := _session.seed_value if _session != null else 20260725
	var code := _session.my_code() if _session != null else "solo"
	_fleet = BattleshipLogic.auto_fleet(
		BoardSession.fleet_seed(seed_base + _reroll_count * 7919, code)
	)
	my_board_view.show_fleet(_fleet)


## Eigenes Brett antippen (Setup): getroffenes Schiff DREHEN (falls gültig).
func _on_my_board_tapped(cell: Vector2i) -> void:
	if _phase != "setup" or _locked:
		return
	for index in _fleet.size():
		var ship := _fleet[index]
		if not BattleshipLogic.ship_cells(ship).has(cell):
			continue
		var rotated := ship.duplicate()
		rotated["horizontal"] = not bool(ship.get("horizontal", true))
		var candidate: Array[Dictionary] = _fleet.duplicate()
		candidate[index] = rotated
		if BattleshipLogic.validate_fleet(candidate)["ok"]:
			_fleet = candidate
			my_board_view.show_fleet(_fleet)
		return


func _on_ready_pressed() -> void:
	if _phase != "setup":
		return
	if _session != null:
		_session.set_fleet(_fleet)
	_enter_play()


func _enter_play() -> void:
	_phase = "play"
	_locked = true
	_setup_box.visible = false
	my_board_view.show_fleet(_fleet)
	_redraw_markers()
	_update_turn_label()


# ── Spielzüge ────────────────────────────────────────────────────────────────


## Gegner-Brett antippen = Schuss (nur wenn dran).
func _on_opp_board_tapped(cell: Vector2i) -> void:
	if _phase != "play" or _session == null:
		return
	if _session.shoot(cell):
		_update_turn_label()


func _on_shot_result(_n: int, cell: Vector2i, hit: bool, sunk: bool) -> void:
	opp_board_view.set_marker(cell, "sunk" if sunk else ("hit" if hit else "miss"))
	if sunk:
		toast.show_toast(I18nService.t("board.sunk"))
	elif hit:
		toast.show_toast(I18nService.t("board.hit"))
	else:
		toast.show_toast(I18nService.t("board.miss"))
	if hit:
		my_gooby.rig.set_emotion("ecstatic")
		my_gooby.rig.play_clip("celebrate")
		opp_gooby.rig.set_emotion("sad")
	_update_turn_label()


func _on_opponent_shot(_n: int, cell: Vector2i, result: Dictionary) -> void:
	# Beim allerersten Gegner-Schuss vor „Bereit!“: Brett steht schon im
	# Session-Board (Antwort kam von dort) — Anzeige nachziehen.
	if _phase == "setup":
		_fleet.assign(_session.board.ships)
		_enter_play()
	var hit := bool(result["hit"])
	if bool(result["sunk"]):
		my_board_view.mark_sunk(result["sunk_cells"])
	else:
		my_board_view.set_marker(cell, "hit" if hit else "miss")
	if hit:
		opp_gooby.rig.set_emotion("ecstatic")
		opp_gooby.rig.play_clip("celebrate")
		my_gooby.rig.set_emotion("sad")
	_update_turn_label()


func _update_turn_label() -> void:
	if _phase != "play" or _session == null or _session.turn == null:
		return
	if _session.my_turn():
		_turn_label.text = I18nService.t("board.your_turn")
	else:
		_turn_label.text = I18nService.t("board.their_turn", {"name": _session.opponent_gooby_name})


## Resume: Marker beider Bretter aus dem Session-Zustand neu zeichnen.
func _on_game_resumed(_data: Dictionary) -> void:
	_fleet.assign(_session.board.ships)
	if _phase != "play":
		_enter_play()
	toast.show_toast(I18nService.t("board.resumed"))
	_redraw_markers()


func _redraw_markers() -> void:
	if _session == null or _session.board == null:
		return
	for cell: Vector2i in _session.board.shots_received:
		var hit := false
		for ship in _session.board.ships:
			if BattleshipLogic.ship_cells(ship).has(cell):
				hit = true
				break
		my_board_view.set_marker(cell, "hit" if hit else "miss")
	if _session.tracker != null:
		for cell: Vector2i in _session.tracker.shots:
			opp_board_view.set_marker(cell, "hit" if _session.tracker.shots[cell] else "miss")


# ── Emotes & Tomate ──────────────────────────────────────────────────────────


func _on_emote_picked(emote_id: String) -> void:
	my_gooby.play_emote(emote_id)
	if _session != null:
		_session.send_emote(emote_id)


func _on_opponent_emote(emote_id: String) -> void:
	opp_gooby.play_emote(emote_id)


func _on_tomato_pressed() -> void:
	if _session == null or not _session.throw_tomato():
		toast.show_toast(I18nService.t("board.tomato.limit"))
		return
	_play_tomato_arc(my_gooby, opp_gooby, false)


func _on_tomato_incoming() -> void:
	_play_tomato_arc(opp_gooby, my_gooby, true)


func _on_tomato_rejected(_code: String) -> void:
	toast.show_toast(I18nService.t("board.tomato.limit"))


## Wurf-Bogen von Gooby zu Gooby; trifft es UNS → Splat auf die Kamera.
func _play_tomato_arc(from_gooby: RemoteGooby, to_gooby: RemoteGooby, hits_me: bool) -> void:
	from_gooby.rig.play_clip(BoardEmotes.throw_clip(from_gooby.rig.clip_names()))
	var tomato := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	tomato.mesh = sphere
	tomato.material_override = _flat(Color(0.85, 0.15, 0.1))
	add_child(tomato)
	var from_pos: Vector3 = from_gooby.global_position + Vector3(0.0, 1.1, 0.0)
	var to_pos: Vector3 = to_gooby.global_position + Vector3(0.0, 1.0, 0.0)
	if hits_me:
		# Auf die „Kamera“ zu (Splat aufs Gesicht des Getroffenen = wir).
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			to_pos = camera.global_position + camera.global_transform.basis.z * -0.3
	tomato.global_position = from_pos
	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var mid := (from_pos + to_pos) * 0.5 + Vector3(0.0, 1.0, 0.0)
			var a := from_pos.lerp(mid, t)
			var b := mid.lerp(to_pos, t)
			tomato.global_position = a.lerp(b, t),
		0.0,
		1.0,
		0.55
	)
	tween.tween_callback(
		func() -> void:
			tomato.queue_free()
			if hits_me:
				overlay.splat()
				toast.show_toast(I18nService.t("board.tomato.hit"))
				my_gooby.rig.set_emotion("angry")
			else:
				opp_gooby.rig.set_emotion("dizzy")
	)


# ── Ende ─────────────────────────────────────────────────────────────────────


func _on_game_over(_winner: String, i_won: bool) -> void:
	_phase = "over"
	toast.show_toast(I18nService.t("board.win" if i_won else "board.lose"))
	_turn_label.text = I18nService.t("board.win" if i_won else "board.lose")
	if i_won:
		my_gooby.rig.set_emotion("ecstatic")
		my_gooby.rig.play_clip("celebrate")
		opp_gooby.rig.set_emotion("sad")
	else:
		opp_gooby.rig.set_emotion("ecstatic")
		opp_gooby.rig.play_clip("celebrate")
		my_gooby.rig.set_emotion("sad")


func _on_opponent_forfeit(_data: Dictionary) -> void:
	toast.show_toast(I18nService.t("board.forfeit", {"name": _session.opponent_gooby_name}))


func _on_leave_pressed() -> void:
	if _session != null:
		await _session.leave()
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


func _my_gooby_name() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_value"):
		return str(gs.get_value("meta.goobyNickname", "Gooby"))
	return "Gooby"


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
