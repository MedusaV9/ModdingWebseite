class_name JuiceKit
extends Node
## Juice-API für alle Minigames (Doc G + POLISH-A-Ausbau): hit_freeze, shake,
## bloom_pulse, slowmo, float_text — plus Feel-Werkzeuge für Belohnungsmomente:
## hit_flash (Trefferblitz), scale_pop (Skalier-Pop), burst/ring_burst
## (Partikel), show_combo (mitwachsende Combo-Anzeige mit steigender Tonhöhe),
## edge_glow (Bildschirmrand-Glühen bei Serien), confetti/coin_rain (Feiern),
## count_to (hochzählende Zahlen) und win_moment (Zeitlupe im Siegmoment).
## Bewegungs-Effekte sind Reduced-Motion-gated (AppSettings.is_reduced_motion,
## Duck-Typing — ohne Autoload = an); Töne spielen auch unter Reduced Motion.
## Der Host hängt das Kit als Kind ein und setzt shake_target /
## world_environment / float_text_parent; Spiele erreichen es via ctx.juice.

## Maximaler Shake-Versatz in px bei Trauma 1.0.
const SHAKE_MAX_OFFSET := 14.0
## Trauma-Abbau pro Sekunde.
const SHAKE_DECAY := 2.2
## Edge-Glow: Abbau pro Sekunde (Serie hält ihn über show_combo frisch).
const GLOW_DECAY := 0.9
## Combo-Anzeige: Grundschriftgröße und Zuwachs pro Stufe (gedeckelt).
const COMBO_FONT_BASE := 36
const COMBO_FONT_STEP := 5
const COMBO_FONT_MAX := 84

## CanvasItem, das beim Shake versetzt wird (der Host nimmt den
## SubViewportContainer). position wird um die Basis herum moduliert.
var shake_target: CanvasItem
## Optionales WorldEnvironment im Host-Viewport für bloom_pulse.
var world_environment: WorldEnvironment
## Parent für float_text-Labels und Overlay-Effekte (Overlay des Hosts).
var float_text_parent: Node

## EF-3 F3: Ticks-Zeitstempel des letzten win_moment()/lose_moment() — der
## MinigameHost erkennt daran, ob ein Spiel sein Rundenende selbst inszeniert
## hat (nie doppelt feiern).
var win_moment_msec := -1_000_000

var _trauma := 0.0
var _shake_base := Vector2.ZERO
var _shake_base_valid := false
var _rng := RandomNumberGenerator.new()
var _pulse_token := 0
var _glow_base := -1.0
var _edge_glow_rect: ColorRect
var _edge_glow_strength := 0.0
var _combo_label: Label
var _coin_texture: Texture2D
var _pop_bases: Dictionary = {}
var _pop_tweens: Dictionary = {}


func _ready() -> void:
	_rng.randomize()


func _exit_tree() -> void:
	# Nie mit verstelltem time_scale zurücklassen (Freeze/Slowmo-Restlauf).
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_process_edge_glow(delta)
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
		# Kit nicht (mehr) im Baum (Late-Callback nach Szenenwechsel):
		# get_tree() gibt es dann nicht — Label sofort aufräumen statt crashen.
		if not is_inside_tree():
			label.queue_free()
			return
		get_tree().create_timer(0.8).timeout.connect(label.queue_free)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 64.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## Feel-Sound nach FeelSfx-Id (spielt auch unter Reduced Motion).
func sfx(id: String, pitch := 1.0) -> void:
	FeelSfx.play(self, id, pitch)


## DER Dopamin-Hebel: Combo-Ton mit steigender Tonhöhe (+1 Halbton/Stufe).
func combo_tone(streak: int) -> void:
	FeelSfx.play(self, "game_combo", FeelSfx.combo_pitch(streak))


## Kurzer Trefferblitz über dem Overlay (Sieg: gold, Fehler: rot …).
func hit_flash(color := Color(1.0, 1.0, 1.0, 0.22), ms := 110) -> void:
	if _reduced_motion():
		return
	var parent := _overlay_parent()
	if parent == null:
		return
	var rect := ColorRect.new()
	rect.color = color
	rect.z_index = 90
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, ms / 1000.0).set_ease(Tween.EASE_OUT)
	tween.tween_callback(rect.queue_free)


