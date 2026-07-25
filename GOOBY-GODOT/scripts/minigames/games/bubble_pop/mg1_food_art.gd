class_name Mg1FoodArt
extends RefCounted
## Gezeichnete Leckereien für die MG-1-Spiele (bubblePop, memoryMatch).
## Reine Optik, KEINE Spiellogik: `draw(ci, key, center, r, tint)` malt die
## Silhouette einer Sorte in ein beliebiges CanvasItem. Die Schriftglyphen der
## ersten Fassung (▲ ● ◆ …) waren im Flug nicht unterscheidbar und fehlen im
## Baloo-Schnitt teils ganz — deshalb echte Formen.

## Grundfarbe je Sorte (Web-Palette der Food-Kit-Modelle).
const TINTS := {
	"carrot": Color("F2913D"),
	"apple": Color("E4574C"),
	"banana": Color("F2D06B"),
	"cheese": Color("F5C445"),
	"watermelon": Color("6FBF73"),
	"donut-sprinkles": Color("EE86B7"),
	"cupcake": Color("C58CE0"),
	"burger": Color("C98A4B"),
	"ice-cream": Color("9FD8E8"),
	"pizza": Color("E88A4E"),
	"cake": Color("F3B6C7"),
	"strawberry": Color("E05068"),
}

const _LEAF := Color("6DB54E")
const _STEM := Color("6B4A2E")


static func tint_of(key: String) -> Color:
	return TINTS.get(key, Color("F5C445"))


## Malt die Sorte `key` zentriert um `center` mit Radius `r`.
static func draw(canvas: CanvasItem, key: String, center: Vector2, r: float) -> void:
	var tint := tint_of(key)
	var ink := AcTokens.INK
	match key:
		"carrot":
			_carrot(canvas, center, r, tint)
		"apple":
			_apple(canvas, center, r, tint)
		"banana":
			_banana(canvas, center, r, tint, ink)
		"cheese":
			_cheese(canvas, center, r, tint)
		"watermelon":
			_watermelon(canvas, center, r, tint, ink)
		"donut-sprinkles":
			_donut(canvas, center, r, tint, ink)
		"cupcake":
			_cupcake(canvas, center, r, tint)
		"burger":
			_burger(canvas, center, r)
		"ice-cream":
			_ice_cream(canvas, center, r, tint)
		"pizza":
			_pizza(canvas, center, r, tint)
		"cake":
			_cake(canvas, center, r, tint, ink)
		"strawberry":
			_strawberry(canvas, center, r, tint)
		_:
			canvas.draw_circle(center, r * 0.9, tint)
			canvas.draw_arc(center, r * 0.9, 0.0, TAU, 22, ink, 2.5)


static func _carrot(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-r * 0.58, -r * 0.45),
				c + Vector2(r * 0.58, -r * 0.45),
				c + Vector2(0.0, r * 1.1)
			]
		),
		tint
	)
	canvas.draw_line(
		c + Vector2(-r * 0.3, -r * 0.1), c + Vector2(-r * 0.1, -r * 0.02), tint.darkened(0.2), 3.0
	)
	for k in 3:
		var dx := (float(k) - 1.0) * r * 0.32
		canvas.draw_line(c + Vector2(dx, -r * 0.45), c + Vector2(dx * 1.5, -r * 1.1), _LEAF, 6.0)


static func _apple(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_circle(c + Vector2(-r * 0.24, r * 0.12), r * 0.66, tint)
	canvas.draw_circle(c + Vector2(r * 0.24, r * 0.12), r * 0.66, tint)
	canvas.draw_line(c + Vector2(0.0, -r * 0.45), c + Vector2(r * 0.1, -r * 1.05), _STEM, 5.0)
	canvas.draw_circle(c + Vector2(r * 0.4, -r * 0.92), r * 0.22, _LEAF)


static func _banana(canvas: CanvasItem, c: Vector2, r: float, tint: Color, ink: Color) -> void:
	var arc := PackedVector2Array()
	for i in 13:
		var a := lerpf(PI * 0.12, PI * 0.88, float(i) / 12.0)
		arc.append(c + Vector2(cos(a), sin(a)) * r * 1.0 - Vector2(0.0, r * 0.28))
	canvas.draw_polyline(arc, ink, r * 0.48)
	canvas.draw_polyline(arc, tint, r * 0.34)


static func _cheese(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-r * 0.95, r * 0.6),
				c + Vector2(r * 0.95, r * 0.6),
				c + Vector2(r * 0.95, -r * 0.2),
				c + Vector2(-r * 0.95, -r * 0.72)
			]
		),
		tint
	)
	canvas.draw_circle(c + Vector2(-r * 0.3, r * 0.16), r * 0.16, tint.darkened(0.28))
	canvas.draw_circle(c + Vector2(r * 0.4, r * 0.3), r * 0.12, tint.darkened(0.28))


static func _watermelon(canvas: CanvasItem, c: Vector2, r: float, tint: Color, ink: Color) -> void:
	var rind := PackedVector2Array()
	var flesh := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var a := lerpf(PI, TAU, float(i) / float(steps))
		rind.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0.0, r * 0.5))
		flesh.append(c + Vector2(cos(a), sin(a)) * r * 0.8 + Vector2(0.0, r * 0.5))
	canvas.draw_colored_polygon(rind, tint)
	canvas.draw_colored_polygon(flesh, Color("F4736F"))
	canvas.draw_polyline(rind, ink, 2.5)
	for k in 3:
		canvas.draw_circle(c + Vector2((float(k) - 1.0) * r * 0.36, r * 0.06), r * 0.09, ink)


