extends SceneTree
## RANCH-2-Screenshot-Werkzeug (KEIN Test — kein test_-Präfix): rendert die
## Ranch-Gameplay-Deliverables als Review-Artefakte (Pferdepflege-Screen,
## Reiten über die Weide, Hindernis-Parcours, Schaf-Hüten quer + hochkant,
## Ranch-Ausbau-UI) und misst die Draw-Calls der Reit-/Minispiel-Ansichten
## (Budget ≤ 300). Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_ranchplay.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RANCH2"
const DRAWCALL_BUDGET := 300
const LANDSCAPE := Vector2i(1280, 720)
const PORTRAIT := Vector2i(760, 1200)
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const WAIT_LIMIT := 400

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const HerdeLogic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")
const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")

var _seq := 0
var _report: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	await _shot_pflege()
	await _shot_ausbau()
	await _shot_reiten()
	await _shot_parcours()
	await _shot_herde(false, "schaf_hueten.png")
	await _shot_herde(true, "schaf_hueten_hochkant.png")
	print("\n== Draw-Calls (Budget %d) ==" % DRAWCALL_BUDGET)
	for line in _report:
		print("  ", line)
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## ------------------------------------------------------- lokaler GameState


func _make_gs() -> Node:
	_seq += 1
	RanchState.register_slice()
	var dir := "user://ranchplay_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", 1500)
	gs.set_value("inventory.food.carrot", 3)
	return gs


## Ein gepflegtes Vorzeige-Pferd mit halbvollen Werten + Gear in den Save.
func _seed_pferd(gs: Node) -> void:
	var luna := RanchPlaySlices.neues_pferd("Luna", "palomino")
	luna["werte"] = {"hunger": 63.0, "durst": 52.0, "sauberkeit": 44.0}
	luna["bindung"] = 62.0
	luna["ausruestung"] = {"sattel": "rot", "decke": "blau", "halfter": "gold"}
	gs.set_value("ranch.tiere.pferde", {"luna": luna})
	gs.set_value("ranch.tiere.stall.sauberkeit", 71.0)
	gs.set_value("ranch.wirtschaft.gear.owned", ["sattel_rot", "decke_blau", "halfter_gold"])


func _teardown_gs(node: Node, gs: Node) -> void:
	if node != null:
		node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


## ---------------------------------------------------------------- Pflege


func _shot_pflege() -> void:
	_resize(LANDSCAPE)
	var gs := _make_gs()
	_seed_pferd(gs)
	var screen := RanchPflegeScreen.new()
	screen.game_state_override = gs
	screen.setup("luna")
	root.add_child(screen)
	for _i in 30:
		await process_frame
	# Einmal striegeln: Feedback „+3 Bindung“ + Freude-Puls sind im Bild.
	var btn: Button = screen._aktion_buttons["striegeln"]
	btn.pressed.emit()
	for _i in 8:
		await process_frame
	await _snap("pferdepflege.png")
	await _teardown_gs(screen, gs)


## ---------------------------------------------------------------- Ausbau


func _shot_ausbau() -> void:
	_resize(LANDSCAPE)
	var gs := _make_gs()
	_seed_pferd(gs)
	var panel := RanchAusbauPanel.new()
	panel.game_state_override = gs
	root.add_child(panel)
	for _i in 20:
		await process_frame
	# Ein Kauf fürs Bild: Heu kaufen zeigt Toast + aktualisierte Münzen.
	panel._heu_kaufen_btn.pressed.emit()
	for _i in 8:
		await process_frame
	await _snap("ranch_ausbau_ui.png")
	await _teardown_gs(panel, gs)


## ---------------------------------------------------------------- Reiten


func _shot_reiten() -> void:
	_resize(LANDSCAPE)
	var welt := Node3D.new()
	root.add_child(welt)
	_build_weide(welt)
	var controller := RanchRideController.new()
	controller.keyboard_input = false
	controller.position = Vector3(0.0, 0.0, 6.0)
	welt.add_child(controller)
	controller.set_bounds(Vector3.ZERO, Vector2(16.0, 12.0))
	controller.set_bindung(80.0)
	await process_frame
	# Gooby aufsitzen lassen (gleiches Mount wie in den Minispielen).
	var gooby: Node3D = (
		(load("res://scripts/minigames/games/_3da_stage/gooby_actor.gd") as GDScript).new()
	)
	gooby.position = Vector3(0.0, RanchHorseStub.RUECKEN_Y + 0.26, -0.1)
	controller.add_child(gooby)
	gooby.call("mount", 0.62, 0.0, "idle")
	controller.steer_input(0.3)
	for _i in 3:
		controller.gait_up()
	# Anreiten lassen: Galopp, Staub, Kopfnicken — dann fotografieren.
	for _i in 55:
		await process_frame
		if gooby.has_method("tick"):
			gooby.call("tick", 1.0 / 30.0)
	var calls := await _mess_draw_calls(20)
	_report.append(_budget_zeile("reiten_weide", calls))
	await _snap("reiten_weide.png")
	welt.queue_free()
	await process_frame


