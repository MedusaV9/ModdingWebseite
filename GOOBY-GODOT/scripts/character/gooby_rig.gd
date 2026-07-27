class_name GoobyRig
extends Node3D
## Gooby-Rig (W1b): lädt das gebaute GLB, baut den AnimationTree in Code auf
## und bietet die M1-API für W2/W3:
##   play_clip(name)          — Loop-Clips = StateMachine-Travel, Einmal-Clips = OneShot
##   set_locomotion(speed01)  — idle↔walk-Blend (BlendSpace1D 0..1)
##   set_emotion(id)          — 8 Emotionen: Gesichts-Shapekeys + Körperpose
##                              (Ohren-Droop, Kopf-Pitch, Arm-Hang; lerp 0.25 s)
##   set_morph(id, value)     — Editor-Morphs im Save-/Editor-Wertebereich
##                              (eye_width -1..1, eye_size/ear_length 0.7..1.4)
##   apply_saved_morphs(gs)   — meta.charMorphs aus dem GameState anwenden
##   squeeze(amount)          — body_squeeze_door-Shapekey (Tür-Gag), 0 = frei;
##                              play_clip("squeeze_door") steuert ihn automatisch
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

## Emotions-Körperposen (P1-1) — Werte 1:1 aus der Web-Referenz
## GOOBY/src/character/emotions.js (FACES: earDroopL/R, headPitch, armsHang).
##   ear_l/ear_r: + = Ohr hängt/klappt runter, − = Ohr perkt hoch (rad-Parameter)
##   head:        + = Kopf neigt sich nach unten (rad)
##   arms:        0 = Pfoten auf dem Bauch … 1 = Arme hängen schlaff
## "angry" übernimmt das Web-"grumpy" (asymmetrische Ohren); "scared" hat kein
## Web-Pendant (Web: "hungry") und ist als Geducktheit gebaut: Ohren angelegt,
## Kopf runter, Arme leicht gelöst.
const EMOTION_POSES: Dictionary = {
	"neutral": {"ear_l": 0.06, "ear_r": 0.06, "head": 0.0, "arms": 0.0},
	"happy": {"ear_l": 0.0, "ear_r": 0.0, "head": 0.0, "arms": 0.0},
	"sad": {"ear_l": 0.7, "ear_r": 0.7, "head": 0.26, "arms": 1.0},
	"sleepy": {"ear_l": 0.35, "ear_r": 0.3, "head": 0.1, "arms": 0.4},
	"ecstatic": {"ear_l": -0.1, "ear_r": -0.1, "head": -0.04, "arms": 0.0},
	"angry": {"ear_l": 0.7, "ear_r": 0.08, "head": 0.06, "arms": 0.0},
	"scared": {"ear_l": 0.55, "ear_r": 0.55, "head": 0.22, "arms": 0.15},
	"dizzy": {"ear_l": 0.3, "ear_r": 0.35, "head": 0.0, "arms": 0.5},
}
## Ohr-Droop-Umsetzung nach gooby.js:806-811 (seitlich = max(−0.1, droop)·k,
## nach hinten = droop·k). Die Faktoren sind gegenüber dem Web HOCHskaliert
## (0.8→1.5, 0.55→0.7): der Web-Gooby hat kurze Ohren, bei den langen
## 3D-Ohren liest derselbe Winkel sonst als "gespreizt" statt "hängend".
## Der Droop verteilt sich auf beide Ohr-Bones (Basis + mehr an der Spitze),
## damit das Ohr weich KURVT statt starr zu kippen.
const EAR_OUT_FACTOR := 1.5
const EAR_BACK_FACTOR := 0.7
const EAR_PERK_MIN := -0.1
const EAR_SHARE_01 := 0.55
const EAR_SHARE_02 := 0.8
## Arm-Ruhepose (gebacken, gooby_params.py ARM): rot.x −0.5 / rot.z ∓0.38.
## armsHang=1 nimmt die Ruhepose weg (gooby.js:813-817) → Arme hängen schlaff.
const ARM_REST_FWD := 0.5
const ARM_REST_OUT := 0.38
## Editor-Morphs → Shapekey-Deltas (P1-2). Die GLB-Shapekeys sind 0..1-DELTAS:
## eye_size +1 = ×1.35 Augen, ear_length +1 = ×1.25 Ohren (build_rig.py).
## Editor/Save liefern MULTIPLIKATOREN 0.7..1.4 (Neutral 1.0, save_schema.gd)
## — Neutral muss auf Delta 0 landen, wie in der 2D-Onboarding-Vorschau.
const EYE_SIZE_DELTA_PER_UNIT := 0.35
const EAR_LENGTH_DELTA_PER_UNIT := 0.25
## Save-Keys (meta.charMorphs, FROZEN W1d) → Rig-Morph-Ids. "chubby" ist
## Weight-Tier (M2), kein Shapekey — bewusst nicht gemappt.
const SAVE_MORPH_MAP := {
	"eyes_apart": "eye_width", "eye_scale": "eye_size", "ear_len": "ear_length"
}
## Tür-Gag (P1-4): moderater Quetsch-Wert. Der Shapekey verschluckt ab ~0.35
## die Nase und ab ~0.5 fast das ganze Gesicht (E8 P2-1, Render-verifiziert);
## 0.3 quetscht sichtbar (~17 % schmaler) und lässt das Gesicht komplett.
const SQUEEZE_DOOR_AMOUNT := 0.3
const SQUEEZE_LERP_SPEED := 5.0

