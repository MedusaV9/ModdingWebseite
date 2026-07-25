extends MinigameBase
## Gemüse-Schnippler (veggieChop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## VeggieChopLogic (zahlengleich zum Web, Bot-zertifiziert): Gemüse fliegt in
## Bögen hoch (1–3 gleichzeitig, ab 20 s / 40 s), ein Wisch schneidet +2 und
## jedes weitere Stück im selben Wisch +3, Müll −3 mit 0,5 s Stun, drei
## verpasste Gemüse beenden die Runde. Alle 25 s Frenzy: 8 Gemüse, kein Müll.
## Optik: Pastellküche mit Schneidebrett, dicke Outlines, Wischspur mit
## Saftspritzern, Gooby-Cameo schnippelt links mit.

## Halbe sichtbare Welthöhe — im Web `tan(CAMERA_FOV/2) * 10` bei FOV 45°
## (veggieChop.js: `halfH = Math.tan(degToRad(camera.fov / 2)) * 10`). Das
## Scheitelband der Logik (−0,4 … 2,3) ist auf DIESEN Rahmen geeicht: die
## Bildmitte liegt bei y = 0, nicht an der Unterkante.
const HALF_H := 4.142135623730951
## Sichtbare Welthöhe in Metern.
const WORLD_SPAN := HALF_H * 2.0
## Weltunterkante.
const GROUND_Y := -HALF_H
## Abwurfhöhe knapp unter der Kante (Web: `launchY = -halfH - 0.6`).
const SPAWN_Y := -HALF_H - 0.6
## Lebensdauer eines Wischspur-Punktes in Sekunden.
const TRAIL_LIFE := 0.24
## Farbenblind-sichere Symbole (gleiche Familie wie bubblePop).
var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var misses := 0
var junk_hits := 0
var swipe_combo := 0
var stun_until := -1.0
var next_spawn := 0.0
var frenzies := 0
var frenzy_until := -1.0
var frenzy_left := 0
var items: Array[Dictionary] = []
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _miss_label: Label
var _hint_label: Label
var _banner_label: Label
var _banner_until := -1.0
var _trail: Array[Dictionary] = []
var _halves: Array[Dictionary] = []
var _swiping := false
var _last_point := Vector2.ZERO
var _bob := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = VeggieChopLogic.apply_difficulty(VeggieChopLogic.CHOP, ctx.difficulty)
	rng = ctx.rng()
	next_spawn = VeggieChopLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
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
	if _time_label == null:
		return
	_time_label.position = Vector2(16.0, 10.0)
	_miss_label.position = Vector2(16.0, 48.0)
	var banner_w := minf(view_size.x - 32.0, 420.0)
	_banner_label.position = Vector2((view_size.x - banner_w) * 0.5, 84.0 if not landscape else 8.0)
	_banner_label.size = Vector2(banner_w, 44.0)
	_hint_label.position = Vector2(view_size.x * 0.5 - 180.0, view_size.y - 40.0)
	_hint_label.size = Vector2(360.0, 34.0)
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_miss_label = Label.new()
	_miss_label.theme_type_variation = &"CaptionLabel"
	add_child(_miss_label)
	_banner_label = Label.new()
	_banner_label.theme_type_variation = &"TitleLabel"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_banner_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.veggieChop.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var step := delta * float(tune.get("SPEED_MULT", 1.0))
	elapsed += step
	_bob += delta
	_frenzy_tick()
	_spawn_tick(step)
	_fly_tick(step)
	_decay_effects(delta)
	if _round_over():
		_finish()
		return
	_update_labels()
	queue_redraw()


## Rundenende: Endlos an drei Müllschnitten, getaktet an Zeit oder 3 Fehlern.
func _round_over() -> bool:
	if VeggieChopLogic.endless_should_end(junk_hits, tune):
		return true
	if misses >= int(tune["MAX_MISSES"]):
		return true
	return not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"])


