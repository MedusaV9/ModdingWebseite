class_name GvzArt
extends RefCounted
## Prozedurale Sticker-Optik für GvZ (W3b): cream Goobys mit Schlappohren,
## mint Zombie-Goobys mit Pflaster — dick umrandet, pastellig, gezeichnet
## als Polygone/Kreise (keine Textur-Assets; Referenz: assets/stickers/
## gvz_*.png). Alle Funktionen zeichnen auf einen CanvasItem; `pos` ist die
## FUSS-Mitte, `s` die Figur-Höhe in Pixeln, `tick` treibt die Wackel-Animation.

const OUTLINE := Color("#4A3B36")
const CREAM := Color("#F9EDD6")
const CREAM_DARK := Color("#EFDDBC")
const MINT := Color("#C7E2C0")
const MINT_DARK := Color("#A8CCA2")
const EAR_PINK := Color("#F6BFC0")
const CHEEK := Color(0.96, 0.63, 0.6, 0.85)
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const NUTELLA := Color("#5C3A21")
const CARROT := Color("#F08A3C")
const CARROT_LEAF := Color("#7AB35C")
const ICE := Color("#A8D8F0")
const STAR_GOLD := Color("#FFD34D")
const BERRY_RED := Color("#E0655F")
const MELON_GREEN := Color("#6DB54E")
const BALLOON_RED := Color("#F28B82")
const METAL := Color("#9DA6AD")
const CONE_ORANGE := Color("#F2A03C")

const OUT_W := 0.055

## ── Basis-Figuren ────────────────────────────────────────────────────────


## Gooby-Grundkörper (Birne + Schlappohren + Gesicht). opts:
## {body, mood: happy|zombie|scared|angry|sleepy, bandage: bool, lean: float}
static func draw_gooby(ci: CanvasItem, pos: Vector2, s: float, tick := 0, opts := {}) -> void:
	var body: Color = opts.get("body", CREAM)
	var mood := str(opts.get("mood", "happy"))
	var lean := float(opts.get("lean", 0.0))
	var wob := sin(float(tick) * 0.22 + float(opts.get("phase", 0.0))) * 0.03
	var c := pos + Vector2(lean * s * 0.1, -s * 0.42)
	var ow := s * OUT_W
	# Ohren zuerst (liegen HINTER dem Kopf): eins hängt, eins knickt hoch.
	_ear(ci, c + Vector2(-s * 0.16, -s * 0.30), s, -0.5 + wob, body, ow)
	_ear(ci, c + Vector2(s * 0.16, -s * 0.30), s, 2.4 - wob, body, ow)
	# Körper: dicke Birne.
	_blob(ci, c + Vector2(0, s * 0.14), s * 0.34, s * 0.30, body, ow)
	# Kopf.
	_blob(ci, c + Vector2(0, -s * 0.16), s * 0.30, s * 0.27, body, ow)
	# Füßchen.
	_blob(ci, pos + Vector2(-s * 0.16, -s * 0.035), s * 0.115, s * 0.075, body, ow * 0.8)
	_blob(ci, pos + Vector2(s * 0.16, -s * 0.035), s * 0.115, s * 0.075, body, ow * 0.8)
	_face(ci, c + Vector2(0, -s * 0.16), s, mood)
	if bool(opts.get("bandage", false)):
		_bandage(ci, c + Vector2(s * 0.17, -s * 0.33), s * 0.15, ow)