## REST-3 Pflege-Darstellung (P1-Bug Gewicht + Krankheits-/Müdigkeits-Optik).
## Gewicht läuft NICHT über einen Shapekey (der Rig-Vertrag hat keinen
## „chubby“-Morph, s. SAVE_MORPH_MAP) sondern — wie die Web-TIER_SCALE —
## als sanfte Körper-X/Z-Skalierung über Weight.body_scale().
const WeightLogic := preload("res://scripts/logic/weight.gd")
## Blasse Kränklichkeits-Tönung (multipliziert aufs Albedo, 1.0 = volle Stufe).
const CARE_PALE_TINT := Color(0.80, 0.88, 0.82)
const CARE_PALE_QUEASY := 0.5
const CARE_PALE_SICK := 1.0
## Rote Schniefnase (ab kränklich) + Eisbeutel (nur richtig krank).
const CARE_NOSE_COLOR := Color("#E86A5E")
const CARE_ICE_COLOR := Color(0.72, 0.88, 0.97, 0.92)
## Augenringe: ab dieser Müdigkeit sichtbar (blendet bis 1.0 kräftiger).
const CARE_EYEBAG_FROM := 0.3
const CARE_EYEBAG_COLOR := Color(0.42, 0.36, 0.52)

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
var _pose_ear_l := 0.06  # aktuelle (geglättete) Körperpose, Start = neutral
var _pose_ear_r := 0.06
var _pose_head := 0.0
var _pose_arms := 0.0
var _squeeze := 0.0
var _squeeze_target := 0.0
var _blink_timer := 0.0
var _blink_phase := -1.0  # <0 = kein Blink aktiv, sonst 0..1
var _mouth_pulse := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _rng := RandomNumberGenerator.new()

## REST-3 Pflege-Zustand (Gewicht/Krankheit/Müdigkeit) + Symptom-Nodes.
var _weight_scale := 1.0
var _care_grade := 0
var _care_tired := 0.0
var _care_mount: BoneAttachment3D
var _care_nose: MeshInstance3D
var _care_ice: Node3D
var _care_eyebags: Array[MeshInstance3D] = []
var _care_base_material: Material
var _care_pale_material: StandardMaterial3D
var _sneeze_tween: Tween