## Skalier-Pop: Node kurz auf amount aufblasen und zurückfedern.
## Funktioniert für Node2D und Control (Control poppt um die Mitte).
## Wiederholte Pops auf demselben Node stapeln sich NICHT (Basis gemerkt).
func scale_pop(item: Node, amount := 1.18, ms := 160) -> void:
	if _reduced_motion() or item == null or not is_instance_valid(item):
		return
	if not (item is Node2D or item is Control):
		return
	if item is Control:
		var control := item as Control
		control.pivot_offset = control.size * 0.5
	var id := item.get_instance_id()
	var base: Vector2 = _pop_bases.get(id, item.get("scale"))
	_pop_bases[id] = base
	var old_tween: Variant = _pop_tweens.get(id)
	if old_tween is Tween and (old_tween as Tween).is_valid():
		(old_tween as Tween).kill()
	var tween := create_tween()
	_pop_tweens[id] = tween
	tween.tween_property(item, "scale", base * amount, ms / 2500.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", base, ms / 1000.0).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_BACK
	)
	tween.tween_callback(_forget_pop.bind(id))


## Partikel-Burst (2D): kleine Funken-Quadrate, die aus pos herausplatzen.
## parent = Spielszene (Node2D) oder Overlay; räumt sich selbst auf.
func burst(parent: Node, pos: Vector2, color := Color(1.0, 0.85, 0.3), count := 14) -> void:
	if _reduced_motion() or parent == null or not is_instance_valid(parent):
		return
	var particles := CPUParticles2D.new()
	particles.position = pos
	particles.z_index = 95
	particles.one_shot = true
	particles.emitting = true
	particles.amount = count
	particles.lifetime = 0.55
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0.0, 640.0)
	particles.initial_velocity_min = 140.0
	particles.initial_velocity_max = 300.0
	particles.scale_amount_min = 2.5
	particles.scale_amount_max = 5.0
	particles.color = color
	particles.color_ramp = _fade_ramp(color)
	parent.add_child(particles)
	# one_shot ist gesetzt: finished feuert nach dem letzten Partikel —
	# szenenwechsel-sicher (SceneTreeTimer feuerte auf freed Instanzen).
	particles.finished.connect(particles.queue_free)


## Burst im Host-Overlay (für 3D-Spiele, die nur Viewport-Pixel haben —
## dieselbe Koordinatenwelt wie float_text).
func overlay_burst(pos: Vector2, color := Color(1.0, 0.85, 0.3), count := 14) -> void:
	burst(_overlay_parent(), pos, color, count)


## Ring-Puls im Host-Overlay (Koordinatenwelt wie float_text).
func overlay_ring(pos: Vector2, color := Color(1.0, 0.9, 0.5), radius := 64.0) -> void:
	ring_burst(_overlay_parent(), pos, color, radius)


## Expandierender Treffer-Ring (Puls) an pos.
func ring_burst(parent: Node, pos: Vector2, color := Color(1.0, 0.9, 0.5), radius := 64.0) -> void:
	if _reduced_motion() or parent == null or not is_instance_valid(parent):
		return
	var ring := JuiceRing.new()
	ring.position = pos
	ring.color = color
	ring.max_radius = radius
	ring.z_index = 95
	parent.add_child(ring)


## Mitwachsende Combo-Anzeige (Overlay, oben mittig): Text poppt, Schrift
## wächst mit der Serie, Ton steigt pro Stufe (combo_tone). streak < 2
## blendet die Anzeige aus. Auch unter Reduced Motion sichtbar (statisch).
func show_combo(streak: int, label_text := "") -> void:
	var parent := _overlay_parent()
	if parent == null:
		return
	if streak < 2:
		if _combo_label != null and is_instance_valid(_combo_label):
			var old := _combo_label
			_combo_label = null
			if _reduced_motion():
				old.queue_free()
			else:
				var out := create_tween()
				out.tween_property(old, "modulate:a", 0.0, 0.25)
				out.tween_callback(old.queue_free)
		return
	if _combo_label == null or not is_instance_valid(_combo_label):
		_combo_label = Label.new()
		_combo_label.z_index = 96
		_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_combo_label.add_theme_color_override("font_outline_color", Color(0.32, 0.14, 0.05, 0.9))
		_combo_label.add_theme_constant_override("outline_size", 8)
		_combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_combo_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_combo_label.position.y = 64.0
		parent.add_child(_combo_label)
	_combo_label.text = label_text if not label_text.is_empty() else "×%d" % streak
	_combo_label.modulate.a = 1.0
	var font_size := mini(COMBO_FONT_BASE + COMBO_FONT_STEP * streak, COMBO_FONT_MAX)
	_combo_label.add_theme_font_size_override("font_size", font_size)
	# Farbe wandert mit der Serie von Sonnengelb Richtung Feuerorange.
	var heat := clampf(float(streak) / 10.0, 0.0, 1.0)
	var color := Color(1.0, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.15), heat)
	_combo_label.add_theme_color_override("font_color", color)
	combo_tone(streak)
	edge_glow(0.25 + 0.6 * heat, color)
	scale_pop(_combo_label, 1.3, 200)


