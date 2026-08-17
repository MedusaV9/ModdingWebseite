extends SceneTree
## RW-2-Screenshot-Werkzeug (KEIN Test — kein test_-Präfix): rendert die
## Pferde-DLC-Deliverables als Review-Artefakte (GLB-Pferde in 3 Rassen/
## Farben nah, Galopp mit Touch-HUD, Sprung mit „Perfekt!"-Callout,
## Zähm-Szene, Stammbaum, Level-Up-Feier, Fohlen) und misst die
## Draw-Calls beim Reiten (Budget ≤ 300). Braucht einen echten Renderer:
## xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --audio-driver Dummy \
##   --script res://tests/unit/screenshot_rpferd.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW2"
const DRAWCALL_BUDGET := 300
const LANDSCAPE := Vector2i(1280, 720)

const Breeding := preload("res://scripts/ranch/gameplay/horse_breeding.gd")
const Taming := preload("res://scripts/ranch/gameplay/horse_taming.gd")

var _report: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(LANDSCAPE)
	await _shot_rassen()
	await _shot_reiten_und_sprung()
	await _shot_zaehmen()
	await _shot_fohlen()
	await _shot_stammbaum()
	await _shot_levelup()
	print("\n== Draw-Calls (Budget %d) ==" % DRAWCALL_BUDGET)
	for line in _report:
		print("  ", line)
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## ---------------------------------------- 1) Drei Rassen/Farben nah


func _shot_rassen() -> void:
	var welt := _welt()
	var balance := RanchRassen.load_balance()
	# Drei sichtbar unterschiedliche Individuen: Glitzer-Sternschnuppler,
	# ein Schecke und ein Moosmähnen-Puschel (deterministische Seeds).
	var links := RanchRassen.neues_individuum("sternschnuppler", 11, balance)
	var mitte := _finde_schecke("wolkentraber", balance)
	var rechts := RanchRassen.neues_individuum("moosmaehne", 4, balance)
	# Blick zur Kamera (-Z ist Blickrichtung → rotation.y um PI).
	var posen: Array = [
		[links, Vector3(-2.3, 0.0, 0.0), PI - 0.4],
		[mitte, Vector3(0.0, 0.0, -0.4), PI],
		[rechts, Vector3(2.3, 0.0, 0.0), PI + 0.4],
	]
	for pose: Array in posen:
		var pferd := RanchPferd.new()
		pferd.position = pose[1]
		pferd.rotation.y = float(pose[2])
		welt.add_child(pferd)
		pferd.set_aussehen(pose[0])
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.0, 1.7, 4.6)
	kamera.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	kamera.fov = 55.0
	welt.add_child(kamera)
	kamera.current = true
	await _settle(40)
	await _snap("pferde_rassen_nah.png")
	welt.queue_free()
	await process_frame


func _finde_schecke(rasse_id: String, balance: Dictionary) -> Dictionary:
	for seed_wert in 400:
		var p := RanchRassen.neues_individuum(rasse_id, seed_wert, balance)
		if RanchRassen.ist_schecke(p["gene"]):
			return p
	return RanchRassen.neues_individuum(rasse_id, 0, balance)


## ------------------------- 2) Galopp mit HUD + 3) Sprung mit Perfekt!


