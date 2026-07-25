extends RefCounted
## Kulissen-Maler des Burger-Baus: Diner-Wand mit rotem Streifen, Regal mit
## Saucenflaschen, Zutatenschächte über den drei Spalten, Theke und der
## rot-weiße Schachbrettboden davor (§C1.3-Look des Web-Originals).
##
## Liegt in einer eigenen Datei, damit `burger_build.gd` schlank bleibt;
## gezeichnet wird immer auf das übergebene CanvasItem der Spielszene.

const CREAM := Color(1.0, 0.937, 0.851)
const WALL := Color(1.0, 0.898, 0.796)
const GROUT := Color(0.976, 0.847, 0.729)
const DINER_RED := Color(0.839, 0.271, 0.271)
const WOOD := Color(0.788, 0.573, 0.404)
const WOOD_DARK := Color(0.612, 0.408, 0.271)
const TILE_WHITE := Color(0.988, 0.965, 0.929)
const INK := Color(0.2, 0.16, 0.14)
const FUR := Color(0.996, 0.906, 0.671)
const FUR_DARK := Color(0.984, 0.855, 0.6)

## Pastelltöne der Saucenflaschen im Regal.
const BOTTLES: Array[Color] = [
	Color(0.91, 0.42, 0.4),
	Color(0.99, 0.79, 0.36),
	Color(0.6, 0.81, 0.55),
	Color(0.72, 0.68, 0.93),
	Color(0.96, 0.66, 0.77),
]


## Wand, roter Diner-Streifen und Kachelfugen bis zur Thekenkante.
static func draw_wall(c: CanvasItem, vp: Vector2, counter_y: float) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), CREAM)
	c.draw_rect(Rect2(0.0, 0.0, vp.x, counter_y), WALL)
	var tile := maxf(28.0, vp.x / 7.0)
	var col := 1
	while tile * col < vp.x:
		c.draw_line(Vector2(tile * col, 0.0), Vector2(tile * col, counter_y), GROUT, 2.0)
		col += 1
	var row := 1
	while tile * row < counter_y:
		c.draw_line(Vector2(0.0, tile * row), Vector2(vp.x, tile * row), GROUT, 2.0)
		row += 1
	# Der rote Diner-Streifen sitzt im Web unter dem Ticket.
	var stripe_y := counter_y * 0.26
	var stripe_h := maxf(10.0, counter_y * 0.045)
	c.draw_rect(Rect2(0.0, stripe_y, vp.x, stripe_h), DINER_RED)
	c.draw_rect(
		Rect2(0.0, stripe_y + stripe_h, vp.x, stripe_h * 0.32), Color(0.72, 0.22, 0.22, 0.45)
	)


## Wandregal mit Saucenflaschen — füllt die leere obere Wandhälfte.
static func draw_shelf(c: CanvasItem, vp: Vector2, counter_y: float) -> void:
	var y := counter_y * 0.52
	var pad := vp.x * 0.08
	var board := Rect2(pad, y, vp.x - pad * 2.0, maxf(6.0, counter_y * 0.018))
	var unit := board.size.x / float(BOTTLES.size() + 1)
	for i in BOTTLES.size():
		var cx := board.position.x + unit * (i + 1)
		var h := unit * (0.62 + 0.12 * float(i % 3))
		var w := unit * 0.34
		c.draw_rect(Rect2(cx - w * 0.5, y - h, w, h), BOTTLES[i])
		c.draw_rect(Rect2(cx - w * 0.5, y - h, w, h), Color(0.35, 0.26, 0.2, 0.22), false, 2.0)
		c.draw_rect(
			Rect2(cx - w * 0.22, y - h - unit * 0.14, w * 0.44, unit * 0.14), Color(0.42, 0.34, 0.3)
		)
		c.draw_rect(Rect2(cx - w * 0.5, y - h * 0.55, w, h * 0.22), Color(1.0, 1.0, 1.0, 0.55))
	c.draw_rect(board, WOOD)
	c.draw_rect(
		Rect2(board.position.x, board.position.y + board.size.y, board.size.x, board.size.y * 0.7),
		WOOD_DARK
	)


