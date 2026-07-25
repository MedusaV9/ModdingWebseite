class_name ShoppingSurfStreet
extends RefCounted
## Zeichen-Werkzeuge der Einkaufsstraße (reine Optik, NIE Spiel-Mathe).
## Farben nach der Web-Vorlage (shoppingSurf.js): rosa Pastellhimmel, rosiges
## Pflaster, cremefarbener Gehsteig, Pastell-Markisen über den Läden.
## Alle Funktionen bekommen `project` (Welt → Pixel) und `scale_at`
## (Pixel pro Meter in dieser Tiefe) vom View gereicht.

const SKY_TOP := Color(1.0, 0.84, 0.9)
const SKY_LOW := Color(1.0, 0.93, 0.94)
const PAVEMENT := Color(0.91, 0.81, 0.84)
const SIDEWALK := Color(0.96, 0.9, 0.84)
const CURB := Color(0.85, 0.72, 0.75)
const DOTS := Color(1.0, 0.96, 0.93, 0.7)
const PASTELS := [
	Color(1.0, 0.7, 0.78),
	Color(0.66, 0.9, 0.81),
	Color(1.0, 0.88, 0.51),
	Color(0.7, 0.85, 1.0),
	Color(0.88, 0.75, 0.91),
	Color(1.0, 0.8, 0.74),
]


## Himmel + Gehsteige + Fahrbahn als Trapez, dazu die Spurpunkte.
static func draw_ground(
	c: CanvasItem,
	size: Vector2,
	horizon: float,
	project: Callable,
	road_half: float,
	near_z: float,
	far_z: float,
	meters: float
) -> void:
	for i in 12:
		var f := float(i) / 11.0
		c.draw_rect(
			Rect2(0.0, horizon * f - 1.0, size.x, horizon / 11.0 + 2.0), SKY_TOP.lerp(SKY_LOW, f)
		)
	c.draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), SIDEWALK)
	var walk := road_half + 3.2
	_quad(c, project, walk, near_z, far_z, SIDEWALK)
	_quad(c, project, road_half, near_z, far_z, PAVEMENT)
	for side in [-1.0, 1.0]:
		c.draw_line(
			project.call(side * road_half, 0.14, near_z),
			project.call(side * road_half, 0.14, far_z),
			CURB,
			3.0
		)
	# Gestrichelte Spurtrenner laufen mit den gelaufenen Metern mit.
	for x in [-0.8, 0.8]:
		var z := near_z - fposmod(meters, 3.0)
		while z > far_z:
			var a: Vector2 = project.call(x, 0.02, z)
			var b: Vector2 = project.call(x, 0.02, maxf(far_z, z - 1.4))
			c.draw_line(a, b, DOTS, maxf(1.0, 0.05 * _px(project, z)))
			z -= 3.0


static func _quad(
	c: CanvasItem, project: Callable, half: float, near_z: float, far_z: float, col: Color
) -> void:
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					project.call(-half, 0.0, far_z),
					project.call(half, 0.0, far_z),
					project.call(half, 0.0, near_z),
					project.call(-half, 0.0, near_z),
				]
			),
			col
		)
	)


## Pixel-pro-Meter aus zwei Projektionen ableiten (spart einen Callable).
static func _px(project: Callable, z: float) -> float:
	var a: Vector2 = project.call(0.0, 0.0, z)
	var b: Vector2 = project.call(1.0, 0.0, z)
	return maxf(0.01, b.x - a.x)


