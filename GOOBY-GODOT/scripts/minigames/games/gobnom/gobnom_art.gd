class_name GobnomArt
extends RefCounted
## Prozedurale Sticker-Optik für GOB NOM (Doc G §5): cream Gooby mit weit
## offenem Mund (Ziel), gewickeltes Bonbon, NUTELLA-Gläser, Seile, Blasen,
## Luftkissen, Ventilatoren, Stachelbretter, Zuckerwatte-Wolken und
## Seil-Schießer — dick umrandet, pastellig, als Polygone/Kreise gezeichnet
## (keine Textur-Assets; gleiche Bildsprache wie GvzArt, eigene Konstanten,
## damit die Shared-File-Regel gewahrt bleibt). Alle Funktionen zeichnen auf
## einen CanvasItem in WELT-Koordinaten; `tick` treibt die Wackel-Animation.

const OUTLINE := Color("#4A3B36")
const CREAM := Color("#F9EDD6")
const CREAM_DARK := Color("#EFDDBC")
const EAR_PINK := Color("#F6BFC0")
const CHEEK := Color(0.96, 0.63, 0.6, 0.85)
const MOUTH_RED := Color("#B5766F")
const TONGUE := Color("#E89A94")
const NUTELLA := Color("#5C3A21")
const NUTELLA_LID := Color("#E8E2D8")
const CANDY_PINK := Color("#F2A0B5")
const CANDY_WRAP := Color("#FFE9F0")
const ROPE_BROWN := Color("#A9744B")
const BUBBLE_BLUE := Color(0.62, 0.82, 0.95, 0.55)
const BUBBLE_RIM := Color(0.45, 0.68, 0.88, 0.9)
const CUSHION_TEAL := Color("#9FD8CF")
const FAN_METAL := Color("#9DA6AD")
const WIND := Color(0.72, 0.84, 0.92, 0.7)
const SPIKE_GRAY := Color("#8C8C94")
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const CLOUD_PINK := Color(0.99, 0.87, 0.93, 0.92)
const STAR_GOLD := Color("#FFD34D")
const RAIL_GRAY := Color("#C9BCA9")

const OUT_W := 0.055

## ── Gooby-Mund (Ziel-Zone) ───────────────────────────────────────────────


## Gooby von unten ins Bild ragend, Mund weit offen Richtung Bonbon.
## `mood`: open (wartet) | nom (frisst, Sieg) | sad (verloren).
static func draw_gooby_mouth(
	ci: CanvasItem, pos: Vector2, s: float, tick := 0, mood := "open"
) -> void:
	var wob := sin(float(tick) * 0.18) * 0.03
	var ow := s * OUT_W
	var head := pos + Vector2(0, s * 0.30)
	_ear(ci, head + Vector2(-s * 0.34, -s * 0.10), s, -0.55 + wob)
	_ear(ci, head + Vector2(s * 0.34, -s * 0.10), s, 2.45 - wob)
	# Körper unter dem Kopf (ragt aus dem Boden).
	_blob(ci, head + Vector2(0, s * 0.42), s * 0.46, s * 0.40, CREAM, ow)
	_blob(ci, head, s * 0.42, s * 0.38, CREAM, ow)
	var eye_y := head + Vector2(0, -s * 0.16)
	match mood:
		"nom":
			# Zugekniffene Freude-Augen + praller Mund.
			for side: int in [-1, 1]:
				var e := eye_y + Vector2(s * 0.16 * side, 0)
				ci.draw_arc(e, s * 0.06, PI + 0.3, TAU - 0.3, 8, OUTLINE, s * 0.028)
			ci.draw_circle(head + Vector2(0, s * 0.10), s * 0.16 + ow * 0.7, OUTLINE)
			ci.draw_circle(head + Vector2(0, s * 0.10), s * 0.16, MOUTH_RED)
			ci.draw_circle(head + Vector2(0, s * 0.16), s * 0.09, TONGUE)
		"sad":
			for side: int in [-1, 1]:
				var e := eye_y + Vector2(s * 0.16 * side, 0)
				ci.draw_circle(e, s * 0.05, OUTLINE)
				ci.draw_line(
					e + Vector2(-s * 0.055 * side, -s * 0.085),
					e + Vector2(s * 0.05 * side, -s * 0.05),
					OUTLINE,
					s * 0.024
				)
			ci.draw_arc(
				head + Vector2(0, s * 0.17), s * 0.09, PI + 0.4, TAU - 0.4, 10, OUTLINE, s * 0.03
			)
		_:
			for side: int in [-1, 1]:
				var e := eye_y + Vector2(s * 0.16 * side, 0)
				ci.draw_circle(e, s * 0.055, OUTLINE)
				ci.draw_circle(e + Vector2(-s * 0.018, -s * 0.018), s * 0.017, Color.WHITE)
			# Weit offener Warte-Mund (die Ziel-Zone!) + Zunge.
			var m := head + Vector2(0, s * 0.13)
			ci.draw_circle(m, s * 0.20 + ow * 0.7, OUTLINE)
			ci.draw_circle(m, s * 0.20, MOUTH_RED)
			_blob(ci, m + Vector2(0, s * 0.10), s * 0.12, s * 0.06, TONGUE, 0.0)
	ci.draw_circle(head + Vector2(-s * 0.30, s * 0.02), s * 0.065, CHEEK)
	ci.draw_circle(head + Vector2(s * 0.30, s * 0.02), s * 0.065, CHEEK)


