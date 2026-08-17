extends TestCase
## FIX-F (E8 P1-1…P1-4): Emotions-Körperposen (earDroop/headPitch/armsHang),
## Morph-Wertebereich-Mapping (Editor-Multiplikator → Shapekey-Delta),
## apply_saved_morphs(gs) und der Tür-Quetsch (body_squeeze_door via
## play_clip("squeeze_door") bzw. squeeze(amount)).

const POSE_CHANNELS: Array[String] = ["ear_l", "ear_r", "head", "arms"]


## Minimaler GameState-Ersatz: nur get_value("meta.charMorphs.*").
class FakeGameState:
	extends RefCounted
	var morphs: Dictionary = {}

	func _init(initial: Dictionary = {}) -> void:
		morphs = initial

	func get_value(path: String, default: Variant = null) -> Variant:
		return morphs.get(path.trim_prefix("meta.charMorphs."), default)


func _make_rig() -> GoobyRig:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	return rig


func _shape(rig: GoobyRig, shape_name: String) -> float:
	var mesh: MeshInstance3D = rig._mesh
	var idx := mesh.find_blend_shape_by_name(shape_name)
	if idx < 0:
		fail_test("Shapekey fehlt: %s" % shape_name)
		return -999.0
	return mesh.get_blend_shape_value(idx)


func test_emotion_poses_tabelle_vollstaendig() -> void:
	for emotion in GoobyRig.EMOTIONS:
		assert_true(GoobyRig.EMOTION_POSES.has(emotion), "EMOTION_POSES fehlt für '%s'" % emotion)
		for channel in POSE_CHANNELS:
			assert_true(
				GoobyRig.EMOTION_POSES[emotion].has(channel),
				"Pose-Kanal %s fehlt für '%s'" % [channel, emotion]
			)
	# Stichproben 1:1 aus der Web-Referenz emotions.js (FACES):
	assert_almost(GoobyRig.EMOTION_POSES["sad"]["ear_l"], 0.7, 1e-6, "sad earDroopL")
	assert_almost(GoobyRig.EMOTION_POSES["sad"]["head"], 0.26, 1e-6, "sad headPitch")
	assert_almost(GoobyRig.EMOTION_POSES["sad"]["arms"], 1.0, 1e-6, "sad armsHang")
	assert_almost(GoobyRig.EMOTION_POSES["angry"]["ear_l"], 0.7, 1e-6, "angry←grumpy earDroopL")
	assert_almost(GoobyRig.EMOTION_POSES["angry"]["ear_r"], 0.08, 1e-6, "angry←grumpy earDroopR")
	assert_almost(GoobyRig.EMOTION_POSES["ecstatic"]["ear_l"], -0.1, 1e-6, "ecstatic perkt")


func test_emotion_pose_blendet_auf_bones() -> void:
	var rig := await _make_rig()
	var modifier: Node = rig._skeleton.find_child("GoobyPoseModifier", false, false)
	assert_true(modifier != null, "PoseModifier hängt nicht am Skelett")
	rig.set_emotion("sad")
	var settled := await wait_until(func() -> bool: return rig._pose_arms > 0.95, 4000)
	assert_true(settled, "Pose lerpt nicht auf Ziel (arms=%f)" % rig._pose_arms)
	assert_almost(rig._pose_ear_l, 0.7, 0.05, "sad: Ohr-Droop links")
	assert_almost(rig._pose_head, 0.26, 0.03, "sad: Kopf-Pitch")
	rig.set_emotion("neutral")
	settled = await wait_until(func() -> bool: return rig._pose_arms < 0.05, 4000)
	assert_true(settled, "Pose lerpt nicht zurück (arms=%f)" % rig._pose_arms)
	rig.free()


