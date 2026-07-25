extends MinigameBase
## Hafen-Hüpfer (harborHopper) — Spiel-Szene. Die GESAMTE Mechanik läuft in
## HarborHopperLogic.HarborEngine (zahlengleich zum Web): Kisten +4, Netzringe
## +2, Bojen/Molen −3 + Slow, Wellenkämme mittig = +30 % für 2 s (kettbar),
## Möwe klaut nach 4 s Spurstillstand, Horn räumt Bojen (2 Ladungen).
##
## 2D statt 3D (Web war three.js mit Watercraft-Kit-GLBs): die GLBs gibt es im
## Godot-Projekt nicht und der Kanal ist eine reine Tiefenachse. Die
## perspektivische Sticker-Projektion (project()) hält JEDE Weltmeter-Zahl
## exakt — Kollisionen rechnet ohnehin die Engine in Weltkoordinaten.
## Anders als im Web wird hier NICHT gespiegelt (Web §G3.1-c drehte die
## Kamera): Ziehen nach rechts fährt nach rechts, Weltachse = Bildschirmachse.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `boat_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Boote liefert.

const Logic := preload("res://scripts/minigames/games/harbor_hopper/harbor_hopper_logic.gd")

## Kamera-Abstand hinter dem Bug (m).
const CAM_BEHIND := 7.0
## Sichtweite (m) und Nahgrenze (m).
const DRAW_FAR_M := 58.0
const DRAW_NEAR_M := -4.5
## Kaimauer-Oberkante über dem Wasser (m).
const QUAY_H := 1.15
## Wie weit außerhalb des Kanals die Kaimauer steht (m).
const QUAY_PAD := 0.75
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

## Autohaus-Haken: später vom Host befüllbar.
var boat_skin := ""
var speed_bonus := 0.0

