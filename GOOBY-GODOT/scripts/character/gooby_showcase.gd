class_name GoobyShowcase
extends Node3D
## Showcase-Szene (W1b): lädt GoobyRig + GoobyVoice, spielt alle Clips und
## Emotionen der Reihe nach durch (Kamera + Licht in Code — kein Asset nötig).
##
## Läufe:
##   Headless-Crashtest:  godot --headless --path GOOBY-GODOT \
##       res://scripts/character/gooby_showcase.tscn --quit-after 5
##   Screenshot-Beweis:   xvfb-run -a godot --path GOOBY-GODOT \
##       --rendering-method gl_compatibility --rendering-driver opengl3 \
##       res://scripts/character/gooby_showcase.tscn -- --shots=/tmp/out
##     (speichert pro Station 1 PNG und beendet sich danach selbst)

const STAGE_SECONDS := 1.6

var rig: GoobyRig
var voice: GoobyVoice

## Stationen: Clip + Emotion (+ optional Morph/Sprech-Text).
var _program: Array[Dictionary] = [
	{"clip": "idle", "emotion": "neutral"},
	{"clip": "walk", "emotion": "happy"},
	{"clip": "wave", "emotion": "happy", "text": "Hallo hallo!"},
	{"clip": "hop", "emotion": "ecstatic"},
	{"clip": "sit", "emotion": "sleepy"},
	{"clip": "sleep", "emotion": "sleepy"},
	{"clip": "brush_teeth", "emotion": "neutral"},
	{"clip": "build_hammer", "emotion": "angry"},
	{"clip": "squeeze_door", "emotion": "scared"},
	{"clip": "celebrate", "emotion": "ecstatic", "text": "Juhu, geschafft?"},
	{"clip": "idle", "emotion": "sad", "morph": ["ear_length", 0.8]},
]

var _shots_dir := ""
var _stage_index := -1
var _stage_clock := 0.0
var _shot_taken := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
	_build_stage()
	rig = GoobyRig.new()
	rig.name = "Gooby"
	add_child(rig)
	voice = GoobyVoice.new()
	voice.name = "Stimme"
	add_child(voice)
	voice.silbe.connect(func(_i: int, _n: int) -> void: rig.babble_pulse())
	_advance_stage()


func _build_stage() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.78, 2.15)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.52, 0.0))
	camera.fov = 45.0
	add_child(camera)
	camera.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.15
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -140.0, 0.0)
	fill.light_energy = 0.45
	add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfe8f7")  # heller Himmel, freundlich
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f2ead9")
	env.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#bfe3a8")  # Wiese
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)


func _process(delta: float) -> void:
	_stage_clock += delta
	if _shots_dir != "" and not _shot_taken and _stage_clock >= STAGE_SECONDS * 0.55:
		_shot_taken = true
		_save_shot()
	if _stage_clock >= STAGE_SECONDS:
		_advance_stage()


func _advance_stage() -> void:
	_stage_index += 1
	_stage_clock = 0.0
	_shot_taken = false
	if _stage_index >= _program.size():
		if _shots_dir != "" or OS.has_feature("movie"):
			print("[showcase] fertig — %d Stationen durchgespielt" % _program.size())
			get_tree().quit(0)
			return
		_stage_index = 0  # Endlos-Schleife für interaktives Zuschauen
	var stage := _program[_stage_index]
	rig.play_clip(stage["clip"])
	rig.set_emotion(stage["emotion"])
	if stage.has("morph"):
		rig.set_morph(stage["morph"][0], stage["morph"][1])
	if stage.has("text"):
		voice.sagt(stage["text"], stage["emotion"])
	print(
		(
			"[showcase] Station %d: clip=%s emotion=%s"
			% [
				_stage_index,
				stage["clip"],
				stage["emotion"],
			]
		)
	)


func _save_shot() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var stage := _program[_stage_index]
	var image := get_viewport().get_texture().get_image()
	var path := (
		"%s/showcase_%02d_%s_%s.png"
		% [
			_shots_dir,
			_stage_index,
			stage["clip"],
			stage["emotion"],
		]
	)
	image.save_png(path)
	print("[showcase] Screenshot: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
