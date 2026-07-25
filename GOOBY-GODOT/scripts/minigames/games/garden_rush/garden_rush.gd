extends MinigameBase
## Gießkannen-Wirbel (gardenRush) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## GardenRushLogic (zahlengleich zum Web, Bot-zertifiziert): 8 Töpfe (Nr. 7 ab
## 20 s, Nr. 8 ab 35 s), Welkfenster rampt 6 s → 3 s, Halten füllt den
## 0,8-s-Ring — Loslassen im letzten Viertel gibt +3, früher +1, verwelkt −2,
## gegossenes Unkraut −1. Bei 30 s erscheint der einmalige Sprinkler (+50 %
## auf alle Ringe). Optik: Beet von oben, dicke Outlines, Gooby gießt mit.

## Verhältnis Topfbreite zu Zellenbreite.
const POT_FILL := 0.74
## Nachlauf nach dem Gießen, bevor der Topf wieder frei wird (Web: 0,55 s).
const WATERED_COOLDOWN := 0.55

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var withered := 0
var next_spawn := 0.0
var pots: Array[Dictionary] = []
var hold_index := -1
var hold_sec := 0.0
var sprinkler_spawned := false
var sprinkler_used := false
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _withered_label: Label
var _hint_label: Label
var _banner_label: Label
var _banner_until := -1.0
var _active_pots := 0
var _bob := 0.0
var _splash := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = GardenRushLogic.apply_difficulty(GardenRushLogic.RUSH, ctx.difficulty)
	rng = ctx.rng()
	for i in int(tune["POTS"]):
		pots.append({"state": "empty", "remaining": 0.0, "window": 0.0, "cooldown": 0.0})
	_active_pots = GardenRushLogic.active_pots_at(0.0)
	next_spawn = 0.35
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
	_withered_label.position = Vector2(16.0, 48.0)
	var banner_w := minf(view_size.x - 32.0, 420.0)
	_banner_label.position = Vector2((view_size.x - banner_w) * 0.5, 84.0 if not landscape else 8.0)
	_banner_label.size = Vector2(banner_w, 44.0)
	_hint_label.position = Vector2(view_size.x * 0.5 - 190.0, view_size.y - 38.0)
	_hint_label.size = Vector2(380.0, 34.0)
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_withered_label = Label.new()
	_withered_label.theme_type_variation = &"CaptionLabel"
	add_child(_withered_label)
	_banner_label = Label.new()
	_banner_label.theme_type_variation = &"TitleLabel"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_banner_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.gardenRush.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_bob += delta
	_splash = maxf(0.0, _splash - delta * 2.5)
	_pot_growth_tick()
	_pot_tick(delta)
	_spawn_tick(delta)
	_sprinkler_tick()
	if hold_index >= 0:
		hold_sec += delta
	if _round_over():
		_finish()
		return
	_update_labels()
	queue_redraw()


## Endlos endet nach drei verwelkten Töpfen, getaktet nach Ablauf der Zeit.
func _round_over() -> bool:
	if GardenRushLogic.endless_should_end(withered, tune):
		return true
	return not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"])


## Töpfe 7 und 8 schalten sich bei 20 s / 35 s frei — mit Banner.
func _pot_growth_tick() -> void:
	var active := GardenRushLogic.active_pots_at(elapsed)
	if active <= _active_pots:
		return
	_active_pots = active
	_banner_label.text = I18nService.t("mg.gardenRush.more_pots")
	_banner_until = elapsed + 2.0
	AudioDirector.try_play(self, "gvz_wave")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.5)


func _pot_tick(delta: float) -> void:
	for i in pots.size():
		var pot: Dictionary = pots[i]
		var state := str(pot["state"])
		if state == "cooldown":
			pot["cooldown"] = float(pot["cooldown"]) - delta
			if float(pot["cooldown"]) <= 0.0:
				pot["state"] = "empty"
			continue
		if state != "sprout" and state != "weed":
			continue
		pot["remaining"] = float(pot["remaining"]) - delta
		if float(pot["remaining"]) > 0.0:
			continue
		if state == "sprout":
			_wilt_out(i)
		else:
			_clear_pot(i, float(tune["RESPAWN_SEC"]))
	if _banner_until > 0.0 and elapsed > _banner_until:
		_banner_until = -1.0
		_banner_label.text = ""