var tune: Dictionary = {}
var engine: RefCounted
var score := 0
var boosts := 0
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _drag_x: Variant = null
var _horn_queued := false
var _touch_from := Vector2.ZERO
var _touch_moved := false
var _horn_flash := 0.0
var _gull_t := 0.0
var _gull_mode := ""
var _wake := 0.0
var _focal_px := 400.0
var _cam_y := 2.2
var _horizon_px := 150.0
var _ui := 1.0
var _time_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.HARBOR, ctx.difficulty)
	engine = Logic.HarborEngine.new(ctx.rng(), tune)
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
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	_recompute_camera()
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_stat_label.position = Vector2(pad, 44.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2(pad, view_size.y - 44.0 * _ui)
	_hint_label.size = Vector2(maxf(120.0, view_size.x - pad * 2.0), 38.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var dt := minf(delta, float(tune["MAX_DT"]))
	_banner_t = maxf(0.0, _banner_t - dt)
	_horn_flash = maxf(0.0, _horn_flash - dt)
	if _gull_mode != "":
		_gull_t += dt
	var input := {"targetX": _drag_x, "horn": _horn_queued}
	_horn_queued = false
	var events: Array = engine.step(input, dt)
	_wake += Logic.speed_of(engine.state, tune) * dt
	for ev: Dictionary in events:
		_handle_event(ev)
	var total := Logic.hopper_score(engine.state, tune)
	if total != score:
		ctx.report_score(total, total - score)
		score = total
	if bool(engine.state["ended"]):
		_finish()
		return
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_from = event.position
			_touch_moved = false
			_steer_to(event.position.x)
		else:
			if not _touch_moved:
				_horn_queued = true
			_drag_x = null
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_touch_from) > 12.0:
			_touch_moved = true
		_steer_to(event.position.x)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Tastatur-Ersatz (Desktop/Screenshot-Harness).
		var half_w := float(tune["CHANNEL_HALF_W"])
		var here := float(engine.state["x"])
		match event.keycode:
			KEY_LEFT:
				_drag_x = clampf(here - 1.6, -half_w, half_w)
			KEY_RIGHT:
				_drag_x = clampf(here + 1.6, -half_w, half_w)
			KEY_DOWN:
				_drag_x = null
			KEY_SPACE:
				_horn_queued = true


## Weltpunkt (x rechts, y hoch, rel_z voraus) → Bildschirmpixel.
func project(wx: float, wy: float, rel_z: float) -> Vector2:
	var s := scale_at(rel_z)
	return Vector2(view_size.x * 0.5 + wx * s, _horizon_px + (_cam_y - wy) * s)


## Pixel pro Meter in dieser Tiefe.
func scale_at(rel_z: float) -> float:
	return _focal_px / maxf(0.4, CAM_BEHIND + rel_z)


## Kamera aus dem Layout ableiten: der Kanal füllt einen festen Anteil der
## Breite, das Boot sitzt auf einem festen Höhenanteil.
func _recompute_camera() -> void:
	var channel_fill := 0.52 if landscape else 0.92
	var horizon_frac := 0.34 if landscape else 0.28
	var boat_frac := 0.8 if landscape else 0.78
	var half_w := float(tune.get("CHANNEL_HALF_W", 3.2))
	_focal_px = channel_fill * view_size.x * CAM_BEHIND / (2.0 * half_w)
	_horizon_px = view_size.y * horizon_frac
	_cam_y = (view_size.y * boat_frac - _horizon_px) * CAM_BEHIND / _focal_px


func _steer_to(px: float) -> void:
	var nx := clampf(px / maxf(1.0, view_size.x) * 2.0 - 1.0, -1.0, 1.0)
	_drag_x = nx * float(tune["CHANNEL_HALF_W"]) * 1.25


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.harborHopper.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf dem Wasser — heller Text mit weichem Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.94))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.06, 0.2, 0.3, 0.45))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _handle_event(ev: Dictionary) -> void:
	var boat_px := project(float(engine.state["x"]), 0.9, 0.0)
	match str(ev["type"]):
		"crate":
			AudioDirector.try_play(self, "mg_good")
			_float("+%d" % int(tune["CRATE_POINTS"]), boat_px, Color(1.0, 0.82, 0.4))
		"ring":
			AudioDirector.try_play(self, "gvz_collect")
			_float("+%d" % int(tune["RING_POINTS"]), boat_px, Color(0.54, 0.88, 0.82))
		"bump":
			AudioDirector.try_play(self, "mg_spill")
			_float("%d" % int(tune["BUMP_PENALTY"]), boat_px, Color(1.0, 0.42, 0.42))
			if ctx.juice != null:
				ctx.juice.shake(0.45)
				ctx.juice.hit_freeze(70)
			_set_banner(I18nService.t("mg.harborHopper.bump"))
		"boost":
			boosts += 1
			AudioDirector.try_play(self, "mg_combo")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.8)
			var chain := int(ev["chain"])
			_set_banner(
				(
					I18nService.t("mg.harborHopper.boost_chain", {"n": chain})
					if chain > 1
					else I18nService.t("mg.harborHopper.boost")
				)
			)
		"buoyCleared":
			AudioDirector.try_play(self, "gvz_wave")
			_horn_flash = 0.5
			_set_banner(I18nService.t("mg.harborHopper.horn", {"n": int(ev["count"])}))
		"hornEmpty":
			AudioDirector.try_play(self, "ui_error")
			_set_banner(I18nService.t("mg.harborHopper.horn_empty"))
		"gullWarn":
			AudioDirector.try_play(self, "mg_junk")
			_gull_mode = "circle"
			_gull_t = 0.0
			_set_banner(I18nService.t("mg.harborHopper.gull_warn"))
		"gullSteal":
			AudioDirector.try_play(self, "mg_lose")
			_gull_mode = "leave"
			_gull_t = 0.0
			_float("-%d" % int(tune["CRATE_POINTS"]), boat_px, Color(1.0, 0.42, 0.42))
			_set_banner(I18nService.t("mg.harborHopper.gull_steal"))
		"gullLeave":
			if _gull_mode == "circle":
				_gull_mode = "leave"
				_gull_t = 0.0