func _shot_reiten_und_sprung() -> void:
	var welt := _welt()
	var controller := RanchRideController.new()
	controller.keyboard_input = false
	controller.position = Vector3(0.0, 0.0, 8.0)
	var reittier := RanchPferd.new()
	controller.add_child(reittier)
	controller.set_horse(reittier)
	welt.add_child(controller)
	controller.set_bounds(Vector3.ZERO, Vector2(40.0, 40.0))
	var luna := RanchPlaySlices.neues_pferd(
		"Luna", "palomino", _finde_farbe("wolkentraber", ["braun", "fuchs", "palomino"])
	)
	luna["bindung"] = 70.0
	controller.set_pferd(luna)
	reittier.set_aussehen(luna)
	await process_frame
	var gooby: Node3D = (
		(load("res://scripts/minigames/games/_3da_stage/gooby_actor.gd") as GDScript).new()
	)
	gooby.position = Vector3(0.0, RanchHorseStub.RUECKEN_Y + 0.26, -0.1)
	controller.add_child(gooby)
	gooby.call("mount", 0.62, 0.0, "idle")
	var hud := RanchRideHud.new()
	hud.controller = controller
	var lage := CanvasLayer.new()
	root.add_child(lage)
	lage.add_child(hud)
	# Anreiten: bis in den Galopp schalten und Tempo aufbauen lassen.
	for _i in 3:
		controller.gait_up()
	controller.steer_input(0.12)
	for _i in 40:
		await process_frame
		if gooby.has_method("tick"):
			gooby.call("tick", 1.0 / 30.0)
	# xvfb-Frames sind langsam (~80 ms) — der Galopp frisst den Tank
	# schneller als in Echtzeit. Fuers Foto den Tank auffuellen.
	controller.ausdauer = controller.ausdauer_max() * 0.8
	var calls := await _mess_draw_calls(8)
	_report.append(_budget_zeile("reiten_galopp_hud", calls))
	controller.ausdauer = controller.ausdauer_max() * 0.8
	await _snap("reiten_galopp_hud.png")
	# Sprung: Tank + Erschoepfung zuruecksetzen und in den Trab bremsen —
	# bei 4,2 m/s bleibt das Pferd im (langsamen) xvfb-Frame-Takt sichtbar
	# NEBEN dem Hindernis in der Luft. Perfekt-Zone: 1,1 m voraus.
	controller.steer_input(0.0)
	controller.ausdauer = controller.ausdauer_max()
	controller.set("_erschoepft_rest", 0.0)
	controller.gait_down()
	for _i in 10:
		await process_frame
		if gooby.has_method("tick"):
			gooby.call("tick", 1.0 / 30.0)
	controller.ausdauer = controller.ausdauer_max()
	var vorwaerts := Vector3(sin(controller.heading), 0.0, cos(controller.heading)) * -1.0
	var punkt: Vector3 = controller.position + vorwaerts * 1.1
	_baue_hindernis(welt, punkt, controller.heading)
	controller.set_hindernisse([punkt])
	controller.jump()
	await process_frame
	await _snap("sprung_perfekt.png")
	lage.queue_free()
	welt.queue_free()
	await process_frame


## Deterministisch ein Individuum mit Wunsch-Fellfarbe suchen.
func _finde_farbe(rasse_id: String, farben: Array) -> Dictionary:
	var balance := RanchRassen.load_balance()
	for seed_wert in 400:
		var p := RanchRassen.neues_individuum(rasse_id, seed_wert, balance)
		if farben.has(str(p["farbe"])):
			return p
	return RanchRassen.neues_individuum(rasse_id, 0, balance)


func _baue_hindernis(welt: Node3D, punkt: Vector3, heading: float) -> void:
	var balken := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 0.16, 0.16)
	balken.mesh = mesh
	balken.material_override = RanchPferd.material(Color(0.74, 0.5, 0.32))
	balken.position = punkt + Vector3(0.0, 0.5, 0.0)
	balken.rotation.y = heading
	welt.add_child(balken)
	for seite: float in [-1.2, 1.2]:
		var pfosten := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(0.14, 1.0, 0.14)
		pfosten.mesh = p_mesh
		pfosten.material_override = RanchPferd.material(Color(0.58, 0.4, 0.26))
		pfosten.position = Vector3(seite, 0.0, 0.0)
		balken.add_child(pfosten)


## ------------------------------------------------- 4) Zähm-Begegnung


func _shot_zaehmen() -> void:
	var szene := RanchZaehmSzene.new()
	szene.seed_wert = 77
	root.add_child(szene)
	await _settle(10)
	# Angeschlichen bis in die Beruhigen-Distanz (Phase kippt) …
	szene.geduckt = true
	szene.get("_spieler").position = Vector3(0.0, 0.0, 1.2)
	await _settle(8)
	# … dann die Foto-Pose: Wildpferd dreht sich dem Gooby zu, etwas
	# Abstand, ein paar Takt-Treffer sind schon gelandet (Ruhe-Balken).
	szene.geduckt = false
	szene.get("_spieler").position = Vector3(0.9, 0.0, 3.0)
	var wurzel: Node3D = (szene.get("_pferd_node") as Node3D).get_parent_node_3d()
	wurzel.rotation.y = PI - 0.35
	szene.zustand["ruhe"] = 46.0
	await _settle(20)
	await _snap("zaehm_szene.png")
	szene.queue_free()
	await process_frame


## -------------------------------------------------------- 5) Fohlen