## Schlappohr als gedrehte Ellipse (+ rosa Innenohr).
static func _ear(ci: CanvasItem, base: Vector2, s: float, angle: float) -> void:
	var dir := Vector2.DOWN.rotated(angle)
	var mid := base + dir * s * 0.24
	_rot_blob(ci, mid, s * 0.11, s * 0.27, angle, CREAM, s * OUT_W)
	_rot_blob(ci, mid + dir * s * 0.03, s * 0.055, s * 0.16, angle, EAR_PINK, 0.0)


## ── Bonbon + Sammelobjekte ───────────────────────────────────────────────


## Gewickeltes Bonbon (rosa Kugel + Wickel-Zipfel), rotiert leicht mit Fahrt.
static func draw_candy(ci: CanvasItem, pos: Vector2, r: float, tick := 0) -> void:
	var spin := float(tick) * 0.06
	for side: int in [-1, 1]:
		var tip := pos + Vector2(r * 1.55 * side, 0).rotated(spin * 0.3)
		var perp := Vector2(0, r * 0.5).rotated(spin * 0.3)
		var points := PackedVector2Array(
			[pos + perp * 0.4, tip + perp, tip - perp, pos - perp * 0.4]
		)
		ci.draw_colored_polygon(points, CANDY_WRAP)
		_outline_poly(ci, points, r * 0.14)
	ci.draw_circle(pos, r + r * 0.16, OUTLINE)
	ci.draw_circle(pos, r, CANDY_PINK)
	ci.draw_arc(pos, r * 0.62, spin, spin + PI * 0.9, 10, CANDY_WRAP, r * 0.22)
	ci.draw_circle(pos + Vector2(-r * 0.32, -r * 0.32), r * 0.18, Color(1, 1, 1, 0.55))


## NUTELLA-Glas (Stern-Äquivalent, Doc G §5.2) mit Deckel + Glanz.
static func draw_jar(ci: CanvasItem, pos: Vector2, r: float, tick := 0, taken := false) -> void:
	if taken:
		ci.draw_circle(pos, r * 0.3, Color(0.3, 0.25, 0.22, 0.18))
		return
	var bob := sin(float(tick) * 0.15 + pos.x * 0.05) * r * 0.08
	var c := pos + Vector2(0, bob)
	var ow := r * 0.14
	var body := Rect2(c + Vector2(-r * 0.72, -r * 0.55), Vector2(r * 1.44, r * 1.35))
	ci.draw_rect(body.grow(ow), OUTLINE)
	ci.draw_rect(body, NUTELLA)
	var lid := Rect2(c + Vector2(-r * 0.82, -r * 0.95), Vector2(r * 1.64, r * 0.5))
	ci.draw_rect(lid.grow(ow), OUTLINE)
	ci.draw_rect(lid, NUTELLA_LID)
	_blob(ci, c + Vector2(0, r * 0.05), r * 0.5, r * 0.32, Color(1, 1, 1, 0.92), 0.0)
	ci.draw_circle(c + Vector2(-r * 0.3, r * 0.5), r * 0.12, Color(1, 1, 1, 0.3))
	_star(ci, c + Vector2(r * 0.85, -r * 1.1), r * 0.3, STAR_GOLD, 0.0)


## ── Seile + Anker ────────────────────────────────────────────────────────


