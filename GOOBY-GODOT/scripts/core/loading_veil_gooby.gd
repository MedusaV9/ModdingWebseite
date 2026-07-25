class_name LoadingVeilGooby
extends Control
## Hüpfender Mini-Gooby fürs LoadingVeil (W4/POLISH-3): reine 2D-Vektor-
## Zeichnung (Kreise/Kapseln) im Stil des Onboarding-Platzhalters
## (`gooby_preview.gd`) — Farben sind CHARAKTER-Kunstfarben (Stil-Anker
## GODOT-PLAN §7.1), bewusst keine UI-Theme-Tokens.
##
## Hop-Zyklus mit Squash & Stretch: am Boden gestaucht, in der Luft
## gestreckt; Ohren schlackern der Bewegung hinterher, der Schatten
## atmet mit. `set_animated(false)` = Reduced Motion (Ruhepose, kein
## _process) — das Veil reicht seinen reduced_motion-Flag durch.

const FUR := Color("#F2E5CE")
const FUR_SHADE := Color("#E3D2B8")
const EAR_PINK := Color("#FFC7D8")
const CHEEK_PINK := Color(1.0, 0.4824, 0.6627, 0.55)
const OUTLINE := Color("#4A3B36")
const SHADOW := Color(0.2902, 0.2314, 0.2118, 0.16)

const HOP_HZ := 1.4  # Hüpfer pro Sekunde
const HOP_HEIGHT := 0.30  # Anteil der Control-Höhe
const BLINK_PERIOD := 2.7
const BLINK_LEN := 0.12

var _t := 0.0
var _animated := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_animated)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Reduced Motion: false = eingefrorene Ruhepose am Boden.
func set_animated(animated: bool) -> void:
	_animated = animated
	set_process(animated)
	if not animated:
		_t = 0.0
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) / 150.0
	var ground := Vector2(size.x / 2.0, size.y - 14.0 * s)
	# Hop-Phase: 0 = Boden, 1 = Scheitelpunkt; vel < 0 = steigt gerade.
	var cycle := _t * HOP_HZ * TAU
	var phase := absf(sin(cycle * 0.5)) if _animated else 0.0
	var vel := (cos(cycle * 0.5) * signf(sin(cycle * 0.5))) if _animated else 0.0
	var hop := pow(phase, 0.85) * HOP_HEIGHT * size.y
	# Squash & Stretch: am Boden breit + platt, in der Luft schlank + lang.
	var ground_k := clampf(1.0 - phase * 4.0, 0.0, 1.0)
	var air_k := clampf(phase, 0.0, 1.0)
	var sx := 1.0 + 0.14 * ground_k - 0.07 * air_k
	var sy := 1.0 - 0.16 * ground_k + 0.10 * air_k
	_draw_shadow(ground, s, phase)
	var base := ground + Vector2(0.0, -hop)
	_draw_body(base, s, sx, sy)
	_draw_head(base, s, sx, sy, vel, air_k)


func _draw_shadow(ground: Vector2, s: float, phase: float) -> void:
	var shadow_w := (44.0 - 16.0 * phase) * s
	var shadow := SHADOW
	shadow.a = SHADOW.a * (1.0 - phase * 0.55)
	draw_set_transform(ground + Vector2(0.0, 6.0 * s), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, shadow_w, shadow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body(base: Vector2, s: float, sx: float, sy: float) -> void:
	var body_c := base + Vector2(0.0, -26.0 * s * sy)
	draw_set_transform(body_c, 0.0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, 25.0 * s + 2.5 * s, OUTLINE)
	draw_circle(Vector2.ZERO, 25.0 * s, FUR_SHADE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Füßchen nur bodennah sichtbar (in der Luft zieht Gooby sie ein).
	for side in [-1.0, 1.0]:
		var foot := base + Vector2(side * 13.0 * s * sx, -3.0 * s)
		draw_circle(foot, 7.0 * s + 2.0 * s, OUTLINE)
		draw_circle(foot, 7.0 * s, FUR_SHADE)


func _draw_head(base: Vector2, s: float, sx: float, sy: float, vel: float, air_k: float) -> void:
	var head_r := 33.0 * s
	var head_c := base + Vector2(0.0, (-26.0 - 40.0 * sy) * s)
	_draw_ears(head_c, head_r, s, vel)
	draw_set_transform(head_c, 0.0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, head_r + 2.5 * s, OUTLINE)
	draw_circle(Vector2.ZERO, head_r, FUR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_face(head_c, s, air_k)


func _draw_ears(head_c: Vector2, head_r: float, s: float, vel: float) -> void:
	# Ohren schlackern gegen die Bewegungsrichtung (vel < 0 = steigt).
	var lag := clampf(vel, -1.0, 1.0) * 10.0 * s
	for side in [-1.0, 1.0]:
		var ear_base := head_c + Vector2(side * head_r * 0.55, -head_r * 0.70)
		var tip := ear_base + Vector2(side * 7.0 * s, -34.0 * s + lag)
		_draw_capsule(ear_base, tip, 11.0 * s, FUR, OUTLINE, 2.5 * s)
		_draw_capsule(
			ear_base + Vector2(0.0, -3.0 * s),
			tip + Vector2(-side * 1.5 * s, 6.0 * s),
			5.0 * s,
			EAR_PINK,
			Color.TRANSPARENT,
			0.0
		)


func _draw_face(head_c: Vector2, s: float, air_k: float) -> void:
	var blinking := _animated and fmod(_t, BLINK_PERIOD) < BLINK_LEN
	for side in [-1.0, 1.0]:
		var eye_c := head_c + Vector2(side * 13.0 * s, -2.0 * s)
		if blinking:
			draw_line(
				eye_c + Vector2(-4.5 * s, 0.0), eye_c + Vector2(4.5 * s, 0.0), OUTLINE, 2.5 * s
			)
		else:
			draw_circle(eye_c, 4.8 * s, OUTLINE)
			draw_circle(eye_c + Vector2(1.4 * s, -1.6 * s), 1.5 * s, Color.WHITE)
		draw_circle(head_c + Vector2(side * 22.0 * s, 7.0 * s), 5.0 * s, CHEEK_PINK)
	# Beim Hochhüpfen macht der Mund ein fröhliches „o“, sonst Lächel-Bogen.
	if air_k > 0.6:
		draw_circle(head_c + Vector2(0.0, 8.0 * s), 3.6 * s, OUTLINE)
	else:
		draw_arc(
			head_c + Vector2(0.0, 6.0 * s), 7.0 * s, 0.35, PI - 0.35, 14, OUTLINE, 2.5 * s, true
		)


func _draw_capsule(
	from: Vector2, to: Vector2, radius: float, fill: Color, outline: Color, outline_w: float
) -> void:
	if outline.a > 0.0:
		draw_line(from, to, outline, (radius + outline_w) * 2.0)
		draw_circle(from, radius + outline_w, outline)
		draw_circle(to, radius + outline_w, outline)
	draw_line(from, to, fill, radius * 2.0)
	draw_circle(from, radius, fill)
	draw_circle(to, radius, fill)