func _float(text: String, pos: Vector2, color: Color) -> void:
	if ctx.juice != null:
		ctx.juice.float_text(pos, text, color)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	var s: Dictionary = engine.state
	(
		ctx
		. report_end(
			{
				"score": Logic.hopper_score(s, tune),
				"crates": int(s["crates"]),
				"rings": int(s["rings"]),
				"bumps": int(s["bumps"]),
				"steals": int(s["steals"]),
				"boosts": boosts,
				"distanceM": int(floorf(float(s["z"]))),
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _update_labels() -> void:
	var s: Dictionary = engine.state
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.harborHopper.bump_count",
			{"n": int(s["bumps"]), "max": int(tune["ENDLESS_BUMP_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(s["elapsed"]))))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t(
		"mg.harborHopper.stats", {"crates": int(s["crates"]), "horn": int(s["hornCharges"])}
	)


func _draw() -> void:
	_draw_sea()
	_draw_quays()
	_draw_piers()
	_draw_waves()
	_draw_items()
	_draw_horn_cone()
	_draw_boat()
	_draw_gull()
	_draw_banner()


func _draw_sea() -> void:
	# Himmel + Hafenkulisse über dem Horizont
	draw_rect(Rect2(0.0, 0.0, view_size.x, _horizon_px), Color(0.68, 0.85, 0.95))
	var skyline := _horizon_px
	for i in 9:
		var w := view_size.x / 9.0
		var h := (14.0 + fposmod(i * 37.0, 44.0)) * (view_size.y / 720.0)
		draw_rect(Rect2(i * w + 4.0, skyline - h, w - 8.0, h), Color(0.55, 0.66, 0.72, 0.75))
		draw_circle(Vector2(i * w + w * 0.5, skyline - h), 3.0, Color(0.95, 0.85, 0.5, 0.8))
	draw_rect(
		Rect2(0.0, _horizon_px, view_size.x, view_size.y - _horizon_px), Color(0.2, 0.48, 0.64)
	)
	# Dunstband direkt unter dem Horizont — Tiefe ohne echten Verlauf
	for i in 8:
		draw_rect(
			Rect2(0.0, _horizon_px + i * 5.0, view_size.x, 5.0),
			Color(0.55, 0.78, 0.86, 0.5 - i * 0.06)
		)
	# Kielwasser-Rippeln: alle 4 m eine Linie, mitscrollend
	var half_w := float(tune["CHANNEL_HALF_W"])
	var offset := fposmod(_wake, 4.0)
	var rel := DRAW_FAR_M
	while rel > DRAW_NEAR_M:
		var z := rel - offset
		if z > DRAW_NEAR_M:
			var a := project(-half_w - QUAY_PAD, 0.0, z)
			var b := project(half_w + QUAY_PAD, 0.0, z)
			var fade := clampf(1.0 - z / DRAW_FAR_M, 0.12, 0.5)
			draw_line(a, b, Color(0.42, 0.72, 0.85, fade), maxf(1.0, scale_at(z) * 0.03))
		rel -= 4.0


func _draw_quays() -> void:
	var half_w := float(tune["CHANNEL_HALF_W"])
	var edge := half_w + QUAY_PAD
	for side: float in [-1.0, 1.0]:
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var rel := DRAW_FAR_M
		while rel > DRAW_NEAR_M:
			top.append(project(side * edge, QUAY_H, rel))
			bottom.append(project(side * edge, 0.0, rel))
			rel -= 2.0
		# Land hinter der Kaikante. Segmentweise Vierecke statt eines großen
		# Polygons: die Kaikante läuft weit aus dem Bild, ein geschlossener
		# Zug würde sich selbst schneiden (Triangulierung schlägt fehl).
		var out_x := -view_size.x * 3.0 if side < 0.0 else view_size.x * 4.0
		var land := Color(0.7, 0.66, 0.58)
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(out_x, _horizon_px),
					Vector2(top[0].x, _horizon_px),
					top[0],
					Vector2(out_x, top[0].y),
				]
			),
			land
		)
		for i in top.size() - 1:
			draw_colored_polygon(
				PackedVector2Array(
					[
						top[i],
						top[i + 1],
						Vector2(out_x, top[i + 1].y),
						Vector2(out_x, top[i].y),
					]
				),
				land
			)
		var wall := PackedVector2Array(top)
		for i in range(bottom.size() - 1, -1, -1):
			wall.append(bottom[i])
		draw_colored_polygon(wall, Color(0.5, 0.44, 0.37))
		draw_polyline(top, Color(0.82, 0.78, 0.68), 3.0)
		# Poller im Abstand von 6 m, dazwischen Hafen-Container
		var post := ceilf(DRAW_NEAR_M / 6.0) * 6.0
		var idx := 0
		while post < DRAW_FAR_M:
			idx += 1
			var base := project(side * edge, QUAY_H, post)
			var s := scale_at(post)
			draw_rect(
				Rect2(base + Vector2(-s * 0.09, -s * 0.4), Vector2(s * 0.18, s * 0.4)),
				Color(0.32, 0.3, 0.28)
			)
			var box_z := post + 3.0
			if box_z < DRAW_FAR_M and idx % 2 == 1:
				var bs := scale_at(box_z)
				var lateral := edge + 1.9 + float(idx % 3) * 0.8
				var anchor := project(side * lateral, QUAY_H, box_z)
				var palette: Array[Color] = [
					Color(0.72, 0.35, 0.3), Color(0.32, 0.5, 0.6), Color(0.6, 0.55, 0.3)
				]
				var hue := palette[(idx + int(side)) % 3]
				var box := Rect2(
					anchor + Vector2(-bs * 0.62, -bs * 0.52), Vector2(bs * 1.24, bs * 0.52)
				)
				draw_rect(
					Rect2(box.position + Vector2(bs * 0.08, bs * 0.46), box.size),
					Color(0.45, 0.42, 0.36, 0.35)
				)
				draw_rect(box, hue)
				draw_rect(box, hue.darkened(0.35), false, 2.0)
				for rib in 4:
					var rx := box.position.x + box.size.x * (rib + 1) / 5.0
					draw_line(
						Vector2(rx, box.position.y),
						Vector2(rx, box.position.y + box.size.y),
						hue.darkened(0.18),
						1.5
					)
			post += 6.0


func _draw_piers() -> void:
	var half_w := float(tune["CHANNEL_HALF_W"])
	var edge := half_w + QUAY_PAD
	var reach := float(tune["PIER_REACH_M"])
	var depth := float(tune["PIER_DEPTH_M"])
	for pier: Dictionary in engine.piers:
		var rel := float(pier["z"]) - float(engine.state["z"])
		if rel > DRAW_FAR_M or rel < DRAW_NEAR_M:
			continue
		var side := float(pier["side"])
		var inner := side * (half_w - reach)
		var outer := side * edge
		var quad := PackedVector2Array(
			[
				project(outer, 0.35, rel + depth * 0.5),
				project(inner, 0.35, rel + depth * 0.5),
				project(inner, 0.35, rel - depth * 0.5),
				project(outer, 0.35, rel - depth * 0.5),
			]
		)
		draw_colored_polygon(quad, Color(0.55, 0.4, 0.28))
		draw_polyline(quad, Color(0.38, 0.27, 0.18), 2.0)
		quad.append(quad[0])
		# Warnstreifen an der Spitze
		var tip := project(inner, 0.35, rel)
		draw_circle(tip, maxf(2.0, scale_at(rel) * 0.14), Color(0.95, 0.78, 0.25))


func _draw_waves() -> void:
	var half_w := float(tune["CHANNEL_HALF_W"])
	var sweet := float(tune["SWEET_HALF_W"])
	for wave: Dictionary in engine.waves:
		var rel := float(wave["z"]) - float(engine.state["z"])
		if rel > DRAW_FAR_M or rel < DRAW_NEAR_M:
			continue
		var s := scale_at(rel)
		var crest := PackedVector2Array()
		var steps := 22
		for i in steps + 1:
			var wx := -half_w + (half_w * 2.0) * i / float(steps)
			var bob := 0.1 * sin(wx * 2.2 + rel * 0.8)
			crest.append(project(wx, 0.16 + bob, rel))
		draw_polyline(crest, Color(0.36, 0.68, 0.84, 0.9), maxf(2.0, s * 0.09))
		draw_polyline(crest, Color(0.86, 0.95, 1.0, 0.55), maxf(1.0, s * 0.035))
		if bool(wave["ridden"]):
			continue
		# Schaumiger Sweet-Spot: HIER gibt es den Surf-Schub
		var sx := float(wave["sweetX"])
		var foam := PackedVector2Array()
		for i in 13:
			var wx := sx - sweet + (sweet * 2.0) * i / 12.0
			foam.append(project(wx, 0.28, rel))
		draw_polyline(foam, Color(1.0, 1.0, 1.0, 0.9), maxf(2.0, s * 0.12))
		var mid := project(sx, 0.45, rel)
		draw_circle(mid, maxf(2.0, s * 0.1), Color(1.0, 1.0, 1.0, 0.75))


func _draw_items() -> void:
	var sorted: Array[Dictionary] = []
	for item: Dictionary in engine.items:
		if bool(item["gone"]):
			continue
		var rel := float(item["z"]) - float(engine.state["z"])
		if rel > DRAW_FAR_M or rel < DRAW_NEAR_M:
			continue
		sorted.append(item)
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["z"]) > float(b["z"])
	)
	for item: Dictionary in sorted:
		var rel := float(item["z"]) - float(engine.state["z"])
		var x := float(item["x"])
		var s := scale_at(rel)
		match str(item["type"]):
			"crate":
				_draw_crate(x, rel, s)
			"ring":
				_draw_ring(x, rel, s)
			"buoy":
				_draw_buoy(x, rel, s)


