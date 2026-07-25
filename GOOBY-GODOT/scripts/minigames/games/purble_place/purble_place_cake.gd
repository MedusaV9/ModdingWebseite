extends RefCounted
## Tortenmaler der Werkstatt: EINE Zeichenroutine für die Formen auf dem Band
## UND für die Auftragskärtchen im HUD — so sieht der Auftrag exakt aus wie
## das, was hinten herauskommen soll (§C9.2-Merkmale: Form, Teig, Guss, Deko,
## Kerzen, Backgrad). Die Farbwerte sind verbatim aus GOOBY/src/minigames/
## games/purblePlace.js (SPONGE_HEX / ICING_HEX / DEKO_HEX / SPRINKLE_COLORS).
##
## 2D-Sticker statt three.js: die Torte wird als flache 3/4-Ansicht gemalt —
## eine gestauchte Deckfläche (die trägt die FORM) auf einer geraden Seitenwand
## (die trägt den TEIG + Backgrad). Alle Umrisse bestehen aus Kreisen, Rechtecken
## und konvexen Polygonen, damit Godots Triangulierung nie aussteigen kann.

const SPONGE := {
	"vanilla": Color(0.961, 0.902, 0.784),
	"chocolate": Color(0.42, 0.29, 0.184),
	"strawberry": Color(0.949, 0.722, 0.776),
}
const ICING := {
	"white": Color(1.0, 0.973, 0.941),
	"pink": Color(0.969, 0.506, 0.69),
	"chocolate": Color(0.306, 0.208, 0.141),
}
const DEKO := {
	"cherry": Color(0.839, 0.161, 0.227),
	"sprinkles": Color(0.961, 0.773, 0.094),
	"berries": Color(0.894, 0.251, 0.373),
}
const SPRINKLES: Array[Color] = [
	Color(0.894, 0.341, 0.18),
	Color(0.961, 0.773, 0.094),
	Color(0.298, 0.71, 0.682),
	Color(0.702, 0.498, 0.831),
	Color(0.486, 0.757, 0.369),
	Color(0.969, 0.506, 0.69),
]

## Blechfarbe einer noch teiglosen Form.
const EMPTY_PAN := Color(0.78, 0.76, 0.79)
const OUTLINE := Color(0.35, 0.26, 0.22, 0.55)


## Sichtbarer Teigton inklusive Backgrad.
static func sponge_color(sponge: Variant, bake: Variant) -> Color:
	if sponge == null:
		return EMPTY_PAN
	var base: Color = SPONGE.get(str(sponge), EMPTY_PAN)
	match str(bake) if bake != null else "":
		"pale":
			return base.lightened(0.18)
		"over":
			return base.darkened(0.22)
		"singed":
			return base.darkened(0.62).lerp(Color(0.16, 0.13, 0.12), 0.45)
		_:
			return base


## Eine Torte zeichnen. `cake` ist eine Bandform ODER eine Auftrags-Spec
## ({shape, sponge, icing, topping, candles}); `w` ist die volle Breite.
static func draw_cake(c: CanvasItem, center: Vector2, w: float, cake: Dictionary) -> void:
	var shape := str(cake.get("shape", "round"))
	var body := sponge_color(cake.get("sponge", null), cake.get("bake", null))
	var wall_h := w * 0.34
	var top := center - Vector2(0.0, wall_h * 0.5)

	# Seitenwand (Teig) — ein gerader Zylindermantel unter der Deckfläche.
	var wall := Rect2(top - Vector2(w * 0.5, 0.0), Vector2(w, wall_h))
	c.draw_rect(wall, body.darkened(0.12))
	c.draw_rect(Rect2(wall.position, Vector2(w, wall_h * 0.35)), body.darkened(0.04))
	# Tortenboden abrunden, damit kein Kasten stehen bleibt.
	_shape_fill(c, Vector2(top.x, top.y + wall_h), w, body.darkened(0.18), shape)

	# Deckfläche: Guss, sonst der blanke Teig.
	var icing: Variant = cake.get("icing", null)
	var has_icing := icing != null and str(icing) != "none"
	var top_col := body
	if has_icing:
		top_col = ICING[str(icing)]
	_shape_fill(c, top, w, top_col, shape)
	_shape_outline(c, top, w, shape, maxf(1.0, w * 0.035))
	if has_icing:
		# Zuckerguss-Nasen über den Rand der Wand.
		var drips := 4
		for i in drips:
			var f := (float(i) + 0.5) / drips
			var dx := (f - 0.5) * w * 0.78
			var dh := wall_h * (0.34 + 0.28 * absf(sin(f * 7.0)))
			c.draw_circle(Vector2(top.x + dx, top.y + dh * 0.5), w * 0.055, top_col)

	_draw_topping(c, top, w, str(cake.get("topping", "none")))
	_draw_candles(c, top, w, int(cake.get("candles", 0)))
	if str(cake.get("bake", "")) == "singed":
		_draw_smoke(c, top, w)