## Ein Ladengeschäft am Straßenrand: Fassade, Markise, Schaufenster.
static func draw_shop(
	c: CanvasItem, project: Callable, side: float, z: float, kind: float, road_half: float
) -> void:
	var sc := _px(project, z)
	var base: Vector2 = project.call(side * (road_half + 3.4), 0.0, z)
	var w := sc * (2.6 + kind * 1.6)
	var h := sc * (4.2 + kind * 2.8)
	var tint: Color = PASTELS[int(kind * PASTELS.size()) % PASTELS.size()]
	var wall := tint.lerp(Color(1.0, 0.99, 0.97), 0.62)
	var ink := tint.darkened(0.42)
	var body := Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h))
	c.draw_rect(body, wall)
	c.draw_rect(body, ink, false, maxf(1.0, sc * 0.05))
	# Dachkante als Giebelband.
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					base + Vector2(-w * 0.58, -h),
					base + Vector2(w * 0.58, -h),
					base + Vector2(w * 0.44, -h - sc * 0.42),
					base + Vector2(-w * 0.44, -h - sc * 0.42),
				]
			),
			ink.lerp(Color(1, 1, 1), 0.25)
		)
	)
	# Ladenschild.
	c.draw_rect(
		Rect2(base + Vector2(-w * 0.34, -h * 0.86), Vector2(w * 0.68, h * 0.12)),
		Color(1.0, 0.98, 0.94)
	)
	# Gestreifte Markise über dem Schaufenster.
	var awn_y := -h * 0.5
	var awn_h := h * 0.13
	var stripes := 6
	for i in stripes:
		var f := float(i) / stripes
		var col := tint if i % 2 == 0 else Color(1.0, 0.99, 0.97)
		c.draw_rect(
			Rect2(
				base + Vector2(-w * 0.58 + w * 1.16 * f, awn_y),
				Vector2(w * 1.16 / stripes + 1.0, awn_h)
			),
			col
		)
	# Schaufenster, Türchen und Blumenkasten als Sticker-Details.
	c.draw_rect(
		Rect2(base + Vector2(-w * 0.42, awn_y + awn_h), Vector2(w * 0.5, h * 0.3)),
		Color(0.74, 0.86, 0.95)
	)
	c.draw_rect(
		Rect2(base + Vector2(-w * 0.42, awn_y + awn_h), Vector2(w * 0.5, h * 0.3)),
		ink,
		false,
		maxf(1.0, sc * 0.035)
	)
	c.draw_rect(
		Rect2(base + Vector2(w * 0.14, -h * 0.3), Vector2(w * 0.24, h * 0.3)),
		Color(0.79, 0.58, 0.47)
	)
	c.draw_rect(
		Rect2(base + Vector2(-w * 0.42, -h * 0.12), Vector2(w * 0.5, h * 0.06)),
		Color(0.5, 0.73, 0.48)
	)


## Ferner Bogen über der Straße (Reisemodus-Ziel bzw. Straßenschmuck).
static func draw_arch(c: CanvasItem, project: Callable, z: float, road_half: float) -> void:
	var sc := _px(project, z)
	var col := Color(1.0, 0.56, 0.67)
	for side in [-1.0, 1.0]:
		var foot: Vector2 = project.call(side * road_half, 0.0, z)
		var top: Vector2 = project.call(side * road_half, 3.4, z)
		c.draw_line(foot, top, col, maxf(2.0, sc * 0.22))
	c.draw_line(
		project.call(-road_half, 3.4, z), project.call(road_half, 3.4, z), col, maxf(2.0, sc * 0.3)
	)


## Einkaufswagen: Drahtkorb, rosa Waren, zwei Räder.
static func draw_cart(c: CanvasItem, at: Vector2, sc: float, telegraphed: bool) -> void:
	var w := sc * 0.55
	var h := sc * 0.62
	if telegraphed:
		c.draw_circle(at, w * 2.1, Color(1.0, 0.5, 0.55, 0.16))
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					at + Vector2(-w, -h),
					at + Vector2(w, -h),
					at + Vector2(w * 0.78, -h * 0.24),
					at + Vector2(-w * 0.78, -h * 0.24),
				]
			),
			Color(0.8, 0.85, 0.9)
		)
	)
	for i in 4:
		var f := -w + 2.0 * w * (i + 1) / 5.0
		c.draw_line(
			at + Vector2(f, -h), at + Vector2(f * 0.78, -h * 0.24), Color(0.6, 0.66, 0.72), 1.5
		)
	c.draw_rect(
		Rect2(at + Vector2(-w * 0.8, -h * 1.24), Vector2(w * 1.6, h * 0.32)), Color(1.0, 0.7, 0.78)
	)
	c.draw_line(at + Vector2(w, -h), at + Vector2(w * 1.25, -h * 1.5), Color(0.6, 0.66, 0.72), 2.0)
	for side in [-1.0, 1.0]:
		c.draw_circle(at + Vector2(side * w * 0.62, 0.0), sc * 0.12, Color(0.29, 0.23, 0.21))


