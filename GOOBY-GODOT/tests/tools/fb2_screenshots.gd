extends SceneTree
## FB2-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte der Szenerie-Runde („Welten sind zu kahl/zu flach"):
## Vorher/Nachher-Paare für Ranch-Übersicht, Ranch-Straßenniveau,
## Stadt-Übersicht, Stadt-Straßenniveau — im Nachher-Modus zusätzlich alle
## sieben Himmel-Stimmungen, Berge/Fernsicht, drei Entdeckungsorte und die
## Gelände-Nahaufnahme. Druckt je Shot die Draw-Calls (Budget ≤ 400).
## Braucht einen echten Renderer (xvfb):
##   FB2_MODE=vorher|nachher xvfb-run -a godot --path . \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --audio-driver Dummy --script res://tests/tools/fb2_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FB2"
## Knapp gehalten: der xvfb-Software-Renderer schafft nur wenige FPS —
## Wetter-Overrides greifen sofort (blend=1), 16 Frames reichen zum Setzen.
const SETTLE := 16

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _prefix := "nachher"
var _region: Node3D
var _cam: Camera3D
var _seq := 0


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var modus := OS.get_environment("FB2_MODE")
	_prefix = "vorher" if modus == "vorher" else "nachher"
	await process_frame
	await _ranch_shots()
	await _stadt_shots()
	print("FB2-Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## ------------------------------------------------------------------ Ranch


func _ranch_shots() -> void:
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	_region = szene.instantiate()
	_region.stunde_override = 11.0
	_region.wetter_override = "sonne"
	root.add_child(_region)
	await _settle(30)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_region.add_child(_cam)
	# Übersicht: hoch über dem Hof, Blick über die ganze Region nach Norden.
	_blick(Vector3(0.0, 240.0, 560.0), Vector3(0.0, 0.0, -220.0))
	await _shot("%s_ranch_uebersicht.png" % _prefix)
	# Straßenniveau: Reiter-Perspektive auf dem Weg Hof→Weidetal.
	_region.reiter.springe_zu(RanchKarte.punkt(-150.0, 60.0), deg_to_rad(75.0))
	_region.reiter.cam.current = true
	await _settle(SETTLE)
	await _shot("%s_ranch_strassenniveau.png" % _prefix)
	if _prefix == "nachher":
		await _himmel_shots()
		await _fernsicht_shots()
		await _entdeckung_shots()
		await _gelaende_shot()
	_region.queue_free()
	await process_frame
	await process_frame


## Alle sieben Himmel-Stimmungen am See (weite Sicht auf den Horizont).
func _himmel_shots() -> void:
	_region.reiter.springe_zu(RanchKarte.punkt(392.0, 190.0), deg_to_rad(-35.0))
	_region.reiter.cam.current = true
	var faelle := [
		{"stunde": 7.0, "wetter": "sonne", "datei": "himmel_1_klarer_morgen.png"},
		{"stunde": 12.5, "wetter": "sonne", "datei": "himmel_2_mittag.png"},
		{"stunde": 17.5, "wetter": "sonne", "datei": "himmel_3_goldene_stunde.png"},
		{"stunde": 19.6, "wetter": "sonne", "datei": "himmel_4_abendrot.png"},
		{"stunde": 23.0, "wetter": "sonne", "datei": "himmel_5_nacht_sterne_mond.png"},
		{"stunde": 12.0, "wetter": "wolken", "datei": "himmel_6_bedeckt.png"},
		{"stunde": 15.0, "wetter": "gewitter", "datei": "himmel_7_gewitter.png"},
	]
	for fall: Dictionary in faelle:
		_region.wetter.wetter_override = str(fall["wetter"])
		_region.stunde_override = float(fall["stunde"])
		await _settle(SETTLE)
		await _shot(str(fall["datei"]))
	_region.wetter.wetter_override = "sonne"
	_region.stunde_override = 11.0


## Bergkette + Fernsicht: vom Hügelkamm-Aussichtspunkt über das Land.
func _fernsicht_shots() -> void:
	_region.stunde_override = 10.0
	_region.reiter.springe_zu(RanchKarte.punkt(160.0, -470.0), deg_to_rad(180.0))
	_region.reiter.cam.current = true
	await _settle(SETTLE)
	await _shot("fernsicht_berge_vom_aussichtspunkt.png")
	_region.reiter.springe_zu(RanchKarte.punkt(-380.0, 90.0), deg_to_rad(-90.0))
	await _settle(SETTLE)
	await _shot("fernsicht_berge_vom_weidetal.png")


## Drei Entdeckungsorte nah (Wasserfall, Steinkreis, alter Baum).
func _entdeckung_shots() -> void:
	_region.stunde_override = 11.0
	var orte: Array = [
		{"id": "wasserfall", "datei": "entdeckung_wasserfall.png"},
		{"id": "steinkreis", "datei": "entdeckung_steinkreis.png"},
		{"id": "alter_baum", "datei": "entdeckung_alter_baum.png"},
	]
	for ort: Dictionary in orte:
		var daten := RanchEntdeckungen.fundort(str(ort["id"]))
		if daten.is_empty():
			continue
		var pos: Array = daten["pos"]
		var p := Vector2(float(pos[0]), float(pos[1]))
		var blick := Vector2(float(daten["blick"][0]), float(daten["blick"][1]))
		# Reiter steht auf der ANREISE-Seite (blick) und schaut zum Fundort —
		# so zeigt der Shot die Schauseite (Wasserfall-Front, Höhleneingang).
		var richtung := (blick - p).normalized() * 20.0
		_region.reiter.springe_zu(
			RanchKarte.punkt(p.x + richtung.x, p.y + richtung.y),
			atan2(-(p.x - (p.x + richtung.x)), -(p.y - (p.y + richtung.y)))
		)
		_region.reiter.cam.current = true
		await _settle(SETTLE)
		await _shot(str(ort["datei"]))


## Gelände-Nahaufnahme: Kamera tief überm Boden — Unebenheit + Textur-Flecken.
func _gelaende_shot() -> void:
	_region.stunde_override = 16.5
	_blick(
		Vector3(-90.0, RanchGelaende.hoehe(-90.0, 40.0) + 2.2, 40.0),
		Vector3(-140.0, RanchGelaende.hoehe(-140.0, 10.0), 10.0)
	)
	await _shot("gelaende_nahaufnahme_textur_unebenheit.png")


## ------------------------------------------------------------------ Stadt


func _stadt_shots() -> void:
	var dir := "user://fb2_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	_seq += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var city: Node3D = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	city.stunde_override = 11.0
	root.add_child(city)
	await _settle(24)
	city.auto.set_frozen(true)
	city.hud.visible = false
	var cam := Camera3D.new()
	city.add_child(cam)
	cam.position = Vector3(0.0, 165.0, 135.0)
	cam.look_at(Vector3(0.0, 0.0, -10.0))
	cam.current = true
	await _shot("%s_stadt_uebersicht.png" % _prefix)
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(4, 6))
	cam.position = strasse + Vector3(0.0, 3.2, 26.0)
	cam.look_at(strasse + Vector3(0.0, 1.6, -30.0))
	await _shot("%s_stadt_strassenniveau.png" % _prefix)
	PanelStack.clear()
	city.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


## --------------------------------------------------------------- Werkzeug


func _blick(von: Vector3, nach: Vector3) -> void:
	_cam.position = von
	_cam.look_at(nach)
	_cam.current = true


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	for _i in SETTLE:
		await process_frame
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, calls])