## Alle 25 s startet ein müllfreier Achterschwung.
func _frenzy_tick() -> void:
	var due := VeggieChopLogic.frenzy_count_at(elapsed)
	if due <= frenzies:
		return
	frenzies = due
	frenzy_until = elapsed + float(tune["FRENZY_DURATION_SEC"])
	frenzy_left = int(tune["FRENZY_ITEMS"])
	next_spawn = 0.0
	_banner_label.text = I18nService.t("mg.veggieChop.frenzy")
	_banner_until = elapsed + 2.0
	AudioDirector.try_play(self, "mg_golden")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)


func _spawn_tick(step: float) -> void:
	next_spawn -= step
	if next_spawn > 0.0:
		return
	if frenzy_left > 0 and elapsed <= frenzy_until:
		next_spawn = VeggieChopLogic.frenzy_spawn_interval()
		frenzy_left -= 1
		_throw(VeggieChopLogic.roll_veggie(rng))
		return
	next_spawn = VeggieChopLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var size := VeggieChopLogic.wave_size_at(rng, elapsed)
	for _i in size:
		_throw(VeggieChopLogic.roll_item(rng, elapsed, tune))


func _throw(item: Dictionary) -> void:
	var g := float(tune["GRAVITY"])
	var arc := VeggieChopLogic.make_arc(rng, _half_w(), SPAWN_Y, g)
	var start := VeggieChopLogic.arc_pos(arc, 0.0, g)
	(
		items
		. append(
			{
				"item": item,
				"arc": arc,
				"t": 0.0,
				"pos": start,
				"prev": start,
				"spin": rng.next() * TAU,
			}
		)
	)
	AudioDirector.try_play(self, "gvz_pop", 1.1)


func _fly_tick(step: float) -> void:
	var g := float(tune["GRAVITY"])
	# Web (veggieChop.js): erst NACH dem Scheitel und unter `launchY − 0.3`
	# zählt ein Wurf als durch. Die frühere Fassung nahm die Weltunterkante
	# plus eine 0,12-s-Schonfrist und verwarf Würfe damit zu früh.
	var floor_y := SPAWN_Y - 0.3
	var kept: Array[Dictionary] = []
	for entry in items:
		entry["prev"] = entry["pos"]
		entry["t"] = float(entry["t"]) + step
		var arc: Dictionary = entry["arc"]
		var pos: Vector2 = VeggieChopLogic.arc_pos(arc, float(entry["t"]), g)
		entry["pos"] = pos
		if float(entry["t"]) <= float(arc["vy"]) / g or pos.y >= floor_y:
			kept.append(entry)
		elif str((entry["item"] as Dictionary)["kind"]) == "veggie":
			_register_miss()
	items = kept


func _register_miss() -> void:
	misses += 1
	swipe_combo = 0
	AudioDirector.try_play(self, "mg_spill", 0.9)
	if ctx.juice == null:
		return
	ctx.juice.shake(0.22)
	ctx.juice.float_text(
		Vector2(view_size.x * 0.5, view_size.y - 120.0),
		I18nService.t("mg.veggieChop.miss", {"n": maxi(0, int(tune["MAX_MISSES"]) - misses)}),
		AcTokens.DANGER
	)


func _decay_effects(delta: float) -> void:
	var trail: Array[Dictionary] = []
	for point in _trail:
		point["age"] = float(point["age"]) + delta
		if float(point["age"]) < TRAIL_LIFE:
			trail.append(point)
	_trail = trail
	var halves: Array[Dictionary] = []
	for half in _halves:
		half["age"] = float(half["age"]) + delta
		half["pos"] = Vector2(half["pos"]) + Vector2(half["vel"]) * delta
		half["vel"] = Vector2(half["vel"]) + Vector2(0.0, 1400.0 * delta)
		if float(half["age"]) < 0.9:
			halves.append(half)
	_halves = halves
	if _banner_until > 0.0 and elapsed > _banner_until:
		_banner_until = -1.0
		_banner_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_swiping = touch.pressed
		_last_point = touch.position
		if touch.pressed:
			swipe_combo = 0
			_trail.append({"pos": touch.position, "age": 0.0})
	elif event is InputEventScreenDrag and _swiping:
		var drag := event as InputEventScreenDrag
		_trail.append({"pos": drag.position, "age": 0.0})
		_cut_segment(_last_point, drag.position)
		_last_point = drag.position