## Kistenstapel — voller Blocker, nur Spurwechsel hilft.
static func draw_crate(c: CanvasItem, at: Vector2, sc: float) -> void:
	var w := sc * 0.6
	var h := sc * 0.9
	var body := Color(0.85, 0.68, 0.52)
	c.draw_rect(Rect2(at + Vector2(-w, -h), Vector2(w * 2.0, h)), body)
	c.draw_rect(
		Rect2(at + Vector2(-w, -h), Vector2(w * 2.0, h)),
		Color(0.58, 0.42, 0.3),
		false,
		maxf(1.5, sc * 0.05)
	)
	c.draw_line(
		at + Vector2(-w, -h * 0.52), at + Vector2(w, -h * 0.52), Color(0.66, 0.5, 0.36), 2.0
	)
	c.draw_rect(
		Rect2(at + Vector2(-w * 0.5, -h * 1.26), Vector2(w, h * 0.26)), Color(0.95, 0.72, 0.42)
	)


## Passant, der die Straße quert — gepunktete Bahn zeigt seinen Weg.
static func draw_npc(c: CanvasItem, at: Vector2, sc: float, walk: float) -> void:
	var h := sc * 1.0
	var fur := Color(0.98, 0.86, 0.78)
	c.draw_circle(at + Vector2(0.0, -h * 0.06), sc * 0.3, Color(0.15, 0.12, 0.12, 0.16))
	var swing := sin(walk * 9.0) * h * 0.1
	for side in [-1.0, 1.0]:
		c.draw_line(
			at + Vector2(side * sc * 0.1, -h * 0.42),
			at + Vector2(side * sc * 0.1 + swing * side, 0.0),
			Color(0.4, 0.42, 0.55),
			maxf(2.0, sc * 0.1)
		)
	c.draw_rect(
		Rect2(at + Vector2(-sc * 0.24, -h * 0.78), Vector2(sc * 0.48, h * 0.4)),
		Color(0.55, 0.72, 0.86)
	)
	c.draw_circle(at + Vector2(0.0, -h * 0.9), sc * 0.2, fur)
	# Einkaufstasche
	c.draw_rect(
		Rect2(at + Vector2(sc * 0.2, -h * 0.5), Vector2(sc * 0.22, sc * 0.3)),
		Color(0.95, 0.6, 0.68)
	)


## Markise quer über eine oder zwei Spuren — nur Rutschen passt darunter.
static func draw_awning(c: CanvasItem, at: Vector2, sc: float, half_w: float, gap_y: float) -> void:
	var w := half_w * sc
	var top := sc * 2.1
	var gap := gap_y * sc
	for side in [-1.0, 1.0]:
		c.draw_line(
			at + Vector2(side * w, 0.0),
			at + Vector2(side * w, -top),
			Color(0.69, 0.36, 0.22),
			maxf(1.5, sc * 0.08)
		)
	var stripes := 8
	for i in stripes:
		var f := float(i) / stripes
		var col := Color(1.0, 0.66, 0.74) if i % 2 == 0 else Color(1.0, 0.98, 0.96)
		c.draw_rect(
			Rect2(
				at + Vector2(-w * 1.05 + 2.1 * w * f, -top),
				Vector2(2.1 * w / stripes + 1.0, top - gap)
			),
			col
		)
	# Zackenkante unten — signalisiert „hier drunter durch".
	var y := -gap
	var teeth := 10
	for i in teeth:
		var x0 := -w * 1.05 + 2.1 * w * i / teeth
		var x1 := -w * 1.05 + 2.1 * w * (i + 1) / teeth
		(
			c
			. draw_colored_polygon(
				PackedVector2Array(
					[
						at + Vector2(x0, y),
						at + Vector2(x1, y),
						at + Vector2((x0 + x1) * 0.5, y + sc * 0.14),
					]
				),
				Color(0.92, 0.55, 0.62)
			)
		)


