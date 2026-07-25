extends RefCounted
## Kulissen- und Bandmaler der Tortenwerkstatt. Liegt in einer eigenen Datei,
## damit `purble_place.gd` unter der 1000-Zeilen-Grenze bleibt.
##
## Weltbild (§G1.4 verbatim): `s` läuft von 0 bis 6 m das Band entlang, `y`
## zählt Meter ÜBER der Bandoberkante. Die Szene reicht ihr `project(s, y)`
## und die Pixel-pro-Meter durch, damit Kulisse und Spiellogik dieselbe
## Projektion benutzen — die Düsen stehen so pixelgenau über ihrer Station.

const Cake := preload("res://scripts/minigames/games/purble_place/purble_place_cake.gd")
const Logic := preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd")

## Wandtöne der Backstube.
const WALL := Color(0.99, 0.92, 0.84)
const WALL_STRIPE := Color(0.97, 0.86, 0.76)
const TILE := Color(0.93, 0.85, 0.8)
const BELT_DARK := Color(0.29, 0.26, 0.3)
const BELT_LIGHT := Color(0.42, 0.38, 0.44)
const FRAME := Color(0.72, 0.56, 0.44)

## Höhe der Düsenköpfe über dem Band = die Fallhöhe (§G1.5 FALL_M).
const NOZZLE_Y := 0.55
## Oberkante der Versorgungsschiene.
const RAIL_Y := 1.15


## Wand, Markise, Regale, Fliesen und Boden hinter dem Band. `belt_px` ist die
## Bandoberkante, `ppm` die Pixel je Weltmeter (skaliert die Kachelzone).
static func draw_backdrop(c: CanvasItem, stage: Rect2, belt_px: float, ppm: float) -> void:
	c.draw_rect(stage, WALL)
	var stripe := stage.size.x / 9.0
	for i in 10:
		if i % 2 == 0:
			c.draw_rect(
				Rect2(stage.position.x + i * stripe, stage.position.y, stripe, stage.size.y),
				WALL_STRIPE
			)
	_draw_awning(c, stage)
	# Kachelspiegel direkt hinter dem Band (1,5 m hoch — Bäckerei-Fliesen)
	var tile_top := belt_px - ppm * 1.5
	c.draw_rect(Rect2(stage.position.x, tile_top, stage.size.x, belt_px - tile_top), TILE)
	var step := maxf(22.0, ppm * 0.3)
	var x := stage.position.x
	while x < stage.position.x + stage.size.x:
		c.draw_line(Vector2(x, tile_top), Vector2(x, belt_px), Color(0.87, 0.77, 0.72), 2.0)
		x += step
	var y := tile_top + step
	while y < belt_px:
		c.draw_line(
			Vector2(stage.position.x, y),
			Vector2(stage.position.x + stage.size.x, y),
			Color(0.87, 0.77, 0.72),
			2.0
		)
		y += step
	c.draw_rect(Rect2(stage.position.x, tile_top - 6.0, stage.size.x, 6.0), Color(0.91, 0.8, 0.74))
	# Boden unter dem Band
	var floor_top := belt_px + ppm * 0.42
	c.draw_rect(
		Rect2(
			stage.position.x,
			floor_top,
			stage.size.x,
			maxf(0.0, stage.position.y + stage.size.y - floor_top)
		),
		Color(0.84, 0.72, 0.62)
	)
	var plank := floor_top + ppm * 0.12
	while plank < stage.position.y + stage.size.y:
		c.draw_line(
			Vector2(stage.position.x, plank),
			Vector2(stage.position.x + stage.size.x, plank),
			Color(0.75, 0.62, 0.52),
			2.0
		)
		plank += ppm * 0.16


static func _draw_awning(c: CanvasItem, stage: Rect2) -> void:
	var awn_h := clampf(stage.size.y * 0.07, 16.0, 46.0)
	var slats := maxi(6, int(stage.size.x / 52.0))
	for i in slats:
		var w := stage.size.x / slats
		var col := Color(0.949, 0.627, 0.722) if i % 2 == 0 else Color(1.0, 0.957, 0.894)
		c.draw_rect(Rect2(stage.position.x + i * w, stage.position.y, w, awn_h), col)
		c.draw_circle(
			Vector2(stage.position.x + (i + 0.5) * w, stage.position.y + awn_h), w * 0.5, col
		)
	c.draw_rect(
		Rect2(stage.position.x, stage.position.y, stage.size.x, awn_h * 0.3),
		Color(0.898, 0.659, 0.737)
	)


