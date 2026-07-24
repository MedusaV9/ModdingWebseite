class_name GoobyPreview
extends Control
## PLATZHALTER-Gooby für den Char-Editor: 2D-Vektor-Zeichnung, die live auf
## die Editor-Morphs reagiert. INTERFACE-VERTRAG mit W1b (Handoff W1c):
## sobald `res://gooby/gooby.tscn` existiert, ersetzt eine 3D-SubViewport-
## Preview diesen Node — sie MUSS dieselbe API anbieten:
##
##     func set_morphs(morphs: Dictionary) -> void
##     # morphs = {eyes_apart:-1..1, eye_scale:0.7..1.4,
##     #           ear_len:0.7..1.4, chubby:0..1}
##
## Farben hier sind CHARAKTER-Kunstfarben (Stil-Anker GODOT-PLAN §7.1),
## bewusst keine UI-Theme-Tokens.

const FUR := Color("#F2E5CE")
const FUR_SHADE := Color("#E3D2B8")
const EAR_PINK := Color("#FFC7D8")
const CHEEK_PINK := Color(1.0, 0.4824, 0.6627, 0.55)
const OUTLINE := Color("#4A3B36")

var _morphs: Dictionary = OnboardingLogic.EDITOR_DEFAULTS.duplicate()


func set_morphs(morphs: Dictionary) -> void:
	for key: String in morphs:
		_morphs[key] = morphs[key]
	queue_redraw()


func get_morphs() -> Dictionary:
	return _morphs.duplicate()


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 260.0
	var chubby: float = _morphs.get("chubby", 0.0)
	var ear_len: float = _morphs.get("ear_len", 1.0)
	var eye_scale: float = _morphs.get("eye_scale", 1.0)
	var eyes_apart: float = _morphs.get("eyes_apart", 0.0)
	var head_r := (62.0 + chubby * 14.0) * s
	var head_c := c + Vector2(0.0, -6.0 * s)
	# Ohren (Kapseln, Innenseite rosa) — Länge über ear_len.
	for side in [-1.0, 1.0]:
		var base := head_c + Vector2(side * head_r * 0.52, -head_r * 0.72)
		var tip := base + Vector2(side * 10.0 * s, -78.0 * ear_len * s)
		_draw_capsule(base, tip, 20.0 * s, FUR, OUTLINE, 3.0 * s)
		_draw_capsule(
			base + Vector2(0.0, -6.0 * s),
			tip + Vector2(-side * 2.0 * s, 10.0 * s),
			10.0 * s,
			EAR_PINK,
			Color.TRANSPARENT,
			0.0
		)
	# Körper + Kopf.
	var body_c := c + Vector2(0.0, 74.0 * s)
	var body_r := (46.0 + chubby * 16.0) * s
	draw_circle(body_c, body_r + 3.0 * s, OUTLINE)
	draw_circle(body_c, body_r, FUR_SHADE)
	draw_circle(head_c, head_r + 3.0 * s, OUTLINE)
	draw_circle(head_c, head_r, FUR)
	# Augen (Abstand über eyes_apart, Größe über eye_scale).
	var eye_dx := (24.0 + eyes_apart * 12.0) * s
	var eye_r := 8.5 * eye_scale * s
	for side in [-1.0, 1.0]:
		var eye_c := head_c + Vector2(side * eye_dx, -4.0 * s)
		draw_circle(eye_c, eye_r, OUTLINE)
		draw_circle(eye_c + Vector2(eye_r * 0.3, -eye_r * 0.35), eye_r * 0.3, Color.WHITE)
	# Wangen + Naschmund.
	for side in [-1.0, 1.0]:
		draw_circle(head_c + Vector2(side * (eye_dx + 16.0 * s), 14.0 * s), 9.0 * s, CHEEK_PINK)
	draw_arc(head_c + Vector2(0.0, 12.0 * s), 12.0 * s, 0.35, PI - 0.35, 16, OUTLINE, 3.0 * s, true)


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