## Seil als leicht durchhängende Kette Anker→Bonbon (Verlet-Optik, rein
## visuell: Quadratische Bezier mit Durchhang abhängig von Spannung).
static func draw_rope(
	ci: CanvasItem, anchor: Vector2, candy: Vector2, rest: float, cut := false
) -> void:
	if cut:
		return
	var dist := anchor.distance_to(candy)
	var slack := clampf(1.0 - dist / maxf(rest, 1.0), 0.0, 1.0)
	var mid := (anchor + candy) * 0.5 + Vector2(0, slack * rest * 0.35)
	var points := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var p := anchor.lerp(mid, t).lerp(mid.lerp(candy, t), t)
		points.append(p)
	ci.draw_polyline(points, OUTLINE, 5.0)
	ci.draw_polyline(points, ROPE_BROWN, 2.6)


## Seil-Anker: Holz-Pin mit Öse.
static func draw_anchor(ci: CanvasItem, pos: Vector2, owner_tint := Color.TRANSPARENT) -> void:
	if owner_tint.a > 0.0:
		ci.draw_circle(pos, 15.0, owner_tint)
	ci.draw_circle(pos, 11.0, OUTLINE)
	ci.draw_circle(pos, 8.0, WOOD)
	ci.draw_circle(pos, 3.4, OUTLINE)


## Schiene eines Schiebe-Ankers.
static func draw_rail(ci: CanvasItem, from: Vector2, to: Vector2) -> void:
	ci.draw_line(from, to, OUTLINE, 7.0)
	ci.draw_line(from, to, RAIL_GRAY, 3.6)
	for p: Vector2 in [from, to]:
		ci.draw_circle(p, 5.0, OUTLINE)


## Seil-Schießer: Holzkiste mit Öse + gestrichelter Reichweiten-Kreis.
static func draw_shooter(ci: CanvasItem, pos: Vector2, radius: float, fired := false) -> void:
	if not fired:
		_dashed_circle(ci, pos, radius, Color(0.66, 0.55, 0.42, 0.5))
	var body := Rect2(pos + Vector2(-16, -13), Vector2(32, 26))
	ci.draw_rect(body.grow(3.0), OUTLINE)
	ci.draw_rect(body, WOOD if not fired else WOOD_DARK)
	ci.draw_circle(pos, 6.5, OUTLINE)
	ci.draw_circle(pos, 4.2, CREAM if not fired else WOOD)


## ── Interaktive Elemente ─────────────────────────────────────────────────


## Blase: transparent-blau mit Glanz; `holds` = trägt gerade das Bonbon.
static func draw_bubble(ci: CanvasItem, pos: Vector2, r: float, tick := 0, holds := false) -> void:
	var pulse := 1.0 + sin(float(tick) * 0.16) * 0.04
	var rr := r * pulse
	ci.draw_circle(pos, rr, BUBBLE_BLUE)
	ci.draw_arc(pos, rr, 0, TAU, 24, BUBBLE_RIM, 2.6)
	ci.draw_arc(pos, rr * 0.68, -2.3, -1.1, 8, Color(1, 1, 1, 0.8), rr * 0.12)
	if holds:
		ci.draw_arc(pos, rr + 4.0, 0, TAU, 24, Color(1, 1, 1, 0.4), 1.6)


## Luftkissen (Blasebalg): Keil + Puff-Richtungspfeil; ready = kann puffen.
static func draw_cushion(
	ci: CanvasItem,
	pos: Vector2,
	dir: Vector2,
	tick := 0,
	ready := true,
	owner_tint := Color.TRANSPARENT
) -> void:
	var angle := dir.angle()
	var squish := 1.0 + (sin(float(tick) * 0.2) * 0.06 if ready else 0.0)
	if owner_tint.a > 0.0:
		ci.draw_circle(pos, 30.0, owner_tint)
	_rot_blob(
		ci, pos, 26.0 * squish, 16.0 / squish, angle, CUSHION_TEAL if ready else RAIL_GRAY, 3.0
	)
	_rot_blob(ci, pos - dir * 16.0, 12.0, 12.0, angle, WOOD, 2.6)
	var tip := pos + dir * 34.0
	var perp := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([tip + dir * 12.0, tip + perp * 7.0, tip - perp * 7.0])
	ci.draw_colored_polygon(arrow, OUTLINE if ready else RAIL_GRAY)