## Gesicht (Augen/Backen/Mund) auf Kopfmitte `head`.
static func _face(ci: CanvasItem, head: Vector2, s: float, mood: String) -> void:
	var ey := head + Vector2(0, -s * 0.02)
	var dx := s * 0.105
	match mood:
		"zombie":
			# Halb zugekniffene Müdigkeits-Augen + offener Mund.
			for side: int in [-1, 1]:
				var e := ey + Vector2(dx * side, 0)
				ci.draw_circle(e, s * 0.052, OUTLINE)
				ci.draw_rect(
					Rect2(e + Vector2(-s * 0.06, -s * 0.065), Vector2(s * 0.12, s * 0.05)), MINT
				)
			_mouth_open(ci, head + Vector2(0, s * 0.11), s * 0.075)
		"scared":
			for side: int in [-1, 1]:
				ci.draw_circle(ey + Vector2(dx * side, 0), s * 0.055, Color.WHITE)
				ci.draw_circle(ey + Vector2(dx * side, 0), s * 0.032, OUTLINE)
			_mouth_open(ci, head + Vector2(0, s * 0.115), s * 0.055)
		"angry":
			for side: int in [-1, 1]:
				var e := ey + Vector2(dx * side, 0)
				ci.draw_circle(e, s * 0.048, OUTLINE)
				ci.draw_line(
					e + Vector2(-s * 0.06 * side, -s * 0.075),
					e + Vector2(s * 0.05 * side, -s * 0.045),
					OUTLINE,
					s * 0.028
				)
			_mouth_smile(ci, head + Vector2(0, s * 0.10), s * 0.05)
		"sleepy":
			for side: int in [-1, 1]:
				var e := ey + Vector2(dx * side, s * 0.01)
				ci.draw_arc(e, s * 0.05, 0.2, PI - 0.2, 8, OUTLINE, s * 0.026)
			_mouth_smile(ci, head + Vector2(0, s * 0.105), s * 0.04)
		_:
			for side: int in [-1, 1]:
				var e := ey + Vector2(dx * side, 0)
				ci.draw_circle(e, s * 0.05, OUTLINE)
				ci.draw_circle(e + Vector2(-s * 0.016, -s * 0.016), s * 0.015, Color.WHITE)
			_mouth_smile(ci, head + Vector2(0, s * 0.10), s * 0.055)
	ci.draw_circle(head + Vector2(-s * 0.19, s * 0.055), s * 0.055, CHEEK)
	ci.draw_circle(head + Vector2(s * 0.19, s * 0.055), s * 0.055, CHEEK)


static func _mouth_smile(ci: CanvasItem, at: Vector2, r: float) -> void:
	ci.draw_arc(at, r, 0.35, PI - 0.35, 10, OUTLINE, r * 0.5)


static func _mouth_open(ci: CanvasItem, at: Vector2, r: float) -> void:
	ci.draw_circle(at, r, OUTLINE)
	ci.draw_circle(at + Vector2(0, r * 0.35), r * 0.55, Color("#B5766F"))


## Schlappohr als gedrehte Ellipse (+ rosa Innenohr).
static func _ear(
	ci: CanvasItem, base: Vector2, s: float, angle: float, body: Color, ow: float
) -> void:
	var dir := Vector2.DOWN.rotated(angle)
	var mid := base + dir * s * 0.26
	_rot_blob(ci, mid, s * 0.105, s * 0.28, angle, body, ow)
	_rot_blob(ci, mid + dir * s * 0.03, s * 0.05, s * 0.17, angle, EAR_PINK, 0.0)