func _spawn_tick(delta: float) -> void:
	next_spawn -= delta
	if next_spawn > 0.0:
		return
	next_spawn = GardenRushLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var free: Array[int] = []
	for i in mini(_active_pots, pots.size()):
		if str((pots[i] as Dictionary)["state"]) == "empty":
			free.append(i)
	if free.is_empty():
		return
	var index: int = free[mini(free.size() - 1, int(floor(rng.next() * float(free.size()))))]
	var weed := GardenRushLogic.roll_weed(rng, elapsed)
	var pot: Dictionary = pots[index]
	var window := GardenRushLogic.wilt_window_at(elapsed, float(tune["DURATION_SEC"]), tune)
	pot["state"] = "weed" if weed else "sprout"
	pot["window"] = float(tune["WEED_LIFE_SEC"]) if weed else window
	pot["remaining"] = float(pot["window"])
	if not weed:
		AudioDirector.try_play(self, "gvz_pop", 1.05)


## Der Sprinkler erscheint einmalig bei 30 s und wartet auf einen Tipp.
func _sprinkler_tick() -> void:
	if not GardenRushLogic.should_spawn_sprinkler(elapsed, sprinkler_spawned):
		return
	sprinkler_spawned = true
	_banner_label.text = I18nService.t("mg.gardenRush.sprinkler_ready")
	_banner_until = elapsed + 2.5
	AudioDirector.try_play(self, "mg_golden")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.8)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.position)
		else:
			_release()


func _press(pos: Vector2) -> void:
	if sprinkler_spawned and not sprinkler_used and _sprinkler_rect().has_point(pos):
		_fire_sprinkler()
		return
	if hold_index >= 0:
		return
	var index := _pot_at(pos)
	if index < 0:
		return
	var state := str((pots[index] as Dictionary)["state"])
	if state != "sprout" and state != "weed":
		return
	hold_index = index
	hold_sec = 0.0
	AudioDirector.try_play(self, "ui_tick", 0.9)


func _release() -> void:
	if hold_index < 0:
		return
	var index := hold_index
	var frac := GardenRushLogic.hold_fill_fraction(hold_sec, tune)
	hold_index = -1
	hold_sec = 0.0
	var pot: Dictionary = pots[index]
	var state := str(pot["state"])
	if state == "weed":
		_water_weed(index)
	elif state == "sprout":
		_water_sprout(index, frac)


func _water_sprout(index: int, frac: float) -> void:
	var points := GardenRushLogic.release_points(frac, tune)
	var perfect := GardenRushLogic.in_perfect_zone(frac, tune)
	score = GardenRushLogic.apply_points(score, points)
	var pot: Dictionary = pots[index]
	pot["state"] = "watered"
	pot["cooldown"] = WATERED_COOLDOWN
	_splash = 1.0
	var pos := _pot_rect(index).get_center()
	AudioDirector.try_play(self, "mg_perfect" if perfect else "mg_good")
	if ctx.juice != null:
		var key := "mg.gardenRush.perfect" if perfect else "mg.gardenRush.early"
		ctx.juice.float_text(
			pos - Vector2(0.0, 30.0),
			I18nService.t(key),
			AcTokens.LEAF_DARK if perfect else AcTokens.INK_SOFT
		)
		if perfect:
			ctx.juice.bloom_pulse(0.55)
	ctx.report_score(score, points)
	# Der Nachlauf läuft über den Cooldown-Zweig ab.
	pot["state"] = "cooldown"
	pot["remaining"] = 0.0


