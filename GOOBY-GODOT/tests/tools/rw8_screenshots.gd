extends SceneTree
## RW-8-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte der
## Ladebildschirme (verschiedene Artworks + Tipps + echter Balkenstand),
## die Zonen-Titel-Einblendung und den Turniersieg-Moment mit Konfetti —
## plus eine Bildfolge eines kompletten Veil-Übergangs (Abdecken → Laden →
## Tipp-Rotation → Aufdecken) für das ffmpeg-Video. Aufruf (echter Renderer,
## --fixed-fps macht die Bildfolge deterministisch 30 fps):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy --fixed-fps 30 \
##     --script res://tests/tools/rw8_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW8"
const FRAMES_DIR := OUT_DIR + "/frames"
## Echte RW-1-Spielszenen als Vorher/Nachher-Kulisse des Übergangs-Videos.
const KULISSE_VORHER := "/tmp/gooby-godot/artifacts/RW1/hof_ausreiten_knopf.png"
const KULISSE_NACHHER := "/tmp/gooby-godot/artifacts/RW1/zone_see_steg.png"

var _veil: LoadingVeil
var _kulisse: TextureRect
var _frame_index := 0
var _recording := false


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(FRAMES_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	# llvmpipe + Volllast: die Auto-Qualitaetsbremse (RW-7) wuerde sonst
	# mitten ins Artefakt hinein einen "Qualitaet angepasst"-Toast legen.
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	_baue_kulisse()
	_veil = (load("res://scripts/core/loading_veil.tscn") as PackedScene).instantiate()
	root.add_child(_veil)
	await _settle(5)
	# --- Ladebildschirme (Regel: Artwork folgt Ziel + Tageszeit) ---
	await _lade_shot(&"ranch/hof", 11.0, 0.42, "ladebildschirm_stall_tag.png")
	await _lade_shot(&"ranch/welt", 11.0, 0.67, "ladebildschirm_galopp_reiten.png")
	await _lade_shot(&"ranch/welt", 22.0, 0.35, "ladebildschirm_nacht_teich.png")
	await _lade_shot(&"ranch/turnierplatz", 11.0, 0.81, "ladebildschirm_turnier.png")
	# --- Momente (Zonen-Titel + Turniersieg mit Konfetti) ---
	await _momente_shots()
	# --- Bildfolge des kompletten Übergangs (fixed 30 fps) ---
	await _video_frames()
	print("RW8-Artefakte fertig -> %s" % OUT_DIR)
	quit(0)


## Ein Ladebildschirm-Still: Reise vorbereiten, sofort abdecken (reduced,
## deterministisch), echten Balkenstand setzen, schiessen, wieder aufdecken.
func _lade_shot(ziel: StringName, stunde: float, progress: float, datei: String) -> void:
	_veil.stunde_override = stunde
	_veil.prepare_for_travel(ziel)
	await _veil.cover(true)
	_veil.set_progress(progress)
	await _settle(6)
	await _shot(datei)
	await _veil.reveal(true)
	await _settle(2)


func _momente_shots() -> void:
	var momente := RanchMoments.new()
	momente.name = "RW8Momente"
	root.add_child(momente)
	await _settle(3)
	momente.zone_entdeckt("see")
	await _settle(14)
	await _shot("zonen_titel_glitzersee.png")
	await _settle(80)
	momente.turniersieg()
	await _settle(26)
	await _shot("turniersieg_konfetti.png")
	await _settle(90)
	momente.queue_free()
	await _settle(2)


## Kompletter Übergang als Bildfolge: Kulisse → cover() → echter Balken
## füllt sich → Tipp rotiert (3,2 s) → Kulisse wechselt → reveal().
func _video_frames() -> void:
	_veil.stunde_override = 11.0
	_veil.prepare_for_travel(&"ranch/welt")
	_starte_aufnahme()
	await _settle(12)
	await _veil.cover(false)
	for i in 106:
		_veil.set_progress(float(i) / 105.0)
		await process_frame
	await _settle(8)
	_setze_kulisse(KULISSE_NACHHER)
	await _veil.reveal(false)
	await _settle(14)
	_recording = false
	await _settle(2)
	print("frames=%d -> %s" % [_frame_index, FRAMES_DIR])


func _starte_aufnahme() -> void:
	_recording = true
	_aufnahme_loop()


func _aufnahme_loop() -> void:
	while _recording:
		await process_frame
		var bild := root.get_texture().get_image()
		bild.save_png("%s/frame_%04d.png" % [FRAMES_DIR, _frame_index])
		_frame_index += 1


## Kulisse hinter dem Veil (echter RW-1-Screenshot, sonst Farbfläche).
func _baue_kulisse() -> void:
	var boden := ColorRect.new()
	boden.name = "KulisseBoden"
	boden.color = Color(0.32, 0.45, 0.28)
	boden.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(boden)
	_kulisse = TextureRect.new()
	_kulisse.name = "Kulisse"
	_kulisse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kulisse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kulisse.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(_kulisse)
	_setze_kulisse(KULISSE_VORHER)


func _setze_kulisse(pfad: String) -> void:
	if not FileAccess.file_exists(pfad):
		return
	var img := Image.load_from_file(pfad)
	if img != null:
		_kulisse.texture = ImageTexture.create_from_image(img)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s" % datei)