func _shot_fohlen() -> void:
	var welt := _welt()
	var balance := RanchRassen.load_balance()
	var mutter_dict := RanchRassen.neues_individuum("puschelhufer", 21, balance)
	var mutter := RanchPferd.new()
	mutter.position = Vector3(-1.1, 0.0, -0.8)
	mutter.rotation.y = PI - 0.45
	welt.add_child(mutter)
	mutter.set_aussehen(mutter_dict)
	var fohlen_dict := Breeding.wuerfle_fohlen(
		mutter_dict, RanchRassen.neues_individuum("sternschnuppler", 5, balance), 99
	)
	fohlen_dict["alter"] = "fohlen"
	var fohlen := RanchPferd.new()
	fohlen.position = Vector3(0.9, 0.0, 0.6)
	fohlen.rotation.y = PI + 0.3
	welt.add_child(fohlen)
	fohlen.set_aussehen(fohlen_dict)
	fohlen.set_gangart(RanchPferd.GANG_SCHRITT)
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.6, 1.3, 3.6)
	kamera.rotation_degrees = Vector3(-10.0, 8.0, 0.0)
	kamera.fov = 55.0
	welt.add_child(kamera)
	kamera.current = true
	await _settle(40)
	await _snap("fohlen_mit_mutter.png")
	welt.queue_free()
	await process_frame


## ----------------------------------------------------- 6) Stammbaum


func _shot_stammbaum() -> void:
	var balance := RanchRassen.load_balance()
	var oma := RanchRassen.neues_individuum("wolkentraber", 31, balance)
	oma["name"] = "Wolke"
	var opa := RanchRassen.neues_individuum("moosmaehne", 32, balance)
	opa["name"] = "Moosbart"
	var mutter := Breeding.wuerfle_fohlen(oma, opa, 7)
	mutter["name"] = "Luna"
	mutter["ahnen"] = {
		"mutter": Breeding.eltern_snapshot(oma), "vater": Breeding.eltern_snapshot(opa)
	}
	var vater := RanchRassen.neues_individuum("sternschnuppler", 33, balance)
	vater["name"] = "Funkel"
	var fohlen := Breeding.wuerfle_fohlen(mutter, vater, 12)
	fohlen["name"] = "Sternchen"
	fohlen["ahnen"] = {
		"mutter": Breeding.eltern_snapshot(mutter), "vater": Breeding.eltern_snapshot(vater)
	}
	var hintergrund := ColorRect.new()
	hintergrund.color = Color("#F3E7D3")
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(hintergrund)
	var mitte := CenterContainer.new()
	mitte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hintergrund.add_child(mitte)
	var panel := RanchStammbaumPanel.new()
	panel.setup(fohlen)
	mitte.add_child(panel)
	await _settle(20)
	await _snap("stammbaum.png")
	hintergrund.queue_free()
	await process_frame


## ------------------------------------------------- 7) Level-Up-Feier


func _shot_levelup() -> void:
	var welt := _welt()
	var pferd := RanchPferd.new()
	pferd.rotation.y = PI - 0.4
	welt.add_child(pferd)
	pferd.set_aussehen(_finde_farbe("wolkentraber", ["braun", "fuchs", "palomino"]))
	pferd.spiele_aktion("kopfschuetteln")
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.0, 1.6, 4.2)
	kamera.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	welt.add_child(kamera)
	kamera.current = true
	await _settle(10)
	var feier := RanchLevelUpFeier.zeige_in(root, "Luna", 10, ["maehnenfrisur"])
	# Voll eingeblendet fotografieren: xvfb-Frames sind langsam, deshalb
	# die Feier nach dem Einblenden einfrieren statt Frames zu zaehlen.
	for _i in 60:
		await process_frame
		if float(feier.get("_alter_s")) >= 0.5:
			break
	feier.set_process(false)
	await _snap("levelup_feier.png")
	feier.queue_free()
	welt.queue_free()
	await process_frame


## --------------------------------------------------------- Technik


## Pastell-Weide: Licht, Himmel, Wiese — gemeinsame Bühne aller 3D-Shots.
func _welt() -> Node3D:
	var welt := Node3D.new()
	root.add_child(welt)
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
	var gras_mesh := PlaneMesh.new()
	gras_mesh.size = Vector2(600.0, 600.0)
	gras.mesh = gras_mesh
	gras.material_override = RanchPferd.material(Color(0.56, 0.78, 0.45))
	welt.add_child(gras)
	return welt


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


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
