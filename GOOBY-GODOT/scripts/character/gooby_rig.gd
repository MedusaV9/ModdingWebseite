class_name GoobyRig
extends Node3D
## Gooby-Rig (W1b): lädt das gebaute GLB, baut den AnimationTree in Code auf
## und bietet die M1-API für W2/W3:
##   play_clip(name)          — Loop-Clips = StateMachine-Travel, Einmal-Clips = OneShot
##   set_locomotion(speed01)  — idle↔walk-Blend (BlendSpace1D 0..1)
##   set_emotion(id)          — 8 Emotionen als Shapekey-Blends (lerp 0.25 s)
##   set_morph(id, value)     — Editor-Morphs (eye_width/eye_size/ear_length)
##   look_at_target           — Node3D; Kopf dreht sanft hin (Clamp ±25°)
##   babble_pulse()           — kurzer mouth_open-Puls (Lipsync-Hook für GoobyVoice)
## Blink-Timer läuft automatisch (2.4–5.2 s, zufällig).
##
## Clip-Namen (logisch, ohne "-loop"): idle, idle_lookaround, walk, hop, sit,
## sleep, wave, squeeze_door, brush_teeth, build_hammer, celebrate.

signal clip_finished(clip: String)

const GLB_PATH := "res://assets/character/gooby.glb"
const EMOTIONS: Array[String] = [
	"neutral",
	"happy",
	"sad",
	"sleepy",
	"ecstatic",
	"angry",
	"scared",
	"dizzy",
]
const EDITOR_MORPHS: Array[String] = ["eye_width", "eye_size", "ear_length"]
## Loop-Clips, die als StateMachine-Zustände leben (idle/walk stecken im BlendSpace).
const LOOP_STATES: Array[String] = [
	"sit",
	"sleep",
	"squeeze_door",
	"brush_teeth",
	"build_hammer",
]
const EMOTION_LERP_SPEED := 4.0  # 1/0.25 s
const LOOK_CLAMP_DEG := 25.0
const LOOK_SMOOTH := 6.0

var look_at_target: Node3D = null

var _model: Node3D
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _anim_player: AnimationPlayer
var _tree: AnimationTree
var _action_clip: AnimationNodeAnimation
var _clip_map: Dictionary = {}  # logischer Name -> Animation-Name im Player
var _pending_oneshot := ""

var _emotion := "neutral"
var _emotion_weights: Dictionary = {}  # emotion -> aktuelles Gewicht
var _blink_timer := 0.0
var _blink_phase := -1.0  # <0 = kein Blink aktiv, sonst 0..1
var _mouth_pulse := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _rng := RandomNumberGenerator.new()


## Innerer SkeletonModifier: schreibt den geglätteten Look-At-Offset auf den
## Head-Bone NACH dem AnimationTree (überschreibt die Animation nicht).
class LookModifier:
	extends SkeletonModifier3D
	var rig: GoobyRig
	var head_idx := -1

	func _process_modification() -> void:
		if rig == null or head_idx < 0:
			return
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		if absf(rig._look_yaw) < 0.001 and absf(rig._look_pitch) < 0.001:
			return
		var pose := skeleton.get_bone_global_pose(head_idx)
		var offset := Basis(Vector3.UP, rig._look_yaw) * Basis(Vector3.RIGHT, rig._look_pitch)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(head_idx, pose)


func _ready() -> void:
	_rng.randomize()
	_load_model()
	if _anim_player == null:
		push_error("GoobyRig: kein AnimationPlayer im GLB gefunden (%s)" % GLB_PATH)
		return
	_build_clip_map()
	_build_animation_tree()
	_setup_look_modifier()
	for emotion in EMOTIONS:
		_emotion_weights[emotion] = 1.0 if emotion == _emotion else 0.0
	_schedule_blink()