## Pfütze — weich, bremst nur 10 % für 2 s.
static func draw_puddle(c: CanvasItem, at: Vector2, sc: float, spent: bool) -> void:
	var col := Color(0.56, 0.78, 0.91, 0.5 if spent else 0.78)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var wobble := 1.0 + 0.12 * sin(a * 3.0)
		pts.append(at + Vector2(cos(a) * sc * 0.66 * wobble, sin(a) * sc * 0.2 * wobble))
	c.draw_colored_polygon(pts, col)
	c.draw_arc(
		at + Vector2(-sc * 0.2, -sc * 0.04), sc * 0.16, 0.6, 2.4, 8, Color(1, 1, 1, 0.6), 2.0
	)


## Bordstein-Lücke über die ganze Straße — nur ein Sprung rettet.
static func draw_gap(
	c: CanvasItem, project: Callable, z: float, half_depth: float, road_half: float
) -> void:
	var back: Vector2 = project.call(-road_half, 0.0, z - half_depth)
	var back_r: Vector2 = project.call(road_half, 0.0, z - half_depth)
	var front: Vector2 = project.call(-road_half, 0.0, z + half_depth)
	var front_r: Vector2 = project.call(road_half, 0.0, z + half_depth)
	c.draw_colored_polygon(
		PackedVector2Array([back, back_r, front_r, front]), Color(0.23, 0.19, 0.21)
	)
	c.draw_line(back, back_r, Color(0.98, 0.83, 0.4), 3.0)
	c.draw_line(front, front_r, Color(0.98, 0.83, 0.4), 3.0)


## Münze mit Drehschimmer.
static func draw_coin(c: CanvasItem, at: Vector2, sc: float, spin: float) -> void:
	var ry := sc * 0.18
	var rx := ry * (0.3 + 0.7 * absf(sin(spin)))
	c.draw_circle(at, ry * 1.5, Color(1.0, 0.85, 0.4, 0.22))
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(at + Vector2(cos(a) * maxf(1.0, rx), sin(a) * maxf(1.0, ry)))
	c.draw_colored_polygon(pts, Color(1.0, 0.82, 0.4))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.83, 0.58, 0.15), 1.5)


## Power-up-Sticker: Magnet, ×2, Schild, Turbo-Möhre.
static func draw_powerup(c: CanvasItem, at: Vector2, sc: float, kind: String, bob: float) -> void:
	var p := at + Vector2(0.0, -sc * (0.85 + 0.1 * sin(bob * 3.0)))
	c.draw_circle(at, sc * 0.28, Color(0.15, 0.12, 0.12, 0.15))
	c.draw_circle(p, sc * 0.46, Color(1.0, 1.0, 1.0, 0.35))
	match kind:
		"magnet":
			var r := sc * 0.3
			c.draw_arc(p, r, PI, TAU, 18, Color(0.9, 0.22, 0.24), maxf(3.0, sc * 0.16))
			for side in [-1.0, 1.0]:
				c.draw_rect(
					Rect2(p + Vector2(side * r - sc * 0.07, 0.0), Vector2(sc * 0.14, sc * 0.16)),
					Color(0.95, 0.95, 0.95)
				)
		"x2":
			c.draw_circle(p, sc * 0.32, Color(1.0, 0.82, 0.35))
			c.draw_arc(p, sc * 0.32, 0.0, TAU, 20, Color(0.8, 0.56, 0.14), 2.0)
		"shield":
			(
				c
				. draw_colored_polygon(
					PackedVector2Array(
						[
							p + Vector2(-sc * 0.3, -sc * 0.28),
							p + Vector2(sc * 0.3, -sc * 0.28),
							p + Vector2(sc * 0.3, sc * 0.06),
							p + Vector2(0.0, sc * 0.38),
							p + Vector2(-sc * 0.3, sc * 0.06),
						]
					),
					Color(0.39, 0.71, 0.96, 0.85)
				)
			)
		_:
			(
				c
				. draw_colored_polygon(
					PackedVector2Array(
						[
							p + Vector2(-sc * 0.16, -sc * 0.3),
							p + Vector2(sc * 0.16, -sc * 0.3),
							p + Vector2(0.0, sc * 0.4),
						]
					),
					Color(1.0, 0.55, 0.26)
				)
			)
			c.draw_circle(p + Vector2(sc * 0.1, -sc * 0.36), sc * 0.11, Color(0.4, 0.73, 0.42))
