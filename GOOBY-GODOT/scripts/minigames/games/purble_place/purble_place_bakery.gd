extends RefCounted
## Rest-Zeichenhilfen der Tortenwerkstatt. Die KULISSE (Wand, Band, Ofen, Düsen,
## Tropfen, Kleckse, Gäste, Gooby) steht seit dem 3D-Rückbau als echte Requisite
## in `purble_place_stage3d.gd` — hier bleibt nur, was Zahlenwerk ist:
##
##   nozzle_color(st) — Farbschlüssel einer Station (Düsenkopf, Dock-Knopf,
##                      Übersichtsmarke); Web `stationHex`
##   draw_overview(…)  — der Streifen unter der Bühne, der das GANZE Band zeigt

const Cake := preload("res://scripts/minigames/games/purble_place/purble_place_cake.gd")
const Logic := preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd")


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
