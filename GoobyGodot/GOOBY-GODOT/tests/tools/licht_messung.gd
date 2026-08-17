extends SceneTree
## LICHT-Kalibrierungs-Messwerkzeug (KEIN Test — kein test_-Präfix).
## Rendert die Referenz-Motive der Belichtungskette (Haus innen, Garten zu
## drei Tageszeiten, Stadt, Ranch) mit FESTEN Kameras und misst pro Motiv
## Durchschnitts-Luma (BT.709 auf sRGB), 16-Bin-Histogramm und die
## Clipping-Anteile (Pixel ≥ 0.98 bzw. ≤ 0.02). Zielwerte laut
## docs/godot-rewrite/EVAL-2026-08/lichtkalibrierung.md: mittlere Luma
## 0.45–0.55, Clipping-Spitzen < 2 % der Pixel.
##
## Aufruf (echter Renderer, IMMER über flock + run_godot_isolated.sh):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/licht_messung.gd -- [vorher|nachher]
##
## Ausgabe: PNGs + eine messwerte.json unter
## /tmp/gooby-godot/artifacts/LICHT/<phase>/.

const OUT_BASIS := "/tmp/gooby-godot/artifacts/LICHT"
const SETTLE := 45
## Jeder n-te Pixel wird gemessen (1280×720 / 4 ≈ 230k Samples).
const MESS_SCHRITT := 2
## Gepinnte Wetterlage der Garten-Motive (Form wie SoulWetter.zustand).
const WETTER_SONNE := {"typ": "sonne", "regen": false, "schnee": false}

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _phase := "nachher"
var _out_dir := ""
var _gs: Node
var _werte: Array = []


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "vorher" or arg == "nachher":
			_phase = arg
	_out_dir = "%s/%s" % [OUT_BASIS, _phase]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	# Frame-Bremse aus: der Headless-Renderer läuft immer „im Keller“, der
	# Qualitäts-Toast legte sonst eine weiße Fläche über die Messung.
	var quality := root.get_node_or_null("/root/Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	await process_frame
	_gs_aufbauen()
	await _haus_motive()
	await _garten_motive()
	_gs_abbauen()
	await _stadt_motiv()
	await _ranch_motiv()
	_json_schreiben()
	print("Messung fertig -> %s" % _out_dir)
	quit(0)


func _gs_aufbauen() -> void:
	var dir := "user://licht_messung/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(_gs)
	HomeState.set_flag(_gs, HomeState.FLAG_BED_PLACED, true)


func _gs_abbauen() -> void:
	_gs.free()
	_gs = null
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Wohnzimmer + Bad, jeweils 13 Uhr in der ECHTEN Rig-Perspektive: Gooby
## wird deterministisch geparkt (_raum_oeffnen), das Rig konvergiert auf
## seine feste Pose und wird dann eingefroren — die Messung sieht exakt
## das Spieler-Bild, ohne Wander-Rauschen.
func _haus_motive() -> void:
	for room_id: String in ["living", "bathroom"]:
		var room := await _raum_oeffnen(room_id, 13.0)
		var rig: HomeCameraRig = room.camera_rig()
		await _settle(30)
		rig.set_process(false)
		await _motiv_messen("haus_%s_tag" % room_id, room)
		await _raum_schliessen(room)


## Weltgröße eines Raums (Meter) aus seiner Grid-Definition.
func _raum_groesse(room: RoomBase) -> Vector2:
	var zellen: Vector2i = room.room_def()["grid"]
	return Vector2(zellen.x * GridData.CELL_SIZE, zellen.y * GridData.CELL_SIZE)


## Garten mit dem Haus am Nordrand aus der Eval-03-Perspektive (Kamera wie
## haussicht_screens Winkel 1) — Tag, goldene Stunde und Abend (Fensterlicht).
## Wetter ist auf SONNE gepinnt: der echte SoulWetter-Tagesplan ist pro
## Datum zufällig — Regenschleier würde die Luma-Reihe unvergleichbar machen.
func _garten_motive() -> void:
	for eintrag: Array in [["tag", 13.0], ["abend", 19.2], ["nacht", 21.5]]:
		var room := await _raum_oeffnen("garden", float(eintrag[1]), WETTER_SONNE)
		var rig: HomeCameraRig = room.camera_rig()
		rig.set_process(false)
		rig.camera.global_position = Vector3(11.5, 5.4, 11.0)
		rig.camera.look_at(Vector3(7.0, 1.4, -1.5))
		await _settle(20)
		await _motiv_messen("garten_%s" % str(eintrag[0]), room)
		await _raum_schliessen(room)


## Stadt auf Straßenniveau (fb2_screenshots-Kamera) — Dokumentation der
## Kette außerhalb der Home-Welt (Stadt-Agent besitzt die lokalen Lichter).
func _stadt_motiv() -> void:
	var dir := "user://licht_messung/stadt_%d" % Time.get_ticks_usec()
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
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(4, 6))
	cam.position = strasse + Vector3(0.0, 3.2, 26.0)
	cam.look_at(strasse + Vector3(0.0, 1.6, -30.0))
	cam.current = true
	await _settle(SETTLE)
	await _messen_und_speichern("stadt_tag")
	PanelStack.clear()
	city.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


