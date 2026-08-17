extends MinigameBase
## Gießkannen-Wirbel (gardenRush) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## GardenRushLogic (zahlengleich zum Web, Bot-zertifiziert): 8 Töpfe (Nr. 7 ab
## 20 s, Nr. 8 ab 35 s), Welkfenster rampt 6 s → 3 s, Halten füllt den
## 0,8-s-Ring — Loslassen im letzten Viertel gibt +3, früher +1, verwelkt −2,
## gegossenes Unkraut −1. Bei 30 s erscheint der einmalige Sprinkler (+50 %
## auf alle Ringe).
##
## ECHTES 3D-BEET (FB-4, GardenRushStage3D): Terrakotta-Töpfe mit wachsenden
## 3D-Sprossen und Unkraut auf einer Gartenbühne, Gooby (echtes Rig) gießt
## mit. Die Töpfe liegen per ground_point-Raycast EXAKT unter den
## 2D-Tap-Rechtecken — Eingabe bleibt zahlengleich. Nur der Füllring beim
## Halten bleibt als 2D-Overlay (Eingabe-Feedback).

const Stage := preload("res://scripts/minigames/games/garden_rush/garden_rush_stage3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")

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
var _stage: Node3D
var _bob := 0.0
var _splash := 0.0
var _hud_plate := Kit.hud_plate()
var _banner_plate := Kit.hud_plate()
var _hint_plate := Kit.hud_plate()
## Reine Anzeige-Serie (Perfekt-Güsse in Folge) — KEINE Punktelogik.
var _perfect_streak := 0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = GardenRushLogic.apply_difficulty(GardenRushLogic.RUSH, ctx.difficulty)
	rng = ctx.rng()
	for i in int(tune["POTS"]):
		pots.append({"state": "empty", "remaining": 0.0, "window": 0.0, "cooldown": 0.0})
	_active_pots = GardenRushLogic.active_pots_at(0.0)
	next_spawn = 0.35
	_stage = Stage.new()
	_stage.name = "Beet3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
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
	if _stage != null:
		# Erst die Kamera stellen, dann die Töpfe unter die Rechtecke raycasten.
		_stage.frame(view_size)
		var rects: Array[Rect2] = []
		for i in pots.size():
			rects.append(_pot_rect(i))
		_stage.layout(rects, _sprinkler_rect())
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0)
	_withered_label.position = Vector2(16.0, 48.0)
	var banner_w := minf(vp.x - 32.0, 420.0)
	_banner_label.position = Vector2((vp.x - banner_w) * 0.5, 84.0 if not landscape else 8.0)
	_banner_label.size = Vector2(banner_w, 44.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 190.0, vp.y - 38.0)
	_hint_label.size = Vector2(380.0, 34.0)


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
	_stage.set_sprinkler_visible(sprinkler_spawned and not sprinkler_used)
	_stage.sync(pots, _active_pots, hold_index, _bob, delta)
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
	_stage.water_fx(index, perfect)
	AudioDirector.try_play(self, "mg_perfect" if perfect else "mg_good")
	_perfect_streak = _perfect_streak + 1 if perfect else 0
	if ctx.juice != null:
		var key := "mg.gardenRush.perfect" if perfect else "mg.gardenRush.early"
		ctx.juice.float_text(
			pos - Vector2(0.0, 30.0),
			I18nService.t(key),
			AcTokens.LEAF_DARK if perfect else AcTokens.INK_SOFT
		)
		# Perfekt-Serie mit steigendem Ton; ein früher Guss setzt sie zurück.
		ctx.juice.show_combo(_perfect_streak)
		if perfect:
			ctx.juice.bloom_pulse(0.55)
			ctx.juice.overlay_ring(pos, Color(0.98, 0.75, 0.85, 0.85), 56.0)
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
	_stage.weed_fx(index)
	AudioDirector.try_play(self, "mg_junk")
	_perfect_streak = 0
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_flash(Color(0.55, 0.65, 0.3, 0.12))
		ctx.juice.show_combo(0)
		ctx.juice.float_text(
			pos - Vector2(0.0, 30.0), I18nService.t("mg.gardenRush.weed"), AcTokens.DANGER
		)
	ctx.report_score(score, delta)


func _wilt_out(index: int) -> void:
	var delta := int(tune["WILT_PTS"])
	score = GardenRushLogic.apply_points(score, delta)
	withered += 1
	var pos := _pot_rect(index).get_center()
	_stage.wilt_fx(index)
	AudioDirector.try_play(self, "mg_spill")
	_perfect_streak = 0
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_freeze(70)
		ctx.juice.hit_flash(Color(0.9, 0.4, 0.3, 0.12))
		ctx.juice.show_combo(0)
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
	_stage.sprinkler_fx()
	AudioDirector.try_play(self, "gvz_collect")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.slowmo(0.4, 240)
		ctx.juice.confetti(40)


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
	_hint_label.modulate.a = _hint_alpha()


## Der Hinweis blendet nach ein paar Sekunden aus — das Beet gehört dann ganz
## den Sprossen.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 5.0) / 1.5, 0.0, 1.0)


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


## Nur noch HUD-Overlay: der Füllring am gehaltenen Topf ist präzises
## Eingabe-Feedback (Perfekt-Zone!) und bleibt deshalb gestochen scharf in 2D.
## Dazu Milchglas hinter Zeit/Welk-Zähler, Banner und Hinweis (Lesbarkeit).
func _draw() -> void:
	if _time_label != null:
		var top_left := _time_label.position - Vector2(12.0, 6.0)
		var bottom_right := (
			_withered_label.position
			+ Vector2(maxf(_time_label.size.x, _withered_label.size.x), _withered_label.size.y)
			+ Vector2(12.0, 6.0)
		)
		draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))
		if not _banner_label.text.is_empty():
			draw_style_box(_banner_plate, Rect2(_banner_label.position, _banner_label.size))
		var hint_a := _hint_alpha()
		if hint_a > 0.0:
			_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
			draw_style_box(
				_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
			)
	if hold_index >= 0:
		_draw_fill_ring()


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