func _draw_crate(x: float, rel: float, s: float) -> void:
	var bob := 0.06 * sin(_wake * 1.4 + x * 3.0)
	var base := project(x, 0.06 + bob, rel)
	var w := s * 0.46
	draw_circle(base + Vector2(0.0, w * 0.28), w * 0.9, Color(0.16, 0.4, 0.55, 0.35))
	var box := Rect2(base + Vector2(-w * 0.5, -w * 0.9), Vector2(w, w * 0.9))
	draw_rect(box, Color(0.78, 0.56, 0.32))
	draw_rect(box, Color(0.5, 0.34, 0.18), false, maxf(1.0, s * 0.02))
	draw_line(
		box.position + Vector2(0.0, box.size.y * 0.45),
		box.position + Vector2(box.size.x, box.size.y * 0.45),
		Color(0.5, 0.34, 0.18),
		maxf(1.0, s * 0.02)
	)
	draw_line(
		box.position + Vector2(box.size.x * 0.5, 0.0),
		box.position + Vector2(box.size.x * 0.5, box.size.y),
		Color(0.5, 0.34, 0.18),
		maxf(1.0, s * 0.02)
	)


func _draw_ring(x: float, rel: float, s: float) -> void:
	var bob := 0.07 * sin(_wake * 1.7 + x * 2.0)
	var c := project(x, 0.42 + bob, rel)
	var r := s * float(tune["RING_RADIUS"])
	draw_arc(c, r, 0.0, TAU, 26, Color(0.35, 0.82, 0.74), maxf(2.0, s * 0.11))
	draw_arc(c, r, 0.0, TAU, 26, Color(0.86, 1.0, 0.96, 0.7), maxf(1.0, s * 0.04))
	# Netzkreuz
	draw_line(c + Vector2(-r, 0.0), c + Vector2(r, 0.0), Color(0.72, 0.95, 0.9, 0.45), 1.5)
	draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, r), Color(0.72, 0.95, 0.9, 0.45), 1.5)