static func _donut(canvas: CanvasItem, c: Vector2, r: float, tint: Color, ink: Color) -> void:
	canvas.draw_circle(c, r * 0.95, Color("E8C39A"))
	canvas.draw_circle(c, r * 0.8, tint)
	canvas.draw_circle(c, r * 0.3, AcTokens.PAPER)
	canvas.draw_arc(c, r * 0.95, 0.0, TAU, 24, ink, 2.5)
	canvas.draw_arc(c, r * 0.3, 0.0, TAU, 16, ink, 2.0)
	for k in 6:
		var a := float(k) * TAU / 6.0 + 0.4
		var at := c + Vector2(cos(a), sin(a)) * r * 0.58
		canvas.draw_line(
			at - Vector2(r * 0.12, r * 0.06), at + Vector2(r * 0.12, r * 0.06), AcTokens.WHITE, 3.0
		)


static func _cupcake(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-r * 0.68, -r * 0.05),
				c + Vector2(r * 0.68, -r * 0.05),
				c + Vector2(r * 0.44, r * 1.0),
				c + Vector2(-r * 0.44, r * 1.0)
			]
		),
		Color("E8C39A")
	)
	canvas.draw_circle(c + Vector2(-r * 0.34, -r * 0.32), r * 0.42, tint)
	canvas.draw_circle(c + Vector2(r * 0.34, -r * 0.32), r * 0.42, tint)
	canvas.draw_circle(c + Vector2(0.0, -r * 0.6), r * 0.42, tint)
	canvas.draw_circle(c + Vector2(0.0, -r * 1.0), r * 0.16, AcTokens.PINK)


static func _burger(canvas: CanvasItem, c: Vector2, r: float) -> void:
	canvas.draw_circle(c + Vector2(0.0, -r * 0.16), r * 0.84, Color("E5A45C"))
	canvas.draw_rect(Rect2(c.x - r * 0.84, c.y - r * 0.16, r * 1.68, r * 0.26), Color("E5A45C"))
	canvas.draw_rect(Rect2(c.x - r * 0.9, c.y + r * 0.1, r * 1.8, r * 0.22), _LEAF)
	canvas.draw_rect(Rect2(c.x - r * 0.84, c.y + r * 0.32, r * 1.68, r * 0.3), Color("8A5A34"))
	canvas.draw_rect(Rect2(c.x - r * 0.84, c.y + r * 0.62, r * 1.68, r * 0.34), Color("E5A45C"))
	for k in 3:
		canvas.draw_circle(
			c + Vector2((float(k) - 1.0) * r * 0.34, -r * 0.62), r * 0.07, Color("FFF0C9")
		)


static func _ice_cream(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-r * 0.48, r * 0.05),
				c + Vector2(r * 0.48, r * 0.05),
				c + Vector2(0.0, r * 1.12)
			]
		),
		Color("D9A566")
	)
	canvas.draw_circle(c + Vector2(-r * 0.28, -r * 0.2), r * 0.44, tint)
	canvas.draw_circle(c + Vector2(r * 0.28, -r * 0.2), r * 0.44, AcTokens.PINK)
	canvas.draw_circle(c + Vector2(0.0, -r * 0.58), r * 0.42, Color("FFF0C9"))


static func _pizza(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(0.0, -r * 0.98),
				c + Vector2(r * 0.84, r * 0.86),
				c + Vector2(-r * 0.84, r * 0.86)
			]
		),
		Color("F5D98F")
	)
	canvas.draw_line(
		c + Vector2(-r * 0.84, r * 0.86), c + Vector2(r * 0.84, r * 0.86), tint, r * 0.32
	)
	canvas.draw_circle(c + Vector2(-r * 0.2, r * 0.2), r * 0.15, Color("D34B3C"))
	canvas.draw_circle(c + Vector2(r * 0.26, r * 0.42), r * 0.13, Color("D34B3C"))
	canvas.draw_circle(c + Vector2(r * 0.02, -r * 0.3), r * 0.12, Color("D34B3C"))


static func _cake(canvas: CanvasItem, c: Vector2, r: float, tint: Color, ink: Color) -> void:
	canvas.draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.08, r * 1.6, r * 0.95), Color("F6E2C4"))
	canvas.draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.4, r * 1.6, r * 0.32), tint)
	canvas.draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.4, r * 1.6, r * 1.27), ink, false, 2.5)
	canvas.draw_line(c + Vector2(0.0, -r * 0.44), c + Vector2(0.0, -r * 0.92), AcTokens.WHITE, 4.0)
	canvas.draw_circle(c + Vector2(0.0, -r * 1.02), r * 0.14, AcTokens.YELLOW)


static func _strawberry(canvas: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-r * 0.78, -r * 0.32),
				c + Vector2(r * 0.78, -r * 0.32),
				c + Vector2(0.0, r * 1.08)
			]
		),
		tint
	)
	canvas.draw_circle(c + Vector2(-r * 0.36, -r * 0.28), r * 0.44, tint)
	canvas.draw_circle(c + Vector2(r * 0.36, -r * 0.28), r * 0.44, tint)
	for k in 3:
		canvas.draw_line(
			c + Vector2((float(k) - 1.0) * r * 0.38, -r * 0.48),
			c + Vector2((float(k) - 1.0) * r * 0.6, -r * 0.92),
			_LEAF,
			6.0
		)
	for k in 4:
		var sx := (float(k % 2) - 0.5) * r * 0.56
		canvas.draw_circle(
			c + Vector2(sx, r * 0.08 + float(k) * r * 0.17), r * 0.07, Color("FFE9B0")
		)
