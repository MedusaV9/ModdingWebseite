extends SceneTree
## M2-HAUS-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Deliverables aus Doc D §5/§6 als Review-Artefakte — Werkstatt + Crafting-UI,
## Goobay-Verhandlung, Garten-Grid mit Gewächshaus, Fenster mit Straßen-
## Diorama und die Liefer-Cutscene.
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_haus.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/HAUS"
const SETTLE_FRAMES := 24
const CAMERA_FRAMES := 150
## Fixe Uhr für die Screenshots (deterministisches Wachstum/Tagesnachfrage).
const JETZT_S := 1768478400.0

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_garten_und_werkstatt()
	await _shot_fenster_diorama()
	await _shot_lieferung()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


# ── Garten, Werkstatt/Crafting und Goobay (ein Spielstand) ───────────────────


func _shot_garten_und_werkstatt() -> void:
	var gs := _fresh_gs()
	_seed_garten(gs)
	_seed_materialien(gs)
	var ctx := await _make_room("garden", gs)
	var host: GardenHost = (ctx["room"] as Node).get_node("GardenHost")
	host.set_jetzt_override(JETZT_S)
	host.select_cell(Vector2i(1, 3))
	# Überblick über das ganze Garten-Grid (Werkstatt, Shed, Gewächshaus).
	_kamera_auf(ctx["room"], Vector3(7.0, 9.0, 14.5), Vector3(7.0, 0.0, 4.0))
	for _i in 20:
		await process_frame
	await _snap("garten_grid_gewaechshaus.png")
	await _shot_crafting(host)
	await _shot_goobay(host, ctx["room"])
	await _teardown(ctx)


func _shot_crafting(host: GardenHost) -> void:
	host.werkstatt_oeffnen()
	for _i in 20:
		await process_frame
	var panel: CraftPanel = host._ui_layer().get_node("CraftPanel")
	panel.select_recipe("r_gartentisch")
	await _snap("werkstatt_crafting_ui.png")
	# Craft wirklich auslösen: Materialien wandern weg, das Möbel ins Lager.
	panel.select_recipe("r_zaun_holz")
	await panel.craft_selected()
	await _snap("werkstatt_crafting_fertig.png")
	panel.close()
	for _i in 10:
		await process_frame


func _shot_goobay(host: GardenHost, room: Node) -> void:
	host.goobay_oeffnen()
	for _i in 20:
		await process_frame
	var panel: GoobayPanel = host._ui_layer().get_node("GoobayPanel")
	panel._rng.seed = 4242
	panel._tag = "2026-07-25"
	panel.starte_verhandlung("table_rustic")
	for _i in 6:
		await process_frame
	panel.hoeher()
	for _i in 6:
		await process_frame
	await _snap("goobay_verhandlung.png")
	panel.close()
	for _i in 10:
		await process_frame
	if room.has_method("say"):
		room.say("")


## Garten füllen: Gewächshaus mit Exot, Beete in verschiedenen Stufen,
## Werkstatt, Shed L2, Baum, Sprinkler und ein Stück Zaun.
func _seed_garten(gs: Object) -> void:
	GardenState.erweitern(gs)
	GardenState.erweitern(gs)
	var grid := GardenState.grid(gs)
	grid.place_structure("gewaechshaus", Vector2i(6, 4), 0, Vector2i(6, 4))
	grid.place_structure("werkstatt", Vector2i(0, 0))
	grid.place_structure("shed", Vector2i(8, 0))
	grid.place_structure("baum", Vector2i(9, 7))
	grid.place_structure("sprinkler", Vector2i(3, 5))
	grid.edges.append({"from": Vector2i(0, 7), "dir": "E", "len": 6, "fence": "fence_wood"})
	GardenState.save_grid(gs, grid)
	gs.update(func(state: Dictionary) -> void: state["home"]["shedStufe"] = 2)
	gs.notify_slice_changed("home")
	for beet: Array in [
		[Vector2i(1, 3), "carrot", 2], [Vector2i(2, 3), "tomate", 3], [Vector2i(1, 4), "salat", 1]
	]:
		GardenState.pflanzen(gs, beet[0], str(beet[1]))
		GardenState.giessen(gs, beet[0], JETZT_S)
		_stufe_setzen(gs, beet[0], int(beet[2]))
	GardenState.pflanzen(gs, Vector2i(6, 5), "ananas")
	GardenState.giessen(gs, Vector2i(6, 5), JETZT_S)
	_stufe_setzen(gs, Vector2i(6, 5), 2)