func _water_weed(index: int) -> void:
	var delta := int(tune["WEED_PTS"])
	score = GardenRushLogic.apply_points(score, delta)
	var pot: Dictionary = pots[index]
	# Der Gag aus dem Web: das Unkraut wächst kurz und verzieht sich dann.
	pot["remaining"] = minf(float(pot["remaining"]), 1.2)
	pot["grown"] = true
	var pos := _pot_rect(index).get_center()
	AudioDirector.try_play(self, "mg_junk")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.float_text(
			pos - Vector2(0.0, 30.0), I18nService.t("mg.gardenRush.weed"), AcTokens.DANGER
		)
	ctx.report_score(score, delta)


func _wilt_out(index: int) -> void:
	var delta := int(tune["WILT_PTS"])
	score = GardenRushLogic.apply_points(score, delta)
	withered += 1
	var pos := _pot_rect(index).get_center()
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_freeze(70)
		ctx.juice.float_text(
			pos - Vector2(0.0, 30.0), I18nService.t("mg.gardenRush.wilted"), AcTokens.DANGER
		)
	ctx.report_score(score, delta)
	_clear_pot(index, float(tune["RESPAWN_SEC"]))


func _clear_pot(index: int, cooldown: float) -> void:
	var pot: Dictionary = pots[index]
	pot["state"] = "cooldown"
	pot["cooldown"] = cooldown
	pot["remaining"] = 0.0
	pot["grown"] = false
	if hold_index == index:
		hold_index = -1
		hold_sec = 0.0


## Ein Tipp auf den Sprinkler füllt jeden lebenden Welkring um 50 % auf.
func _fire_sprinkler() -> void:
	sprinkler_used = true
	var refilled := 0
	for pot: Dictionary in pots:
		if str(pot["state"]) != "sprout":
			continue
		pot["remaining"] = GardenRushLogic.sprinkler_refill(
			float(pot["remaining"]), float(pot["window"])
		)
		refilled += 1
	_banner_label.text = I18nService.t("mg.gardenRush.sprinkler_used", {"n": refilled})
	_banner_until = elapsed + 2.5
	AudioDirector.try_play(self, "gvz_collect")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.slowmo(0.4, 240)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "withered": withered, "elapsed": elapsed})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.gardenRush.withered", {"n": withered, "max": int(tune["ENDLESS_WILTS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_withered_label.text = (
		I18nService.t("mg.gardenRush.withered", {"n": withered, "max": int(tune["ENDLESS_WILTS"])})
		if not bool(tune["ENDLESS"]) and withered > 0
		else ""
	)


## Beet-Raster: Hochkant 2×4, Quer 4×2 — beide Orientierungen bleiben groß.
func _grid() -> Vector2i:
	return Vector2i(4, 2) if landscape else Vector2i(2, 4)


func _field_rect() -> Rect2:
	var top := 130.0 if not landscape else 58.0
	var bottom := 64.0 if not landscape else 44.0
	var inset := view_size.x * (0.06 if not landscape else 0.1)
	return Rect2(inset, top, view_size.x - inset * 2.0, view_size.y - top - bottom)


func _pot_rect(index: int) -> Rect2:
	var grid := _grid()
	var field := _field_rect()
	var cell := Vector2(field.size.x / float(grid.x), field.size.y / float(grid.y))
	var col := index % grid.x
	var row := index / grid.x
	var side := minf(cell.x, cell.y) * POT_FILL
	var center := field.position + Vector2((col + 0.5) * cell.x, (row + 0.5) * cell.y)
	return Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))


func _pot_at(pos: Vector2) -> int:
	for i in mini(_active_pots, pots.size()):
		if _pot_rect(i).grow(10.0).has_point(pos):
			return i
	return -1


func _sprinkler_rect() -> Rect2:
	var side := 62.0
	var field := _field_rect()
	return Rect2(
		Vector2(field.position.x + field.size.x - side - 6.0, field.position.y - side - 6.0),
		Vector2(side, side)
	)


func _draw() -> void:
	_draw_field()
	for i in pots.size():
		_draw_pot(i)
	_draw_gooby()
	if sprinkler_spawned and not sprinkler_used:
		_draw_sprinkler()
	if hold_index >= 0:
		_draw_fill_ring()


