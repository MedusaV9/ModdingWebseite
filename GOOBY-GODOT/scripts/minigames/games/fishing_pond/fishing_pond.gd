extends MinigameBase
## Angelteich (fishingPond) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## FishingPondLogic (zahlengleich zum Web): 90 s, HALTEN senkt den Haken,
## LOSLASSEN angelt den nächsten Schwimmer im Fangradius, S/M/L = 2/3/5,
## Stiefel −3, große Fische brauchen 5 Wackel-Taps in 2 s.
## Die Web-Fassung war bereits eine flache x/Tiefe-Ebene — die Godot-Szene
## zeichnet sie als Teich-Querschnitt im Sticker-Look.

const Logic := preload("res://scripts/minigames/games/fishing_pond/fishing_pond_logic.gd")

## Anteil der Viewport-Höhe über der Wasseroberfläche.
const SKY_FRAC := 0.2
## Wie lange ein Fang-Text stehen bleibt (s).
const FLASH_SEC := 1.0

const WATER_TOP := Color(0.42, 0.72, 0.85)
const WATER_DEEP := Color(0.14, 0.34, 0.52)
const SKY := Color(0.78, 0.9, 0.97)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var hook_depth := 0.0
var phase := "idle"
var fish: Array[Dictionary] = []
var hooked: Dictionary = {}
var reel_taps := 0
var reel_elapsed := 0.0
var since_boot := 0.0
var endless_state: Dictionary = {}
var caught_species: Array[String] = []
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _stream: Callable
var _respawn: Array[float] = []
var _flash := 0.0
var _flash_text := ""
var _flash_color := Color.WHITE
var _splash := 0.0
var _time_label: Label
var _score_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.FISHING, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
	endless_state = Logic.create_endless_state()
	for i in int(tune["FISH_COUNT"]):
		fish.append(_spawn_fish())
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
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_score_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 52.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	since_boot += delta
	_flash = maxf(0.0, _flash - delta)
	_splash = maxf(0.0, _splash - delta)
	_swim(delta)
	_step_respawns(delta)
	_step_hook(delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if not (event is InputEventScreenTouch):
		return
	if phase == "reel":
		if event.pressed:
			reel_taps += 1
			AudioDirector.try_play(self, "mg_combo", 1.0 + 0.05 * reel_taps)
		return
	if event.pressed and phase == "idle":
		phase = "lower"
	elif not event.pressed and phase == "lower":
		_release()


## Sichtbare Wassertiefe in Weltmetern (Rand oben/unten eingerechnet).
func pond_depth_span() -> float:
	return float(tune["MAX_DEPTH"]) + 0.35


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_score_label = Label.new()
	_score_label.theme_type_variation = &"CaptionLabel"
	add_child(_score_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.fishingPond.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Der Hinweis steht über dem tiefen (dunklen) Wasser.
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0))
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Neuen Schwimmer würfeln (Art, Tiefe, Richtung, Tempo).
func _spawn_fish() -> Dictionary:
	var half := float(tune["POND_HALF_W"])
	if Logic.should_spawn_boot(_stream, since_boot, tune):
		since_boot = 0.0
		return {
			"kind": "boot",
			"species": "boot",
			"x": -half if rng.next() < 0.5 else half,
			"depth": 0.7 + rng.next() * 0.5,
			"dir": 1.0,
			"speed": float(tune["BOOT_SPEED"]),
			"scale": 0.42,
			"wiggle": rng.next() * TAU,
		}
	var kind := Logic.roll_fish_kind(_stream)
	var detail := Logic.roll_species_detail(kind, _stream)
	var lo := float(tune["FISH_DEPTH_MIN"])
	var hi := float(tune["FISH_DEPTH_MAX"])
	return {
		"kind": kind,
		"species": str(detail["species"]),
		"rare": bool(detail["rare"]),
		"collectionId": str(detail["collectionId"]),
		"x": -half + rng.next() * half * 2.0,
		"depth": lo + rng.next() * (hi - lo),
		"dir": 1.0 if rng.next() < 0.5 else -1.0,
		"speed": Logic.fish_speed_for(kind, _stream),
		"scale": float((tune["SIZES"] as Dictionary)[kind]["scale"]),
		"wiggle": rng.next() * TAU,
	}