## Pendelleuchten in den Lücken ZWISCHEN den Fallspuren plus Menütafel links —
## füllt die Wand, ohne den Regen zu verdecken.
static func draw_lamps(c: CanvasItem, vp: Vector2, rail_x: Array[float], counter_y: float) -> void:
	var gaps: Array[float] = []
	for i in maxi(0, rail_x.size() - 1):
		gaps.append((rail_x[i] + rail_x[i + 1]) * 0.5)
	var drop := counter_y * 0.36
	var r := maxf(20.0, vp.x * 0.08)
	for x in gaps:
		c.draw_line(Vector2(x, 0.0), Vector2(x, drop), Color(0.45, 0.42, 0.4), 3.0)
		(
			c
			. draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x - r * 0.28, drop),
						Vector2(x + r * 0.28, drop),
						Vector2(x + r, drop + r * 0.78),
						Vector2(x - r, drop + r * 0.78),
					]
				),
				Color(0.91, 0.45, 0.42)
			)
		)
		c.draw_circle(Vector2(x, drop + r * 0.86), r * 0.4, Color(1.0, 0.95, 0.72))
		c.draw_circle(Vector2(x, drop + r * 1.4), r * 2.1, Color(1.0, 0.93, 0.62, 0.13))


## Menütafel an der linken Wand (schmal genug, um die Spuren freizulassen).
static func draw_menu_board(
	c: CanvasItem, vp: Vector2, rail_x: Array[float], counter_y: float
) -> void:
	if rail_x.is_empty():
		return
	var right := rail_x[0] - vp.x * 0.04
	var w := right - vp.x * 0.02
	if w < vp.x * 0.1:
		return
	var board := Rect2(vp.x * 0.02, counter_y * 0.6, w, counter_y * 0.24)
	c.draw_rect(board.grow(maxf(3.0, w * 0.05)), WOOD_DARK)
	c.draw_rect(board, Color(0.29, 0.34, 0.3))
	for i in 4:
		var y := board.position.y + board.size.y * (0.2 + 0.2 * i)
		var line_w := board.size.x * (0.72 if i % 2 == 0 else 0.52)
		c.draw_line(
			Vector2(board.position.x + board.size.x * 0.14, y),
			Vector2(board.position.x + board.size.x * 0.14 + line_w, y),
			Color(0.86, 0.9, 0.84, 0.6),
			maxf(2.0, board.size.y * 0.05)
		)


## Zutatenschächte: über jeder Spalte hängt ein Trichter, aus dem es regnet.
static func draw_chutes(c: CanvasItem, rail_x: Array[float], counter_y: float) -> void:
	var h := maxf(22.0, counter_y * 0.075)
	for x in rail_x:
		var top := h * 1.05
		var bot := h * 0.55
		var poly := PackedVector2Array(
			[
				Vector2(x - top, 0.0),
				Vector2(x + top, 0.0),
				Vector2(x + bot, h),
				Vector2(x - bot, h),
			]
		)
		c.draw_colored_polygon(poly, Color(0.83, 0.85, 0.9))
		c.draw_rect(Rect2(x - bot, h, bot * 2.0, h * 0.22), Color(0.7, 0.73, 0.79))
		c.draw_line(
			Vector2(x - top * 0.6, h * 0.3),
			Vector2(x - bot * 0.6, h * 0.85),
			Color(1.0, 1.0, 1.0, 0.5),
			3.0
		)
		# Fallschiene bis zur Theke, damit die Spalten ablesbar bleiben.
		c.draw_line(Vector2(x, h * 1.3), Vector2(x, counter_y), Color(1.0, 1.0, 1.0, 0.3), 3.0)


## Theke plus Schachbrettboden davor (perspektivisch tiefer werdende Reihen).
static func draw_counter(c: CanvasItem, vp: Vector2, counter_y: float) -> void:
	var slab := maxf(10.0, vp.y * 0.016)
	c.draw_rect(Rect2(0.0, counter_y, vp.x, slab), Color(0.95, 0.9, 0.85))
	c.draw_rect(Rect2(0.0, counter_y + slab, vp.x, vp.y * 0.06), WOOD)
	c.draw_line(Vector2(0.0, counter_y), Vector2(vp.x, counter_y), Color(0.66, 0.48, 0.34), 3.0)
	var floor_y := counter_y + slab + vp.y * 0.06
	if floor_y >= vp.y:
		return
	c.draw_rect(Rect2(0.0, floor_y, vp.x, vp.y - floor_y), TILE_WHITE)
	_draw_checker(c, vp, floor_y)