func _draw_field() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("EAF5DC"))
	var field := _field_rect()
	draw_rect(field.grow(14.0), Color("D8E9C0"))
	draw_rect(field.grow(14.0), AcTokens.INK, false, 4.0)
	# Beet-Furchen als ruhige Struktur unter den Töpfen.
	var rows := 9
	for i in rows:
		var y := field.position.y + field.size.y * (float(i) + 0.5) / float(rows)
		draw_line(
			Vector2(field.position.x + 6.0, y),
			Vector2(field.position.x + field.size.x - 6.0, y),
			Color(0.55, 0.68, 0.45, 0.22),
			3.0
		)


func _draw_pot(index: int) -> void:
	var rect := _pot_rect(index)
	var center := rect.get_center()
	var half := rect.size.x * 0.5
	var locked := index >= _active_pots
	var soil := Color(0.44, 0.33, 0.25, 0.35 if locked else 1.0)
	draw_circle(center, half, Color("C98A5B") if not locked else Color(0.8, 0.74, 0.68, 0.5))
	draw_arc(center, half, 0.0, TAU, 30, AcTokens.INK, 3.0 if not locked else 2.0)
	draw_circle(center, half * 0.76, soil)
	if locked:
		_draw_glyph(center, "+", int(half * 0.9), Color(0.35, 0.3, 0.28, 0.45))
		return
	var pot: Dictionary = pots[index]
	match str(pot["state"]):
		"sprout":
			_draw_sprout(center, half, false)
			_draw_wilt_ring(index, center, half)
		"weed":
			_draw_sprout(center, half, true)
		"cooldown":
			draw_arc(center, half * 0.5, 0.0, TAU, 20, Color(0.4, 0.55, 0.35, 0.35), 3.0)
		_:
			pass


## Frische Sprossen sind hell und rund, Unkraut dunkel und stachelig.
func _draw_sprout(center: Vector2, half: float, weed: bool) -> void:
	var stem := center + Vector2(0.0, half * 0.25)
	var tip := center - Vector2(0.0, half * (0.85 if not weed else 1.0))
	var tint := Color("4E8B3A") if not weed else Color("2F5D2A")
	draw_line(stem, tip, tint, 6.0)
	var leaves := 3 if not weed else 5
	for i in leaves:
		var t := (float(i) + 1.0) / float(leaves + 1)
		var base := stem.lerp(tip, t)
		var dir := 1.0 if i % 2 == 0 else -1.0
		var sway := sin(_bob * 2.0 + float(i)) * 3.0
		var leaf := base + Vector2(dir * half * (0.55 if not weed else 0.42), -half * 0.18 + sway)
		if weed:
			draw_line(base, leaf, tint, 4.0)
		else:
			draw_circle(base.lerp(leaf, 0.6), half * 0.2, Color("7CC15A"))
			draw_arc(base.lerp(leaf, 0.6), half * 0.2, 0.0, TAU, 14, AcTokens.INK, 2.0)
	if weed:
		_draw_glyph(center - Vector2(0.0, half * 1.25), "!", int(half * 0.6), AcTokens.DANGER)


## Der Welkring zeigt die Restzeit — er wird knapp und rot, bevor es −2 gibt.
func _draw_wilt_ring(index: int, center: Vector2, half: float) -> void:
	var pot: Dictionary = pots[index]
	var window := maxf(0.05, float(pot["window"]))
	var ratio := clampf(float(pot["remaining"]) / window, 0.0, 1.0)
	var tint := AcTokens.LEAF if ratio > 0.35 else AcTokens.DANGER
	draw_arc(center, half * 1.16, 0.0, TAU, 32, Color(0.4, 0.35, 0.3, 0.18), 5.0)
	draw_arc(center, half * 1.16, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, tint, 5.0)