static func _draw_topping(c: CanvasItem, top: Vector2, w: float, topping: String) -> void:
	if topping == "cherry":
		var r := w * 0.11
		var p := top - Vector2(0.0, r * 0.5)
		c.draw_circle(p, r, DEKO["cherry"])
		c.draw_circle(p - Vector2(r * 0.3, r * 0.35), r * 0.28, Color(1.0, 1.0, 1.0, 0.55))
		c.draw_line(p - Vector2(0.0, r), p - Vector2(r * 0.5, r * 1.9), Color(0.35, 0.5, 0.24), 2.0)
	elif topping == "sprinkles":
		for i in 7:
			var a := float(i) * 0.9
			var off := Vector2(cos(a), sin(a) * 0.42) * w * (0.12 + 0.06 * ((i * 3) % 3))
			c.draw_line(
				top + off,
				top + off + Vector2(w * 0.05, w * 0.02 * (1 if i % 2 == 0 else -1)),
				SPRINKLES[i % SPRINKLES.size()],
				maxf(1.5, w * 0.03)
			)
	elif topping == "berries":
		for i in 3:
			var off := Vector2((i - 1) * w * 0.19, (0.02 if i == 1 else 0.06) * w)
			c.draw_circle(top + off, w * 0.075, DEKO["berries"])
			c.draw_circle(
				top + off - Vector2(w * 0.02, w * 0.025), w * 0.024, Color(1.0, 1.0, 1.0, 0.5)
			)


static func _draw_candles(c: CanvasItem, top: Vector2, w: float, candles: int) -> void:
	if candles <= 0:
		return
	var h := w * 0.32
	for i in candles:
		var f := (float(i) + 0.5) / candles
		var x := top.x + (f - 0.5) * w * 0.62
		var y := top.y - w * 0.02
		c.draw_line(Vector2(x, y), Vector2(x, y - h), Color(0.98, 0.95, 0.86), maxf(1.5, w * 0.045))
		c.draw_line(
			Vector2(x, y - h * 0.55),
			Vector2(x, y - h * 0.75),
			Color(0.95, 0.55, 0.66),
			maxf(1.5, w * 0.045)
		)
		c.draw_circle(Vector2(x, y - h - w * 0.03), w * 0.045, Color(1.0, 0.78, 0.28))
		c.draw_circle(Vector2(x, y - h - w * 0.04), w * 0.022, Color(1.0, 0.96, 0.7))


static func _draw_smoke(c: CanvasItem, top: Vector2, w: float) -> void:
	for i in 3:
		var t := float(i) / 3.0
		c.draw_circle(
			top + Vector2(sin(t * 5.0) * w * 0.16, -w * (0.3 + t * 0.36)),
			w * (0.08 + t * 0.05),
			Color(0.44, 0.42, 0.44, 0.35 - t * 0.09)
		)