## Ladenschild unter der Markise + Wimpelkette.
static func draw_sign(c: CanvasItem, rect: Rect2, text: String, font: Font) -> void:
	var flags := maxi(6, int(rect.size.x / 46.0))
	for i in flags:
		var x0 := rect.position.x + rect.size.x * (float(i) / flags)
		var x1 := rect.position.x + rect.size.x * (float(i + 1) / flags)
		var sag := rect.position.y + sin(float(i) / flags * PI) * 7.0
		c.draw_line(Vector2(x0, sag), Vector2(x1, sag + 2.0), Color(0.76, 0.62, 0.55), 2.0)
		(
			c
			. draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x0 + 2.0, sag),
						Vector2(x1 - 2.0, sag),
						Vector2((x0 + x1) * 0.5, sag + rect.size.y * 0.3),
					]
				),
				Cake.SPRINKLES[i % Cake.SPRINKLES.size()].lightened(0.18)
			)
		)
	var board := Rect2(
		rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.38),
		Vector2(rect.size.x * 0.56, rect.size.y * 0.56)
	)
	c.draw_rect(board, Color(0.996, 0.925, 0.855))
	c.draw_rect(board, Color(0.898, 0.643, 0.694), false, 3.0)
	c.draw_string(
		font,
		board.position + Vector2(0.0, board.size.y * 0.72),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		board.size.x,
		int(clampf(board.size.y * 0.46, 12.0, 64.0)),
		Color(0.769, 0.361, 0.478)
	)


## Wartender Gast vor der Theke; `mood` 0..1 = Restgeduld (färbt das Gesicht).
static func draw_customer(c: CanvasItem, foot: Vector2, h: float, tint: Color, mood: float) -> void:
	var head_r := h * 0.3
	var body_top := foot.y - h + head_r * 1.5
	c.draw_circle(Vector2(foot.x, foot.y + h * 0.03), h * 0.3, Color(0.0, 0.0, 0.0, 0.12))
	# Körper
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(foot.x - h * 0.16, body_top),
					Vector2(foot.x + h * 0.16, body_top),
					Vector2(foot.x + h * 0.26, foot.y),
					Vector2(foot.x - h * 0.26, foot.y),
				]
			),
			tint
		)
	)
	c.draw_circle(Vector2(foot.x - h * 0.26, body_top + h * 0.16), h * 0.075, tint.darkened(0.1))
	c.draw_circle(Vector2(foot.x + h * 0.26, body_top + h * 0.16), h * 0.075, tint.darkened(0.1))
	var head := Vector2(foot.x, body_top - head_r * 0.55)
	c.draw_circle(head, head_r, Color(0.996, 0.906, 0.671))
	c.draw_circle(head + Vector2(-head_r * 0.95, 0.0), head_r * 0.3, Color(0.984, 0.855, 0.6))
	c.draw_circle(head + Vector2(head_r * 0.95, 0.0), head_r * 0.3, Color(0.984, 0.855, 0.6))
	c.draw_circle(
		head + Vector2(-head_r * 0.34, -head_r * 0.06), head_r * 0.12, Color(0.2, 0.16, 0.14)
	)
	c.draw_circle(
		head + Vector2(head_r * 0.34, -head_r * 0.06), head_r * 0.12, Color(0.2, 0.16, 0.14)
	)
	# Mund: lächelt bei viel Geduld, wird zum Strich und kippt bei Eile.
	var curve := lerpf(-0.45, 0.45, clampf(mood, 0.0, 1.0))
	c.draw_arc(
		head + Vector2(0.0, head_r * (0.22 - curve * 0.24)),
		head_r * 0.34,
		0.0 if curve > 0.0 else PI,
		PI if curve > 0.0 else TAU,
		14,
		Color(0.2, 0.16, 0.14),
		maxf(1.5, head_r * 0.1)
	)
	var blush := Color(0.98, 0.62, 0.62, 0.45 + 0.35 * (1.0 - clampf(mood, 0.0, 1.0)))
	c.draw_circle(head + Vector2(-head_r * 0.58, head_r * 0.3), head_r * 0.17, blush)
	c.draw_circle(head + Vector2(head_r * 0.58, head_r * 0.3), head_r * 0.17, blush)


