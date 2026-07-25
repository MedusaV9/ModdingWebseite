extends MinigameBase
## Geisterjagd (ghostHunt) — Spiel-Szene. Alle MECHANIK-Zahlen kommen aus
## GhostHuntLogic (zahlengleich zum Web): 90-s-Runde, Sichtfenster 2.2 s → 0.9 s,
## Fang +3 mit Kettenbonus (max. +5), Kürbis-Attrappe −2, alle 25 s eine
## Buh-Welle mit 5 Geistern (≥ 4 Fänge = +10) sowie Laterne/Netz als Aufsammler.
##
## 2D statt 3D (bewusste Entscheidung): das Web nutzt eine KayKit-Friedhofs-
## szene, das Spiel ist aber reines Ziel-Tippen auf 12 FESTE Ankerpunkte. Eine
## 2D-Sticker-Kulisse mit Tiefenprojektion (Weltkoordinate z → Skalierung +
## Bildschirmhöhe) liefert dieselbe Lesbarkeit, größere Tippflächen auf dem
## Handy und kostet keine Modelle. Die Anker sind exakt GhostHuntLogic.SPOTS.

const Logic := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd")

## Tiefenband der Kulisse in Weltkoordinaten (SPOTS liegen bei z = −1.5 … −6.4).
const DEPTH_NEAR := 1.45
const DEPTH_FAR := 6.9
## Perspektivstärke: p = 1 / (1 + t · STRENGTH) (t = 0 vorn, 1 hinten).
const PERSPECTIVE := 1.7

const SKY_TOP := Color(0.165, 0.118, 0.259)
const SKY_HORIZON := Color(0.478, 0.286, 0.322)
const GROUND_NEAR := Color(0.196, 0.157, 0.235)
const GROUND_FAR := Color(0.286, 0.208, 0.318)
const GHOST_TINT := Color(0.925, 0.941, 1.0)
const LANTERN_TINT := Color(1.0, 0.694, 0.302)
const NET_TINT := Color(0.608, 0.878, 0.784)

var state: Dictionary = {}
var view_size := Vector2(390.0, 844.0)
var landscape := false
var finished := false

var _banner := ""
var _banner_t := 0.0
var _pops: Array[Dictionary] = []
var _bob := 0.0
var _score_label: Label
var _chain_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	var tune := Logic.apply_difficulty(Logic.HUNT, ctx.difficulty)
	state = Logic.create_hunt(ctx.run_seed, tune)
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _score_label != null:
		_score_label.position = Vector2(16.0, 10.0)
		_chain_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 42.0)
		_hint_label.size = Vector2(340.0, 34.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_bob += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	_age_pops(delta)
	Logic.step_hunt(state, delta)
	_drain_events()
	ctx.report_score(Logic.hunt_score(state), 0)
	_update_labels()
	queue_redraw()
	if bool(state["ended"]):
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch and event.pressed:
		_tap_at(event.position)


## Horizontlinie in Pixeln (Oberkante des Friedhofsbodens).
func horizon_y() -> float:
	return view_size.y * (0.24 if landscape else 0.30)


## Perspektivfaktor einer Welt-Tiefe (1.0 = ganz vorn, klein = hinten).
func depth_scale(z: float) -> float:
	var t := clampf((-z - DEPTH_NEAR) / (DEPTH_FAR - DEPTH_NEAR), 0.0, 1.0)
	return 1.0 / (1.0 + t * PERSPECTIVE)


## Weltkoordinate (x, z) auf den Bildschirm projizieren.
func project(x: float, z: float) -> Vector2:
	var p := depth_scale(z)
	var far := 1.0 / (1.0 + PERSPECTIVE)
	var f := (p - far) / (1.0 - far)
	var top := horizon_y()
	var bottom := view_size.y * (0.88 if landscape else 0.84)
	return Vector2(view_size.x * 0.5 + x * unit() * p, top + (bottom - top) * f)


## Pixel pro Welteinheit in der vordersten Reihe.
func unit() -> float:
	return minf(view_size.x / 5.6, view_size.y * (0.16 if landscape else 0.1))


## Tipp-Radius eines Ankers in dieser Tiefe (min. 34 px = Daumenfläche).
func hit_radius(z: float) -> float:
	return maxf(34.0, unit() * 0.52 * depth_scale(z))


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	add_child(_score_label)
	_chain_label = Label.new()
	_chain_label.theme_type_variation = &"CaptionLabel"
	add_child(_chain_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.ghostHunt.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Die Dämmerungskulisse ist dunkel — die Theme-Schriftfarben sind es auch.
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	_chain_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_hint_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.95))
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Nächstliegendes Ziel unter dem Finger; Aufsammler haben Vorrang.
func _tap_at(pos: Vector2) -> void:
	var best := {}
	var best_d := INF
	for token: Dictionary in state["tokens"]:
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(token["window"])]
		var d := pos.distance_to(_token_pos(anchor))
		if d < hit_radius(float(anchor["z"])) * 1.2 and d < best_d:
			best_d = d
			best = {"kind": "token", "window": int(token["window"])}
	if best.is_empty():
		best_d = INF
		for ghost: Dictionary in state["ghosts"]:
			var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
			var d := pos.distance_to(_ghost_pos(ghost, spot))
			if d < hit_radius(float(spot["z"])) and d < best_d:
				best_d = d
				best = {"kind": "ghost", "id": int(ghost["id"])}
		for flick: Dictionary in state["flickers"]:
			var spot: Dictionary = Logic.DECOY_SPOTS[int(flick["decoy"])]
			var d := pos.distance_to(project(float(spot["x"]), float(spot["z"])))
			if d < hit_radius(float(spot["z"])) and d < best_d:
				best_d = d
				best = {"kind": "decoy", "decoy": int(flick["decoy"])}
	Logic.tap_hunt(state, best)
	_drain_events()