func _draw_buoy(x: float, rel: float, s: float) -> void:
	var bob := 0.09 * sin(_wake * 2.1 + x * 4.0)
	var base := project(x, 0.02 + bob, rel)
	var r := s * float(tune["BUOY_RADIUS"])
	draw_circle(base + Vector2(0.0, r * 0.3), r * 0.95, Color(0.16, 0.4, 0.55, 0.35))
	draw_circle(base + Vector2(0.0, -r * 0.5), r * 0.62, Color(0.88, 0.28, 0.26))
	draw_circle(base + Vector2(0.0, -r * 0.5), r * 0.62, Color(0.62, 0.16, 0.16), false, 2.0)
	draw_rect(
		Rect2(base + Vector2(-r * 0.62, -r * 0.66), Vector2(r * 1.24, r * 0.24)),
		Color(0.98, 0.96, 0.92)
	)
	draw_line(
		base + Vector2(0.0, -r * 1.1),
		base + Vector2(0.0, -r * 1.9),
		Color(0.35, 0.35, 0.38),
		maxf(1.5, s * 0.03)
	)
	draw_circle(base + Vector2(0.0, -r * 2.0), r * 0.2, Color(0.98, 0.85, 0.35))


func _draw_horn_cone() -> void:
	if _horn_flash <= 0.0:
		return
	var x := float(engine.state["x"])
	var reach := float(tune["HORN_CONE_M"])
	var spread := float(tune["HORN_CONE_SPREAD"])
	var base := float(tune["HORN_CONE_BASE"])
	var cone := PackedVector2Array(
		[
			project(x - base, 0.25, 0.0),
			project(x - base - reach * spread, 0.25, reach),
			project(x + base + reach * spread, 0.25, reach),
			project(x + base, 0.25, 0.0),
		]
	)
	draw_colored_polygon(cone, Color(1.0, 0.94, 0.6, 0.28 * (_horn_flash / 0.5)))