## Innerer SkeletonModifier: schreibt Look-At- UND Emotions-Pose-Offsets auf
## die Bones NACH dem AnimationTree (additiv — überschreibt die Animation
## nicht). Kopf: Look-Yaw/-Pitch + Emotions-Pitch; Ohren: Droop seitlich/nach
## hinten; Arme: Hängen (Inverse der gebackenen Ruhepose).
class PoseModifier:
	extends SkeletonModifier3D
	var rig: GoobyRig
	var head_idx := -1
	var ear_l1 := -1
	var ear_l2 := -1
	var ear_r1 := -1
	var ear_r2 := -1
	var arm_l := -1
	var arm_r := -1

	func _process_modification() -> void:
		if rig == null:
			return
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		_apply_head(skeleton)
		_apply_ear(skeleton, ear_l1, rig._pose_ear_l, 1.0, GoobyRig.EAR_SHARE_01)
		_apply_ear(skeleton, ear_l2, rig._pose_ear_l, 1.0, GoobyRig.EAR_SHARE_02)
		_apply_ear(skeleton, ear_r1, rig._pose_ear_r, -1.0, GoobyRig.EAR_SHARE_01)
		_apply_ear(skeleton, ear_r2, rig._pose_ear_r, -1.0, GoobyRig.EAR_SHARE_02)
		_apply_arm(skeleton, arm_l, rig._pose_arms, 1.0)
		_apply_arm(skeleton, arm_r, rig._pose_arms, -1.0)

	func _apply_head(skeleton: Skeleton3D) -> void:
		if head_idx < 0:
			return
		# Look-Pitch: + = Ziel oben = Kopf hoch; Emotions-Pitch: + = Kopf runter.
		var pitch := rig._look_pitch - rig._pose_head
		if absf(rig._look_yaw) < 0.001 and absf(pitch) < 0.001:
			return
		var pose := skeleton.get_bone_global_pose(head_idx)
		var offset := Basis(Vector3.UP, rig._look_yaw) * Basis(Vector3.RIGHT, pitch)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(head_idx, pose)

	## droop + = seitlich raus/runter (um ±Z) und nach hinten (um X) — die
	## Godot-Übersetzung von earGrps.rotation.x/z aus gooby.js:806-811.
	func _apply_ear(
		skeleton: Skeleton3D, idx: int, droop: float, out_sign: float, share: float
	) -> void:
		if idx < 0 or absf(droop) < 0.001:
			return
		var out_angle := maxf(GoobyRig.EAR_PERK_MIN, droop) * GoobyRig.EAR_OUT_FACTOR * share
		var back_angle := droop * GoobyRig.EAR_BACK_FACTOR * share
		var pose := skeleton.get_bone_global_pose(idx)
		var offset := (
			Basis(Vector3(0.0, 0.0, out_sign), out_angle) * Basis(Vector3.RIGHT, -back_angle)
		)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(idx, pose)

	## hang 0..1: dreht die gebackene "Pfoten auf dem Bauch"-Ruhepose raus
	## (gooby.js:813-817, rest = 1 − armsHang) → Arme hängen schlaff runter.
	func _apply_arm(skeleton: Skeleton3D, idx: int, hang: float, out_sign: float) -> void:
		if idx < 0 or hang < 0.001:
			return
		var pose := skeleton.get_bone_global_pose(idx)
		var offset := (
			Basis(Vector3(0.0, 0.0, out_sign), GoobyRig.ARM_REST_OUT * hang)
			* Basis(Vector3.RIGHT, GoobyRig.ARM_REST_FWD * hang)
		)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(idx, pose)


func _ready() -> void:
	_rng.randomize()
	_load_model()
	if _anim_player == null:
		push_error("GoobyRig: kein AnimationPlayer im GLB gefunden (%s)" % GLB_PATH)
		return
	_build_clip_map()
	_build_animation_tree()
	_setup_pose_modifier()
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


func _setup_pose_modifier() -> void:
	if _skeleton == null:
		return
	var modifier := PoseModifier.new()
	modifier.name = "GoobyPoseModifier"
	modifier.rig = self
	modifier.head_idx = _skeleton.find_bone("head")
	modifier.ear_l1 = _skeleton.find_bone("ear.L.01")
	modifier.ear_l2 = _skeleton.find_bone("ear.L.02")
	modifier.ear_r1 = _skeleton.find_bone("ear.R.01")
	modifier.ear_r2 = _skeleton.find_bone("ear.R.02")
	modifier.arm_l = _skeleton.find_bone("arm.L")
	modifier.arm_r = _skeleton.find_bone("arm.R")
	_skeleton.add_child(modifier)