## Theke, vor der die Gäste warten.
static func draw_counter(c: CanvasItem, rect: Rect2) -> void:
	c.draw_rect(rect, Color(0.87, 0.71, 0.55))
	c.draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.28)), Color(0.94, 0.82, 0.68)
	)
	c.draw_rect(rect, Color(0.7, 0.53, 0.4), false, 2.0)


## Laufband mit mitwandernden Querstreben; `scroll` ist der Bandweg in Metern.
static func draw_belt(
	c: CanvasItem, stage: Rect2, project: Callable, ppm: float, scroll: float
) -> void:
	var top: Vector2 = project.call(0.0, 0.0)
	var thickness := maxf(10.0, ppm * 0.17)
	var band := Rect2(stage.position.x, top.y, stage.size.x, thickness)
	c.draw_rect(band, BELT_DARK)
	c.draw_rect(Rect2(band.position, Vector2(band.size.x, thickness * 0.3)), BELT_LIGHT)
	# Querstreben alle 0,25 m — sie zeigen Richtung und Tempo des Bandes.
	var pitch := 0.25
	var phase := fmod(fmod(scroll, pitch) + pitch, pitch)
	var s := -phase
	while s < 7.0:
		var p: Vector2 = project.call(s, 0.0)
		if p.x > stage.position.x - 6.0 and p.x < stage.position.x + stage.size.x + 6.0:
			c.draw_line(
				Vector2(p.x, band.position.y + 1.0),
				Vector2(p.x, band.position.y + thickness - 1.0),
				Color(0.2, 0.18, 0.22),
				maxf(1.5, ppm * 0.018)
			)
		s += pitch
	# Rahmen + Rollen
	c.draw_rect(
		Rect2(band.position.x, band.position.y + thickness, band.size.x, thickness * 0.5), FRAME
	)
	var roll := 0.0
	while roll < 7.0:
		var p: Vector2 = project.call(roll, 0.0)
		if p.x > stage.position.x - 20.0 and p.x < stage.position.x + stage.size.x + 20.0:
			c.draw_circle(
				Vector2(p.x, band.position.y + thickness * 1.25),
				thickness * 0.34,
				Color(0.62, 0.47, 0.36)
			)
		roll += 0.5
	# Stützbeine
	var leg := 0.5
	while leg < 6.5:
		var p: Vector2 = project.call(leg, 0.0)
		if p.x > stage.position.x - 20.0 and p.x < stage.position.x + stage.size.x + 20.0:
			c.draw_line(
				Vector2(p.x, band.position.y + thickness * 1.5),
				Vector2(p.x, band.position.y + thickness * 1.5 + ppm * 0.5),
				Color(0.66, 0.5, 0.39),
				maxf(2.0, ppm * 0.035)
			)
		leg += 1.5


## Ofentunnel über [OVEN_START_S, OVEN_END_S]; `heat` 0..1 färbt das Sichtfenster.
static func draw_oven(
	c: CanvasItem, project: Callable, ppm: float, s0: float, s1: float, heat: float
) -> void:
	var left: Vector2 = project.call(s0, 0.0)
	var right: Vector2 = project.call(s1, 0.0)
	var h := ppm * 0.86
	var body := Rect2(left.x, left.y - h, right.x - left.x, h)
	c.draw_rect(body, Color(0.93, 0.62, 0.44))
	c.draw_rect(Rect2(body.position, Vector2(body.size.x, h * 0.22)), Color(0.85, 0.52, 0.36))
	c.draw_rect(body, Color(0.68, 0.4, 0.28), false, maxf(2.0, ppm * 0.02))
	# Sichtfenster
	var win := Rect2(
		body.position + Vector2(body.size.x * 0.12, h * 0.34), Vector2(body.size.x * 0.76, h * 0.44)
	)
	c.draw_rect(win, Color(0.24, 0.16, 0.14))
	c.draw_rect(win, Color(1.0, 0.62 + 0.2 * heat, 0.32, 0.35 + 0.45 * heat))
	c.draw_rect(win, Color(0.55, 0.32, 0.22), false, maxf(1.5, ppm * 0.015))
	# Ein-/Ausfahrtsvorhänge
	for x in [left.x, right.x]:
		c.draw_rect(
			Rect2(float(x) - ppm * 0.02, left.y - h * 0.32, ppm * 0.04, h * 0.32),
			Color(0.72, 0.44, 0.3)
		)
	# Schornstein
	c.draw_rect(
		Rect2(
			body.position + Vector2(body.size.x * 0.72, -h * 0.22), Vector2(ppm * 0.16, h * 0.22)
		),
		Color(0.78, 0.47, 0.33)
	)
	if heat > 0.05:
		for i in 3:
			var t := float(i) / 3.0
			c.draw_circle(
				body.position + Vector2(body.size.x * 0.8, -h * (0.26 + t * 0.3)),
				ppm * (0.05 + t * 0.03),
				Color(0.92, 0.86, 0.82, (0.32 - t * 0.09) * heat)
			)