## Deckflächen-Umriss je Form (immer konvexe Teilstücke).
static func _shape_fill(c: CanvasItem, at: Vector2, w: float, col: Color, shape: String) -> void:
	var h := w * 0.5
	if shape == "square":
		c.draw_rect(Rect2(at - Vector2(w * 0.5, h * 0.5), Vector2(w, h)), col)
		return
	if shape == "heart":
		var r := w * 0.26
		c.draw_circle(at + Vector2(-r * 0.92, -h * 0.12), r, col)
		c.draw_circle(at + Vector2(r * 0.92, -h * 0.12), r, col)
		(
			c
			. draw_colored_polygon(
				PackedVector2Array(
					[
						at + Vector2(-w * 0.47, -h * 0.1),
						at + Vector2(w * 0.47, -h * 0.1),
						at + Vector2(0.0, h * 0.58),
					]
				),
				col
			)
		)
		return
	c.draw_colored_polygon(_ellipse(at, w * 0.5, h * 0.5), col)


static func _shape_outline(
	c: CanvasItem, at: Vector2, w: float, shape: String, width: float
) -> void:
	var h := w * 0.5
	if shape == "square":
		c.draw_rect(Rect2(at - Vector2(w * 0.5, h * 0.5), Vector2(w, h)), OUTLINE, false, width)
	elif shape == "round":
		var pts := _ellipse(at, w * 0.5, h * 0.5)
		pts.append(pts[0])
		c.draw_polyline(pts, OUTLINE, width)


static func _ellipse(at: Vector2, rx: float, ry: float, steps := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / steps
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Wunschblase eines Gastes: Zieltorte + Geduldsbalken. `tail` zeichnet die
## Sprechblasen-Spitze nach unten zum Gast.
static func draw_ticket_card(
	c: CanvasItem, rect: Rect2, ticket: Dictionary, font: Font, highlight: bool, tail := false
) -> void:
	var frac := clampf(float(ticket["remain"]) / maxf(0.001, float(ticket["patience"])), 0.0, 1.0)
	var card := Color(1.0, 0.98, 0.95, 0.96)
	var edge := Color(0.96, 0.55, 0.7) if highlight else Color(0.78, 0.66, 0.6)
	var lw := maxf(2.0, rect.size.x * 0.026)
	if tail:
		var base_y := rect.position.y + rect.size.y - lw
		var left := Vector2(rect.position.x + rect.size.x * 0.34, base_y)
		var right := Vector2(rect.position.x + rect.size.x * 0.6, base_y)
		var point := Vector2(rect.position.x + rect.size.x * 0.4, base_y + rect.size.y * 0.16)
		c.draw_colored_polygon(PackedVector2Array([left, right, point]), card)
		c.draw_line(left, point, edge, lw)
		c.draw_line(right, point, edge, lw)
	c.draw_rect(rect, card)
	c.draw_rect(rect, edge, false, lw)
	var spec: Dictionary = ticket["spec"]
	var cake_w := minf(rect.size.x * 0.62, rect.size.y * 0.62)
	draw_cake(
		c,
		Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.46),
		cake_w,
		spec
	)
	# Geduldsbalken: grün → gelb → rot.
	var bar_h := rect.size.y * 0.07
	var bar := Rect2(
		rect.position + Vector2(rect.size.x * 0.06, rect.size.y - bar_h * 1.9),
		Vector2(rect.size.x * 0.88, bar_h)
	)
	c.draw_rect(bar, Color(0.86, 0.83, 0.8))
	var col := Color(0.85, 0.28, 0.28).lerp(Color(0.98, 0.76, 0.2), minf(1.0, frac * 2.0))
	if frac > 0.5:
		col = Color(0.98, 0.76, 0.2).lerp(Color(0.36, 0.72, 0.4), (frac - 0.5) * 2.0)
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	if int(spec["candles"]) > 0:
		var pt := int(clampf(rect.size.x * 0.15, 11.0, 30.0))
		c.draw_string(
			font,
			rect.position + Vector2(rect.size.x * 0.06, pt * 1.2),
			"%d×" % int(spec["candles"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x * 0.88,
			pt,
			Color(0.45, 0.34, 0.3)
		)
