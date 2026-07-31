extends TestCase
## W13C/CLIPS: die 6 P1-Clips (F §1.4) + 2 Idle-Variety-Clips aus der
## Blender-Pipeline. Prüft Clip-Existenz mit EXAKTEN Namen, Loop-Flags,
## das Tri-Budget des GLB, das Rig-API-Mapping (Konstanten, LOOP_STATES,
## StateMachine/OneShot-Verhalten, play_clip_for, Gähn-Morph) und die
## Idle-Akt-Rotation in GoobyHome (Verteilung mit injiziertem RNG).

const GLB_PATH := "res://assets/character/gooby.glb"
## Loop-Semantik der 8 neuen Clips (Rig-Vertrag, gooby_params.py CLIP_LIST).
const NEUE_LOOPS: Array[String] = [
	"dance",
	"ragdoll_flail",
	"grip_floor",
	"ceiling_cling",
	"idle_ear_flick",
	"idle_stretch",
]
const NEUE_ONESHOTS: Array[String] = ["refuse", "tomato_throw"]
## Alt-Clips (W1-Vertrag) — dürfen durch den Rebuild NICHT verschwinden.
const ALT_CLIPS: Array[String] = [
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
]
const TRI_BUDGET := 8000


func test_glb_hat_alle_alt_und_neu_clips_exakt() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	assert_true(player != null, "kein AnimationPlayer im GLB")
	if player != null:
		var have := player.get_animation_list()
		var erwartet: Array[String] = []
		erwartet.append_array(ALT_CLIPS)
		erwartet.append_array(NEUE_LOOPS)
		erwartet.append_array(NEUE_ONESHOTS)
		for clip in erwartet:
			assert_true(clip in have, "Clip fehlt (Name exakt): %s" % clip)
		assert_eq(have.size(), erwartet.size(), "unerwartete Extra-Clips: %s" % [have])
	model.free()


func test_neue_clips_loop_flags() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	assert_true(player != null, "kein AnimationPlayer im GLB")
	if player != null:
		for clip in NEUE_LOOPS:
			var anim := player.get_animation(clip)
			assert_true(
				anim != null and anim.loop_mode != Animation.LOOP_NONE, "%s muss loopen" % clip
			)
		for clip in NEUE_ONESHOTS:
			var anim := player.get_animation(clip)
			assert_true(
				anim != null and anim.loop_mode == Animation.LOOP_NONE,
				"%s muss One-Shot sein" % clip
			)
	model.free()


