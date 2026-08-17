extends TestCase
## W1b: verifiziert die Charakter-Pipeline — GLB vorhanden/importierbar,
## erwartete Clips (inkl. Loop-Flags), Skelett, Shapekeys, GoobyRig-API
## und GoobyVoice-Silben.

const GLB_PATH := "res://assets/character/gooby.glb"
## Der Godot-Importer setzt das Loop-Flag anhand des "-loop"-Suffixes im GLB
## und STRIPPT das Suffix aus dem Namen — erwartete Namen sind also logisch.
const EXPECTED_CLIPS: Array[String] = [
	"idle",
	"idle_lookaround",
	"walk",
	"hop",
	"sit",
	"sleep",
	"wave",
	"squeeze_door",
	"brush_teeth",
	"build_hammer",
	"celebrate",
	# W13C: 6 P1-Clips (F §1.4) + 2 Idle-Variety-Clips
	"dance",
	"refuse",
	"ragdoll_flail",
	"grip_floor",
	"tomato_throw",
	"ceiling_cling",
	"idle_ear_flick",
	"idle_stretch",
	# W15/VOICE2: IGohbie-Selfie-Clips (phone_up = Halte-Loop, phone_tap = Gag)
	"phone_up",
	"phone_tap",
]
const LOOPING_CLIPS: Array[String] = [
	"idle",
	"walk",
	"sit",
	"sleep",
	"squeeze_door",
	"brush_teeth",
	"build_hammer",
	# W13C: Loops (One-Shots: refuse, tomato_throw)
	"dance",
	"ragdoll_flail",
	"grip_floor",
	"ceiling_cling",
	"idle_ear_flick",
	"idle_stretch",
	# W15/VOICE2: Selfie-Haltepose loopt (One-Shot: phone_tap)
	"phone_up",
]
const EXPECTED_BONES: Array[String] = [
	"root",
	"hips",
	"spine",
	"chest",
	"head",
	"jaw",
	"eye.L",
	"eye.R",
	"ear.L.01",
	"ear.L.02",
	"ear.R.01",
	"ear.R.02",
	"arm.L",
	"arm.R",
	"leg.L",
	"foot.L",
	"leg.R",
	"foot.R",
	"tail",
]
const EXPECTED_SHAPEKEYS: Array[String] = [
	"emotion_neutral",
	"emotion_happy",
	"emotion_sad",
	"emotion_sleepy",
	"emotion_ecstatic",
	"emotion_angry",
	"emotion_scared",
	"emotion_dizzy",
	"blink",
	"mouth_open",
	"body_squeeze_door",
	"eye_width",
	"eye_size",
	"ear_length",
]
const EXPECTED_SYLLABLES := 14


func test_glb_existiert_und_laedt() -> void:
	assert_true(
		FileAccess.file_exists(GLB_PATH), "gooby.glb fehlt — tools/blender/build_gooby.sh ausführen"
	)
	var packed: Variant = load(GLB_PATH)
	assert_true(packed is PackedScene, "gooby.glb importiert nicht als PackedScene")


func test_glb_clips_und_loop_flags() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	assert_true(player != null, "kein AnimationPlayer im GLB")
	if player != null:
		var have := player.get_animation_list()
		for clip in EXPECTED_CLIPS:
			assert_true(clip in have, "Clip fehlt: %s" % clip)
			if clip in have:
				var anim := player.get_animation(clip)
				var should_loop := LOOPING_CLIPS.has(clip)
				var loops := anim.loop_mode != Animation.LOOP_NONE
				assert_eq(loops, should_loop, "Loop-Flag falsch für %s" % clip)
				assert_true(
					anim.length >= 0.5 and anim.length <= 3.0,
					"Clip-Länge %s = %.2fs (soll 0.5–3s)" % [clip, anim.length]
				)
	model.free()


func test_glb_skelett_und_shapekeys() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var skeleton: Skeleton3D = model.find_child("*", true, false) as Skeleton3D
	if skeleton == null:
		for child in model.find_children("*", "Skeleton3D", true, false):
			skeleton = child
			break
	assert_true(skeleton != null, "kein Skeleton3D im GLB")
	if skeleton != null:
		assert_true(
			skeleton.get_bone_count() >= 19, "zu wenige Bones: %d" % skeleton.get_bone_count()
		)
		for bone in EXPECTED_BONES:
			assert_true(skeleton.find_bone(bone) >= 0, "Bone fehlt: %s" % bone)
	var mesh: MeshInstance3D = null
	for child in model.find_children("*", "MeshInstance3D", true, false):
		mesh = child
		break
	assert_true(mesh != null, "kein MeshInstance3D im GLB")
	if mesh != null:
		for shape in EXPECTED_SHAPEKEYS:
			assert_true(mesh.find_blend_shape_by_name(shape) >= 0, "Shapekey fehlt: %s" % shape)
	model.free()


func test_gooby_rig_api() -> void:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	assert_eq(rig.current_state(), "move", "Rig startet nicht im move-State")
	assert_true(rig.clip_names().size() >= 11, "clip_names unvollständig")
	rig.set_emotion("happy")
	assert_eq(rig.get_emotion(), "happy")
	rig.set_emotion("gibtsnicht")  # darf nur warnen, nicht wechseln
	assert_eq(rig.get_emotion(), "happy")
	rig.set_morph("ear_length", 0.5)
	rig.set_locomotion(1.0)
	rig.play_clip("sit")
	var sitting := await wait_until(func() -> bool: return rig.current_state() == "sit", 2000)
	assert_true(sitting, "travel zu sit-State schlug fehl (state=%s)" % rig.current_state())
	var finished_clip := [""]
	rig.clip_finished.connect(func(clip: String) -> void: finished_clip[0] = clip)
	rig.play_clip("wave")  # 1.0 s OneShot
	var done := await wait_until(func() -> bool: return finished_clip[0] != "", 4000)
	assert_true(done, "clip_finished für wave kam nicht")
	assert_eq(finished_clip[0], "wave")
	rig.free()


func test_gooby_voice_babbelt() -> void:
	var voice := GoobyVoice.new()
	tree.root.add_child(voice)
	await wait_frames(2)
	assert_eq(voice.syllable_count(), EXPECTED_SYLLABLES, "Silben-WAVs fehlen")
	var events := {"silben": 0, "fertig": false}
	voice.silbe.connect(func(_i: int, _n: int) -> void: events["silben"] += 1)
	voice.fertig.connect(func() -> void: events["fertig"] = true)
	voice.sagt("Hallo?", "happy")
	assert_true(voice.ist_am_reden(), "sagt() startet nicht")
	var done := await wait_until(func() -> bool: return events["fertig"], 4000)
	assert_true(done, "fertig-Signal kam nicht")
	assert_eq(events["silben"], 5, "5 Buchstaben = 5 Silben erwartet")
	assert_false(voice.ist_am_reden())
	voice.free()
