class_name JuiceKit
extends Node
## Juice-API für alle Minigames (Doc G): hit_freeze, shake, bloom_pulse,
## slowmo, float_text. Bewegungs-Effekte sind Reduced-Motion-gated
## (AppSettings.is_reduced_motion, Duck-Typing — ohne Autoload = an).
## Der Host hängt das Kit als Kind ein und setzt shake_target /
## world_environment / float_text_parent; Spiele erreichen es via ctx.juice.

## Maximaler Shake-Versatz in px bei Trauma 1.0.
const SHAKE_MAX_OFFSET := 14.0
## Trauma-Abbau pro Sekunde.
const SHAKE_DECAY := 2.2

## CanvasItem, das beim Shake versetzt wird (der Host nimmt den
## SubViewportContainer). position wird um die Basis herum moduliert.
var shake_target: CanvasItem
## Optionales WorldEnvironment im Host-Viewport für bloom_pulse.
var world_environment: WorldEnvironment
## Parent für float_text-Labels (Overlay-Control des Hosts).
var float_text_parent: Node

var _trauma := 0.0
var _shake_base := Vector2.ZERO
var _shake_base_valid := false
var _rng := RandomNumberGenerator.new()
var _pulse_token := 0
var _glow_base := -1.0


func _ready() -> void:
	_rng.randomize()


func _exit_tree() -> void:
	# Nie mit verstelltem time_scale zurücklassen (Freeze/Slowmo-Restlauf).
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	if _trauma <= 0.0 or shake_target == null or not is_instance_valid(shake_target):
		if _shake_base_valid and shake_target != null and is_instance_valid(shake_target):
			shake_target.position = _shake_base
			_shake_base_valid = false
		return
	if not _shake_base_valid:
		_shake_base = shake_target.position
		_shake_base_valid = true
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var amount := _trauma * _trauma * SHAKE_MAX_OFFSET
	shake_target.position = (
		_shake_base + Vector2(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount))
	)
	if _trauma <= 0.0:
		shake_target.position = _shake_base
		_shake_base_valid = false


## Kurzer Hit-Stop: time_scale fast auf 0 für ms Millisekunden.
func hit_freeze(ms := 90) -> void:
	_time_scale_pulse(0.05, ms)


## Zeitlupe: time_scale = scale für ms Millisekunden.
func slowmo(scale := 0.3, ms := 300) -> void:
	_time_scale_pulse(scale, ms)


## Screen-Shake über Trauma (0..1, quadratische Wirkung, klingt selbst ab).
func shake(trauma: float) -> void:
	if _reduced_motion():
		return
	_trauma = clampf(_trauma + trauma, 0.0, 1.0)


## Glow-Puls auf dem WorldEnvironment des Host-Viewports (falls gesetzt).
func bloom_pulse(strength := 1.0, ms := 350) -> void:
	if _reduced_motion() or world_environment == null:
		return
	var env := world_environment.environment
	if env == null:
		return
	if _glow_base < 0.0:
		_glow_base = env.glow_intensity
	env.glow_enabled = true
	var tween := create_tween()
	tween.tween_property(env, "glow_intensity", _glow_base + strength, ms / 2000.0)
	tween.tween_property(env, "glow_intensity", _glow_base, ms / 2000.0)


## Schwebender Punkte-/Info-Text (auch unter Reduced Motion, dann statisch).
func float_text(pos: Vector2, text: String, color := Color.WHITE) -> void:
	var parent := float_text_parent if float_text_parent != null else self
	var label := Label.new()
	label.text = text
	label.position = pos
	label.z_index = 100
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.1, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 30)
	parent.add_child(label)
	if _reduced_motion():
		get_tree().create_timer(0.8).timeout.connect(label.queue_free)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 64.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _time_scale_pulse(scale: float, ms: int) -> void:
	if _reduced_motion():
		return
	_pulse_token += 1
	var token := _pulse_token
	Engine.time_scale = scale
	# ignore_time_scale=true, sonst dauert der Freeze 1/scale-mal so lange.
	await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	if token == _pulse_token:
		Engine.time_scale = 1.0


func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