func _swim(delta: float) -> void:
	var half := float(tune["POND_HALF_W"])
	for f in fish:
		f["x"] = float(f["x"]) + float(f["dir"]) * float(f["speed"]) * delta
		f["wiggle"] = float(f["wiggle"]) + delta * 6.0
		if float(f["x"]) > half:
			f["x"] = half
			f["dir"] = -1.0
		elif float(f["x"]) < -half:
			f["x"] = -half
			f["dir"] = 1.0


func _step_respawns(delta: float) -> void:
	var kept: Array[float] = []
	for t in _respawn:
		var left := t - delta
		if left <= 0.0:
			fish.append(_spawn_fish())
		else:
			kept.append(left)
	_respawn = kept


func _step_hook(delta: float) -> void:
	match phase:
		"lower":
			hook_depth = Logic.lower_depth(hook_depth, delta, tune)
		"raise":
			hook_depth = maxf(0.0, hook_depth - float(tune["RAISE_SPEED"]) * delta)
			if hook_depth <= 0.0:
				phase = "idle"
		"reel":
			reel_elapsed = Logic.advance_reel_elapsed(reel_elapsed, delta, tune)
			var verdict := Logic.reel_resolve(reel_taps, reel_elapsed, tune)
			if verdict != "reeling":
				_resolve_reel(verdict)


func _release() -> void:
	phase = "raise"
	_splash = 0.4
	var index := Logic.nearest_catch(
		fish, float(tune["HOOK_X"]), hook_depth, float(tune["CATCH_RADIUS"])
	)
	if index < 0:
		AudioDirector.try_play(self, "mg_junk", 0.85)
		return
	hooked = fish[index]
	fish.remove_at(index)
	_respawn.append(float(tune["RESPAWN_SEC"]))
	if Logic.needs_reel(str(hooked["kind"])):
		phase = "reel"
		reel_taps = 0
		reel_elapsed = 0.0
		AudioDirector.try_play(self, "mg_golden", 0.8)
		if ctx.juice != null:
			ctx.juice.shake(0.3)
		return
	_land_catch()


func _resolve_reel(verdict: String) -> void:
	phase = "raise"
	if verdict == "caught":
		_land_catch()
		return
	_flash_text = I18nService.t("mg.fishingPond.line_break")
	_flash_color = Color(0.85, 0.35, 0.35)
	_flash = FLASH_SEC
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.45)
		ctx.juice.float_text(_hook_pos(), _flash_text, _flash_color)
	hooked = {}
	if bool(tune["ENDLESS"]) and Logic.record_failure(endless_state, "lineBreak"):
		_finish()


