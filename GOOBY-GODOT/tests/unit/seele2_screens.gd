extends SceneTree
## SEELE-2-Artefakte (KEIN Test — kein test_-Präfix): rendert Gooby nah
## (Gesicht groß im Bild) in 6 Stimmungen sowie den Vorher/Nachher-Vergleich
## desselben Moments (17:00, verhungert + erschöpft — vorher zeigte der
## hart verdrahtete Revert dort "happy"). Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/seele2_screens.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/SEELE2"

## 6 Stationen quer durch die Bänder; Stats passend zur Laune, damit
## ruhe_emotion ehrlich ableitet (statOverride inklusive).
const STIMMUNGEN: Array[Dictionary] = [
	{"name": "1_selig_95", "wert": 95.0, "energy": 90.0},
	{"name": "2_froh_72", "wert": 72.0, "energy": 80.0},
	{"name": "3_neutral_50", "wert": 50.0, "energy": 60.0},
	{"name": "4_brummig_32", "wert": 32.0, "energy": 50.0},
	{"name": "5_elend_15", "wert": 15.0, "energy": 30.0},
	{"name": "6_erschoepft_8", "wert": 8.0, "energy": 5.0},
]

var _rig: GoobyRig = null
var _schicht: GoobyExpressions = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(960, 720)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()
	_rig = GoobyRig.new()
	_rig.name = "Gooby"
	root.add_child(_rig)
	await _settle(5)
	_rig.play_clip("idle")

	# ── Vorher: exakt der alte Zustand — 17:00, alles im Keller, aber das
	# Gesicht steht auf dem hart verdrahteten "happy", keine Ausdrucks-Schicht.
	_rig.set_emotion("happy")
	await _settle(30)
	await _shot("vergleich_1700_vorher_happy_maske.png")

	# ── Ausdrucks-Schicht dazu (SEELE-2) und dieselbe Szene ehrlich zeigen.
	_schicht = GoobyExpressions.attach_to(_rig)
	_schicht.reduced_motion_override = 0
	var elend_stats := {"hunger": 0.0, "energy": 0.0, "hygiene": 7.0, "fun": 0.0}
	_rig.set_emotion(SoulMood.ruhe_emotion(4.0, elend_stats))
	_schicht.set_stimmung(4.0)
	await _settle(150)
	await _shot("vergleich_1700_nachher_ehrliches_gesicht.png")

	# ── 6 Stimmungen, Gesicht groß.
	for station in STIMMUNGEN:
		var wert := float(station["wert"])
		var stats := {
			"hunger": wert,
			"energy": float(station["energy"]),
			"hygiene": wert,
			"fun": wert,
		}
		_rig.set_emotion(SoulMood.ruhe_emotion(wert, stats))
		_schicht.set_stimmung(wert)
		await _settle(150)
		await _shot("stimmung_%s.png" % str(station["name"]))

	print("SEELE2-Screens fertig -> %s" % OUT_DIR)
	quit(0)


## Nahe Bühne: Kamera auf Kopfhöhe, Gesicht füllt das Bild — die Ohren
## (wichtigster Hasen-Kanal) bleiben komplett im Ausschnitt.
func _build_stage() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.8, 1.25)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.62, 0.0))
	camera.fov = 40.0
	root.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.15
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -140.0, 0.0)
	fill.light_energy = 0.45
	root.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfe8f7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f2ead9")
	env.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
