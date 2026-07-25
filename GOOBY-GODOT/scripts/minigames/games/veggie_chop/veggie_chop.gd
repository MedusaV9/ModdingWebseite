extends MinigameBase
## Gemüse-Schnippler (veggieChop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## VeggieChopLogic (zahlengleich zum Web, Bot-zertifiziert): Gemüse fliegt in
## Bögen hoch (1–3 gleichzeitig, ab 20 s / 40 s), ein Wisch schneidet +2 und
## jedes weitere Stück im selben Wisch +3, Müll −3 mit 0,5 s Stun, drei
## verpasste Gemüse beenden die Runde. Alle 25 s Frenzy: 8 Gemüse, kein Müll.
##
## ECHTE 3D-KÜCHE (VeggieChopKitchen3D): Gooby steht als KOCH hinter der
## Arbeitsplatte und schnippelt mit, davor fliegen echte Food-Kit-Modelle durch
## die Luft und platzen beim Schnitt in ihre „-half"-Gegenstücke. Die 3D-Kamera
## ist pixelgenau auf `_to_screen()` gerahmt — die getestete Trefferrechnung
## (Wischsegment gegen Kreis) bleibt unverändert; nur die Wischspur bleibt 2D.

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
const Kitchen := preload("res://scripts/minigames/games/veggie_chop/veggie_chop_kitchen3d.gd")

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
var _stage: Node3D
var _swiping := false
var _last_point := Vector2.ZERO


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = VeggieChopLogic.apply_difficulty(VeggieChopLogic.CHOP, ctx.difficulty)
	rng = ctx.rng()
	next_spawn = VeggieChopLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_build_stage()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## 3D-Bühne unter die Node2D-Wurzel hängen (Godot rendert 3D hinter 2D).
func _build_stage() -> void:
	_stage = Kitchen.new()
	_stage.name = "Kitchen3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.world_env


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		var half_h := view_size.y * 0.5 / _ppu()
		_stage.apply_size(view_size)
		_stage.frame(half_h, GROUND_Y + half_h)
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
	_frenzy_tick()
	_spawn_tick(step)
	_fly_tick(step)
	_decay_effects(delta)
	if _round_over():
		_finish()
		return
	_stage.tick(delta)
	_stage.sync(items, elapsed)
	_stage.feel(_mood())
	_update_labels()
	queue_redraw()


## Gooby-Laune aus dem Küchenzustand (Reihenfolge = Dringlichkeit).
func _mood() -> String:
	if elapsed < stun_until:
		return "dizzy"
	if misses >= int(tune["MAX_MISSES"]) - 1:
		return "scared"
	if frenzy_left > 0 and elapsed <= frenzy_until:
		return "ecstatic"
	return "happy" if swipe_combo > 0 else "neutral"


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
	_stage.split(Vector2(entry["pos"]), str(item["half"]), Color(str(item["juice"])))
	_stage.chop()
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


## Die WELT lebt in der 3D-Küche — 2D bleibt nur die Wischspur (sie gehört auf
## die Fingerspitze, nicht in die Szene) und der Stun-Schleier.
func _draw() -> void:
	_draw_trail()
	if elapsed < stun_until:
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.9, 0.4, 0.4, 0.16))


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
