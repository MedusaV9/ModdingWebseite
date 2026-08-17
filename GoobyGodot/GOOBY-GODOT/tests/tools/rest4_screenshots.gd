extends SceneTree
## REST-4-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte für
## Funkelpark, Radio, Codes, Galerie und Postkarten und misst je Ansicht die
## Draw-Calls. Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/rest4_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/REST4"
const SETTLE := 40

const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _park: Funkelpark


## GameState-Double (wie tests/unit/test_rest4_park.gd — Screenshots laufen
## ohne die Spiel-Autoloads).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(int(Time.get_unix_time_from_system() * 1000.0))
		s["economy"]["coins"] = 500

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass

	func xp_ratio() -> float:
		return 0.3


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	await _park_shots()
	await _radio_shot()
	await _codes_shot()
	await _galerie_shot()
	await _postkarten_shots()
	print("REST4-Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


func _park_shots() -> void:
	var gs := FakeGameState.new()
	_park = (load("res://scenes/park/funkelpark.tscn") as PackedScene).instantiate()
	_park.game_state_override = gs
	_park.stunde_override = 12.0
	root.add_child(_park)
	await _settle(SETTLE)
	# Eingangs-Totale: schräg von oben über das Tor auf die Plaza, damit
	# Schild, Ticketschalter UND Fahrgeschäfte gemeinsam im Bild sind.
	var eingang_cam := root.get_camera_3d()
	if eingang_cam != null:
		eingang_cam.global_position = Vector3(13.0, 12.0, 31.0)
		eingang_cam.look_at(Vector3(-3.0, 2.5, -2.0))
	await _settle(8)
	await _shot("park_eingang_plaza.png")
	# Achterbahn: Fahrt kaufen, bis kurz vor den Looping simulieren, Foto aus
	# der POV-Verfolgerkamera (Gooby sichtbar im vorderen Wagen).
	_park.fahre("coaster")
	_park.coaster.set_hands_up(true)
	_simuliere_coaster_bis("drop")
	await _settle(8)
	await _shot("park_achterbahn_drop_pov.png")
	_simuliere_coaster_bis("loop")
	_park.coaster.simuliere(0.55)
	await _settle(8)
	await _shot("park_achterbahn_looping_pov.png")
	while _park.coaster.faehrt:
		_park.coaster.simuliere(1.0 / 30.0)
	await _settle(5)
	# Riesenrad: Fahrt bis zum Scheitel, Außenansicht mit Gooby in Gondel 0.
	_park.fahre("wheel")
	_park.wheel.speed_scale = 40.0
	for _i in 90:
		_park.wheel.simuliere(1.0 / 30.0)
		if not _park.wheel.faehrt:
			break
		if _park.wheel._gefahren >= TAU * 0.5:
			break
	_park.wheel.speed_scale = 0.0
	# Das Rad steht bei x=-16 und ist 90 Grad um Y gedreht — seine Fläche
	# zeigt nach +X. Also von rechts (Plaza-Seite) draufschauen, leicht
	# nach oben zu Gondel 0 (nach der halben Runde ganz oben).
	# Gondel 0 steht nach der halben Runde vorn bei (-16, 7.6, +6.5); nah
	# genug ran, dass Gooby beim Winken sichtbar ist, Rad bleibt im Bild.
	var cam := root.get_camera_3d()
	if cam != null:
		cam.global_position = Vector3(-12.2, 8.9, 9.4)
		cam.look_at(Vector3(-16.2, 7.9, 5.6))
	await _settle(8)
	await _shot("park_riesenrad_gooby_gondel.png")
	_park.wheel.speed_scale = 40.0
	while _park.wheel.faehrt:
		_park.wheel.simuliere(1.0 / 30.0)
	# Nacht: Lichterketten an, Abendstimmung an der Naschgasse.
	if cam != null:
		cam.global_position = Vector3(0.0, 9.5, 24.0)
		cam.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	_park.stunde_override = 21.0
	_park._wende_nacht_an()
	await _settle(SETTLE)
	await _shot("park_nacht_lichter.png")
	_park.queue_free()
	await process_frame


## MusicDirector-Double fürs Radio-Bild (echte Wiedergabe braucht es nicht).
class FakeMusic:
	extends Node
	signal track_changed(track_id: String)
	var playing := true
	var track := "radio-gooby-fm-1"

	func radio_play(id: String) -> void:
		playing = true
		var ids := MusicRegistry.station_track_ids(id)
		track = str(ids[0]) if not ids.is_empty() else ""
		track_changed.emit(track)

	func radio_stop() -> void:
		playing = false

	func radio_next() -> void:
		track_changed.emit(track)

	func is_radio_playing() -> bool:
		return playing

	func current_track_id() -> String:
		return track


func _radio_shot() -> void:
	var hintergrund := ColorRect.new()
	hintergrund.color = AcTokens.BG_CREAM
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(hintergrund)
	var gs := FakeGameState.new()
	gs.set_value("radio.playing", true)
	gs.set_value("radio.station", "gooby-fm")
	gs.set_value("radio.likes", {"radio-gooby-fm-1": true})
	gs.set_value("progression.level", 5)
	var music := FakeMusic.new()
	root.add_child(music)
	music.radio_play("gooby-fm")
	var panel := PanelContainer.new()
	panel.theme = ThemeService.theme()
	panel.theme_type_variation = "AcCard"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Wie RadioGeraet: Höhen-Deckel + Scroll, damit nichts überläuft.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560.0, 620.0)
	panel.add_child(scroll)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sheet)
	root.add_child(panel)
	await _settle(SETTLE)
	await _shot("radio_oberflaeche.png")
	panel.queue_free()
	music.queue_free()
	hintergrund.queue_free()
	await process_frame