func _stufe_setzen(gs: Object, at: Vector2i, stufe: int) -> void:
	var grid := GardenState.grid(gs)
	var data := grid.cell(at)
	var crop := GardenCrops.crop(str(data.get("crop", "")))
	data["stage"] = stufe
	data["progress_min"] = stufe * float(crop.get("minuten_pro_stufe", 60.0))
	grid.set_cell(at, data)
	GardenState.save_grid(gs, grid)


func _seed_materialien(gs: Object) -> void:
	for eintrag: Array in [["holz", 9], ["naegel", 20], ["eisen", 3], ["stock", 6], ["blatt", 5]]:
		CraftState.add_material(gs, str(eintrag[0]), int(eintrag[1]))
	CraftState.add_blueprint(gs, "bp_gartentisch")
	CraftState.add_blueprint(gs, "bp_regal_rustikal")
	HomeState.store_item(gs, "table_rustic")
	HomeState.store_item(gs, "stool_rustic")
	gs.set_value("economy.coins", 4200)


# ── Fenster + Straßen-Diorama ────────────────────────────────────────────────


func _shot_fenster_diorama() -> void:
	var gs := _fresh_gs()
	var ctx := await _make_room("living", gs)
	var room: RoomBase = ctx["room"]
	# Breites Außenfenster an die Nordwand hängen (Bau-Commit-Weg).
	var def := FurnitureCatalog.def("window_wide")
	var uid := HomeState.next_uid(gs)
	var ergebnis := room.grid.place_wall(def, "N", 4, uid)
	if not bool(ergebnis["ok"]):
		print("  WARNUNG: Fenster nicht platzierbar: %s" % ergebnis["reason"])
	HomeState.save_room_grid(gs, "living", room.grid)
	room.rebuild_furniture()
	# Dicht und hoch vor dem Fenster: nur so fällt der Blick durch den
	# Wandausschnitt bis auf die Fahrbahn (sonst sieht man nur Hauswand).
	_kamera_auf(room, Vector3(2.68, 2.35, 2.2), Vector3(2.68, 1.79, 0.0), 60.0)
	for _i in 40:
		await process_frame
	# Verkehr für den Screenshot anhalten, sonst ist gerade kein Auto im
	# Fensterausschnitt (die Autos fahren im _process weiter).
	var diorama: StreetDiorama = room._dioramas.get("N")
	if diorama != null:
		diorama.set_process(false)
		diorama._autos[1].position.x = 0.1
	for _i in 6:
		await process_frame
	await _snap("fenster_strassen_diorama.png")
	await _teardown(ctx)


# ── Liefer-Cutscene ──────────────────────────────────────────────────────────


func _shot_lieferung() -> void:
	var gs := _fresh_gs()
	DeliveryCutscene.bestellen(gs, "loungeSofaCorner", 1)
	DeliveryCutscene.bestellen(gs, "bookcaseOpen", 2)
	# Wenig Vorlauf: die Cutscene startet sofort beim Betreten des Gartens.
	var ctx := await _make_room("garden", gs, 8)
	var room: RoomBase = ctx["room"]
	var szene: DeliveryCutscene = room.get_node_or_null("DeliveryCutscene")
	if szene == null:
		print("  WARNUNG: keine Liefer-Cutscene aktiv!")
		await _teardown(ctx)
		return
	# Die Cutscene läuft bereits (GardenHost startet sie deferred) — auf den
	# Moment warten, in dem der LKW steht und Gooby einweist.
	var frames := 0
	while is_instance_valid(szene) and szene._kartons.is_empty() and frames < 3000:
		frames += 1
		await process_frame
	# Genau im Abladen-Moment einfrieren, sonst fährt der LKW während der
	# Settle-Frames schon wieder aus dem Bild.
	paused = true
	_kamera_auf(room, Vector3(10.56, 6.21, 10.07), Vector3(7.5, 0.8, 1.6))
	await _snap("liefer_cutscene.png")
	paused = false
	await _teardown(ctx)


## Kamera-Rig anhalten und die Kamera frei stellen (nur für Screenshots).
func _kamera_auf(room: RoomBase, pos: Vector3, ziel: Vector3, fov := 45.0) -> void:
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	rig.follow_target = null
	rig.camera.fov = fov
	rig.camera.global_position = pos
	rig.camera.look_at(ziel, Vector3.UP)


# ── Gerüst ───────────────────────────────────────────────────────────────────


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://haus_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	return gs


func _make_room(room_id: String, gs: Node, warten := CAMERA_FRAMES) -> Dictionary:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	await process_frame
	for _i in warten:
		await process_frame
	return {"room": room, "gs": gs}


func _teardown(ctx: Dictionary) -> void:
	PanelStack.clear()
	(ctx["room"] as Node).queue_free()
	await process_frame
	await process_frame
	(ctx["gs"] as Node).free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