## Wischsegment gegen den zurückgelegten Weg jedes Objekts prüfen (Low-FPS-fest).
func _cut_segment(from: Vector2, to: Vector2) -> void:
	if elapsed < stun_until or from.distance_to(to) < 1.0:
		return
	var a := _to_world(from)
	var b := _to_world(to)
	var radius := float(tune["HIT_RADIUS"])
	var kept: Array[Dictionary] = []
	for entry in items:
		var hit := VeggieChopLogic.segment_hits_moving_circle(
			a, b, Vector2(entry["prev"]), Vector2(entry["pos"]), radius
		)
		if hit:
			_resolve_hit(entry)
		else:
			kept.append(entry)
	items = kept


func _resolve_hit(entry: Dictionary) -> void:
	var item: Dictionary = entry["item"]
	var pos := _to_screen(Vector2(entry["pos"]))
	var kind := str(item["kind"])
	swipe_combo = VeggieChopLogic.combo_after_hit(swipe_combo, kind)
	if kind == "junk":
		_hit_junk(pos)
		return
	var points := VeggieChopLogic.chop_points(swipe_combo)
	score = VeggieChopLogic.apply_points(score, points)
	_spawn_halves(pos, Color(str(item["juice"])))
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.04 * minf(swipe_combo, 6.0))
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % points, AcTokens.LEAF_DARK)
	if swipe_combo > 1:
		AudioDirector.try_play(self, "mg_combo", 1.0 + 0.05 * minf(swipe_combo, 6.0))
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.35 + 0.1 * float(swipe_combo))
			ctx.juice.float_text(
				pos - Vector2(0.0, 40.0), I18nService.t("mg.veggieChop.combo"), AcTokens.PINK
			)
	ctx.report_score(score, points)


func _hit_junk(pos: Vector2) -> void:
	junk_hits += 1
	stun_until = elapsed + float(tune["STUN_SEC"])
	var delta := int(tune["JUNK_PTS"])
	score = VeggieChopLogic.apply_points(score, delta)
	AudioDirector.try_play(self, "mg_junk")
	if ctx.juice != null:
		ctx.juice.shake(0.42)
		ctx.juice.hit_freeze(90)
		ctx.juice.float_text(pos, I18nService.t("mg.veggieChop.junk"), AcTokens.DANGER)
	ctx.report_score(score, delta)


## Zwei Hälften fliegen auseinander — das ist die Schnitt-Rückmeldung.
func _spawn_halves(pos: Vector2, tint: Color) -> void:
	for dir in [-1.0, 1.0]:
		(
			_halves
			. append(
				{
					"pos": pos,
					"vel": Vector2(dir * 220.0, -160.0),
					"tint": tint,
					"age": 0.0,
					"dir": dir,
				}
			)
		)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	var total := VeggieChopLogic.final_score(score, tune)
	ctx.report_end({"score": total, "misses": misses, "junkHits": junk_hits, "elapsed": elapsed})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.veggieChop.junk_hits", {"n": junk_hits, "max": int(tune["ENDLESS_JUNK_HITS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_miss_label.text = I18nService.t(
		"mg.veggieChop.missed", {"n": misses, "max": int(tune["MAX_MISSES"])}
	)


## Pixel pro Meter — die Aktionsbahn füllt beide Orientierungen.
func _ppu() -> float:
	return clampf(view_size.y / WORLD_SPAN, 70.0, 220.0)


func _half_w() -> float:
	return maxf(0.9, view_size.x * 0.5 / _ppu())


func _to_screen(world: Vector2) -> Vector2:
	var ppu := _ppu()
	return Vector2(view_size.x * 0.5 + world.x * ppu, view_size.y - (world.y - GROUND_Y) * ppu)


func _to_world(screen: Vector2) -> Vector2:
	var ppu := _ppu()
	return Vector2((screen.x - view_size.x * 0.5) / ppu, GROUND_Y + (view_size.y - screen.y) / ppu)


func _draw() -> void:
	_draw_kitchen()
	_draw_gooby()
	for entry in items:
		_draw_item(entry)
	for half in _halves:
		_draw_half(half)
	_draw_trail()
	if elapsed < stun_until:
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.9, 0.4, 0.4, 0.16))


