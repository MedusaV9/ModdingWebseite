extends SceneTree
## SEELE-2-Artefakt (KEIN Test): Bildfolge eines Absichts-Verhaltens im
## echten Wohnzimmer — Gooby hat Hunger, im Raum steht kein Kühlschrank,
## also geht er zur KÜCHENTÜR und schaut dich an; am Ende kommt (über die
## Bubble-Bremse) seine Zeile. Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/seele2_absicht_screens.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/SEELE2/absicht"

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const MS_D := 86_400_000
const START_MS := 1_785_139_200_000

var _gs: Node = null
var _room: Node = null
var _runner: GoobyReactions = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	SoulState.register_slice()
	var dir := "user://seele2_absicht/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	_gs.update(
		func(s: Dictionary) -> void:
			s["meta"]["playerName"] = "Mira"
			# Hunger unter der Absichts-Schwelle, Rest gesund — die EINE
			# klare Absicht ist „will zum Kühlschrank/in die Küche“.
			s["gooby"]["stats"] = {"hunger": 12.0, "energy": 80.0, "hygiene": 85.0, "fun": 80.0}
	)
	_build_room()
	await _settle(70)
	_attach_runner()
	await _settle(10)

	var absicht := _erwartete_absicht()
	print("gewählte Absicht: %s" % str(absicht))
	await _shot("absicht_1_hunger_start.png")
	# Absicht ausführen (läuft asynchron: hinlaufen → Blick zur Kamera →
	# Zeile) und die Bildfolge POSITIONS-basiert festhalten — Frame-Zählen
	# ist unter Last unzuverlässig (delta = Wanduhr, der Weg wäre schon um).
	_runner._last_bubble_s = -1000.0
	var gooby: Node3D = _room.gooby()
	var start: Vector3 = gooby.global_position
	_runner._seele.try_intent()
	await _wait_weg(gooby, start, 0.3)
	await _shot("absicht_2_unterwegs_zur_kuechentuer.png")
	await _wait_weg(gooby, start, 0.75)
	await _shot("absicht_3_fast_da.png")
	await _settle(60)
	await _shot("absicht_4_angekommen_blick_und_zeile.png")
	await _settle(60)
	await _shot("absicht_5_wartet_an_der_tuer.png")

	print("Absicht-Screens fertig -> %s" % OUT_DIR)
	_room.queue_free()
	await _settle(2)
	_gs.free()
	SaveSchema.unregister_slice(SoulState.SLICE_ID)
	SoulState.reset_for_tests()
	quit(0)


func _build_room() -> void:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	_room = scene.instantiate()
	_room.set("game_state_override", _gs)
	_room.set("stunde_override", 12.0)
	root.add_child(_room)


func _attach_runner() -> void:
	# Beziehung VOR dem Runner-Setup seeden — sonst feiert der Enter-Moment
	# fälschlich „Gooby-Geburtstag“ (firstMetAt=heute) ins Artefakt hinein.
	SoulState.mutate(
		_gs,
		func(s: Dictionary) -> void:
			s["firstMetAt"] = START_MS - 10 * MS_D
			s["lastVisitAt"] = START_MS - 3_600_000
	)
	_runner = GoobyReactions.new()
	_runner.name = "GoobyReactions"
	_runner.now_ms_override = START_MS
	_room.add_child(_runner)
	_runner.setup(_room)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/soul/data/soul.json")
	)
	_runner._defs = parsed.get("items", [])
	# Nur die Absicht soll laufen: Prozess-Takt + Eigenwanderung aus.
	_runner.set_process(false)
	var gooby: Node3D = _room.gooby()
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(false)
	# Deterministischer Start MITTIG im Raum: je nach Spawn-Zelle stünde
	# Gooby sonst hinter der Sprechblase — die Bildfolge braucht ihn sichtbar.
	if gooby != null and _room.grid != null:
		gooby.global_position = _mitte_zelle_welt()


## Weltposition der freien Zelle, die dem Zellen-Schwerpunkt am nächsten ist.
func _mitte_zelle_welt() -> Vector3:
	var cells: Array[Vector2i] = _room.grid.free_cells()
	var schwerpunkt := Vector2.ZERO
	for cell: Vector2i in cells:
		schwerpunkt += Vector2(cell)
	schwerpunkt /= float(maxi(cells.size(), 1))
	var best: Vector2i = cells[0]
	for cell: Vector2i in cells:
		if Vector2(cell).distance_to(schwerpunkt) < Vector2(best).distance_to(schwerpunkt):
			best = cell
	return GridData.world_center(best, Vector2i.ONE, 0)


## Vorab prüfen (Protokoll): Welche Absicht würde SoulIntent wählen?
func _erwartete_absicht() -> Dictionary:
	var state: Dictionary = _gs.state()
	var ctx := {
		"regen": false,
		"schlaeft": false,
		"vorhanden": _runner._seele.intent_ziele_vorhanden(),
	}
	return SoulIntent.waehle(state["gooby"]["stats"], ctx, {}, START_MS)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


## Warten, bis Gooby mindestens `anteil` des Wegs (Luftlinie ab `start`)
## geschafft hat — Sicherheitsnetz: nach 600 Frames geht es trotzdem weiter.
func _wait_weg(gooby: Node3D, start: Vector3, anteil: float) -> void:
	var ziel := _runner._seele._intent_ziel_welt(_erwartete_absicht())
	var strecke := maxf((ziel - start).length(), 0.001)
	for _i in 600:
		if (gooby.global_position - start).length() >= strecke * anteil:
			return
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