static func _bandage(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	_rot_blob(ci, at, r, r * 0.42, 0.7, Color("#EAD9A8"), ow * 0.7)
	for offset: float in [-r * 0.3, 0.0, r * 0.3]:
		var p := at + Vector2(offset, 0).rotated(0.7)
		ci.draw_circle(p, r * 0.07, OUTLINE)


## ── Türme (Doc G §4.2) ───────────────────────────────────────────────────


## Turm-Dispatcher: zeichnet Typ `type` (auch für die Karten-Icons benutzt).
static func draw_tower(ci: CanvasItem, type: String, pos: Vector2, s: float, tick := 0) -> void:
	var ow := s * OUT_W
	match type:
		"moehrenschuetze":
			draw_gooby(ci, pos + Vector2(-s * 0.10, 0), s * 0.92, tick)
			_headband(ci, pos + Vector2(-s * 0.10, 0), s * 0.92, CARROT_LEAF)
			_cannon(ci, pos + Vector2(s * 0.16, -s * 0.22), s, ow)
		"doppelmoehre":
			draw_gooby(ci, pos + Vector2(-s * 0.12, 0), s * 0.92, tick)
			_headband(ci, pos + Vector2(-s * 0.12, 0), s * 0.92, BERRY_RED)
			_cannon(ci, pos + Vector2(s * 0.10, -s * 0.30), s * 0.9, ow)
			_cannon(ci, pos + Vector2(s * 0.18, -s * 0.14), s * 0.9, ow)
		"nutella_sammler":
			draw_gooby(ci, pos, s * 0.92, tick)
			_jar(ci, pos + Vector2(0, -s * 0.16), s * 0.34, ow)
		"goldi":
			draw_gooby(ci, pos, s * 0.92, tick, {"body": Color("#F6D98A")})
			_jar(ci, pos + Vector2(0, -s * 0.16), s * 0.36, ow)
			ci.draw_circle(pos + Vector2(-s * 0.3, -s * 0.72), s * 0.05, STAR_GOLD)
			ci.draw_circle(pos + Vector2(s * 0.32, -s * 0.5), s * 0.04, STAR_GOLD)
		"dicker_bert":
			draw_gooby(ci, pos, s * 1.05, tick, {"mood": "sleepy"})
			_shield(ci, pos + Vector2(0, -s * 0.28), s * 0.30, ow)
		"schnarch_knolle":
			_knolle(ci, pos, s, tick, ow)
		"boom_beere":
			_berry(ci, pos, s, tick, ow)
		"eis_gooby":
			draw_gooby(ci, pos, s * 0.92, tick)
			_beanie(ci, pos, s * 0.92, ICE)
			_snow_breath(ci, pos + Vector2(s * 0.3, -s * 0.5), s, tick)
		"magnet_gooby":
			draw_gooby(ci, pos + Vector2(-s * 0.06, 0), s * 0.92, tick)
			_magnet(ci, pos + Vector2(s * 0.24, -s * 0.42), s * 0.24, ow)
		"trampolin_gooby":
			_trampoline(ci, pos, s, ow)
			draw_gooby(
				ci,
				pos + Vector2(0, -s * 0.16 + sin(float(tick) * 0.3) * s * 0.05),
				s * 0.7,
				tick,
				{"mood": "scared"}
			)
		"pust_gooby":
			draw_gooby(ci, pos, s * 0.92, tick, {"mood": "scared"})
			_gust_cloud(ci, pos + Vector2(s * 0.32, -s * 0.48), s, tick)
		"sternchen_gooby":
			draw_gooby(ci, pos, s * 0.92, tick)
			_star(ci, pos + Vector2(0, -s * 0.95), s * 0.14, STAR_GOLD, ow)
			ci.draw_line(pos + Vector2(0, -s * 0.82), pos + Vector2(0, -s * 0.9), OUTLINE, ow)
		"melonen_meier":
			draw_gooby(ci, pos + Vector2(s * 0.08, 0), s * 0.92, tick)
			_melon(ci, pos + Vector2(-s * 0.26, -s * 0.22), s * 0.24, ow)
		_:
			draw_gooby(ci, pos, s, tick)


static func _headband(ci: CanvasItem, pos: Vector2, s: float, color: Color) -> void:
	var y := pos.y - s * 0.72
	ci.draw_rect(Rect2(pos.x - s * 0.28, y, s * 0.56, s * 0.09), color)


static func _beanie(ci: CanvasItem, pos: Vector2, s: float, color: Color) -> void:
	var top := pos + Vector2(0, -s * 0.78)
	_blob(ci, top, s * 0.27, s * 0.13, color, s * OUT_W * 0.8)
	ci.draw_circle(top + Vector2(0, -s * 0.12), s * 0.08, Color.WHITE)


static func _cannon(ci: CanvasItem, at: Vector2, s: float, ow: float) -> void:
	_rot_blob(ci, at, s * 0.13, s * 0.24, -PI / 2 + 0.25, WOOD, ow)
	ci.draw_circle(at + Vector2(-s * 0.05, s * 0.16), s * 0.09, WOOD_DARK)
	_carrot_shape(ci, at + Vector2(s * 0.22, -s * 0.10), s * 0.14, 0.25)


static func _jar(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	_blob(ci, at + Vector2(0, r * 0.15), r * 0.62, r * 0.62, NUTELLA, ow)
	ci.draw_rect(Rect2(at.x - r * 0.5, at.y - r * 0.72, r, r * 0.3), Color("#EFE6D8"))
	ci.draw_rect(
		Rect2(at.x - r * 0.5, at.y - r * 0.72, r, r * 0.3), OUTLINE, false, maxf(1.0, ow * 0.6)
	)
	_blob(ci, at + Vector2(0, r * 0.1), r * 0.34, r * 0.3, Color("#8A5A33"), 0.0)


static func _shield(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	ci.draw_circle(at, r + ow, OUTLINE)
	ci.draw_circle(at, r, WOOD)
	ci.draw_arc(at, r * 0.7, 0, TAU, 20, WOOD_DARK, ow)
	ci.draw_circle(at, r * 0.22, METAL)


static func _knolle(ci: CanvasItem, pos: Vector2, s: float, tick: int, ow: float) -> void:
	var c := pos + Vector2(0, -s * 0.3)
	_blob(ci, c, s * 0.32, s * 0.28, Color("#C9A36B"), ow)
	_blob(ci, c + Vector2(0, -s * 0.3), s * 0.1, s * 0.16, CARROT_LEAF, ow * 0.7)
	_face(ci, c + Vector2(0, -s * 0.02), s * 0.9, "sleepy")
	if (tick / 20) % 2 == 0:
		_zzz(ci, c + Vector2(s * 0.34, -s * 0.4), s * 0.1)


static func _zzz(ci: CanvasItem, at: Vector2, r: float) -> void:
	for i in 2:
		var p := at + Vector2(i * r * 1.1, -i * r * 1.2)
		var half := r * (0.5 + 0.25 * i)
		ci.draw_line(p + Vector2(-half, -half), p + Vector2(half, -half), OUTLINE, r * 0.28)
		ci.draw_line(p + Vector2(half, -half), p + Vector2(-half, half), OUTLINE, r * 0.28)
		ci.draw_line(p + Vector2(-half, half), p + Vector2(half, half), OUTLINE, r * 0.28)


static func _berry(ci: CanvasItem, pos: Vector2, s: float, tick: int, ow: float) -> void:
	var c := pos + Vector2(0, -s * 0.32)
	var hot := (tick / 4) % 2 == 0
	_blob(ci, c, s * 0.30, s * 0.30, BERRY_RED if not hot else Color("#F08078"), ow)
	for side: int in [-1, 1]:
		ci.draw_circle(c + Vector2(s * 0.12 * side, s * 0.1), s * 0.05, Color(1, 1, 1, 0.35))
	_face(ci, c + Vector2(0, -s * 0.04), s * 0.85, "angry")
	ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(s * 0.12, -s * 0.46), OUTLINE, ow)
	if hot:
		_star(ci, c + Vector2(s * 0.14, -s * 0.5), s * 0.07, STAR_GOLD, 0.0)


static func _magnet(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	ci.draw_arc(at, r, PI * 0.15, PI * 0.85 + PI, 16, OUTLINE, r * 0.62 + ow)
	ci.draw_arc(at, r, PI * 0.15, PI * 0.85 + PI, 16, BERRY_RED, r * 0.55)
	for side: int in [-1, 1]:
		ci.draw_rect(Rect2(at.x + r * side - r * 0.32, at.y + r * 0.55, r * 0.64, r * 0.4), METAL)


static func _trampoline(ci: CanvasItem, pos: Vector2, s: float, ow: float) -> void:
	_blob(ci, pos + Vector2(0, -s * 0.08), s * 0.42, s * 0.1, Color("#7FB6D9"), ow)
	for side: int in [-1, 1]:
		ci.draw_line(
			pos + Vector2(s * 0.3 * side, -s * 0.05), pos + Vector2(s * 0.36 * side, 0), OUTLINE, ow
		)


static func _gust_cloud(ci: CanvasItem, at: Vector2, s: float, tick: int) -> void:
	var push := fmod(float(tick) * 0.8, 6.0) * s * 0.02
	for i in 3:
		var p := at + Vector2(s * 0.1 * i + push, -s * 0.05 * i + s * 0.04 * (i % 2))
		ci.draw_circle(p, s * (0.1 - 0.02 * i), Color(0.92, 0.97, 1.0, 0.9 - 0.2 * i))


static func _snow_breath(ci: CanvasItem, at: Vector2, s: float, tick: int) -> void:
	_gust_cloud(ci, at, s, tick)
	for i in 2:
		var p := at + Vector2(s * 0.12 * i + s * 0.05, -s * 0.08 + s * 0.1 * i)
		_star(ci, p, s * 0.04, Color.WHITE, 0.0)


static func _melon(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	ci.draw_circle(at, r + ow, OUTLINE)
	ci.draw_circle(at, r, MELON_GREEN)
	ci.draw_arc(at, r * 0.65, -0.6, 0.6, 8, Color("#4E8F38"), r * 0.2)
	ci.draw_arc(at, r * 0.65, PI - 0.6, PI + 0.6, 8, Color("#4E8F38"), r * 0.2)


## ── Zombies (Doc G §4.3) ─────────────────────────────────────────────────


## Zombie-Dispatcher; `zombie` ist der Sim-Eintrag (state/armor/raged/…).
static func draw_zombie(
	ci: CanvasItem, type: String, pos: Vector2, s: float, tick := 0, zombie := {}
) -> void:
	var ow := s * OUT_W
	var phase := float(int(zombie.get("id", 0)) % 7)
	var opts := {"body": MINT, "mood": "zombie", "bandage": true, "phase": phase, "lean": -0.6}
	if str(zombie.get("state", "walk")) == "dig":
		_mole_mound(ci, pos, s, tick)
		return
	match type:
		"schlurfi":
			draw_gooby(ci, pos, s, tick, opts)
			_zombie_arms(ci, pos, s, tick, phase)
		"huetchen":
			draw_gooby(ci, pos, s, tick, opts)
			_zombie_arms(ci, pos, s, tick, phase)
			if int(zombie.get("armor_hp", 1)) > 0:
				_cone(ci, pos + Vector2(0, -s * 0.92), s * 0.24, ow)
		"eimer":
			draw_gooby(ci, pos, s, tick, opts)
			_zombie_arms(ci, pos, s, tick, phase)
			if int(zombie.get("armor_hp", 1)) > 0:
				_bucket(ci, pos + Vector2(0, -s * 0.9), s * 0.26, ow)
		"sprinter":
			opts["lean"] = -1.4
			draw_gooby(ci, pos, s * 0.95, tick, opts)
			_headband(ci, pos + Vector2(-s * 0.1, 0), s * 0.95, BERRY_RED)
			for i in 2:
				var p := pos + Vector2(s * (0.4 + 0.15 * i), -s * 0.2 - s * 0.06 * i)
				ci.draw_line(p, p + Vector2(s * 0.12, 0), Color(1, 1, 1, 0.5), ow)
		"huepfer":
			var hop := absf(sin(float(tick) * 0.25 + phase)) * s * 0.22
			draw_gooby(ci, pos + Vector2(0, -hop), s, tick, opts)
			_blob(ci, pos + Vector2(0, -s * 0.02), s * 0.3, s * 0.05, Color(0, 0, 0, 0.12), 0.0)
		"zeitungsopa":
			draw_gooby(
				ci,
				pos,
				s,
				tick,
				(
					opts
					if not bool(zombie.get("raged", false))
					else {
						"body": MINT, "mood": "angry", "bandage": true, "phase": phase, "lean": -1.2
					}
				)
			)
			for side: int in [-1, 1]:
				ci.draw_arc(
					pos + Vector2(s * 0.105 * side, -s * 0.6),
					s * 0.07,
					0,
					TAU,
					10,
					OUTLINE,
					ow * 0.6
				)
			if int(zombie.get("armor_hp", 1)) > 0 and not bool(zombie.get("raged", false)):
				ci.draw_rect(
					Rect2(pos.x - s * 0.34, pos.y - s * 0.52, s * 0.3, s * 0.36), Color("#EDE7DA")
				)
				ci.draw_rect(
					Rect2(pos.x - s * 0.34, pos.y - s * 0.52, s * 0.3, s * 0.36),
					OUTLINE,
					false,
					ow * 0.6
				)
		"tuersteher":
			draw_gooby(ci, pos, s * 1.02, tick, opts)
			ci.draw_rect(
				Rect2(pos.x - s * 0.2, pos.y - s * 0.52, s * 0.4, s * 0.2), Color("#3E3A45")
			)
			if int(zombie.get("armor_hp", 1)) > 0:
				_riot_shield(ci, pos + Vector2(-s * 0.42, -s * 0.36), s, ow)
		"maulwurf":
			draw_gooby(
				ci, pos, s * 0.9, tick, {"body": Color("#8A6B54"), "mood": "zombie", "phase": phase}
			)
			ci.draw_circle(pos + Vector2(0, -s * 0.46), s * 0.06, Color("#E2A9A0"))
		"ballon":
			if bool(zombie.get("flying", true)):
				var lift := s * 0.5 + sin(float(tick) * 0.1 + phase) * s * 0.06
				var top := pos + Vector2(0, -lift)
				ci.draw_line(
					top + Vector2(0, -s * 0.6), top + Vector2(0, -s * 1.0), OUTLINE, ow * 0.6
				)
				ci.draw_circle(top + Vector2(0, -s * 1.25), s * 0.3 + ow, OUTLINE)
				ci.draw_circle(top + Vector2(0, -s * 1.25), s * 0.3, BALLOON_RED)
				ci.draw_circle(top + Vector2(-s * 0.1, -s * 1.33), s * 0.07, Color(1, 1, 1, 0.4))
				draw_gooby(ci, top, s * 0.82, tick, opts)
			else:
				draw_gooby(ci, pos, s * 0.9, tick, opts)
				_zombie_arms(ci, pos, s * 0.9, tick, phase)
		"brocken":
			opts["mood"] = "angry" if bool(zombie.get("raged", false)) else "zombie"
			draw_gooby(ci, pos, s * 1.55, tick, opts)
			_zombie_arms(ci, pos + Vector2(0, -s * 0.2), s * 1.5, tick, phase)
		_:
			draw_gooby(ci, pos, s, tick, opts)
			_zombie_arms(ci, pos, s, tick, phase)
	var slow := int(zombie.get("slow_until", 0)) > tick
	if slow and not bool(zombie.get("flying", false)):
		_star(ci, pos + Vector2(-s * 0.34, -s * 0.75), s * 0.08, ICE, 0.0)


## Ausgestreckte Zombie-Ärmchen (die klassische Schlurfi-Pose).
static func _zombie_arms(ci: CanvasItem, pos: Vector2, s: float, tick: int, phase: float) -> void:
	var sway := sin(float(tick) * 0.2 + phase) * s * 0.03
	var base := pos + Vector2(-s * 0.26, -s * 0.5)
	_rot_blob(ci, base + Vector2(-s * 0.09, sway), s * 0.14, s * 0.06, 0.15, MINT, s * OUT_W * 0.7)
	_rot_blob(
		ci,
		base + Vector2(-s * 0.02, s * 0.12 - sway),
		s * 0.12,
		s * 0.055,
		-0.1,
		MINT_DARK,
		s * OUT_W * 0.7
	)


static func _cone(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	var points := PackedVector2Array(
		[at + Vector2(-r, r * 0.5), at + Vector2(r, r * 0.5), at + Vector2(0, -r * 1.3)]
	)
	ci.draw_colored_polygon(points, CONE_ORANGE)
	_outline_poly(ci, points, ow * 0.8)
	ci.draw_rect(Rect2(at.x - r * 0.45, at.y - r * 0.45, r * 0.9, r * 0.28), Color.WHITE)


static func _bucket(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	var points := PackedVector2Array(
		[
			at + Vector2(-r, -r * 0.9),
			at + Vector2(r, -r * 0.9),
			at + Vector2(r * 0.72, r * 0.5),
			at + Vector2(-r * 0.72, r * 0.5),
		]
	)
	ci.draw_colored_polygon(points, METAL)
	_outline_poly(ci, points, ow * 0.8)
	ci.draw_rect(Rect2(at.x - r, at.y - r * 1.02, r * 2.0, r * 0.24), Color("#B7BEC4"))


static func _riot_shield(ci: CanvasItem, at: Vector2, s: float, ow: float) -> void:
	var rect := Rect2(at.x - s * 0.09, at.y - s * 0.34, s * 0.18, s * 0.68)
	ci.draw_rect(rect.grow(ow * 0.7), OUTLINE)
	ci.draw_rect(rect, Color(0.75, 0.85, 0.92, 0.9))
	ci.draw_rect(
		Rect2(rect.position + Vector2(s * 0.03, s * 0.06), Vector2(s * 0.04, s * 0.5)),
		Color(1, 1, 1, 0.5)
	)


static func _mole_mound(ci: CanvasItem, pos: Vector2, s: float, tick: int) -> void:
	_blob(ci, pos + Vector2(0, -s * 0.12), s * 0.34, s * 0.16, Color("#8A6B54"), s * OUT_W)
	_blob(ci, pos + Vector2(-s * 0.2, -s * 0.05), s * 0.12, s * 0.08, Color("#A5825F"), 0.0)
	if (tick / 10) % 2 == 0:
		_blob(ci, pos + Vector2(s * 0.18, -s * 0.3), s * 0.07, s * 0.05, Color("#A5825F"), 0.0)


## ── Boss, Projektile, Kleinkram ──────────────────────────────────────────


## Boss Knurps: qualmender Müllwagen mit gekröntem Zombie-König.
static func draw_boss(ci: CanvasItem, pos: Vector2, s: float, tick := 0, boss := {}) -> void:
	var ow := s * OUT_W * 0.7
	var wob := sin(float(tick) * 0.15) * s * 0.02
	var body := Rect2(pos.x - s * 0.55, pos.y - s * 0.72 + wob, s * 1.1, s * 0.52)
	ci.draw_rect(body.grow(ow), OUTLINE)
	ci.draw_rect(body, Color("#7B8794"))
	ci.draw_rect(
		Rect2(body.position + Vector2(s * 0.08, s * 0.1), Vector2(s * 0.3, s * 0.16)),
		Color("#5A6572")
	)
	ci.draw_rect(
		Rect2(body.position + Vector2(s * 0.72, s * 0.1), Vector2(s * 0.3, s * 0.16)),
		Color("#5A6572")
	)
	for wheel_x: float in [-0.34, 0.34]:
		var w := pos + Vector2(s * wheel_x, -s * 0.14)
		ci.draw_circle(w, s * 0.15 + ow, OUTLINE)
		ci.draw_circle(w, s * 0.15, Color("#3E3A45"))
		ci.draw_circle(w, s * 0.06, METAL)
	draw_gooby(
		ci,
		pos + Vector2(0, -s * 0.66 + wob),
		s * 0.62,
		tick,
		{"body": MINT, "mood": "angry", "bandage": true}
	)
	_crown(ci, pos + Vector2(0, -s * 1.22 + wob), s * 0.14, ow)
	var phase := int(boss.get("phase", 1))
	for i in phase - 1:
		var puff := (
			pos
			+ Vector2(
				-s * 0.5 - s * 0.1 * i - fmod(float(tick) * 0.6 + i * 7.0, 12.0) * s * 0.02,
				-s * 0.8 - s * 0.12 * i
			)
		)
		ci.draw_circle(puff, s * (0.1 + 0.03 * i), Color(0.4, 0.38, 0.36, 0.4))


static func _crown(ci: CanvasItem, at: Vector2, r: float, ow: float) -> void:
	var points := PackedVector2Array(
		[
			at + Vector2(-r, r * 0.6),
			at + Vector2(-r, -r * 0.5),
			at + Vector2(-r * 0.5, r * 0.05),
			at + Vector2(0, -r * 0.7),
			at + Vector2(r * 0.5, r * 0.05),
			at + Vector2(r, -r * 0.5),
			at + Vector2(r, r * 0.6),
		]
	)
	ci.draw_colored_polygon(points, STAR_GOLD)
	_outline_poly(ci, points, ow * 0.7)


## Projektil (kind: carrot|frost|star|melon).
static func draw_projectile(ci: CanvasItem, kind: String, pos: Vector2, s: float) -> void:
	match kind:
		"frost":
			ci.draw_circle(pos, s * 0.16, Color(0.7, 0.88, 1.0, 0.5))
			_star(ci, pos, s * 0.13, ICE, 0.0)
		"star":
			_star(ci, pos, s * 0.16, STAR_GOLD, s * 0.02)
		"melon":
			ci.draw_circle(pos, s * 0.17 + s * 0.03, OUTLINE)
			ci.draw_circle(pos, s * 0.17, MELON_GREEN)
		_:
			_carrot_shape(ci, pos, s * 0.2, 0.0)


static func _carrot_shape(ci: CanvasItem, at: Vector2, r: float, angle: float) -> void:
	var tip := Vector2(r * 1.4, 0).rotated(angle)
	var up := Vector2(0, -r * 0.55).rotated(angle)
	var points := PackedVector2Array([at - tip * 0.5 + up, at - tip * 0.5 - up, at + tip])
	ci.draw_colored_polygon(points, CARROT)
	_outline_poly(ci, points, r * 0.14)
	ci.draw_circle(at - tip * 0.62, r * 0.28, CARROT_LEAF)


## Panik-Gooby (Rasenmäher-Äquivalent): panischer Gooby auf Rollbrett.
static func draw_mower(ci: CanvasItem, pos: Vector2, s: float, tick := 0, used := false) -> void:
	if used:
		ci.draw_circle(pos + Vector2(0, -s * 0.1), s * 0.1, Color(0.3, 0.25, 0.22, 0.25))
		return
	_blob(ci, pos + Vector2(0, -s * 0.08), s * 0.3, s * 0.07, WOOD, s * OUT_W * 0.7)
	for side: int in [-1, 1]:
		ci.draw_circle(pos + Vector2(s * 0.18 * side, -s * 0.03), s * 0.06, OUTLINE)
	draw_gooby(ci, pos + Vector2(0, -s * 0.12), s * 0.62, tick, {"mood": "scared"})


## Nutella-Klecks (Drop) bzw. Zähler-Icon.
static func draw_nutella_drop(ci: CanvasItem, pos: Vector2, s: float, tick := 0) -> void:
	var bob := sin(float(tick) * 0.2) * s * 0.04
	var c := pos + Vector2(0, -s * 0.3 + bob)
	ci.draw_circle(c, s * 0.26 + s * 0.05, OUTLINE)
	ci.draw_circle(c, s * 0.26, NUTELLA)
	ci.draw_circle(c + Vector2(-s * 0.08, -s * 0.08), s * 0.07, Color(1, 1, 1, 0.35))
	ci.draw_arc(c, s * 0.34, -2.2, -0.9, 8, Color(1.0, 0.9, 0.5, 0.8), s * 0.04)


## ── Low-Level ────────────────────────────────────────────────────────────


## Umrandete Ellipse ("Sticker-Blob"). ow 0 = ohne Umrandung.
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