## Ranch-Panorama (welt1_screenshots-Kamera) — Dokumentation wie Stadt.
func _ranch_motiv() -> void:
	var region: Node3D = load("res://scenes/ranch/welt/ranch_region.tscn").instantiate()
	region.stunde_override = 11.0
	region.wetter_override = "sonne"
	root.add_child(region)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 6000.0
	root.add_child(cam)
	cam.position = Vector3(0, 330, 900)
	cam.look_at(Vector3(0, 0, -100))
	cam.current = true
	await _settle(SETTLE)
	await _messen_und_speichern("ranch_panorama")
	region.queue_free()
	cam.queue_free()
	await process_frame


func _raum_oeffnen(room_id: String, stunde: float, wetter: Dictionary = {}) -> RoomBase:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = _gs
	room.stunde_override = stunde
	room.wetter_override = wetter
	root.add_child(room)
	await _settle(SETTLE)
	# Der Garten-WetterFx (GardenHost) liest den Tagesplan selbst — für die
	# Messung folgt er derselben gepinnten Wetterlage wie der Himmel.
	if not wetter.is_empty():
		var fx := room.get_node_or_null("WetterFx")
		if fx is WetterFx:
			(fx as WetterFx).wende_zustand_an(wetter)
	# Gooby deterministisch parken (wandert sonst zufällig durchs Bild).
	var gooby := room.gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		var groesse := _raum_groesse(room)
		gooby.global_position = Vector3(groesse.x * 0.42, 0.0, groesse.y * 0.55)
	return room


func _raum_schliessen(room: Node) -> void:
	root.remove_child(room)
	room.queue_free()
	await _settle(4)


## Misst ein Raum-Motiv OHNE UI-Ebene (Panels würden die Szenen-Luma
## verfälschen); das PNG zeigt denselben Frame.
func _motiv_messen(motiv: String, room: RoomBase) -> void:
	room.ui_layer().visible = false
	await _settle(3)
	await _messen_und_speichern(motiv)
	room.ui_layer().visible = true


func _messen_und_speichern(motiv: String) -> void:
	# Autoload-UI (Toasts/Notify-Banner) würde die Szenen-Luma verfälschen —
	# ALLE CanvasLayer schlafen während der Messläufe.
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await process_frame
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s.png" % [_out_dir, motiv])
	var mess := luma_statistik(bild, MESS_SCHRITT)
	mess["motiv"] = motiv
	mess["phase"] = _phase
	_werte.append(mess)
	print(
		(
			"LUMA %s: mittel=%.3f clip_hoch=%.2f%% clip_tief=%.2f%%"
			% [motiv, mess["mittel"], mess["clip_hoch_prozent"], mess["clip_tief_prozent"]]
		)
	)


## PURE Luma-Statistik über ein Bild: BT.709-Luma auf sRGB-Werten,
## 16-Bin-Histogramm (Anteile), Clipping-Anteile in Prozent.
static func luma_statistik(bild: Image, schritt := 2) -> Dictionary:
	var summe := 0.0
	var anzahl := 0
	var clip_hoch := 0
	var clip_tief := 0
	var histogramm: Array[int] = []
	histogramm.resize(16)
	histogramm.fill(0)
	for y in range(0, bild.get_height(), schritt):
		for x in range(0, bild.get_width(), schritt):
			var farbe := bild.get_pixel(x, y)
			var luma := 0.2126 * farbe.r + 0.7152 * farbe.g + 0.0722 * farbe.b
			summe += luma
			anzahl += 1
			histogramm[clampi(int(luma * 16.0), 0, 15)] += 1
			if luma >= 0.98:
				clip_hoch += 1
			elif luma <= 0.02:
				clip_tief += 1
	var n := maxf(1.0, float(anzahl))
	var anteile: Array = []
	for bin: int in histogramm:
		anteile.append(snappedf(float(bin) / n, 0.0001))
	return {
		"mittel": snappedf(summe / n, 0.001),
		"clip_hoch_prozent": snappedf(100.0 * float(clip_hoch) / n, 0.01),
		"clip_tief_prozent": snappedf(100.0 * float(clip_tief) / n, 0.01),
		"histogramm_16": anteile,
	}


func _json_schreiben() -> void:
	var datei := FileAccess.open("%s/messwerte.json" % _out_dir, FileAccess.WRITE)
	datei.store_string(JSON.stringify(_werte, "  "))
	datei.close()


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