func _load_model() -> void:
	var packed: PackedScene = load(GLB_PATH)
	if packed == null:
		push_error("GoobyRig: GLB lädt nicht: %s" % GLB_PATH)
		return
	_model = packed.instantiate()
	add_child(_model)
	_anim_player = _model.find_child("AnimationPlayer", true, false)
	_skeleton = _find_first(_model, "Skeleton3D")
	_mesh = _find_first(_model, "MeshInstance3D")


func _find_first(node: Node, klass: String) -> Variant:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found: Variant = _find_first(child, klass)
		if found != null:
			return found
	return null


func _build_clip_map() -> void:
	_clip_map.clear()
	for anim_name in _anim_player.get_animation_list():
		var logical := String(anim_name).trim_suffix("-loop")
		_clip_map[logical] = anim_name


func _anim(logical: String) -> String:
	return _clip_map.get(logical, "")


func _build_animation_tree() -> void:
	var blend_tree := AnimationNodeBlendTree.new()

	# Locomotion-StateMachine: "move" = BlendSpace1D idle↔walk + Loop-Zustände.
	var sm := AnimationNodeStateMachine.new()
	var blend_space := AnimationNodeBlendSpace1D.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = _anim("idle")
	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = _anim("walk")
	blend_space.add_blend_point(idle_node, 0.0)
	blend_space.add_blend_point(walk_node, 1.0)
	sm.add_node("move", blend_space)
	for state in LOOP_STATES:
		if _anim(state) == "":
			continue
		var state_node := AnimationNodeAnimation.new()
		state_node.animation = _anim(state)
		sm.add_node(state, state_node)
		sm.add_transition("move", state, _make_transition())
		sm.add_transition(state, "move", _make_transition())
	sm.add_transition("Start", "move", _make_transition())

	blend_tree.add_node("locomotion", sm, Vector2(0, 0))

	# OneShot-Layer für Einmal-Clips (wave/hop/celebrate/idle_lookaround).
	var oneshot := AnimationNodeOneShot.new()
	_action_clip = AnimationNodeAnimation.new()
	_action_clip.animation = _anim("wave")
	blend_tree.add_node("action", oneshot, Vector2(300, 0))
	blend_tree.add_node("action_clip", _action_clip, Vector2(100, 200))
	blend_tree.connect_node("action", 0, "locomotion")
	blend_tree.connect_node("action", 1, "action_clip")
	blend_tree.connect_node("output", 0, "action")

	_tree = AnimationTree.new()
	_tree.name = "GoobyAnimationTree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim_player)
	_tree.tree_root = blend_tree
	_tree.animation_finished.connect(_on_animation_finished)
	_tree.active = true
	_playback().travel("move")


func _make_transition() -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = 0.3
	return transition


func _playback() -> AnimationNodeStateMachinePlayback:
	return _tree.get("parameters/locomotion/playback")


func _setup_look_modifier() -> void:
	if _skeleton == null:
		return
	var modifier := LookModifier.new()
	modifier.name = "GoobyLookModifier"
	modifier.rig = self
	modifier.head_idx = _skeleton.find_bone("head")
	_skeleton.add_child(modifier)


# ---------------------------------------------------------------- Clips


## Spielt einen Clip. Loop-Clips wechseln den StateMachine-Zustand,
## Einmal-Clips feuern den OneShot-Layer und melden clip_finished.
func play_clip(clip: String) -> void:
	var logical := clip.trim_suffix("-loop")
	if not _clip_map.has(logical):
		push_warning("GoobyRig.play_clip: unbekannter Clip '%s'" % clip)
		return
	if logical == "idle" or logical == "walk":
		_playback().travel("move")
		set_locomotion(0.0 if logical == "idle" else 1.0)
	elif LOOP_STATES.has(logical):
		_playback().travel(logical)
	else:
		_action_clip.animation = _anim(logical)
		_pending_oneshot = logical
		_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 0.0 = idle, 1.0 = walk (BlendSpace1D).
func set_locomotion(speed01: float) -> void:
	_tree.set("parameters/locomotion/move/blend_position", clampf(speed01, 0.0, 1.0))