# ---------------------------------------------------------------- Clips


## Spielt einen Clip. Loop-Clips wechseln den StateMachine-Zustand,
## Einmal-Clips feuern den OneShot-Layer und melden clip_finished.
## squeeze_door steuert zusätzlich den body_squeeze_door-Shapekey an
## (der GLB-Clip selbst hat keine Shapekey-Kanäle) — jeder andere Clip
## löst den Quetsch wieder.
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
	squeeze(SQUEEZE_DOOR_AMOUNT if logical == "squeeze_door" else 0.0)


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


## Setzt die Ziel-Emotion; Shapekeys UND Körperpose blenden in _process weich um.
func set_emotion(id: String) -> void:
	if not EMOTIONS.has(id):
		push_warning("GoobyRig.set_emotion: unbekannte Emotion '%s'" % id)
		return
	_emotion = id


func get_emotion() -> String:
	return _emotion


## Editor-Morphs — `value` kommt im SAVE-/EDITOR-Wertebereich an (identisch
## zur 2D-Onboarding-Vorschau, meta.charMorphs-Kontrakt):
##   eye_width:  −1 … +1, Neutral 0  (eyes_apart; Shapekey-Delta 1:1)
##   eye_size:   0.7 … 1.4, Neutral 1.0  (eye_scale-Multiplikator)
##   ear_length: 0.7 … 1.4, Neutral 1.0  (ear_len-Multiplikator)
## Neutral landet auf Shapekey-Delta 0 (Basis-Optik). Unbekannte Ids gehen
## unverändert auf den gleichnamigen Shapekey.
func set_morph(id: String, value: float) -> void:
	_set_shape(id, _morph_to_delta(id, value))


## Wendet die gespeicherten meta.charMorphs aus dem GameState auf den Rig an
## (P1-3). `gs` ist der GameState (braucht nur `get_value`). "chubby" ist
## Weight-Tier (M2) und (noch) kein Rig-Morph.
func apply_saved_morphs(gs: Object) -> void:
	if gs == null or not gs.has_method("get_value"):
		return
	for save_key: String in SAVE_MORPH_MAP:
		var neutral := 0.0 if save_key == "eyes_apart" else 1.0
		var value: float = float(gs.get_value("meta.charMorphs.%s" % save_key, neutral))
		set_morph(SAVE_MORPH_MAP[save_key], value)


## Tür-Quetsch (P1-4): blendet den body_squeeze_door-Shapekey weich auf
## `amount` (0 = frei). Werte um SQUEEZE_DOOR_AMOUNT quetschen sichtbar,
## OHNE das Gesicht zu verlieren (bei 1.0 verschluckt der Kopf die Decals).
func squeeze(amount: float) -> void:
	_squeeze_target = clampf(amount, 0.0, 1.0)


## Kurzer Mundöffner-Puls für Silben-Lipsync (GoobyVoice ruft das pro Silbe).
func babble_pulse() -> void:
	_mouth_pulse = 1.0


# ------------------------------------------------- REST-3: Pflege-Optik


## P1-Fix Gewicht: Silhouette dem Gewichtswert (5–95) nachführen — stetige
## Kurve durch die Web-TIER_SCALE-Anker (sleek 0.93 … floof 1.14) als
## Körper-X/Z-Scale. Kein Stufensprung, kein Kommentar — Gooby wird bei viel
## Süßem weich runder und bei Bewegung wieder schlanker.
func set_weight(value: float) -> void:
	_weight_scale = WeightLogic.body_scale(value)
	_apply_weight_scale()


## Aktuell angewandter Körper-Scale (Tests messen hierüber die Wirkung).
func weight_scale() -> float:
	return _weight_scale


func _apply_weight_scale() -> void:
	if _model != null:
		_model.scale = Vector3(_weight_scale, 1.0, _weight_scale)


