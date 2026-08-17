extends SceneTree
## WELT-1-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte des
## Openworld-Ausbaus — Panoramen, jede neue Zone, Bergmassiv/Serpentinen/
## Hängebrücke, Morgennebel — und misst je Ansicht die Draw-Calls.
## Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/welt1_screenshots.gd -- [vorher|nachher]

const OUT_DIR := "/tmp/gooby-godot/artifacts/WELT1"
const SETTLE := 55

var _region: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	var modus := "nachher"
	for arg in OS.get_cmdline_user_args():
		if arg == "vorher":
			modus = "vorher"
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	_region = szene.instantiate()
	_region.stunde_override = 11.0
	_region.wetter_override = "sonne"
	root.add_child(_region)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 6000.0
	root.add_child(_cam)
	await _settle(30)
	if modus == "vorher":
		await _vorher()
	else:
		await _nachher()
	print("Screenshots fertig -> %s" % OUT_DIR)
	_region.queue_free()
	await process_frame
	quit(0)


## Vorher-Set: Panorama + Blick vom Hügelkamm nach Norden (wo der Berg hin
## soll) — VOR dem Ausbau aufgenommen.
func _vorher() -> void:
	await _frei_shot(Vector3(0, 330, 900), Vector3(0, 0, -100), "vorher_panorama_region.png")
	await _frei_shot(Vector3(160, 40, -430), Vector3(120, 10, -900), "vorher_blick_nach_norden.png")


func _nachher() -> void:
	# --- Panoramen (gleiche Kameras wie vorher) ---
	await _frei_shot(Vector3(0, 330, 900), Vector3(0, 0, -100), "nachher_panorama_region.png")
	await _frei_shot(
		Vector3(160, 40, -430), Vector3(120, 10, -900), "nachher_blick_nach_norden.png"
	)
	# --- Bergmassiv ---
	await _reiter_shot(Vector2(120, -640), Vector2(60, -1010), "berg_von_unten.png")
	await _reiter_shot(Vector2(60, -1010), Vector2(0, 160), "berg_plateau_rundumblick.png")
	await _reiter_shot(Vector2(10, -762), Vector2(150, -822), "berg_serpentinenpfad.png")
	await _reiter_shot(Vector2(60, -796), Vector2(60, -846), "berg_haengebruecke.png")
	await _reiter_shot(Vector2(160, -1035), Vector2(112, -1004), "berg_bergsee.png")
	# --- Neue Zonen ---
	await _reiter_shot(Vector2(-720, 100), Vector2(-810, 90), "zone_blumenwiese_lavendel.png")
	await _reiter_shot(Vector2(60, 700), Vector2(60, 800), "zone_obstgarten.png")
	await _reiter_shot(Vector2(-380, 700), Vector2(-450, 790), "zone_kornfeld.png")
	await _reiter_shot(Vector2(760, -40), Vector2(800, -130), "zone_moor_stege.png")
	await _reiter_shot(Vector2(726, -458), Vector2(700, -500), "zone_ruine_turm.png")
	await _reiter_shot(Vector2(792, 252), Vector2(890, 262), "zone_strand.png")
	# --- Wegenetz ---
	await _reiter_shot(Vector2(11, 166), Vector2(4, 157), "wegweiser_kreuzung_hof.png")
	# --- Morgennebel in der Senke ---
	_region.stunde_override = 6.6
	await _reiter_shot(Vector2(-368, 78), Vector2(-470, 92), "morgennebel_weidetal.png", 90)
	# --- Reiter im neuen Gelände ---
	_region.stunde_override = 16.5
	_region.reiter.pferd.set_gangart(RanchPferd.GANG_TRAB)
	await _reiter_shot(Vector2(96, -742), Vector2(10, -762), "reiter_im_neuen_gelaende.png")


## Freie Kamera (Panoramen).
func _frei_shot(pos: Vector3, ziel: Vector3, datei: String) -> void:
	_cam.current = true
	_cam.position = pos
	_cam.look_at(ziel)
	await _settle(SETTLE)
	await _shot(datei)


## Reiter-Perspektive: Reiter nach `von` teleportieren, Blick auf `nach`.
func _reiter_shot(von: Vector2, nach: Vector2, datei: String, extra := 0) -> void:
	_cam.current = false
	_region.reiter.cam.current = true
	var blick := atan2(-(nach.x - von.x), -(nach.y - von.y))
	_region.reiter.springe_zu(RanchKarte.punkt(von.x, von.y), blick)
	await _settle(SETTLE + extra)
	await _shot(datei)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, int(calls)])