func test_glb_tri_budget_bleibt() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var mesh: MeshInstance3D = null
	for child in model.find_children("*", "MeshInstance3D", true, false):
		mesh = child
		break
	assert_true(mesh != null and mesh.mesh != null, "kein Mesh im GLB")
	if mesh != null and mesh.mesh != null:
		var tris := 0
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
				tris += (indices as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		assert_true(tris > 1000, "Tri-Zählung unplausibel: %d" % tris)
		assert_true(tris <= TRI_BUDGET, "Tri-Budget gerissen: %d > %d" % [tris, TRI_BUDGET])
	model.free()


func test_rig_api_mapping_vollstaendig() -> void:
	assert_eq(GoobyRig.CLIP_DANCE, "dance")
	assert_eq(GoobyRig.CLIP_REFUSE, "refuse")
	assert_eq(GoobyRig.CLIP_RAGDOLL_FLAIL, "ragdoll_flail")
	assert_eq(GoobyRig.CLIP_GRIP_FLOOR, "grip_floor")
	assert_eq(GoobyRig.CLIP_TOMATO_THROW, "tomato_throw")
	assert_eq(GoobyRig.CLIP_CEILING_CLING, "ceiling_cling")
	assert_eq(GoobyRig.CLIP_IDLE_EAR_FLICK, "idle_ear_flick")
	assert_eq(GoobyRig.CLIP_IDLE_STRETCH, "idle_stretch")
	assert_eq(GoobyRig.W13C_LOOP_CLIPS, NEUE_LOOPS, "Loop-Mapping unvollständig")
	assert_eq(GoobyRig.W13C_ONESHOT_CLIPS, NEUE_ONESHOTS, "One-Shot-Mapping unvollständig")
	for clip in NEUE_LOOPS:
		assert_true(GoobyRig.LOOP_STATES.has(clip), "LOOP_STATES ohne %s" % clip)
	for clip in NEUE_ONESHOTS:
		assert_false(GoobyRig.LOOP_STATES.has(clip), "%s darf kein Loop-State sein" % clip)


func test_rig_spielt_neue_clips() -> void:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var names := rig.clip_names()
	for clip in NEUE_LOOPS + NEUE_ONESHOTS:
		assert_true(names.has(clip), "Rig kennt Clip nicht: %s" % clip)
	# Loop-Clip = StateMachine-Zustand …
	rig.play_clip("dance")
	var tanzt := await wait_until(func() -> bool: return rig.current_state() == "dance", 2000)
	assert_true(tanzt, "travel zu dance schlug fehl (state=%s)" % rig.current_state())
	# … One-Shot meldet clip_finished (refuse ist 1.2 s lang).
	var fertig := [""]
	rig.clip_finished.connect(func(clip: String) -> void: fertig[0] = clip)
	rig.play_clip("refuse")
	var done := await wait_until(func() -> bool: return fertig[0] != "", 5000)
	assert_true(done, "clip_finished für refuse kam nicht")
	assert_eq(fertig[0], "refuse")
	rig.free()


func test_play_clip_for_kehrt_in_move_zurueck() -> void:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var fertig := [""]
	rig.clip_finished.connect(func(clip: String) -> void: fertig[0] = clip)
	rig.play_clip_for("idle_ear_flick", 0.3)
	var zuckt := await wait_until(
		func() -> bool: return rig.current_state() == "idle_ear_flick", 2000
	)
	assert_true(zuckt, "travel zu idle_ear_flick schlug fehl")
	var zurueck := await wait_until(
		func() -> bool: return fertig[0] == "idle_ear_flick" and rig.current_state() == "move", 3000
	)
	assert_true(
		zurueck, "kein Rückweg in move (state=%s, fertig=%s)" % [rig.current_state(), fertig]
	)
	rig.free()


func test_idle_stretch_gaehnt_ueber_mouth_open() -> void:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var mesh: MeshInstance3D = null
	for child in rig.find_children("*", "MeshInstance3D", true, false):
		mesh = child
		break
	assert_true(mesh != null, "kein Mesh im Rig")
	if mesh != null:
		var idx := mesh.find_blend_shape_by_name("mouth_open")
		assert_true(idx >= 0, "mouth_open-Morph fehlt")
		rig.play_clip_for("idle_stretch", 2.6)
		var gaehnt := await wait_until(
			func() -> bool: return mesh.get_blend_shape_value(idx) > 0.3, 3000
		)
		assert_true(gaehnt, "Gähn-Morph fuhr nicht auf")
		var zu := await wait_until(
			func() -> bool: return mesh.get_blend_shape_value(idx) < 0.05, 3000
		)
		assert_true(zu, "Gähn-Morph fuhr nicht wieder zu")
	rig.free()


func test_idle_akt_rotation_enthaelt_neue_akte() -> void:
	var akte: Array[String] = []
	for eintrag: Dictionary in GoobyHome.IDLE_AKTE:
		akte.append(str(eintrag["akt"]))
	assert_true(akte.has(GoobyHome.IDLE_AKT_WANDER), "Streifzug fehlt in der Rotation")
	assert_true(akte.has("idle_ear_flick"), "idle_ear_flick fehlt in der Rotation")
	assert_true(akte.has("idle_stretch"), "idle_stretch fehlt in der Rotation")
	# Grenzwerte deterministisch (Gewichte 0.90 / 0.05 / 0.05).
	assert_eq(GoobyHome.waehle_idle_akt(0.0), "wander")
	assert_eq(GoobyHome.waehle_idle_akt(0.899), "wander")
	assert_eq(GoobyHome.waehle_idle_akt(0.91), "idle_ear_flick")
	assert_eq(GoobyHome.waehle_idle_akt(0.96), "idle_stretch")
	assert_eq(GoobyHome.waehle_idle_akt(1.0), "idle_stretch", "Roll 1.0 wird geklemmt")


func test_idle_akt_verteilung_mit_injiziertem_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	var zaehler := {"wander": 0, "idle_ear_flick": 0, "idle_stretch": 0}
	var n := 20000
	for _i in n:
		zaehler[GoobyHome.waehle_idle_akt(rng.randf())] += 1
	var wander_anteil := float(zaehler["wander"]) / float(n)
	var flick_anteil := float(zaehler["idle_ear_flick"]) / float(n)
	var stretch_anteil := float(zaehler["idle_stretch"]) / float(n)
	assert_true(absf(wander_anteil - 0.90) < 0.015, "Streifzug ≈90%% (ist %f)" % wander_anteil)
	assert_true(absf(flick_anteil - 0.05) < 0.01, "ear_flick ≈5%% (ist %f)" % flick_anteil)
	assert_true(absf(stretch_anteil - 0.05) < 0.01, "stretch ≈5%% (ist %f)" % stretch_anteil)