## Krankheits-/Müdigkeits-Optik: grade 0 = gesund, 1 = kränklich (blasse
## Haut + Schniefnase), 2 = krank (dazu Eisbeutel). tired01 (0..1) steuert
## die Augenringe (ab CARE_EYEBAG_FROM sichtbar). Idempotent und jederzeit
## rückstandsfrei zurück auf gesund/wach — Symptome sind nie eine Strafe.
func set_care(grade: int, tired01 := 0.0) -> void:
	_care_grade = clampi(grade, 0, 2)
	_care_tired = clampf(tired01, 0.0, 1.0)
	_apply_care_look()


func care_grade() -> int:
	return _care_grade


func care_tiredness() -> float:
	return _care_tired


## Niesen (Symptom, nur richtig krank): kurzes Aufplustern + Squash mit
## Mund-Puls. Reduced Motion: nur der Mund-Puls, kein Körper-Ruck. Ton und
## Sprech-Zeile macht der Aufrufer (PflegeRunner).
func sneeze() -> void:
	babble_pulse()
	if _care_reduced_motion() or not is_inside_tree():
		return
	if _sneeze_tween != null and _sneeze_tween.is_valid():
		_sneeze_tween.kill()
	_sneeze_tween = create_tween()
	_sneeze_tween.tween_property(self, "scale:y", 1.06, 0.16)
	_sneeze_tween.tween_property(self, "scale:y", 0.86, 0.09)
	_sneeze_tween.tween_property(self, "scale:y", 1.0, 0.22)


func _care_reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


func _apply_care_look() -> void:
	_apply_care_pale()
	_ensure_care_props()
	if _care_nose != null:
		_care_nose.visible = _care_grade >= 1
	if _care_ice != null:
		_care_ice.visible = _care_grade >= 2
	var bag_strength := _care_tired
	if _care_grade > 0:
		bag_strength = maxf(bag_strength, 0.45)
	var sichtbar := bag_strength >= CARE_EYEBAG_FROM
	for bag: MeshInstance3D in _care_eyebags:
		bag.visible = sichtbar
		var mat := bag.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(
				CARE_EYEBAG_COLOR.r,
				CARE_EYEBAG_COLOR.g,
				CARE_EYEBAG_COLOR.b,
				0.2 + 0.4 * bag_strength
			)


## Blasse Haut über EIN Surface-Override (Basis-Material bleibt unberührt —
## Zurücksetzen = Override entfernen, andere Goobys teilen ihre Materialien).
func _apply_care_pale() -> void:
	if _mesh == null:
		return
	if _care_grade <= 0:
		_mesh.set_surface_override_material(0, null)
		return
	if _care_pale_material == null:
		_care_base_material = _mesh.mesh.surface_get_material(0)
		if _care_base_material is StandardMaterial3D:
			_care_pale_material = (_care_base_material as StandardMaterial3D).duplicate()
		else:
			_care_pale_material = StandardMaterial3D.new()
	var k := CARE_PALE_SICK if _care_grade >= 2 else CARE_PALE_QUEASY
	var basis_farbe := Color.WHITE
	if _care_base_material is StandardMaterial3D:
		basis_farbe = (_care_base_material as StandardMaterial3D).albedo_color
	_care_pale_material.albedo_color = basis_farbe * Color.WHITE.lerp(CARE_PALE_TINT, k)
	_mesh.set_surface_override_material(0, _care_pale_material)