func _land_catch() -> void:
	var kind := str(hooked["kind"])
	var value := Logic.catch_value(kind)
	score = Logic.apply_catch(score, value)
	_flash_text = "%+d" % value
	_flash_color = Color(0.85, 0.35, 0.35) if value < 0 else Color(1.0, 0.78, 0.3)
	_flash = FLASH_SEC
	if kind == "boot":
		AudioDirector.try_play(self, "mg_junk")
		if ctx.juice != null:
			ctx.juice.shake(0.3)
	else:
		caught_species.append(str(hooked["species"]))
		var bonus := Logic.rare_set_bonus(caught_species)
		if bonus > 0 and not caught_species.has("__bonus"):
			caught_species.append("__bonus")
			score += bonus
			_flash_text = I18nService.t("mg.fishingPond.rare_set", {"n": bonus})
			AudioDirector.try_play(self, "mg_golden")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(1.0)
		elif bool(hooked.get("rare", false)):
			AudioDirector.try_play(self, "mg_golden")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.8)
		else:
			AudioDirector.try_play(self, "mg_perfect" if kind == "L" else "mg_good")
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.4 if kind == "L" else 0.2)
	if ctx.juice != null:
		ctx.juice.hit_freeze(40)
		ctx.juice.float_text(_hook_pos(), _flash_text, _flash_color)
	ctx.report_score(score, value)
	var was_boot := kind == "boot"
	hooked = {}
	if was_boot and bool(tune["ENDLESS"]) and Logic.record_failure(endless_state, "boot"):
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "species": caught_species.size()})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.fishingPond.failures",
			{"n": int(endless_state["failures"]), "max": int(endless_state["limit"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_score_label.text = I18nService.t("mg.fishingPond.depth", {"m": "%.1f" % hook_depth})


func _surface_y() -> float:
	return view_size.y * SKY_FRAC


func _ppu() -> float:
	return (view_size.y * (0.92 - SKY_FRAC)) / pond_depth_span()


## Waagerechter Maßstab — der Teich ist breiter als tief, deshalb weicht er
## vom Tiefenmaßstab ab. Fischgrößen MÜSSEN ihn benutzen, sonst quellen sie
## über den halben Bildschirm.
func _ppu_x() -> float:
	return minf(_ppu(), view_size.x / (float(tune["POND_HALF_W"]) * 2.4))


## Teichkoordinaten (x, Tiefe) → Bildschirmpixel.
func _to_screen(x: float, depth: float) -> Vector2:
	return Vector2(view_size.x * 0.5 + x * _ppu_x(), _surface_y() + depth * _ppu())


func _hook_pos() -> Vector2:
	return _to_screen(float(tune["HOOK_X"]), hook_depth)


func _draw() -> void:
	_draw_pond()
	for f in fish:
		_draw_fish(f)
	_draw_line_and_hook()
	if not hooked.is_empty():
		_draw_fish(hooked, true)
	_draw_gooby()
	if phase == "reel":
		_draw_reel_meter()
	_draw_flash()


func _draw_pond() -> void:
	var vp := view_size
	var surface := _surface_y()
	draw_rect(Rect2(0.0, 0.0, vp.x, surface), SKY)
	# Wolken + Ufer.
	for i in 4:
		var cx := vp.x * (0.15 + i * 0.24)
		draw_circle(Vector2(cx, surface * 0.35 + (i % 2) * 14.0), 20.0, Color(1, 1, 1, 0.75))
		draw_circle(Vector2(cx + 20.0, surface * 0.35 + (i % 2) * 14.0), 15.0, Color(1, 1, 1, 0.7))
	var rows := 14
	for i in rows:
		var f := float(i) / (rows - 1)
		var y0 := surface + (vp.y - surface) * f
		var y1 := surface + (vp.y - surface) * (f + 1.0 / (rows - 1))
		draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), WATER_TOP.lerp(WATER_DEEP, f))
	# Wellenlinie mit Plätschern beim Loslassen.
	var pts := PackedVector2Array()
	for i in 33:
		var x := vp.x * i / 32.0
		var amp := 3.0 + 5.0 * _splash
		pts.append(Vector2(x, surface + sin(x * 0.05 + elapsed * 2.0) * amp))
	draw_polyline(pts, Color(1, 1, 1, 0.55), 3.0)
	# Seerosen + Schilf als Deko am Rand.
	for i in 3:
		var lx := vp.x * (0.1 + i * 0.38)
		draw_circle(Vector2(lx, surface + 6.0), 16.0, Color(0.35, 0.62, 0.36, 0.9))
	draw_rect(Rect2(0.0, vp.y - 26.0, vp.x, 26.0), Color(0.32, 0.26, 0.2, 0.85))


func _draw_fish(f: Dictionary, on_hook := false) -> void:
	var pos := _to_screen(float(f["x"]), float(f["depth"]))
	if on_hook:
		pos = _hook_pos() + Vector2(0.0, 8.0)
	var s := float(f["scale"]) * _ppu_x()
	var dir := float(f.get("dir", 1.0))
	if str(f["kind"]) == "boot":
		draw_rect(Rect2(pos.x - s * 0.5, pos.y - s * 0.4, s, s * 0.8), Color(0.35, 0.28, 0.24))
		draw_rect(
			Rect2(pos.x - s * 0.5, pos.y + s * 0.1, s * 1.4, s * 0.3), Color(0.28, 0.22, 0.19)
		)
		return
	var color := Logic.species_color(str(f["species"]))
	var wob := sin(float(f["wiggle"])) * s * 0.12
	# Rückenflosse zuerst, damit sie hinter dem Rumpf sitzt.
	draw_colored_polygon(
		PackedVector2Array(
			[
				pos + Vector2(-dir * s * 0.1, -s * 0.28),
				pos + Vector2(dir * s * 0.16, -s * 0.62),
				pos + Vector2(dir * s * 0.3, -s * 0.26),
			]
		),
		color.darkened(0.25)
	)
	# Schwanzflosse.
	draw_colored_polygon(
		PackedVector2Array(
			[
				pos + Vector2(-dir * s * 0.5, wob * 0.6),
				pos + Vector2(-dir * s * 0.92, wob - s * 0.4),
				pos + Vector2(-dir * s * 0.92, wob + s * 0.4),
			]
		),
		color.darkened(0.18)
	)
	# Tropfenförmiger Rumpf statt Raute — sonst sehen die Fische aus wie
	# Papierflieger.
	var body := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		var taper := 0.55 + 0.45 * cos(a)
		body.append(
			pos + Vector2(dir * s * 0.72 * cos(a), s * 0.33 * sin(a) * taper + wob * (1.0 - taper))
		)
	draw_colored_polygon(body, color)
	draw_polyline(body + PackedVector2Array([body[0]]), color.darkened(0.3), 1.6)
	# Kiemenbogen + Auge.
	draw_arc(
		pos + Vector2(dir * s * 0.18, 0.0),
		s * 0.26,
		-PI * 0.45,
		PI * 0.45,
		10,
		color.darkened(0.22),
		maxf(1.2, s * 0.05)
	)
	draw_circle(pos + Vector2(dir * s * 0.45, -s * 0.07), maxf(2.0, s * 0.1), Color(1, 1, 1, 0.9))
	draw_circle(
		pos + Vector2(dir * s * 0.47, -s * 0.07), maxf(1.2, s * 0.05), Color(0.1, 0.1, 0.12)
	)
	if bool(f.get("rare", false)):
		draw_arc(pos, s * 0.95, 0.0, TAU, 20, Color(1.0, 0.9, 0.45, 0.7), 2.0)


func _draw_line_and_hook() -> void:
	var rod_tip := Vector2(view_size.x * 0.5, _surface_y() - 54.0)
	var hook := _hook_pos()
	draw_line(rod_tip, hook, Color(0.96, 0.96, 0.92, 0.9), 2.0)
	draw_circle(hook, 5.0, Color(0.85, 0.85, 0.9))
	draw_arc(hook + Vector2(0.0, 4.0), 5.0, 0.0, PI, 10, Color(0.75, 0.75, 0.82), 2.5)
	if phase == "lower" or phase == "idle":
		# Der Fangradius ist in Teichkoordinaten rund, auf dem Schirm wegen der
		# unterschiedlichen Maßstäbe aber eine Ellipse.
		var r := float(tune["CATCH_RADIUS"])
		var ring := PackedVector2Array()
		for i in 33:
			var a := TAU * float(i) / 32.0
			ring.append(hook + Vector2(cos(a) * r * _ppu_x(), sin(a) * r * _ppu()))
		draw_polyline(ring, Color(1.0, 1.0, 1.0, 0.2), 2.0)


func _draw_reel_meter() -> void:
	var w := view_size.x * 0.62
	var x := view_size.x * 0.19
	var y := view_size.y * 0.16
	var need := float(tune["REEL_TAPS"])
	draw_rect(Rect2(x, y, w, 22.0), Color(0.1, 0.15, 0.2, 0.55))
	draw_rect(Rect2(x, y, w * clampf(reel_taps / need, 0.0, 1.0), 22.0), Color(0.4, 0.85, 0.5))
	var left := 1.0 - clampf(reel_elapsed / float(tune["REEL_WINDOW_SEC"]), 0.0, 1.0)
	draw_rect(Rect2(x, y + 24.0, w * left, 6.0), Color(0.95, 0.6, 0.3))
	draw_string(
		ThemeService.font(800),
		Vector2(x, y - 10.0),
		I18nService.t("mg.fishingPond.reel"),
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		24,
		Color(1.0, 0.98, 0.9)
	)


func _draw_gooby() -> void:
	var r := maxf(22.0, view_size.x * 0.055)
	var pos := Vector2(view_size.x * 0.5 - r * 2.1, _surface_y() - r * 1.2)
	# Bootsrumpf + Angel.
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(pos.x - r * 2.4, pos.y + r * 0.7),
				Vector2(pos.x + r * 3.0, pos.y + r * 0.7),
				Vector2(pos.x + r * 2.3, pos.y + r * 1.7),
				Vector2(pos.x - r * 1.7, pos.y + r * 1.7),
			]
		),
		Color(0.55, 0.4, 0.28)
	)
	draw_rect(Rect2(pos.x - r * 2.4, pos.y + r * 0.7, r * 5.4, r * 0.22), Color(0.72, 0.55, 0.38))
	draw_line(
		pos + Vector2(r * 0.6, -r * 0.2),
		Vector2(view_size.x * 0.5, _surface_y() - 54.0),
		Color(0.72, 0.5, 0.3),
		4.0
	)
	draw_circle(pos + Vector2(-r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos, r, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_arc(pos + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 10, Color(0.2, 0.16, 0.14), 2.2)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.5, 0.0, 1.0)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.28),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(_flash_color, alpha)
	)