func _draw_boat() -> void:
	var s: Dictionary = engine.state
	var x := float(s["x"])
	var px := scale_at(0.0)
	var roll := clampf(float(s["vx"]) / float(tune["MAX_LATERAL_SPEED"]), -1.0, 1.0)
	var bob := 0.045 * sin(_wake * 2.6)
	var c := project(x, 0.12 + bob, 0.0)
	var hull_w := px * 1.5
	var hull_h := px * 0.52
	# Bugwelle als V-Kielwasser (läuft nach hinten/unten auseinander)
	var wake_color := Color(0.62, 0.86, 0.95, 0.45)
	if float(s["boostT"]) > 0.0:
		wake_color = Color(1.0, 1.0, 1.0, 0.6)
	draw_colored_polygon(
		PackedVector2Array(
			[
				c + Vector2(-hull_w * 0.34, -hull_h * 0.2),
				c + Vector2(hull_w * 0.34, -hull_h * 0.2),
				c + Vector2(hull_w * 0.8, hull_h * 1.0),
				c + Vector2(-hull_w * 0.8, hull_h * 1.0),
			]
		),
		Color(wake_color.r, wake_color.g, wake_color.b, wake_color.a * 0.45)
	)
	draw_line(
		c + Vector2(-hull_w * 0.34, -hull_h * 0.2),
		c + Vector2(-hull_w * 0.8, hull_h * 1.0),
		wake_color,
		maxf(2.0, px * 0.04)
	)
	draw_line(
		c + Vector2(hull_w * 0.34, -hull_h * 0.2),
		c + Vector2(hull_w * 0.8, hull_h * 1.0),
		wake_color,
		maxf(2.0, px * 0.04)
	)
	var lean := roll * hull_w * 0.06
	var hull := PackedVector2Array(
		[
			c + Vector2(-hull_w * 0.5 + lean, -hull_h * 0.5),
			c + Vector2(hull_w * 0.5 + lean, -hull_h * 0.5),
			c + Vector2(hull_w * 0.36, hull_h * 0.5),
			c + Vector2(-hull_w * 0.36, hull_h * 0.5),
		]
	)
	var flash := float(s["iframesT"]) > 0.0 and fmod(_wake * 6.0, 2.0) < 1.0
	draw_colored_polygon(hull, Color(0.94, 0.5, 0.35) if not flash else Color(1.0, 0.8, 0.75))
	var rim := PackedVector2Array(hull)
	rim.append(hull[0])
	draw_polyline(rim, Color(0.62, 0.28, 0.2), maxf(2.0, px * 0.03))
	# Deckskisten (Fracht an Bord)
	var crates := mini(int(s["crates"]), 5)
	for i in crates:
		var cw := hull_w * 0.14
		var cx := c.x - hull_w * 0.3 + i * cw * 1.15 + lean
		draw_rect(Rect2(cx, c.y - hull_h * 0.5 - cw, cw, cw), Color(0.8, 0.58, 0.34))
		draw_rect(Rect2(cx, c.y - hull_h * 0.5 - cw, cw, cw), Color(0.52, 0.35, 0.2), false, 1.5)
	# Steuerhaus + Gooby
	var cab := Rect2(
		c + Vector2(hull_w * 0.08 + lean, -hull_h * 0.5 - px * 0.5), Vector2(px * 0.42, px * 0.5)
	)
	draw_rect(cab, Color(0.98, 0.95, 0.88))
	draw_rect(cab, Color(0.62, 0.28, 0.2), false, 2.0)
	draw_rect(
		Rect2(cab.position + Vector2(px * 0.06, px * 0.1), Vector2(px * 0.3, px * 0.18)),
		Color(0.6, 0.82, 0.94)
	)
	var head := cab.position + Vector2(cab.size.x * 0.5, -px * 0.16)
	draw_circle(head, px * 0.19, Color(0.99, 0.87, 0.72))
	draw_circle(head + Vector2(-px * 0.07, -px * 0.02), px * 0.03, Color(0.22, 0.16, 0.14))
	draw_circle(head + Vector2(px * 0.07, -px * 0.02), px * 0.03, Color(0.22, 0.16, 0.14))
	draw_arc(head, px * 0.19, PI, TAU, 14, Color(0.24, 0.42, 0.66), maxf(2.0, px * 0.05))