## Symptom-Requisiten am Kopf-Bone (lazy, einmalig): Schniefnase, Eisbeutel,
## zwei Augenring-Monde — alles Primitives, kein Asset nötig. Hängen am
## BoneAttachment3D und machen damit jede Kopf-Pose/Animation mit.
func _ensure_care_props() -> void:
	if _care_mount != null or _skeleton == null:
		return
	_care_mount = BoneAttachment3D.new()
	_care_mount.name = "CareMount"
	_skeleton.add_child(_care_mount)
	_care_mount.bone_name = "head"
	_care_nose = _care_ball(0.048, CARE_NOSE_COLOR, 1.0)
	_care_nose.name = "SchniefNase"
	_care_nose.position = Vector3(0.0, 0.06, 0.20)
	_care_nose.visible = false
	_care_mount.add_child(_care_nose)
	_care_ice = _care_ice_pack()
	_care_ice.name = "Eisbeutel"
	_care_ice.position = Vector3(0.0, 0.30, 0.0)
	_care_ice.rotation_degrees = Vector3(0.0, 0.0, 8.0)
	_care_ice.visible = false
	_care_mount.add_child(_care_ice)
	for seite: float in [-1.0, 1.0]:
		var bag := _care_ball(0.045, CARE_EYEBAG_COLOR, 0.4)
		bag.name = "Augenring_L" if seite < 0.0 else "Augenring_R"
		bag.scale = Vector3(1.0, 0.38, 0.5)
		bag.position = Vector3(seite * 0.082, 0.095, 0.155)
		bag.visible = false
		_care_mount.add_child(bag)
		_care_eyebags.append(bag)


func _care_ball(radius: float, farbe: Color, alpha: float) -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	ball.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(farbe.r, farbe.g, farbe.b, alpha)
	mat.roughness = 0.55
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ball


## Eisbeutel: hellblauer weicher Beutel + kleiner Knoten obendrauf.
func _care_ice_pack() -> Node3D:
	var beutel := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.13
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARE_ICE_COLOR
	mat.roughness = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beutel.add_child(body)
	var knoten := MeshInstance3D.new()
	var knoten_mesh := CylinderMesh.new()
	knoten_mesh.top_radius = 0.028
	knoten_mesh.bottom_radius = 0.045
	knoten_mesh.height = 0.05
	knoten.mesh = knoten_mesh
	var knoten_mat := StandardMaterial3D.new()
	knoten_mat.albedo_color = Color(0.92, 0.97, 1.0)
	knoten_mat.roughness = 0.4
	knoten.material_override = knoten_mat
	knoten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knoten.position = Vector3(0.0, 0.075, 0.0)
	beutel.add_child(knoten)
	return beutel


func _morph_to_delta(id: String, value: float) -> float:
	match id:
		"eye_size":
			return (value - 1.0) / EYE_SIZE_DELTA_PER_UNIT
		"ear_length":
			return (value - 1.0) / EAR_LENGTH_DELTA_PER_UNIT
		_:
			return value


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
	_process_squeeze(delta)
	_process_look(delta)


func _process_emotions(delta: float) -> void:
	var lerp_step := minf(EMOTION_LERP_SPEED * delta, 1.0)
	for emotion in EMOTIONS:
		var target := 1.0 if emotion == _emotion else 0.0
		var weight: float = lerpf(_emotion_weights[emotion], target, lerp_step)
		if absf(weight - _emotion_weights[emotion]) > 0.0005:
			_emotion_weights[emotion] = weight
			_set_shape("emotion_" + emotion, weight)
	# Körperpose (P1-1): Ohren/Kopf/Arme lerpen zur EMOTION_POSES-Zielpose;
	# der PoseModifier schreibt die Offsets nach dem AnimationTree auf die Bones.
	var pose: Dictionary = EMOTION_POSES[_emotion]
	_pose_ear_l = lerpf(_pose_ear_l, float(pose["ear_l"]), lerp_step)
	_pose_ear_r = lerpf(_pose_ear_r, float(pose["ear_r"]), lerp_step)
	_pose_head = lerpf(_pose_head, float(pose["head"]), lerp_step)
	_pose_arms = lerpf(_pose_arms, float(pose["arms"]), lerp_step)


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


func _process_squeeze(delta: float) -> void:
	if is_equal_approx(_squeeze, _squeeze_target):
		return
	var step := minf(SQUEEZE_LERP_SPEED * delta, 1.0)
	_squeeze = lerpf(_squeeze, _squeeze_target, step)
	if absf(_squeeze - _squeeze_target) < 0.005:
		_squeeze = _squeeze_target
	_set_shape("body_squeeze_door", _squeeze)


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