## Rot-weißes Schachbrett in Fluchtperspektive (Reihen wachsen nach unten).
static func _draw_checker(c: CanvasItem, vp: Vector2, floor_y: float) -> void:
	var depth := vp.y - floor_y
	var y := floor_y
	var row := 0
	var step := depth * 0.16
	while y < vp.y and row < 12:
		var next_y := minf(vp.y, y + step)
		var cells := 8
		var w := vp.x / float(cells)
		for i in cells:
			if (i + row) % 2 == 0:
				c.draw_rect(Rect2(i * w, y, w, next_y - y), DINER_RED.lerp(CREAM, 0.12))
		y = next_y
		step *= 1.34
		row += 1


## Gooby als Koch hinter der Theke: Kopf, Ohren, Mütze, Körper, Arme.
static func draw_chef(c: CanvasItem, at: Vector2, s: float, bob: float) -> void:
	var head := at + Vector2(0.0, sin(bob * 3.0) * s * 0.06)
	# Körper hinter der Theke (unten von der Theke verdeckt).
	c.draw_rect(
		Rect2(head.x - s * 0.62, head.y + s * 0.35, s * 1.24, s * 1.6), Color(1.0, 1.0, 1.0)
	)
	c.draw_rect(
		Rect2(head.x - s * 0.62, head.y + s * 0.35, s * 1.24, s * 1.6),
		Color(0.78, 0.73, 0.68, 0.55),
		false,
		maxf(2.0, s * 0.05)
	)
	c.draw_rect(
		Rect2(head.x - s * 0.12, head.y + s * 0.4, s * 0.24, s * 1.5), Color(0.9, 0.86, 0.82)
	)
	# Arme mit Pfannenwender — der Koch war sonst ein reiner Papierklotz.
	var wrist := head + Vector2(s * 0.92, s * 0.62 + sin(bob * 6.0) * s * 0.1)
	c.draw_line(head + Vector2(s * 0.5, s * 0.6), wrist, FUR, maxf(3.0, s * 0.17))
	c.draw_circle(wrist, s * 0.15, FUR)
	c.draw_line(
		wrist, wrist + Vector2(s * 0.3, -s * 0.34), Color(0.62, 0.55, 0.5), maxf(2.0, s * 0.07)
	)
	c.draw_rect(
		Rect2(wrist.x + s * 0.22, wrist.y - s * 0.56, s * 0.28, s * 0.2), Color(0.75, 0.77, 0.8)
	)
	c.draw_line(
		head - Vector2(s * 0.5, -s * 0.6),
		head + Vector2(-s * 0.86, s * 0.9),
		FUR,
		maxf(3.0, s * 0.17)
	)
	c.draw_circle(head + Vector2(-s * 0.62, -s * 0.12), s * 0.2, FUR_DARK)
	c.draw_circle(head + Vector2(s * 0.62, -s * 0.12), s * 0.2, FUR_DARK)
	c.draw_circle(head, s * 0.6, FUR)
	# Kochmütze
	c.draw_rect(Rect2(head.x - s * 0.5, head.y - s * 0.78, s, s * 0.2), Color(1.0, 0.99, 0.96))
	for i in 3:
		c.draw_circle(
			head + Vector2((i - 1) * s * 0.34, -s * 0.9), s * 0.26, Color(1.0, 0.99, 0.96)
		)
	c.draw_circle(head + Vector2(-s * 0.21, -s * 0.06), s * 0.075, INK)
	c.draw_circle(head + Vector2(s * 0.21, -s * 0.06), s * 0.075, INK)
	c.draw_arc(
		head + Vector2(0.0, s * 0.12), s * 0.22, 0.35, PI - 0.35, 14, INK, maxf(1.5, s * 0.055)
	)
	c.draw_circle(head + Vector2(-s * 0.42, s * 0.14), s * 0.1, Color(0.98, 0.7, 0.72, 0.6))
	c.draw_circle(head + Vector2(s * 0.42, s * 0.14), s * 0.1, Color(0.98, 0.7, 0.72, 0.6))