func _draw_kitchen() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("FDF2E3"))
	# Kachelwand oben, damit der Bogen einen ruhigen Hintergrund hat.
	var tile := 54.0
	var wall_h := view_size.y - _counter_y()
	var rows := int(ceil((view_size.y - wall_h) / tile)) + 1
	for row in rows:
		for col in int(ceil(view_size.x / tile)) + 1:
			var pos := Vector2(col * tile, row * tile)
			var shade := 0.02 if (row + col) % 2 == 0 else 0.06
			draw_rect(Rect2(pos, Vector2(tile - 2.0, tile - 2.0)), Color(0.85, 0.78, 0.68, shade))
	if frenzy_left > 0 and elapsed <= frenzy_until:
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(1.0, 0.83, 0.42, 0.12))
	var counter := _counter_y()
	draw_rect(Rect2(0.0, counter, view_size.x, view_size.y - counter), Color("E4C79C"))
	draw_line(Vector2(0.0, counter), Vector2(view_size.x, counter), AcTokens.INK, 4.0)
	# Schneidebrett als Bühne für die Würfe.
	var board := Rect2(view_size.x * 0.28, counter + 12.0, view_size.x * 0.44, 30.0)
	draw_rect(board, Color("C99A63"))
	draw_rect(board, AcTokens.INK, false, 3.0)


func _counter_y() -> float:
	return view_size.y - (96.0 if not landscape else 62.0)


func _draw_item(entry: Dictionary) -> void:
	var item: Dictionary = entry["item"]
	var pos := _to_screen(Vector2(entry["pos"]))
	var r := float(tune["HIT_RADIUS"]) * _ppu() * 0.78
	var spin := float(entry["spin"]) + float(entry["t"]) * 3.0
	if str(item["kind"]) == "junk":
		_draw_junk(pos, r, spin, str(item["key"]))
		return
	draw_set_transform(pos, spin, Vector2.ONE)
	_draw_produce(str(item["key"]), Color(str(item["juice"])), r)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Jede Sorte hat eine eigene Silhouette — ein getönter Kreis mit Glyphe