## Aufsteig-/Absink-Kurve eines Geistes (RISE_FRAC/SINK_FRAC aus der Logik).
func _ghost_lift(ghost: Dictionary) -> float:
	var age := float(state["t"]) - float(ghost["spawnT"])
	var dur := maxf(0.001, float(ghost["dur"]))
	var f := clampf(age / dur, 0.0, 1.0)
	var rise := float(Logic.HUNT["RISE_FRAC"])
	var sink := float(Logic.HUNT["SINK_FRAC"])
	if f < rise:
		return _ease_out_back(f / rise)
	if f > 1.0 - sink:
		return maxf(0.0, (1.0 - f) / sink)
	return 1.0


func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _ghost_pos(ghost: Dictionary, spot: Dictionary) -> Vector2:
	var base := project(float(spot["x"]), float(spot["z"]))
	var s := unit() * depth_scale(float(spot["z"]))
	return base - Vector2(0.0, s * (0.5 + 0.7 * _ghost_lift(ghost)))


func _token_pos(anchor: Dictionary) -> Vector2:
	var base := project(float(anchor["x"]), float(anchor["z"]))
	return base - Vector2(0.0, unit() * 1.1 + sin(_bob * 2.4) * 6.0)


## Logik-Ereignisse in SFX, Juice und Banner übersetzen.
func _drain_events() -> void:
	var events: Array = state["events"]
	for e: Dictionary in events:
		_handle_event(e)
	events.clear()


func _handle_event(e: Dictionary) -> void:
	match str(e["type"]):
		"catch":
			_on_catch(e)
		"decoy":
			_on_decoy()
		"booWave":
			_show_banner(I18nService.t("mg.ghostHunt.boo"))
			AudioDirector.try_play(self, "mg_combo")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.7)
		"booBonus":
			_show_banner(I18nService.t("mg.ghostHunt.booBonus", {"n": int(e["bonus"])}))
			AudioDirector.try_play(self, "mg_golden")
			if ctx.juice != null:
				ctx.juice.hit_freeze(90)
		"booEnd":
			_show_banner(I18nService.t("mg.ghostHunt.booMiss", {"n": int(e["caught"])}))
			AudioDirector.try_play(self, "mg_lose")
		"powerup":
			var key := "mg.ghostHunt.%s" % str(e["kind"])
			_show_banner(I18nService.t(key))
			AudioDirector.try_play(self, "mg_golden")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
		"ghostGone":
			AudioDirector.try_play(self, "mg_spill")


func _on_catch(e: Dictionary) -> void:
	var spot: Dictionary = Logic.SPOTS[int(e["spot"])]
	var at := project(float(spot["x"]), float(spot["z"]))
	_pops.append({"pos": at, "t": 0.32})
	AudioDirector.try_play(self, "mg_perfect" if int(e["chain"]) > 1 else "mg_good")
	if ctx.juice == null:
		return
	ctx.juice.float_text(at, "+%d" % int(e["points"]), Color(1.0, 0.93, 0.72))
	if int(e["chain"]) >= 3:
		ctx.juice.bloom_pulse(0.4)