## Füllring am gehaltenen Topf: das letzte Viertel ist die grüne Perfekt-Zone.
func _draw_fill_ring() -> void:
	var rect := _pot_rect(hold_index)
	var center := rect.get_center()
	var half := rect.size.x * 0.5
	var frac := GardenRushLogic.hold_fill_fraction(hold_sec, tune)
	var perfect := GardenRushLogic.in_perfect_zone(frac, tune)
	var zone := float(tune["PERFECT_ZONE"])
	var radius := half * 1.42
	draw_arc(center, radius, 0.0, TAU, 34, Color(1, 1, 1, 0.65), 9.0)
	draw_arc(
		center,
		radius,
		-PI * 0.5 + TAU * (1.0 - zone),
		-PI * 0.5 + TAU,
		18,
		Color(0.45, 0.78, 0.42, 0.55),
		9.0
	)
	draw_arc(
		center,
		radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * frac,
		34,
		AcTokens.LEAF_DARK if perfect else AcTokens.TEAL,
		7.0
	)
	_draw_can(center - Vector2(half * 1.5, half * 1.1))


func _draw_can(pos: Vector2) -> void:
	var tilt := -0.5
	draw_set_transform(pos, tilt, Vector2.ONE)
	draw_rect(Rect2(-16.0, -14.0, 32.0, 26.0), Color("7FB7D8"))
	draw_rect(Rect2(-16.0, -14.0, 32.0, 26.0), AcTokens.INK, false, 3.0)
	draw_line(Vector2(16.0, -8.0), Vector2(34.0, -18.0), Color("7FB7D8"), 6.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 4:
		var drop := pos + Vector2(30.0 + float(i) * 5.0, -10.0 + float(i) * 9.0)
		draw_circle(drop, 3.5, Color(0.53, 0.78, 0.92, 0.9))


func _draw_sprinkler() -> void:
	var rect := _sprinkler_rect()
	var center := rect.get_center()
	var pulse := 1.0 + sin(_bob * 5.0) * 0.06
	draw_circle(center, rect.size.x * 0.5 * pulse, Color("FFD166"))
	draw_arc(center, rect.size.x * 0.5 * pulse, 0.0, TAU, 26, AcTokens.INK, 3.0)
	for i in 6:
		var a := TAU * float(i) / 6.0 + _bob
		draw_line(
			center + Vector2(cos(a), sin(a)) * rect.size.x * 0.32,
			center + Vector2(cos(a), sin(a)) * rect.size.x * 0.52,
			Color(0.45, 0.72, 0.92),
			4.0
		)
	draw_circle(center, rect.size.x * 0.18, Color(0.45, 0.72, 0.92))


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


## Gooby steht am Beetrand und gießt mit — bei Perfekt hüpft der Spritzer.
func _draw_gooby() -> void:
	var field := _field_rect()
	# Rechte Seite: links kleben Zeit- und Welk-Label, dort sass der Cameo drauf.
	var base := Vector2(field.end.x - 34.0, field.position.y - 40.0 + sin(_bob * 1.8) * 4.0)
	if landscape:
		base = Vector2(view_size.x - 44.0, view_size.y - 52.0 + sin(_bob * 1.8) * 4.0)
	var r := 24.0
	for side in [-1.0, 1.0]:
		var ear_root := base + Vector2(side * r * 0.42, -r * 0.72)
		var ear_tip := ear_root + Vector2(side * r * 0.34, -r * 0.85)
		draw_line(ear_root, ear_tip, Color(0.98, 0.88, 0.66), r * 0.32)
		draw_circle(ear_tip, r * 0.16, Color(0.98, 0.88, 0.66))
	draw_circle(base, r, Color(0.99, 0.91, 0.7))
	draw_arc(base, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_circle(base + Vector2(-r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	var smile := 0.36 if _splash > 0.1 else 0.28
	draw_arc(base + Vector2(0.0, r * 0.16), r * smile, 0.3, PI - 0.3, 12, AcTokens.INK, 2.5)
	if _splash > 0.05:
		draw_arc(
			base,
			r * (1.5 + (1.0 - _splash)),
			0.0,
			TAU,
			20,
			Color(0.53, 0.78, 0.92, _splash * 0.5),
			4.0
		)