## darauf war im Flug nicht auseinanderzuhalten.
func _draw_produce(key: String, tint: Color, r: float) -> void:
	var stem := Color("6B8F3A")
	match key:
		"pear":
			draw_circle(Vector2(0.0, r * 0.34), r * 0.72, tint)
			draw_circle(Vector2(0.0, -r * 0.34), r * 0.5, tint)
			draw_arc(Vector2(0.0, r * 0.34), r * 0.72, 0.0, TAU, 24, AcTokens.INK, 3.0)
			draw_arc(Vector2(0.0, -r * 0.34), r * 0.5, PI, TAU, 16, AcTokens.INK, 3.0)
		"lemon":
			# Liegende Zitrone aus zwei Kreisen plus zwei Spitzen.
			draw_circle(Vector2(-r * 0.24, 0.0), r * 0.66, tint)
			draw_circle(Vector2(r * 0.24, 0.0), r * 0.66, tint)
			for side in [-1.0, 1.0]:
				draw_colored_polygon(
					PackedVector2Array(
						[
							Vector2(side * r * 0.6, -r * 0.4),
							Vector2(side * r * 1.12, 0.0),
							Vector2(side * r * 0.6, r * 0.4),
						]
					),
					tint
				)
			draw_arc(Vector2(-r * 0.24, 0.0), r * 0.66, PI * 0.45, PI * 1.55, 18, AcTokens.INK, 3.0)
			draw_arc(Vector2(r * 0.24, 0.0), r * 0.66, -PI * 0.55, PI * 0.55, 18, AcTokens.INK, 3.0)
		"onion":
			draw_circle(Vector2(0.0, r * 0.1), r * 0.86, tint)
			draw_arc(Vector2(0.0, r * 0.1), r * 0.86, 0.0, TAU, 26, AcTokens.INK, 3.0)
			for k in 3:
				var dx := (float(k) - 1.0) * r * 0.36
				draw_line(Vector2(dx, -r * 0.6), Vector2(dx * 1.3, r * 0.8), Color("C9B79C"), 2.5)
			for k in 3:
				var a := -PI * 0.5 + (float(k) - 1.0) * 0.45
				draw_line(Vector2(0.0, -r * 0.7), Vector2(cos(a), sin(a)) * r * 1.5, stem, 4.0)
		"mushroom":
			draw_rect(Rect2(-r * 0.26, 0.0, r * 0.52, r * 0.9), Color("F2E7D6"))
			draw_rect(Rect2(-r * 0.26, 0.0, r * 0.52, r * 0.9), AcTokens.INK, false, 3.0)
			draw_circle(Vector2.ZERO, r * 0.88, Color("C0705A"))
			draw_rect(Rect2(-r * 0.9, 0.0, r * 1.8, r * 0.9), Color("FDF2E3"))
			draw_arc(Vector2.ZERO, r * 0.88, PI, TAU, 22, AcTokens.INK, 3.0)
			draw_circle(Vector2(-r * 0.3, -r * 0.4), r * 0.14, Color("FFF1E0"))
			draw_circle(Vector2(r * 0.34, -r * 0.28), r * 0.11, Color("FFF1E0"))
		"paprika":
			draw_circle(Vector2(-r * 0.3, r * 0.16), r * 0.6, tint)
			draw_circle(Vector2(r * 0.3, r * 0.16), r * 0.6, tint)
			draw_circle(Vector2(0.0, -r * 0.2), r * 0.66, tint)
			draw_line(Vector2(0.0, -r * 0.7), Vector2(0.0, -r * 1.3), stem, 6.0)
		"tomato":
			draw_circle(Vector2(0.0, r * 0.06), r * 0.92, tint)
			draw_arc(Vector2(0.0, r * 0.06), r * 0.92, 0.0, TAU, 26, AcTokens.INK, 3.0)
			for k in 5:
				var a := -PI * 0.5 + float(k) * TAU / 5.0
				draw_line(
					Vector2(0.0, -r * 0.7),
					Vector2(cos(a), sin(a)) * r * 0.62 - Vector2(0.0, r * 0.7),
					stem,
					5.0
				)
		"coconut":
			draw_circle(Vector2.ZERO, r * 0.9, Color("8A6A4B"))
			draw_arc(Vector2.ZERO, r * 0.9, 0.0, TAU, 26, AcTokens.INK, 3.0)
			for k in 3:
				draw_circle(
					Vector2(-r * 0.3 + float(k) * r * 0.3, -r * 0.2), r * 0.13, Color("5C4531")
				)
		_:
			# Apfel als Standard: Kerbe oben, Stiel, Blatt.
			draw_circle(Vector2(-r * 0.24, r * 0.06), r * 0.72, tint)
			draw_circle(Vector2(r * 0.24, r * 0.06), r * 0.72, tint)
			draw_arc(
				Vector2(-r * 0.24, r * 0.06), r * 0.72, PI * 0.55, TAU + 0.2, 22, AcTokens.INK, 3.0
			)
			draw_arc(
				Vector2(r * 0.24, r * 0.06), r * 0.72, -PI * 0.2, PI * 0.55, 18, AcTokens.INK, 3.0
			)
			draw_line(Vector2(0.0, -r * 0.6), Vector2(r * 0.12, -r * 1.25), Color("6B4A2E"), 5.0)
			draw_circle(Vector2(r * 0.42, -r * 1.05), r * 0.24, stem)
	draw_circle(Vector2(-r * 0.36, -r * 0.36), r * 0.16, Color(1, 1, 1, 0.55))