## Bildschirmrand-Glühen (Serien-Vignette): baut sich selbst wieder ab.
func edge_glow(strength: float, color := Color(1.0, 0.72, 0.25)) -> void:
	if _reduced_motion():
		return
	var parent := _overlay_parent()
	if parent == null:
		return
	if _edge_glow_rect == null or not is_instance_valid(_edge_glow_rect):
		_edge_glow_rect = ColorRect.new()
		_edge_glow_rect.z_index = 80
		_edge_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_glow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = _edge_glow_shader()
		_edge_glow_rect.material = mat
		parent.add_child(_edge_glow_rect)
	var material := _edge_glow_rect.material as ShaderMaterial
	material.set_shader_parameter("glow_color", Vector3(color.r, color.g, color.b))
	_edge_glow_strength = clampf(maxf(_edge_glow_strength, strength), 0.0, 1.0)
	material.set_shader_parameter("strength", _edge_glow_strength)
	_edge_glow_rect.visible = true


## Konfetti-Regen von der Oberkante (Rekord/Sieg feiern).
func confetti(count := 90) -> void:
	if _reduced_motion():
		return
	var parent := _overlay_parent()
	if parent == null:
		return
	var size := (parent as Control).size if parent is Control else Vector2(390, 200)
	var particles := CPUParticles2D.new()
	particles.position = Vector2(size.x * 0.5, -12.0)
	particles.z_index = 97
	particles.one_shot = true
	particles.emitting = true
	particles.amount = count
	particles.lifetime = 1.7
	particles.explosiveness = 0.85
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(maxf(size.x * 0.5, 60.0), 6.0)
	particles.direction = Vector2.DOWN
	particles.spread = 30.0
	particles.gravity = Vector2(0.0, 380.0)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 200.0
	particles.angular_velocity_min = -260.0
	particles.angular_velocity_max = 260.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.5
	particles.hue_variation_min = -0.5
	particles.hue_variation_max = 0.5
	particles.color = Color(1.0, 0.75, 0.35)
	parent.add_child(particles)
	# Szenenwechsel-sicher aufräumen (one_shot gesetzt, s. burst()).
	particles.finished.connect(particles.queue_free)


## Münz-Regen (Results/Coin-Chunks): goldene Münzen + Münz-Klimpern.
func coin_rain(count := 26) -> void:
	sfx("game_coin", 1.0)
	if _reduced_motion():
		return
	var parent := _overlay_parent()
	if parent == null:
		return
	var size := (parent as Control).size if parent is Control else Vector2(390, 200)
	var particles := CPUParticles2D.new()
	particles.position = Vector2(size.x * 0.5, -16.0)
	particles.z_index = 97
	particles.one_shot = true
	particles.emitting = true
	particles.amount = count
	particles.lifetime = 1.5
	particles.explosiveness = 0.6
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(maxf(size.x * 0.38, 50.0), 4.0)
	particles.direction = Vector2.DOWN
	particles.spread = 12.0
	particles.gravity = Vector2(0.0, 560.0)
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 150.0
	particles.scale_amount_min = 1.4
	particles.scale_amount_max = 2.2
	particles.texture = _coin_tex()
	particles.color = Color(1.0, 0.84, 0.25)
	parent.add_child(particles)
	# Szenenwechsel-sicher aufräumen (one_shot gesetzt, s. burst()).
	particles.finished.connect(particles.queue_free)
	# Klimpern in kleinen aufsteigenden Stufen hinterher. Gebundenes
	# Methoden-Callable statt Lambda (REST5-B2): wird das Kit vor dem
	# SceneTreeTimer freed, trennt Godot die Verbindung automatisch.
	for i in 3:
		var pitch := 1.0 + 0.08 * (i + 1)
		get_tree().create_timer(0.14 * (i + 1)).timeout.connect(sfx.bind("game_coin", pitch))