func _on_decoy() -> void:
	AudioDirector.try_play(self, "mg_junk")
	_show_banner(I18nService.t("mg.ghostHunt.decoy"))
	if ctx.juice != null:
		ctx.juice.shake(0.4)


func _show_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _age_pops(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for p in _pops:
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) > 0.0:
			kept.append(p)
	_pops = kept


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	var result := Logic.run_meta(state)
	result["score"] = Logic.hunt_score(state)
	ctx.report_end(result)


func _update_labels() -> void:
	var tune: Dictionary = state["tune"]
	if bool(tune["ENDLESS"]):
		_score_label.text = I18nService.t(
			"mg.ghostHunt.escapes",
			{"n": int(state["escapedWaves"]), "max": int(tune["ENDLESS_ESCAPE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(state["t"]))))
		_score_label.text = I18nService.t("mg.game.time", {"sec": left})
	var parts: Array[String] = []
	if int(state["chain"]) > 1:
		parts.append(I18nService.t("mg.ghostHunt.chainPill", {"n": int(state["chain"])}))
	if int(state["netLeft"]) > 0:
		parts.append(I18nService.t("mg.ghostHunt.netPill", {"n": int(state["netLeft"])}))
	if float(state["lanternT"]) > 0.0:
		parts.append(
			I18nService.t("mg.ghostHunt.lanternPill", {"n": int(ceil(float(state["lanternT"])))})
		)
	_chain_label.text = "  ".join(parts)


func _draw() -> void:
	_draw_sky()
	_draw_ground()
	_draw_props()
	_draw_flickers()
	_draw_ghosts()
	_draw_tokens()
	_draw_pops()
	_draw_gooby()
	if float(state.get("lanternT", 0.0)) > 0.0:
		_draw_lantern_glow()
	if _banner_t > 0.0:
		_draw_banner()


func _draw_sky() -> void:
	var top := horizon_y()
	for i in 14:
		var f := float(i) / 13.0
		draw_rect(
			Rect2(0.0, top * f, view_size.x, top / 13.0 + 1.0), SKY_TOP.lerp(SKY_HORIZON, f * f)
		)
	# Mond + Nebelschleier über dem Horizont.
	var moon := Vector2(view_size.x * 0.78, top * 0.34)
	draw_circle(moon, unit() * 0.9, Color(1.0, 0.94, 0.82, 0.16))
	draw_circle(moon, unit() * 0.44, Color(0.98, 0.95, 0.86))
	draw_circle(
		moon + Vector2(unit() * 0.16, -unit() * 0.1), unit() * 0.4, SKY_TOP.lerp(SKY_HORIZON, 0.2)
	)
	for i in 3:
		var y := top * (0.62 + i * 0.12) + sin(_bob * 0.5 + i) * 3.0
		draw_rect(Rect2(0.0, y, view_size.x, top * 0.05), Color(0.85, 0.8, 1.0, 0.05))


func _draw_ground() -> void:
	var top := horizon_y()
	var height := view_size.y - top
	for i in 12:
		var f := float(i) / 11.0
		draw_rect(
			Rect2(0.0, top + height * f, view_size.x, height / 11.0 + 1.0),
			GROUND_FAR.lerp(GROUND_NEAR, f)
		)
	draw_line(Vector2(0.0, top), Vector2(view_size.x, top), Color(0.55, 0.38, 0.42, 0.6), 2.0)


func _draw_props() -> void:
	for spot: Dictionary in Logic.SPOTS:
		var base := project(float(spot["x"]), float(spot["z"]))
		var s := unit() * depth_scale(float(spot["z"]))
		draw_circle(base + Vector2(0.0, s * 0.16), s * 0.5, Color(0.08, 0.06, 0.12, 0.45))
		match str(spot["kind"]):
			"pumpkin":
				# Unbeleuchtet — nur die Attrappen weiter unten flackern hell.
				_draw_pumpkin(base, s, Color(0.55, 0.29, 0.14), 0.0)
			"crypt":
				_draw_crypt(base, s)
			_:
				_draw_grave(base, s)


func _draw_grave(base: Vector2, s: float) -> void:
	var stone := Color(0.62, 0.6, 0.68)
	draw_rect(Rect2(base.x - s * 0.3, base.y - s * 0.85, s * 0.6, s * 0.85), stone)
	draw_circle(Vector2(base.x, base.y - s * 0.85), s * 0.3, stone)
	draw_rect(
		Rect2(base.x - s * 0.07, base.y - s * 0.95, s * 0.14, s * 0.45), Color(0.44, 0.42, 0.5)
	)
	draw_rect(
		Rect2(base.x - s * 0.22, base.y - s * 0.8, s * 0.44, s * 0.12), Color(0.44, 0.42, 0.5)
	)


func _draw_pumpkin(base: Vector2, s: float, tint: Color, glow: float) -> void:
	draw_circle(base - Vector2(0.0, s * 0.3), s * 0.62, Color(tint, glow * 0.5))
	draw_circle(base - Vector2(0.0, s * 0.3), s * 0.38, tint)
	draw_line(
		base - Vector2(0.0, s * 0.68),
		base - Vector2(0.0, s * 0.84),
		Color(0.32, 0.45, 0.2),
		maxf(2.0, s * 0.09)
	)
	# Grinsegesicht.
	var face := Color(1.0, 0.93, 0.55, 0.4 + glow)
	for side in [-1.0, 1.0]:
		draw_circle(base + Vector2(side * s * 0.14, -s * 0.36), s * 0.07, face)
	draw_arc(
		base - Vector2(0.0, s * 0.24), s * 0.18, 0.15 * PI, 0.85 * PI, 12, face, maxf(1.5, s * 0.06)
	)


func _draw_crypt(base: Vector2, s: float) -> void:
	var wall := Color(0.5, 0.48, 0.58)
	draw_rect(Rect2(base.x - s * 0.65, base.y - s * 1.15, s * 1.3, s * 1.15), wall)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(base.x - s * 0.78, base.y - s * 1.15),
				Vector2(base.x + s * 0.78, base.y - s * 1.15),
				Vector2(base.x, base.y - s * 1.6),
			]
		),
		Color(0.4, 0.38, 0.48)
	)
	draw_rect(Rect2(base.x - s * 0.2, base.y - s * 0.7, s * 0.4, s * 0.7), Color(0.14, 0.1, 0.18))


func _draw_flickers() -> void:
	for flick: Dictionary in state["flickers"]:
		var spot: Dictionary = Logic.DECOY_SPOTS[int(flick["decoy"])]
		var base := project(float(spot["x"]), float(spot["z"]))
		var s := unit() * depth_scale(float(spot["z"]))
		var age := float(state["t"]) - float(flick["startT"])
		var flick_f := 0.55 + 0.45 * sin(age * 22.0)
		draw_circle(base - Vector2(0.0, s * 0.3), s * 1.3, Color(LANTERN_TINT, 0.13 * flick_f))
		draw_circle(base - Vector2(0.0, s * 0.3), s * 0.85, Color(LANTERN_TINT, 0.16 * flick_f))
		_draw_pumpkin(base, s, Color(1.0, 0.66, 0.24), 0.4 + 0.6 * flick_f)


func _draw_ghosts() -> void:
	for ghost: Dictionary in state["ghosts"]:
		var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
		var s := unit() * depth_scale(float(spot["z"]))
		var lift := _ghost_lift(ghost)
		if lift <= 0.01:
			continue
		var pos := _ghost_pos(ghost, spot)
		var tint := GHOST_TINT
		if ghost["wave"] != null:
			tint = Color(0.85, 0.78, 1.0)
		var alpha := 0.55 + 0.45 * lift
		draw_circle(pos, s * 1.05, Color(tint, 0.06 * lift))
		draw_circle(pos, s * 0.78, Color(tint, 0.06 * lift))
		_draw_sheet(pos, s * (0.5 + 0.16 * lift), Color(tint, alpha))
		if bool(ghost["revealed"]):
			draw_arc(pos, s * 0.8, 0.0, TAU, 24, Color(LANTERN_TINT, 0.6), 2.0)


## Bettlaken-Geist: Kuppel + Wellensaum + zwei Kulleraugen.
func _draw_sheet(pos: Vector2, r: float, tint: Color) -> void:
	var pts := PackedVector2Array()
	for i in 15:
		var a := PI + PI * float(i) / 14.0
		pts.append(pos + Vector2(cos(a), sin(a)) * r)
	var tips := 8
	for i in range(tips + 1):
		var f := 1.0 - float(i) / float(tips)
		var x := pos.x - r + 2.0 * r * f
		var deep := 0.62 + 0.34 * float(i % 2)
		var y := pos.y + r * (deep + 0.08 * sin(_bob * 5.0 + float(i)))
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, tint)
	for side in [-1.0, 1.0]:
		draw_circle(
			pos + Vector2(side * r * 0.34, -r * 0.12), r * 0.17, Color(0.16, 0.13, 0.24, tint.a)
		)
	draw_circle(pos + Vector2(0.0, r * 0.3), r * 0.11, Color(0.16, 0.13, 0.24, tint.a * 0.8))


