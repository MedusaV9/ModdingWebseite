extends SceneTree
## REST-3-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Pflege-Kreislauf-Deliverables als Review-Artefakte — müder Gooby mit
## Augenringen + Gähnen, Zubettgeh-Moment im Schlafzimmer, kranker Gooby mit
## allen Symptomen, Tierarzt-Wartezimmer + Behandlung, Gewichtsvergleich.
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_rest3.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/REST3"
const SETTLE_FRAMES := 24
const ROOM_FRAMES := 90

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")
const Weight := preload("res://scripts/logic/weight.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_muede()
	await _shot_zubettgehen()
	await _shot_krank()
	await _shot_tierarzt()
	await _shot_gewicht()
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


# ── 1) Müder Gooby: Augenringe, sleepy-Gesicht, Gähnen ───────────────────────


func _shot_muede() -> void:
	var gs := _fresh_gs()
	gs.update(func(state: Dictionary) -> void: state["gooby"]["stats"]["energy"] = 12.0)
	var ctx := await _make_room("living", gs, 21.0)
	var room: RoomBase = ctx["room"]
	var runner := PflegeRunner.attach_to(room)
	runner.refresh()
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	_stelle_gooby(gooby, Vector3(1.4, 0.02, 1.7))
	await _frames(10)
	_kamera_auf_gooby(room)
	runner._yawn()
	await _frames(8)
	print("  muede: tired01=%.2f speed=%.2f" % [runner._tired01(), float(gooby.get("speed_mult"))])
	await _snap("muede_gooby_gaehnt.png")
	await _teardown(ctx)


# ── 2) Zubettgeh-Moment: Gooby schläft im Bett (sleep-Clip) ──────────────────


func _shot_zubettgehen() -> void:
	var gs := _fresh_gs()
	gs.update(func(state: Dictionary) -> void: state["gooby"]["stats"]["energy"] = 20.0)
	var ctx := await _make_room("bedroom", gs, 22.5)
	var room: RoomBase = ctx["room"]
	# Das bedSingle liegt im Default-Save im Lager — für den Moment stellen
	# wir es an die Wand und legen Gooby hinein.
	var def := FurnitureCatalog.def("bedSingle")
	var uid := HomeState.next_uid(gs)
	var bett_at := Vector2i(6, 2)
	var ergebnis := room.grid.place(def, bett_at, 0, uid)
	if not bool(ergebnis.get("ok", false)):
		print("  WARNUNG: Bett nicht platzierbar: %s" % ergebnis.get("reason", "?"))
	HomeState.save_room_grid(gs, "bedroom", room.grid)
	room.rebuild_furniture()
	await _frames(20)
	var eingeschlafen := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			eingeschlafen["ok"] = Sleep.start_sleep_state(state, gs.clock.now_ms())
	)
	print("  zubettgehen: eingeschlafen=%s" % eingeschlafen["ok"])
	var runner := PflegeRunner.attach_to(room)
	runner.refresh()
	var gooby := room.gooby()
	var footprint: Vector2i = def.get("footprint", Vector2i(2, 3))
	var bett_pos := GridData.world_center(bett_at, footprint, 0)
	gooby.global_position = bett_pos + Vector3(0.0, 0.32, 0.0)
	gooby.rotation.y = 0.0
	await _frames(12)
	# Kamera bleibt IM Raum (Schlafzimmer ist 5.0 x 4.0 m): schraeg von links
	# vorn aufs Bett, sonst steht sie in der Aussenwand.
	_kamera_auf(room, bett_pos + Vector3(-1.7, 1.45, 1.6), bett_pos + Vector3(0.0, 0.35, 0.0))
	await _snap("zubettgehen_schlafpose.png")
	await _teardown(ctx)


# ── 3) Kranker Gooby: blass, Schniefnase, Eisbeutel, Augenringe ──────────────


func _shot_krank() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void:
			state["gooby"]["stats"]["energy"] = 35.0
			state["gooby"]["health"] = {
				"state": "sick",
				"junkScore": 9.0,
				"neglectMin": 0.0,
				"recoverMin": 0.0,
				"since": gs.clock.now_ms(),
			}
	)
	var ctx := await _make_room("living", gs, 14.0)
	var room: RoomBase = ctx["room"]
	var runner := PflegeRunner.attach_to(room)
	runner.refresh()
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	_stelle_gooby(gooby, Vector3(1.4, 0.02, 1.7))
	room.say(I18nService.t("health.krank"))
	await _frames(10)
	_kamera_auf_gooby(room)
	var rig: GoobyRig = gooby.rig
	print(
		(
			"  krank: grade=%d weight_scale=%.3f speed=%.2f"
			% [rig.care_grade(), rig.weight_scale(), float(gooby.get("speed_mult"))]
		)
	)
	await _snap("kranker_gooby_symptome.png")
	await _teardown(ctx)


# ── 4) Tierarzt: Wartezimmer + Behandlungs-Moment ────────────────────────────