func current_state() -> String:
	return String(_playback().get_current_node())


func clip_names() -> Array:
	return _clip_map.keys()


func _on_animation_finished(anim_name: StringName) -> void:
	if _pending_oneshot != "" and String(anim_name) == _anim(_pending_oneshot):
		var done := _pending_oneshot
		_pending_oneshot = ""
		clip_finished.emit(done)


# ---------------------------------------------------------------- Gesicht


## Setzt die Ziel-Emotion; die Shapekeys blenden in _process weich um.
func set_emotion(id: String) -> void:
	if not EMOTIONS.has(id):
		push_warning("GoobyRig.set_emotion: unbekannte Emotion '%s'" % id)
		return
	_emotion = id


func get_emotion() -> String:
	return _emotion


## Editor-Morphs (eye_width/eye_size/ear_length) oder beliebige Shapekeys direkt.
func set_morph(id: String, value: float) -> void:
	_set_shape(id, value)


## Kurzer Mundöffner-Puls für Silben-Lipsync (GoobyVoice ruft das pro Silbe).
func babble_pulse() -> void:
	_mouth_pulse = 1.0


func _set_shape(shape_name: String, value: float) -> void:
	if _mesh == null:
		return
	var idx := _mesh.find_blend_shape_by_name(shape_name)
	if idx >= 0:
		_mesh.set_blend_shape_value(idx, value)


func _schedule_blink() -> void:
	_blink_timer = _rng.randf_range(2.4, 5.2)


func _process(delta: float) -> void:
	_process_emotions(delta)
	_process_blink(delta)
	_process_mouth(delta)
	_process_look(delta)


func _process_emotions(delta: float) -> void:
	var lerp_step := minf(EMOTION_LERP_SPEED * delta, 1.0)
	for emotion in EMOTIONS:
		var target := 1.0 if emotion == _emotion else 0.0
		var weight: float = lerpf(_emotion_weights[emotion], target, lerp_step)
		if absf(weight - _emotion_weights[emotion]) > 0.0005:
			_emotion_weights[emotion] = weight
			_set_shape("emotion_" + emotion, weight)


func _process_blink(delta: float) -> void:
	if _blink_phase >= 0.0:
		_blink_phase += delta / 0.14  # Blinzeldauer 140 ms
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
			_set_shape("blink", 0.0)
			_schedule_blink()
		else:
			# Dreieck: schnell zu, etwas langsamer auf
			var weight := _blink_phase / 0.4 if _blink_phase < 0.4 else (1.0 - _blink_phase) / 0.6
			_set_shape("blink", clampf(weight, 0.0, 1.0))
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_phase = 0.0


func _process_mouth(delta: float) -> void:
	if _mouth_pulse > 0.0:
		_set_shape("mouth_open", _mouth_pulse * 0.6)
		_mouth_pulse = maxf(_mouth_pulse - delta * 9.0, 0.0)
		if _mouth_pulse == 0.0:
			_set_shape("mouth_open", 0.0)


func _process_look(delta: float) -> void:
	var target_yaw := 0.0
	var target_pitch := 0.0
	if look_at_target != null and is_instance_valid(look_at_target):
		var local := to_local(look_at_target.global_position)
		local.y -= 1.0  # ungefähre Kopfhöhe
		var clamp_rad := deg_to_rad(LOOK_CLAMP_DEG)
		target_yaw = clampf(atan2(local.x, local.z), -clamp_rad, clamp_rad)
		var horizontal := Vector2(local.x, local.z).length()
		target_pitch = clampf(atan2(local.y, horizontal), -clamp_rad, clamp_rad)
	var smooth_step := minf(LOOK_SMOOTH * delta, 1.0)
	_look_yaw = lerpf(_look_yaw, target_yaw, smooth_step)
	_look_pitch = lerpf(_look_pitch, target_pitch, smooth_step)