func _draw_tokens() -> void:
	for token: Dictionary in state["tokens"]:
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(token["window"])]
		var pos := _token_pos(anchor)
		var s := unit() * depth_scale(float(anchor["z"])) * 0.6
		var is_lantern := str(token["kind"]) == "lantern"
		var tint := LANTERN_TINT if is_lantern else NET_TINT
		draw_circle(pos, s * 1.7, Color(tint, 0.16 + 0.06 * sin(_bob * 6.0)))
		if is_lantern:
			draw_rect(Rect2(pos.x - s * 0.45, pos.y - s * 0.55, s * 0.9, s * 1.1), tint)
			draw_arc(pos - Vector2(0.0, s * 0.8), s * 0.35, PI, TAU, 12, Color(0.8, 0.7, 0.5), 2.0)
		else:
			draw_arc(pos, s * 0.8, 0.0, TAU, 20, tint, 3.0)
			for i in 3:
				var o := (float(i) - 1.0) * s * 0.5
				draw_line(pos + Vector2(o, -s * 0.7), pos + Vector2(o, s * 0.7), tint, 2.0)
				draw_line(pos + Vector2(-s * 0.7, o), pos + Vector2(s * 0.7, o), tint, 2.0)


func _draw_pops() -> void:
	for p in _pops:
		var f := 1.0 - float(p["t"]) / 0.32
		draw_arc(
			p["pos"], unit() * (0.3 + 0.8 * f), 0.0, TAU, 24, Color(1.0, 0.98, 0.9, 1.0 - f), 3.0
		)