func _shot_tierarzt() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 500)
	gs.update(
		func(state: Dictionary) -> void:
			state["gooby"]["health"] = {
				"state": "sick",
				"junkScore": 9.0,
				"neglectMin": 0.0,
				"recoverMin": 0.0,
				"since": gs.clock.now_ms(),
			}
			state["gooby"]["weight"] = 64.0
	)
	var ort: OrtScene = load("res://scenes/city/orte/tierarzt.tscn").instantiate()
	ort.game_state_override = gs
	root.add_child(ort)
	await _frames(50)
	await _snap("tierarzt_wartezimmer.png")
	# Dialog durchklicken: Empfang (2 Zeilen) → "Gooby ist richtig krank."
	# → Untersuchung (3 Zeilen + Befund-Sequenz) → Diagnose → Behandlung.
	await _dialog_weiter(ort, 2)
	_dialog_option(ort, 0)
	await _frames(6)
	await _dialog_weiter(ort, 3)
	# Untersuchungs-Sequenz (Toasts + Patient niest) abwarten.
	await _frames(200)
	await _dialog_weiter(ort, 2)
	_dialog_option(ort, 0)
	await _frames(10)
	print("  tierarzt: Bubble = %s" % ort.dialog._bubble.current_line())
	await _snap("tierarzt_behandlung.png")
	# Behandlung zu Ende (vet_cure zahlt 120 c und heilt den Patienten).
	await _dialog_weiter(ort, 2)
	await _frames(20)
	print(
		(
			"  tierarzt: coins=%d health=%s"
			% [
				int(gs.get_value("economy.coins", -1)),
				str(((gs.state()["gooby"] as Dictionary).get("health") as Dictionary).get("state"))
			]
		)
	)
	await _snap("tierarzt_nachsorge_geheilt.png")
	PanelStack.clear()
	ort.queue_free()
	await _frames(2)
	_free_gs(gs)


func _dialog_weiter(ort: OrtScene, klicks: int) -> void:
	for _i in klicks:
		ort.dialog._bubble._advance()
		await _frames(4)


func _dialog_option(ort: OrtScene, index: int) -> void:
	ort.dialog._on_option(index)


# ── 5) Gewichtsvergleich: schlank / normal / rund nebeneinander ──────────────


func _shot_gewicht() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#F3E8FF")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.9
	var cam := Camera3D.new()
	cam.environment = env
	stage.add_child(cam)
	cam.position = Vector3(0.0, 0.6, 2.35)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.38, 0.0), Vector3.UP)
	cam.current = true
	var licht := DirectionalLight3D.new()
	stage.add_child(licht)
	licht.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	licht.light_energy = 1.1
	var boden := MeshInstance3D.new()
	var boden_mesh := PlaneMesh.new()
	boden_mesh.size = Vector2(12.0, 12.0)
	boden.mesh = boden_mesh
	var boden_mat := StandardMaterial3D.new()
	boden_mat.albedo_color = Color("#DFF3E4")
	boden.material_override = boden_mat
	stage.add_child(boden)
	var faelle: Array = [[-1.35, 10.0, "schlank"], [0.0, 50.0, "normal"], [1.35, 90.0, "rund"]]
	for fall: Array in faelle:
		var rig := GoobyRig.new()
		stage.add_child(rig)
		rig.position = Vector3(float(fall[0]), 0.0, 0.0)
		rig.set_weight(float(fall[1]))
		rig.set_emotion("happy")
		rig.play_clip.call_deferred("idle")
		var label := Label3D.new()
		label.text = "%s\nGewicht %d" % [str(fall[2]), int(fall[1])]
		label.font_size = 44
		label.pixel_size = 0.0026
		label.outline_size = 10
		label.modulate = Color("#4A3A6B")
		label.position = Vector3(float(fall[0]), 1.22, 0.3)
		stage.add_child(label)
		print("  gewicht %s: scale=%.3f" % [str(fall[2]), rig.weight_scale()])
	await _frames(40)
	await _snap("gewicht_vergleich_schlank_normal_rund.png")
	stage.queue_free()
	await _frames(2)


# ── Gerüst ───────────────────────────────────────────────────────────────────


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rest3_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	return gs


func _free_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	HomeState.reset_for_tests()
	CityState.reset_for_tests()


func _make_room(room_id: String, gs: Node, stunde: float) -> Dictionary:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = stunde
	root.add_child(room)
	await process_frame
	for _i in ROOM_FRAMES:
		await process_frame
	return {"room": room, "gs": gs}


func _teardown(ctx: Dictionary) -> void:
	PanelStack.clear()
	(ctx["room"] as Node).queue_free()
	await process_frame
	await process_frame
	_free_gs(ctx["gs"] as Node)


## Gooby an eine freie Stelle stellen und zur Kamera (Sueden, +Z) drehen.
func _stelle_gooby(gooby: Node3D, pos: Vector3) -> void:
	gooby.global_position = pos
	gooby.rotation.y = 0.0
	var rig: Variant = gooby.get("rig")
	if rig is Node3D:
		(rig as Node3D).rotation.y = 0.0


## Kamera frontal nah an Gooby heran (Rig-Details: Augenringe, Nase,
## Eisbeutel) — Gooby schaut nach +Z, die Kamera steht suedlich davon.
## Der Standort (Westhaelfte Wohnzimmer) ist im Default-Layout frei; das
## Sofa (Zellen x 4-6, z 7-8) bleibt hinter der Kamera.
func _kamera_auf_gooby(room: RoomBase) -> void:
	var gooby := room.gooby()
	var ziel: Vector3 = gooby.global_position + Vector3(0.0, 0.42, 0.0)
	_kamera_auf(room, ziel + Vector3(0.15, 0.5, 1.6), ziel)


func _kamera_auf(room: RoomBase, pos: Vector3, ziel: Vector3, fov := 45.0) -> void:
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	rig.follow_target = null
	rig.camera.fov = fov
	rig.camera.global_position = pos
	rig.camera.look_at(ziel, Vector3.UP)


func _frames(anzahl: int) -> void:
	for _i in anzahl:
		await process_frame


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