## Formentrichter über der Spawn-Marke.
static func draw_spawn(c: CanvasItem, project: Callable, ppm: float, s: float, ready: bool) -> void:
	var base: Vector2 = project.call(s, 0.0)
	var col := Color(0.55, 0.75, 0.88) if ready else Color(0.72, 0.7, 0.72)
	var top := base.y - ppm * 1.0
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(base.x - ppm * 0.42, top),
					Vector2(base.x + ppm * 0.42, top),
					Vector2(base.x + ppm * 0.14, top + ppm * 0.4),
					Vector2(base.x - ppm * 0.14, top + ppm * 0.4),
				]
			),
			col
		)
	)
	c.draw_rect(
		Rect2(base.x - ppm * 0.14, top + ppm * 0.4, ppm * 0.28, ppm * 0.18), col.darkened(0.15)
	)
	c.draw_line(
		Vector2(base.x, base.y - ppm * 0.02),
		Vector2(base.x, base.y - ppm * 0.2),
		Color(1.0, 1.0, 1.0, 0.4),
		maxf(1.5, ppm * 0.02)
	)


## Versandkiste am rechten Bandende inkl. Fangzone.
static func draw_ship(
	c: CanvasItem, project: Callable, ppm: float, s: float, half: float, armed: bool
) -> void:
	var z0: Vector2 = project.call(s - half, 0.0)
	var z1: Vector2 = project.call(s + half, 0.0)
	var zone := Rect2(z0.x, z0.y - ppm * 0.06, z1.x - z0.x, ppm * 0.06)
	c.draw_rect(zone, Color(0.42, 0.76, 0.5, 0.75) if armed else Color(0.8, 0.78, 0.74, 0.55))
	var base: Vector2 = project.call(s, 0.0)
	var w := ppm * 0.62
	var h := ppm * 0.52
	var box := Rect2(base.x - w * 0.5, base.y - h - ppm * 0.06, w, h)
	c.draw_rect(box, Color(0.85, 0.66, 0.45))
	c.draw_rect(box, Color(0.62, 0.45, 0.3), false, maxf(1.5, ppm * 0.018))
	c.draw_line(
		box.position + Vector2(0.0, h * 0.34),
		box.position + Vector2(w, h * 0.34),
		Color(0.95, 0.6, 0.72),
		maxf(2.0, ppm * 0.03)
	)
	c.draw_line(
		box.position + Vector2(w * 0.5, 0.0),
		box.position + Vector2(w * 0.5, h),
		Color(0.95, 0.6, 0.72),
		maxf(2.0, ppm * 0.03)
	)