func _codes_shot() -> void:
	var gs := FakeGameState.new()
	var screen: CodesScreen = (
		(load("res://scripts/ui/codes/codes_screen.tscn") as PackedScene).instantiate()
	)
	screen.theme = ThemeService.theme()
	screen.gs_override = gs
	screen.auto_navigate = false
	root.add_child(screen)
	await _settle(10)
	# Live-Einlösung: Erfolgs-Feier (Feedback + Verlauf + Konfetti) im Bild.
	screen.set_input_text("ich lie3b dich")
	screen.redeem_now()
	screen.set_input_text("")
	await _settle(12)
	await _shot("codes_screen_einloesung.png")
	screen.queue_free()
	await process_frame


func _galerie_shot() -> void:
	# Demo-Fotos aus den frischen Park-Artefakten in den Foto-Index legen.
	var quellen: Array[String] = [
		"park_eingang_plaza.png", "park_achterbahn_looping_pov.png", "park_nacht_lichter.png"
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rest4_demo_fotos"))
	var fotos: Array = []
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	for i in quellen.size():
		var bild := Image.new()
		if bild.load("%s/%s" % [OUT_DIR, quellen[i]]) != OK:
			continue
		var ziel := "user://rest4_demo_fotos/demo_%d.png" % i
		bild.save_png(ziel)
		fotos.append({"pfad": ziel, "at": now - i * 3600000, "ort": "funkelpark", "fav": i == 1})
	var gs := FakeGameState.new()
	gs.s["city"]["fotos"] = fotos
	var screen: GalerieScreen = (
		(load("res://scripts/ui/galerie/galerie_screen.tscn") as PackedScene).instantiate()
	)
	screen.theme = ThemeService.theme()
	screen.gs_override = gs
	screen.auto_navigate = false
	root.add_child(screen)
	await _settle(SETTLE)
	await _shot("galerie_raster.png")
	if not fotos.is_empty():
		screen.oeffne_vollansicht(str((fotos[1] as Dictionary)["pfad"]))
		screen._zoom_rein()
		await _settle(10)
		await _shot("galerie_vollansicht_zoom.png")
	screen.queue_free()
	await process_frame


func _postkarten_shots() -> void:
	var gs := FakeGameState.new()
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var archiv: Array = []
	var ziele: Array[String] = ["beach", "space", "harbor", "bakery", "nightSky"]
	for i in ziele.size():
		(
			archiv
			. append(
				{
					"destId": ziele[i],
					"dayIndex": i + 1,
					"variant": PostkartenLogic.variant_of(ziele[i], now, i + 1),
					"atMs": now - (ziele.size() - i) * 86400000,
				}
			)
		)
	var v: Dictionary = gs.s["vacation"]
	v["archive"] = archiv
	v["visited"] = {"beach": true, "space": true, "harbor": true}
	var screen: PostkartenScreen = (
		(load("res://scripts/ui/postkarten/postkarten_screen.tscn") as PackedScene).instantiate()
	)
	screen.theme = ThemeService.theme()
	screen.gs_override = gs
	screen.auto_navigate = false
	root.add_child(screen)
	await _settle(SETTLE)
	await _shot("postkarten_archiv_screen.png")
	screen.queue_free()
	await process_frame
	# 3D-Ansicht: Postkartenwand + Souvenirregal wie im Wohnzimmer an der Wand.
	var welt := Node3D.new()
	root.add_child(welt)
	var wand_flaeche := MeshInstance3D.new()
	var wand_mesh := BoxMesh.new()
	wand_mesh.size = Vector3(4.0, 2.6, 0.1)
	wand_flaeche.mesh = wand_mesh
	var wand_mat := StandardMaterial3D.new()
	wand_mat.albedo_color = AcTokens.PAPER
	wand_flaeche.material_override = wand_mat
	wand_flaeche.position = Vector3(0.0, 1.3, -0.06)
	welt.add_child(wand_flaeche)
	var wand := PostkartenProps.postkartenwand_mit(archiv)
	wand.position = Vector3(-1.0, 1.45, 0.02)
	welt.add_child(wand)
	var regal := PostkartenProps.souvenirregal_mit(["beach", "space", "harbor"])
	regal.position = Vector3(1.1, 1.15, 0.02)
	welt.add_child(regal)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	welt.add_child(licht)
	var kamera := Camera3D.new()
	# Näher ran (enger FOV), damit die Souvenir-Minis gut erkennbar sind.
	kamera.position = Vector3(0.25, 1.4, 2.05)
	kamera.fov = 52.0
	kamera.look_at_from_position(kamera.position, Vector3(0.05, 1.32, 0.0))
	welt.add_child(kamera)
	kamera.make_current()
	await _settle(20)
	await _shot("postkarten_wand_und_souvenirregal_3d.png")
	welt.queue_free()
	await process_frame


func _simuliere_coaster_bis(zone: String) -> void:
	var schritte := 0
	while _park.coaster.faehrt and _park.coaster.zone_jetzt() != zone and schritte < 8000:
		_park.coaster.simuliere(1.0 / 30.0)
		schritte += 1


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, int(calls)])