## Müll ist grau, kantig und trägt ein „!“ — nie schnippeln.
func _draw_junk(pos: Vector2, r: float, spin: float, key: String) -> void:
	draw_set_transform(pos, spin, Vector2.ONE)
	if key == "boot":
		draw_rect(Rect2(-r * 0.7, -r * 0.9, r * 1.0, r * 1.6), Color("6C5B4B"))
		draw_rect(Rect2(-r * 0.7, r * 0.3, r * 1.7, r * 0.4), Color("52443A"))
		draw_rect(Rect2(-r * 0.7, -r * 0.9, r * 1.0, r * 1.6), AcTokens.INK, false, 3.0)
	else:
		draw_rect(Rect2(-r * 0.55, -r * 0.85, r * 1.1, r * 1.7), Color("AAB2BD"))
		draw_rect(Rect2(-r * 0.55, -r * 0.85, r * 1.1, r * 1.7), AcTokens.INK, false, 3.0)
		draw_line(Vector2(-r * 0.55, -r * 0.3), Vector2(r * 0.55, -r * 0.3), Color("7C8794"), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_glyph(pos + Vector2(0.0, -r * 1.35), "!", int(maxf(16.0, r * 0.9)), AcTokens.DANGER)


func _draw_half(half: Dictionary) -> void:
	var age := float(half["age"])
	var alpha := clampf(1.0 - age / 0.9, 0.0, 1.0)
	var pos := Vector2(half["pos"])
	var tint: Color = half["tint"]
	var r := 20.0
	var start := -PI * 0.5 if float(half["dir"]) > 0.0 else PI * 0.5
	draw_arc(pos, r, start, start + PI, 16, Color(tint.r, tint.g, tint.b, alpha), 12.0)
	draw_circle(pos + Vector2(0.0, -6.0), 3.0 * alpha + 1.0, Color(tint.r, tint.g, tint.b, alpha))


func _draw_trail() -> void:
	if _trail.size() < 2:
		return
	for i in range(1, _trail.size()):
		var a: Dictionary = _trail[i - 1]
		var b: Dictionary = _trail[i]
		var alpha := clampf(1.0 - float(b["age"]) / TRAIL_LIFE, 0.0, 1.0)
		var width := 3.0 + 9.0 * alpha
		draw_line(Vector2(a["pos"]), Vector2(b["pos"]), Color(1.0, 1.0, 1.0, alpha * 0.85), width)
		draw_line(
			Vector2(a["pos"]), Vector2(b["pos"]), Color(0.53, 0.84, 0.86, alpha * 0.5), width * 0.5
		)


func _draw_glyph(pos: Vector2, glyph: String, size: int, tint: Color) -> void:
	var font := ThemeService.font(800)
	var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(
		font,
		pos + Vector2(-width * 0.5, size * 0.36),
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		size,
		tint
	)


## Gooby steht links an der Arbeitsplatte und wirft mit.
func _draw_gooby() -> void:
	var base := Vector2(view_size.x * 0.13, _counter_y() - 18.0 + sin(_bob * 2.0) * 4.0)
	var r := 26.0
	for side in [-1.0, 1.0]:
		var ear_root := base + Vector2(side * r * 0.42, -r * 0.72)
		var ear_tip := ear_root + Vector2(side * r * 0.34, -r * 0.85)
		draw_line(ear_root, ear_tip, Color(0.98, 0.88, 0.66), r * 0.32)
		draw_circle(ear_tip, r * 0.16, Color(0.98, 0.88, 0.66))
	draw_circle(base, r, Color(0.99, 0.91, 0.7))
	draw_arc(base, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_circle(base + Vector2(-r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_arc(base + Vector2(0.0, r * 0.16), r * 0.32, 0.3, PI - 0.3, 12, AcTokens.INK, 2.5)
	# Kochmütze + Messer, damit die Rolle sofort lesbar ist.
	draw_rect(Rect2(base.x - r * 0.7, base.y - r * 1.9, r * 1.4, r * 0.5), Color(1, 1, 1))
	draw_rect(Rect2(base.x - r * 0.7, base.y - r * 1.9, r * 1.4, r * 0.5), AcTokens.INK, false, 2.5)
	var knife := base + Vector2(r * 1.15, -r * 0.2 + sin(_bob * 6.0) * 6.0)
	draw_line(knife, knife + Vector2(0.0, 26.0), Color("8A6A4A"), 6.0)
	draw_line(knife, knife + Vector2(6.0, -26.0), Color("CBD5DD"), 8.0)
	draw_line(knife, knife + Vector2(6.0, -26.0), AcTokens.INK, 2.0)