## Die 10 Düsen (§G1.5) mit Sperrbalken und Farbtupfer.
static func draw_nozzles(
	c: CanvasItem, project: Callable, ppm: float, stations: Array, lockouts: Dictionary
) -> void:
	var rail: Vector2 = project.call(0.0, RAIL_Y)
	c.draw_line(
		Vector2(-4000.0, rail.y),
		Vector2(4000.0, rail.y),
		Color(0.72, 0.65, 0.62),
		maxf(3.0, ppm * 0.05)
	)
	for st: Dictionary in stations:
		if not bool(st["drop"]):
			continue
		var id := str(st["id"])
		var head: Vector2 = project.call(float(st["s"]), NOZZLE_Y)
		var tint := nozzle_color(st)
		var locked := float(lockouts.get(id, 0.0)) > 0.0
		c.draw_line(
			Vector2(head.x, rail.y),
			Vector2(head.x, head.y - ppm * 0.1),
			Color(0.68, 0.61, 0.58),
			maxf(2.0, ppm * 0.035)
		)
		var cup := PackedVector2Array(
			[
				Vector2(head.x - ppm * 0.14, head.y - ppm * 0.14),
				Vector2(head.x + ppm * 0.14, head.y - ppm * 0.14),
				Vector2(head.x + ppm * 0.05, head.y),
				Vector2(head.x - ppm * 0.05, head.y),
			]
		)
		c.draw_colored_polygon(cup, tint.darkened(0.25) if locked else tint)
		c.draw_circle(Vector2(head.x, head.y - ppm * 0.19), ppm * 0.075, tint.lightened(0.2))
		# Lotlinie: zeigt, wo der Tropfen landet.
		var floor_pt: Vector2 = project.call(float(st["s"]), 0.0)
		c.draw_dashed_line(
			Vector2(head.x, head.y + 2.0),
			Vector2(head.x, floor_pt.y),
			Color(tint.r, tint.g, tint.b, 0.3),
			maxf(1.0, ppm * 0.012),
			maxf(3.0, ppm * 0.05)
		)


## Farbe einer Station (Teig/Guss/Deko/Kerzenwachs) — Web `stationHex`.
static func nozzle_color(st: Dictionary) -> Color:
	var kind := str(st["kind"])
	if kind == "teig":
		return Cake.SPONGE[str(st["value"])]
	if kind == "guss":
		return Cake.ICING[str(st["value"])]
	if kind == "deko":
		return Cake.DEKO[str(st["value"])]
	return Color(0.969, 0.906, 0.784)


## Ein fallender Tropfen zwischen Düse und Band.
static func draw_drop(
	c: CanvasItem, project: Callable, ppm: float, st: Dictionary, frac: float
) -> void:
	var y := NOZZLE_Y * (1.0 - clampf(frac, 0.0, 1.0))
	var p: Vector2 = project.call(float(st["s"]), y + 0.06)
	var tint := nozzle_color(st)
	var r := ppm * 0.075
	c.draw_circle(p, r, tint)
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(p.x - r * 0.8, p.y - r * 0.2),
					Vector2(p.x + r * 0.8, p.y - r * 0.2),
					Vector2(p.x, p.y - r * 2.2),
				]
			),
			tint
		)
	)
	c.draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.3, Color(1.0, 1.0, 1.0, 0.45))


## Klecks auf dem Band (−2 Punkte, verschwindet nach SPLAT_TTL_SEC).
static func draw_splat(
	c: CanvasItem, project: Callable, ppm: float, splat: Dictionary, ttl_max: float
) -> void:
	var p: Vector2 = project.call(float(splat["s"]), 0.0)
	var fade := clampf(float(splat["ttl"]) / ttl_max, 0.0, 1.0)
	var col := Color(0.62, 0.44, 0.36, 0.35 + 0.4 * fade)
	for i in 5:
		var a := float(i) * 1.3
		c.draw_circle(
			Vector2(p.x + cos(a) * ppm * 0.09, p.y - ppm * 0.01 + sin(a) * ppm * 0.02),
			ppm * (0.035 + 0.02 * ((i * 2) % 3)),
			col
		)