## Gooby steht vorn links mit der Kescher-Laterne und wippt.
func _draw_gooby() -> void:
	var s := unit() * 0.85
	var pos := Vector2(view_size.x * 0.13, view_size.y * (0.86 if landscape else 0.93))
	var bob := sin(_bob * 2.2) * s * 0.05
	pos.y += bob
	draw_circle(pos + Vector2(0.0, s * 0.85), s * 0.95, Color(0.99, 0.9, 0.66))
	draw_circle(pos, s * 0.7, Color(0.99, 0.93, 0.74))
	for side in [-1.0, 1.0]:
		draw_circle(pos + Vector2(side * s * 0.33, -s * 0.84), s * 0.23, Color(0.99, 0.93, 0.74))
		draw_circle(pos + Vector2(side * s * 0.25, -s * 0.05), s * 0.1, Color(0.22, 0.18, 0.16))
	draw_circle(pos + Vector2(0.0, s * 0.2), s * 0.09, Color(0.96, 0.62, 0.68))
	var hand := pos + Vector2(s * 0.95, s * 0.35 - bob)
	draw_line(pos + Vector2(s * 0.6, s * 0.7), hand, Color(0.99, 0.9, 0.66), s * 0.2)
	draw_circle(hand, s * 0.5, Color(LANTERN_TINT, 0.22))
	draw_circle(hand, s * 0.2, LANTERN_TINT)


func _draw_lantern_glow() -> void:
	var alpha := 0.1 * clampf(float(state["lanternT"]) / float(Logic.HUNT["LANTERN_SEC"]), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(LANTERN_TINT, alpha))


func _draw_banner() -> void:
	var fade := clampf(_banner_t / 0.4, 0.0, 1.0)
	var y := horizon_y() + view_size.y * 0.06
	var size := int(maxf(22.0, view_size.y * 0.032))
	draw_rect(
		Rect2(0.0, y - size * 1.2, view_size.x, size * 2.2), Color(0.1, 0.07, 0.16, 0.4 * fade)
	)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, y + size * 0.4),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		size,
		Color(1.0, 0.9, 0.65, fade)
	)