func _build_weide(welt: Node3D) -> void:
	var licht := DirectionalLight3D.new()
	licht.shadow_enabled = true
	licht.light_energy = 1.2
	licht.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	welt.add_child(licht)
	var umgebung := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.68, 0.93)
	sky_mat.sky_horizon_color = Color(0.9, 0.95, 1.0)
	sky_mat.ground_horizon_color = Color(0.85, 0.92, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	welt.add_child(umgebung)
	umgebung.environment = env
	var gras := MeshInstance3D.new()
	var gras_mesh := BoxMesh.new()
	gras_mesh.size = Vector3(60.0, 0.3, 50.0)
	gras.mesh = gras_mesh
	gras.material_override = RanchPferd.material(Color(0.56, 0.78, 0.45))
	gras.position.y = -0.15
	welt.add_child(gras)
	# Koppelzaun: vier Riegel.
	for wand: Array in [
		[Vector3(0.0, 0.5, -12.0), Vector3(32.0, 0.5, 0.16)],
		[Vector3(0.0, 0.5, 12.0), Vector3(32.0, 0.5, 0.16)],
		[Vector3(-16.0, 0.5, 0.0), Vector3(0.16, 0.5, 24.0)],
		[Vector3(16.0, 0.5, 0.0), Vector3(0.16, 0.5, 24.0)],
	]:
		var riegel := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = wand[1]
		riegel.mesh = mesh
		riegel.material_override = RanchPferd.material(Color(0.72, 0.53, 0.36))
		riegel.position = wand[0]
		welt.add_child(riegel)
	# Deko-Bäume als EIN MultiMesh.
	var baeume := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var kugel := SphereMesh.new()
	kugel.radius = 1.6
	kugel.height = 3.2
	kugel.radial_segments = 12
	kugel.rings = 6
	mm.mesh = kugel
	mm.instance_count = 10
	var rng := GoobyRng.new(11)
	for i in 10:
		var seite := -1.0 if i % 2 == 0 else 1.0
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(rng.next() * 28.0 - 14.0, 1.7, seite * (13.5 + rng.next() * 4.0))
			)
		)
	baeume.multimesh = mm
	baeume.material_override = RanchPferd.material(Color(0.4, 0.66, 0.4))
	baeume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(baeume)


## -------------------------------------------------------------- Parcours


func _shot_parcours() -> void:
	_resize(Vector2i(1200, 760))
	var host := await _mount_host("ranchParcours", "landscape")
	var game: MinigameBase = _game(host)
	if game == null:
		print("  ÜBERSPRUNGEN: ranchParcours startet nicht")
		host.queue_free()
		return
	await _until(func() -> bool: return bool(game.running))
	game.call("_on_level_chosen", 3)
	await _until(func() -> bool: return bool(game.level_running))
	game.set("galopp", true)
	# Bot-Absprung am ersten Hindernis: Bogenmitte aufs Hindernis legen.
	var hindernisse: Array = game.get("hindernisse")
	var mitte := float((hindernisse[0] as Dictionary)["at"])
	await _until(
		func() -> bool:
			var weite := float(Feel.sprung_daten(float(game.get("tempo")))["weite_m"])
			return float(game.get("x")) >= mitte - weite * 0.62
	)
	game.call("_sprung_input")
	# Mitten im Bogen über dem Hindernis fotografieren.
	await _until(
		func() -> bool: return not bool(game.get("in_luft")) or float(game.get("x")) >= mitte - 0.8
	)
	var calls := await _mess_draw_calls(6)
	_report.append(_budget_zeile("parcours", calls))
	await _snap("hindernis_parcours.png")
	host.queue_free()
	await process_frame


## ----------------------------------------------------------------- Herde


func _shot_herde(hochkant: bool, datei: String) -> void:
	_resize(PORTRAIT if hochkant else Vector2i(1200, 760))
	var host := await _mount_host("ranchHerde", "portrait" if hochkant else "landscape")
	var game: MinigameBase = _game(host)
	if game == null:
		print("  ÜBERSPRUNGEN: ranchHerde startet nicht")
		host.queue_free()
		return
	await _until(func() -> bool: return bool(game.running))
	game.call("_on_level_chosen", 2)
	await _until(func() -> bool: return bool(game.level_running))
	# Bot-Regie: den Reiter hinter das tor-fernste Schaf schicken, bis die
	# ersten Schafe im Pferch sind (Zustand, nicht Bildzahl — xvfb ist träge).
	for _i in WAIT_LIMIT:
		await process_frame
		if not bool(game.level_running):
			break
		var schafe: Array = game.get("schafe")
		game.set("ziel", HerdeLogic.bot_ziel(schafe, game.get("level")))
		if HerdeLogic.drin_anzahl(schafe) >= 2:
			break
	var calls := await _mess_draw_calls(6)
	_report.append(_budget_zeile("herde%s" % ("_hochkant" if hochkant else ""), calls))
	await _snap(datei)
	host.queue_free()
	await process_frame


## --------------------------------------------------------------- Technik


func _mount_host(game_id: String, orientation: String) -> Node:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	(
		host
		. receive_params(
			{
				"game_id": game_id,
				"difficulty": "normal",
				"seed": 4242,
				"orientation": orientation,
			}
		)
	)
	root.add_child(host)
	for _i in 24:
		await process_frame
	return host


func _game(host: Node) -> MinigameBase:
	var found := host.find_children("*", "MinigameBase", true, false)
	return null if found.is_empty() else found[0] as MinigameBase


func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _until(cond: Callable) -> void:
	for _i in WAIT_LIMIT:
		if bool(cond.call()):
			return
		await process_frame
	push_warning("[RANCH2] Wartebedingung nie erfüllt — fotografiere trotzdem")


func _mess_draw_calls(frames: int) -> int:
	var maximum := 0
	for _i in frames:
		await process_frame
		maximum = maxi(
			maximum,
			int(
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				)
			)
		)
	return maximum


func _budget_zeile(name_id: String, calls: int) -> String:
	var status := "OK" if calls <= DRAWCALL_BUDGET else "ÜBER BUDGET"
	return "%s: %d Draw-Calls -> %s" % [name_id, calls, status]


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	root.set_content_scale_size(size)


func _snap(file_name: String) -> void:
	for _i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file_name])
	print("  %s (%dx%d)" % [file_name, image.get_width(), image.get_height()])
