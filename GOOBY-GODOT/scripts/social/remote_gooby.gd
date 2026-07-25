class_name RemoteGooby
extends Node3D
## Der ANDERE Gooby im Besuch/Brettspiel (W3c VISIT): W1b-Rig + Spitzname-
## Label über dem Kopf. Positionen kommen mit 5 Hz aus dem POS-Relay —
## _process interpoliert weich dazwischen (Doc C §3.4 „Godot interpoliert“).

const LERP_SPEED := 8.0
const LABEL_HEIGHT := 1.35

var rig: GoobyRig

var _label: Label3D
var _target := Vector3.ZERO
var _has_target := false
var _anim := "idle"


func _ready() -> void:
	rig = GoobyRig.new()
	add_child(rig)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.004
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.98, 0.9)
	_label.outline_modulate = Color(0.25, 0.18, 0.12)
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	add_child(_label)


func set_display_name(display_name: String) -> void:
	if _label != null:
		_label.text = display_name


## Ziel aus dem POS-Relay übernehmen (snap beim allerersten Update).
func apply_state(pos: Vector3, anim: String) -> void:
	_target = pos
	if not _has_target:
		_has_target = true
		global_position = pos
	if anim != _anim:
		_anim = anim
		if anim != "walk" and anim != "idle":
			rig.play_clip(anim)


func play_emote(emote_id: String) -> void:
	if rig == null or not BoardEmotes.is_valid(emote_id):
		return
	rig.set_emotion(BoardEmotes.emotion_for(emote_id))
	rig.play_clip(BoardEmotes.clip_for(emote_id))


func _process(delta: float) -> void:
	if not _has_target or rig == null:
		return
	var to_target := _target - global_position
	to_target.y = 0.0
	var moving := to_target.length() > 0.05
	if moving:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to_target.x, to_target.z), 10.0 * delta)
	global_position = global_position.lerp(_target, 1.0 - exp(-LERP_SPEED * delta))
	if _anim == "walk" or _anim == "idle":
		rig.set_locomotion(1.0 if moving else 0.0)