## Gooby am Pult links neben dem Band.
static func draw_gooby(c: CanvasItem, at: Vector2, size: float, cheer: float) -> void:
	var bob := sin(cheer * 8.0) * size * 0.06
	c.draw_circle(at + Vector2(0.0, size * 0.9), size * 0.75, Color(0.0, 0.0, 0.0, 0.12))
	# Pult
	c.draw_rect(
		Rect2(at + Vector2(-size * 0.7, size * 0.35), Vector2(size * 1.4, size * 0.8)),
		Color(0.86, 0.68, 0.5)
	)
	var head := at + Vector2(0.0, bob)
	c.draw_circle(head, size * 0.62, Color(0.996, 0.906, 0.671))
	c.draw_circle(head + Vector2(-size * 0.62, -size * 0.1), size * 0.2, Color(0.984, 0.855, 0.6))
	c.draw_circle(head + Vector2(size * 0.62, -size * 0.1), size * 0.2, Color(0.984, 0.855, 0.6))
	# Bäckermütze
	c.draw_rect(
		Rect2(head + Vector2(-size * 0.5, -size * 0.78), Vector2(size, size * 0.2)),
		Color(1.0, 0.98, 0.95)
	)
	for i in 3:
		c.draw_circle(
			head + Vector2((i - 1) * size * 0.34, -size * 0.9), size * 0.26, Color(1.0, 0.98, 0.95)
		)
	c.draw_circle(head + Vector2(-size * 0.21, -size * 0.06), size * 0.075, Color(0.2, 0.16, 0.14))
	c.draw_circle(head + Vector2(size * 0.21, -size * 0.06), size * 0.075, Color(0.2, 0.16, 0.14))
	c.draw_arc(
		head + Vector2(0.0, size * 0.12),
		size * 0.22,
		0.35,
		PI - 0.35,
		14,
		Color(0.2, 0.16, 0.14),
		maxf(1.5, size * 0.055)
	)
	c.draw_circle(
		head + Vector2(-size * 0.42, size * 0.14), size * 0.1, Color(0.98, 0.7, 0.72, 0.6)
	)
	c.draw_circle(head + Vector2(size * 0.42, size * 0.14), size * 0.1, Color(0.98, 0.7, 0.72, 0.6))


## Übersichtsstreifen: das GANZE Band (0…6 m) mit Stationen, Ofen, Versand,
## den Formen und dem Ausschnitt, den die Bühne gerade zeigt.
static func draw_overview(
	c: CanvasItem, rect: Rect2, line: Dictionary, tune: Dictionary, cam_s: float, window: float
) -> void:
	var length := float(tune["BELT_LENGTH_M"])
	var to_x := func(s: float) -> float: return rect.position.x + (s / length) * rect.size.x
	var lw := maxf(2.0, rect.size.y * 0.1)
	c.draw_rect(rect, Color(0.93, 0.87, 0.81))
	c.draw_rect(rect, Color(0.62, 0.5, 0.44), false, lw)
	# Ofenzone + Versandzone
	var o0: float = to_x.call(float(tune["OVEN_START_S"]))
	var o1: float = to_x.call(float(tune["OVEN_END_S"]))
	c.draw_rect(Rect2(o0, rect.position.y, o1 - o0, rect.size.y), Color(0.95, 0.66, 0.45, 0.55))
	var v0: float = to_x.call(float(tune["SHIP_S"]) - float(tune["SHIP_HALF_M"]))
	var v1: float = to_x.call(float(tune["SHIP_S"]) + float(tune["SHIP_HALF_M"]))
	c.draw_rect(Rect2(v0, rect.position.y, v1 - v0, rect.size.y), Color(0.46, 0.76, 0.52, 0.75))
	# Stationsmarken
	for st: Dictionary in Logic.STATIONS:
		if not bool(st["drop"]):
			continue
		var x: float = to_x.call(float(st["s"]))
		c.draw_line(
			Vector2(x, rect.position.y + lw),
			Vector2(x, rect.position.y + rect.size.y - lw),
			nozzle_color(st).darkened(0.1),
			lw * 1.6
		)
	# Kamerafenster
	var c0: float = to_x.call(maxf(0.0, cam_s - window * 0.5))
	var c1: float = to_x.call(minf(length, cam_s + window * 0.5))
	c.draw_rect(Rect2(c0, rect.position.y, c1 - c0, rect.size.y), Color(1.0, 1.0, 1.0, 0.28))
	c.draw_rect(
		Rect2(c0, rect.position.y, c1 - c0, rect.size.y), Color(0.24, 0.2, 0.28), false, lw * 1.2
	)
	# Formen
	for pan: Dictionary in line["pans"]:
		var x: float = to_x.call(float(pan["s"]))
		var col := Cake.sponge_color(pan["sponge"], pan["bake"])
		c.draw_circle(Vector2(x, rect.position.y + rect.size.y * 0.5), rect.size.y * 0.34, col)
		c.draw_arc(
			Vector2(x, rect.position.y + rect.size.y * 0.5),
			rect.size.y * 0.34,
			0.0,
			TAU,
			16,
			Color(0.3, 0.24, 0.22),
			lw
		)
