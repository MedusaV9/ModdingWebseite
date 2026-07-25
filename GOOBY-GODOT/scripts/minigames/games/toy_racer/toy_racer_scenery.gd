extends RefCounted
## Kulissen-Maler des Spielzeug-Rennens: Kinderzimmer (Wand, Fenster, Regal,
## Wimpelkette, Dielenboden) und die Bauklotz-Türme neben dem Kurs. Liegt in
## einer eigenen Datei, damit `toy_racer.gd` unter der 1000-Zeilen-Grenze
## bleibt; gezeichnet wird auf das übergebene CanvasItem der Spielszene.

## Bauklotz-Farben (Web BLOCK_COLORS §C10.1).
const BLOCKS: Array[Color] = [
	Color(0.95, 0.47, 0.47),
	Color(0.49, 0.76, 0.37),
	Color(0.44, 0.72, 0.91),
	Color(0.95, 0.76, 0.31),
	Color(0.78, 0.61, 0.88),
	Color(0.95, 0.62, 0.3),
]


## Warme Wand über dem Horizont, Dielenboden darunter.
static func draw_room(c: CanvasItem, size: Vector2, horizon: float) -> void:
	c.draw_rect(Rect2(0.0, 0.0, size.x, horizon), Color(0.97, 0.89, 0.78))
	var stripe := size.x / 14.0
	for i in 14:
		if i % 2 == 0:
			c.draw_rect(Rect2(i * stripe, 0.0, stripe, horizon), Color(1.0, 0.93, 0.84, 0.55))
	_draw_wall_props(c, size, horizon)
	# Fußleiste
	c.draw_rect(Rect2(0.0, horizon - 10.0, size.x, 10.0), Color(0.98, 0.96, 0.92))
	c.draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), Color(0.78, 0.56, 0.37))
	# Dielenfugen: perspektivisch dichter zum Horizont
	var y := horizon
	var gap := 3.0
	while y < size.y:
		c.draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.7, 0.48, 0.3, 0.55), 2.0)
		gap *= 1.22
		y += gap


## Wandschmuck: Fenster, Regal mit Spielzeug, Wimpelkette — das Kinderzimmer
## soll bewohnt aussehen, nicht nach leerer Fläche.
static func _draw_wall_props(c: CanvasItem, size: Vector2, horizon: float) -> void:
	# Fenster mit Sprossen (rechts vom HUD-Text)
	var win := Rect2(size.x * 0.3, horizon * 0.16, size.x * 0.17, horizon * 0.46)
	c.draw_rect(win, Color(0.72, 0.88, 0.96))
	c.draw_rect(
		Rect2(win.position, Vector2(win.size.x, win.size.y * 0.55)), Color(0.82, 0.93, 0.99)
	)
	c.draw_circle(
		win.position + Vector2(win.size.x * 0.72, win.size.y * 0.24),
		win.size.y * 0.12,
		Color(1.0, 0.94, 0.66)
	)
	c.draw_line(
		win.position + Vector2(win.size.x * 0.5, 0.0),
		win.position + Vector2(win.size.x * 0.5, win.size.y),
		Color(0.99, 0.97, 0.93),
		4.0
	)
	c.draw_line(
		win.position + Vector2(0.0, win.size.y * 0.5),
		win.position + Vector2(win.size.x, win.size.y * 0.5),
		Color(0.99, 0.97, 0.93),
		4.0
	)
	c.draw_rect(win, Color(0.86, 0.74, 0.6), false, 6.0)
	# Regalbrett rechts mit ein paar Bauklötzen
	var shelf := Rect2(size.x * 0.62, horizon * 0.5, size.x * 0.3, 9.0)
	c.draw_rect(shelf, Color(0.82, 0.64, 0.45))
	for i in 4:
		var tw := shelf.size.x / 9.0
		var th := tw * (0.7 + 0.22 * ((i * 5) % 3))
		c.draw_rect(
			Rect2(shelf.position + Vector2(tw * (0.6 + i * 1.9), -th), Vector2(tw, th)), BLOCKS[i]
		)
	# Wimpelkette
	var flags := 12
	for i in flags:
		var x0 := size.x * (float(i) / flags)
		var x1 := size.x * (float(i + 1) / flags)
		var sag := horizon * 0.06 + sin(float(i) / flags * PI) * horizon * 0.05
		c.draw_line(Vector2(x0, sag), Vector2(x1, sag + 2.0), Color(0.72, 0.6, 0.5), 2.0)
		(
			c
			. draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x0 + 3.0, sag),
						Vector2(x1 - 3.0, sag),
						Vector2((x0 + x1) * 0.5, sag + horizon * 0.1),
					]
				),
				BLOCKS[i % BLOCKS.size()].lightened(0.12)
			)
		)


## Bauklotz-Türme neben dem Kurs, hinten zuerst. `project` liefert Pixel oder
## null, `scale_of`/`depth_of` die Tiefe eines Weltpunkts (Callables der
## Spielszene, damit die Kulisse dieselbe Projektion nutzt).
static func draw_towers(
	c: CanvasItem,
	towers: Array[Dictionary],
	project: Callable,
	scale_of: Callable,
	depth_of: Callable,
	near: float,
	far: float
) -> void:
	var visible: Array[Dictionary] = []
	for tower: Dictionary in towers:
		var depth := float(depth_of.call(tower["pos"]))
		if depth < near or depth > far:
			continue
		visible.append({"t": tower, "d": depth})
	visible.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) > float(b["d"])
	)
	for entry: Dictionary in visible:
		var tower: Dictionary = entry["t"]
		var base: Vector3 = tower["pos"]
		var s := float(scale_of.call(base))
		var stack: Array = tower["stack"]
		var ground: Variant = project.call(base)
		if ground != null:
			c.draw_circle(Vector2(ground), s * 0.34, Color(0.5, 0.33, 0.2, 0.25))
		for level in stack.size():
			var pt: Variant = project.call(Vector3(base.x, base.y + 0.34 * (level + 1), base.z))
			if pt == null:
				continue
			var w := s * 0.62
			var h := s * 0.34
			var color: Color = BLOCKS[int(stack[level]) % BLOCKS.size()]
			var box := Rect2(Vector2(pt) - Vector2(w * 0.5, 0.0), Vector2(w, h))
			c.draw_rect(box, color)
			c.draw_rect(box, color.darkened(0.3), false, maxf(1.0, s * 0.012))
			for stud in 2:
				c.draw_circle(
					box.position + Vector2(w * (0.28 + stud * 0.44), -h * 0.1),
					maxf(1.0, w * 0.09),
					color.lightened(0.2)
				)