## Ventilator: Gehäuse + Rotor (dreht wenn an) + Windlinien in Blasrichtung.
static func draw_fan(
	ci: CanvasItem,
	pos: Vector2,
	dir: Vector2,
	tick := 0,
	on := true,
	owner_tint := Color.TRANSPARENT
) -> void:
	if owner_tint.a > 0.0:
		ci.draw_circle(pos, 30.0, owner_tint)
	ci.draw_circle(pos, 22.0, OUTLINE)
	ci.draw_circle(pos, 18.5, FAN_METAL)
	var spin := float(tick) * (0.45 if on else 0.0)
	for i in 3:
		var a := spin + TAU * float(i) / 3.0
		_rot_blob(ci, pos + Vector2(11, 0).rotated(a), 8.0, 4.0, a, CREAM, 0.0)
	ci.draw_circle(pos, 4.0, OUTLINE)
	if on:
		for i in 3:
			var off := float(i) * 16.0 + fmod(float(tick) * 2.2, 16.0)
			var base := pos + dir * (26.0 + off)
			var perp := Vector2(-dir.y, dir.x)
			ci.draw_line(
				base + perp * (6.0 + float(i) * 3.0),
				base - perp * (6.0 + float(i) * 3.0),
				WIND,
				2.4
			)


## Stachelbrett: Holzbrett mit Dreiecks-Spitzen nach oben in Rect (x,y,w,h).
static func draw_spikes(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect.grow(2.5), OUTLINE)
	ci.draw_rect(rect, WOOD_DARK)
	var horizontal := rect.size.x >= rect.size.y
	var count := int(maxf(2.0, (rect.size.x if horizontal else rect.size.y) / 20.0))
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var points: PackedVector2Array
		if horizontal:
			var bx := rect.position.x + rect.size.x * t
			points = PackedVector2Array(
				[
					Vector2(bx - 8, rect.position.y + 2),
					Vector2(bx + 8, rect.position.y + 2),
					Vector2(bx, rect.position.y - 14),
				]
			)
		else:
			var by := rect.position.y + rect.size.y * t
			points = PackedVector2Array(
				[
					Vector2(rect.position.x + 2, by - 8),
					Vector2(rect.position.x + 2, by + 8),
					Vector2(rect.position.x - 14, by),
				]
			)
		ci.draw_colored_polygon(points, SPIKE_GRAY)
		_outline_poly(ci, points, 2.0)


## Zuckerwatte-Wolke: überlappende Pastell-Blobs im Rect (x,y,w,h).
static func draw_cloud(ci: CanvasItem, rect: Rect2, tick := 0) -> void:
	var c := rect.get_center()
	var drift := sin(float(tick) * 0.06) * rect.size.x * 0.02
	for i in 5:
		var t := float(i) / 4.0 - 0.5
		var at := c + Vector2(t * rect.size.x * 0.72 + drift, sin(t * 4.0) * rect.size.y * 0.16)
		_blob(ci, at, rect.size.x * 0.24, rect.size.y * 0.38, CLOUD_PINK, 0.0)
	ci.draw_circle(c + Vector2(-rect.size.x * 0.2, 0), 3.0, Color(1, 1, 1, 0.6))
	ci.draw_circle(c + Vector2(rect.size.x * 0.15, -rect.size.y * 0.1), 2.4, Color(1, 1, 1, 0.6))


## ── Low-Level ────────────────────────────────────────────────────────────


static func _blob(
	ci: CanvasItem, at: Vector2, rx: float, ry: float, fill: Color, ow: float
) -> void:
	if ow > 0.0:
		ci.draw_colored_polygon(_ellipse(at, rx + ow, ry + ow), OUTLINE)
	ci.draw_colored_polygon(_ellipse(at, rx, ry), fill)


static func _rot_blob(
	ci: CanvasItem, at: Vector2, rx: float, ry: float, angle: float, fill: Color, ow: float
) -> void:
	if ow > 0.0:
		ci.draw_colored_polygon(_ellipse(at, rx + ow, ry + ow, angle), OUTLINE)
	ci.draw_colored_polygon(_ellipse(at, rx, ry, angle), fill)


static func _ellipse(at: Vector2, rx: float, ry: float, angle := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		points.append(at + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	return points


static func _star(ci: CanvasItem, at: Vector2, r: float, color: Color, ow: float) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + TAU * float(i) / 10.0
		var rad := r if i % 2 == 0 else r * 0.45
		points.append(at + Vector2(cos(a), sin(a)) * rad)
	if ow > 0.0:
		var outer := PackedVector2Array()
		for p in points:
			outer.append(at + (p - at) * ((r + ow) / r))
		ci.draw_colored_polygon(outer, OUTLINE)
	ci.draw_colored_polygon(points, color)


static func _outline_poly(ci: CanvasItem, points: PackedVector2Array, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	ci.draw_polyline(closed, OUTLINE, maxf(1.0, width))


static func _dashed_circle(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	for i in 16:
		var a := TAU * float(i) / 16.0
		ci.draw_arc(at, r, a, a + TAU / 32.0, 4, color, 2.0)