## Zahl hochzählen (Score/Coins im Results): tickt hörbar mit steigender
## Tonhöhe; unter Reduced Motion steht sofort der Endwert da (ein Tick).
func count_to(label: Label, from: int, to: int, dur := 0.8, prefix := "", suffix := "") -> void:
	if label == null or not is_instance_valid(label):
		return
	if _reduced_motion() or to == from or dur <= 0.05:
		label.text = "%s%d%s" % [prefix, to, suffix]
		sfx("game_count")
		return
	var state := {"last_tick": -1, "steps": mini(absi(to - from), 24)}
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(_count_step.bind(label, from, to, prefix, suffix, state), 0.0, 1.0, dur)
	tween.tween_callback(_count_done.bind(label, to, prefix, suffix))


## Der Siegmoment: kurze Zeitlupe + Goldblitz + Konfetti (Sound macht der
## Aufrufer über sfx("game_win"), damit Sieg/Rekord unterscheidbar bleiben).
func win_moment() -> void:
	win_moment_msec = Time.get_ticks_msec()
	slowmo(0.35, 420)
	hit_flash(Color(1.0, 0.9, 0.5, 0.28), 300)
	confetti(70)


## Der Trost-Moment am Rundenende OHNE Punkte (EF-3 F3): weiche kurze
## Zeitlupe + kühler Blitz — bewusst kein Konfetti, Niederlagen feiern nicht.
func lose_moment() -> void:
	win_moment_msec = Time.get_ticks_msec()
	slowmo(0.55, 300)
	hit_flash(Color(0.55, 0.6, 0.75, 0.16), 260)


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


func _overlay_parent() -> Node:
	if float_text_parent != null and is_instance_valid(float_text_parent):
		return float_text_parent
	return self if is_inside_tree() else null


func _process_edge_glow(delta: float) -> void:
	if _edge_glow_rect == null or not is_instance_valid(_edge_glow_rect):
		return
	if _edge_glow_strength <= 0.0:
		_edge_glow_rect.visible = false
		return
	_edge_glow_strength = maxf(0.0, _edge_glow_strength - GLOW_DECAY * delta)
	var material := _edge_glow_rect.material as ShaderMaterial
	material.set_shader_parameter("strength", _edge_glow_strength)
	if _edge_glow_strength <= 0.0:
		_edge_glow_rect.visible = false


func _edge_glow_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec3 glow_color = vec3(1.0, 0.72, 0.25);
uniform float strength = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.30, 0.72, length(d) * 1.25);
	COLOR = vec4(glow_color, edge * strength * 0.55);
}
"""
	return shader


func _forget_pop(id: int) -> void:
	_pop_bases.erase(id)
	_pop_tweens.erase(id)


func _count_step(
	t: float, label: Label, from: int, to: int, prefix: String, suffix: String, state: Dictionary
) -> void:
	if not is_instance_valid(label):
		return
	var value := lerpf(float(from), float(to), t)
	label.text = "%s%d%s" % [prefix, int(round(value)), suffix]
	var steps := int(state["steps"])
	var tick := int(t * steps)
	if tick != int(state["last_tick"]):
		state["last_tick"] = tick
		sfx("game_count", 0.9 + 0.5 * (float(tick) / maxf(1.0, float(steps))))


func _count_done(label: Label, to: int, prefix: String, suffix: String) -> void:
	if is_instance_valid(label):
		label.text = "%s%d%s" % [prefix, to, suffix]
		scale_pop(label, 1.15, 180)


func _fade_ramp(color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	return gradient


func _coin_tex() -> Texture2D:
	if _coin_texture != null:
		return _coin_texture
	var side := 10
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2(side - 1, side - 1) * 0.5
	for y in side:
		for x in side:
			var dist := Vector2(x, y).distance_to(center)
			if dist <= side * 0.5 - 0.5:
				var rim := dist > side * 0.5 - 2.0
				image.set_pixel(x, y, Color(0.85, 0.6, 0.1) if rim else Color(1.0, 0.85, 0.3))
	_coin_texture = ImageTexture.create_from_image(image)
	return _coin_texture


## Expandierender Ring für ring_burst (zeichnet sich selbst, räumt sich auf).
class JuiceRing:
	extends Node2D

	var color := Color(1.0, 0.9, 0.5)
	var max_radius := 64.0
	var _age := 0.0
	var _life := 0.38

	func _process(delta: float) -> void:
		_age += delta
		if _age >= _life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_age / _life, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 3.0)
		var col := Color(color.r, color.g, color.b, (1.0 - t) * 0.9)
		draw_arc(
			Vector2.ZERO, maxf(2.0, max_radius * eased), 0.0, TAU, 40, col, 4.0 * (1.0 - t) + 1.5
		)