func test_morph_mapping_neutral_und_extreme() -> void:
	var rig := await _make_rig()
	# Neutral (Editor-Defaults) → Shapekey-Delta 0 = Basis-Optik.
	rig.set_morph("eye_size", 1.0)
	rig.set_morph("ear_length", 1.0)
	rig.set_morph("eye_width", 0.0)
	assert_almost(_shape(rig, "eye_size"), 0.0, 1e-6, "eye_size neutral")
	assert_almost(_shape(rig, "ear_length"), 0.0, 1e-6, "ear_length neutral")
	assert_almost(_shape(rig, "eye_width"), 0.0, 1e-6, "eye_width neutral")
	# Extreme: Multiplikator → Delta ((v−1)/0.35 bzw. /0.25); eye_width 1:1.
	rig.set_morph("eye_size", 1.4)
	assert_almost(_shape(rig, "eye_size"), 0.4 / 0.35, 1e-4, "eye_size max")
	rig.set_morph("eye_size", 0.7)
	assert_almost(_shape(rig, "eye_size"), -0.3 / 0.35, 1e-4, "eye_size min")
	rig.set_morph("ear_length", 1.25)
	assert_almost(_shape(rig, "ear_length"), 1.0, 1e-4, "ear_length +1 = ×1.25")
	rig.set_morph("ear_length", 0.7)
	assert_almost(_shape(rig, "ear_length"), -1.2, 1e-4, "ear_length min")
	rig.set_morph("eye_width", -1.0)
	assert_almost(_shape(rig, "eye_width"), -1.0, 1e-6, "eye_width 1:1")
	# Unbekannte Ids gehen unverändert durch (Doku-Vertrag von set_morph).
	rig.set_morph("mouth_open", 0.4)
	assert_almost(_shape(rig, "mouth_open"), 0.4, 1e-6, "unbekannte Id roh")
	rig.free()


func test_apply_saved_morphs() -> void:
	var rig := await _make_rig()
	var gs := FakeGameState.new(
		{"eyes_apart": 0.5, "eye_scale": 1.35, "ear_len": 0.75, "chubby": 1.0}
	)
	rig.apply_saved_morphs(gs)
	assert_almost(_shape(rig, "eye_width"), 0.5, 1e-6, "eyes_apart → eye_width")
	assert_almost(_shape(rig, "eye_size"), 1.0, 1e-4, "eye_scale 1.35 → Delta 1.0")
	assert_almost(_shape(rig, "ear_length"), -1.0, 1e-4, "ear_len 0.75 → Delta −1.0")
	# Leerer Save (get_value liefert Defaults) → alles neutral.
	rig.apply_saved_morphs(FakeGameState.new())
	assert_almost(_shape(rig, "eye_width"), 0.0, 1e-6, "Default eyes_apart neutral")
	assert_almost(_shape(rig, "eye_size"), 0.0, 1e-6, "Default eye_scale neutral")
	assert_almost(_shape(rig, "ear_length"), 0.0, 1e-6, "Default ear_len neutral")
	# Objekte ohne get_value (oder null) dürfen nicht crashen.
	rig.apply_saved_morphs(RefCounted.new())
	rig.apply_saved_morphs(null)
	rig.free()


func test_squeeze_tuergag() -> void:
	var rig := await _make_rig()
	assert_almost(_shape(rig, "body_squeeze_door"), 0.0, 1e-6, "Start ungequetscht")
	rig.play_clip("squeeze_door")
	var squeezed := await wait_until(
		func() -> bool:
			return absf(_shape(rig, "body_squeeze_door") - GoobyRig.SQUEEZE_DOOR_AMOUNT) < 0.01,
		4000
	)
	assert_true(squeezed, "squeeze_door steuert body_squeeze_door nicht an")
	assert_true(
		GoobyRig.SQUEEZE_DOOR_AMOUNT > 0.15 and GoobyRig.SQUEEZE_DOOR_AMOUNT < 0.35,
		"Quetsch-Wert muss sichtbar sein, aber das Gesicht behalten (E8 P2-1: Nase weg ab ~0.35)"
	)
	# Jeder andere Clip löst den Quetsch (Tür-Gag endet mit hop).
	rig.play_clip("hop")
	var released := await wait_until(
		func() -> bool: return _shape(rig, "body_squeeze_door") < 0.01, 4000
	)
	assert_true(released, "Quetsch löst sich nach dem Gag nicht")
	# Manuelle API fürs Tür-System, geclampt auf 0..1.
	rig.squeeze(2.0)
	assert_almost(rig._squeeze_target, 1.0, 1e-6, "squeeze() clampt auf 1.0")
	rig.squeeze(0.0)
	rig.free()