func _draw_gull() -> void:
	if _gull_mode == "":
		return
	var px := scale_at(0.0)
	var boat := project(float(engine.state["x"]), 0.12, 0.0)
	var pos := boat
	if _gull_mode == "circle":
		pos += Vector2(cos(_gull_t * 3.0) * px * 0.55, -px * 1.15 + sin(_gull_t * 3.0) * px * 0.1)
	else:
		pos += Vector2(_gull_t * px * 1.4, -px * 1.2 - _gull_t * px * 0.9)
		if _gull_t > 1.6:
			_gull_mode = ""
			return
	var flap := sin(_gull_t * 14.0) * px * 0.12
	draw_circle(pos, px * 0.13, Color(0.98, 0.98, 1.0))
	draw_line(pos, pos + Vector2(-px * 0.3, -flap), Color(0.92, 0.93, 0.98), maxf(2.0, px * 0.05))
	draw_line(pos, pos + Vector2(px * 0.3, -flap), Color(0.92, 0.93, 0.98), maxf(2.0, px * 0.05))
	draw_circle(pos + Vector2(px * 0.11, -px * 0.02), px * 0.03, Color(0.98, 0.72, 0.2))
	if _gull_mode == "leave":
		draw_rect(
			Rect2(pos + Vector2(-px * 0.08, px * 0.1), Vector2(px * 0.16, px * 0.16)),
			Color(0.8, 0.58, 0.34)
		)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	draw_string(
		font,
		Vector2(view_size.x * 0.5 - 220.0, view_size.y * 0.16),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		440.0,
		26,
		Color(1.0, 0.99, 0.94, alpha)
	)
