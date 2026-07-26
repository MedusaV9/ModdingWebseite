extends MinigameBase
## Karottenwache (carrotGuard) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## CarrotGuardLogic (zahlengleich zum Web, Bot-zertifiziert): 3×3 Erdhügel,
## Maulwürfe bleiben 0,9 s → 0,5 s oben, 10 Karotten im Beet, Treffer +1, jede
## 5er-Kombo +3, entwischt einer klaut er eine Karotte. Nach je 20 Treffern
## kommt der Maulwurfkönig (3 Taps, +8 + 2 Münzen). 45 s oder Beet leer;
## Endlos endet nach drei geklauten Karotten.
##
## ECHTE 3D-GARTENWIESE (FB-4, CarrotGuardStage3D): 3D-Maulwürfe tauchen aus
## Erdhügeln auf einer Sommerwiese auf, hinten Zaun/Bäume/Karottenbeet, Gooby
## (echtes Rig) hält Wache. Die Hügel liegen per ground_point-Raycast EXAKT
## unter den 2D-Tap-Rechtecken (_holes) — Eingabe und Trefferflächen bleiben
## zahlengleich, die MECHANIK unangetastet.

const Stage := preload("res://scripts/minigames/games/carrot_guard/carrot_guard_stage3d.gd")

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var combo := 0
var bonks := 0
var kings_spawned := 0
var carrots := 10
var elapsed := 0.0
var next_spawn := 0.0
var last_tap_at := -INF
var moles: Array[Dictionary] = []
var king: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _carrot_label: Label
var _hint_label: Label
var _holes: Array[Rect2] = []
var _stage: Node3D
var _pulse := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = CarrotGuardLogic.apply_difficulty(CarrotGuardLogic.GUARD, ctx.difficulty)
	rng = ctx.rng()
	carrots = int(tune["CARROTS"])
	next_spawn = CarrotGuardLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_stage = Stage.new()
	_stage.name = "Wiese3D"
	add_child(_stage)
	_stage.setup_stage(carrots)
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
	var grid := int(tune.get("GRID", 3))
	var top := 108.0 if not landscape else 66.0
	# Hochkant bleibt unten Platz fürs Karottenbeet, quer wandert es nach rechts.
	var bed := 108.0 if not landscape else 0.0
	var right := 0.0 if not landscape else view_size.x * 0.26
	var avail := Vector2(view_size.x - 32.0 - right, maxf(120.0, view_size.y - top - bed - 52.0))
	var cell := minf(avail.x, avail.y) / float(grid)
	var board := cell * grid
	var origin := Vector2((view_size.x - right - board) * 0.5, top + (avail.y - board) * 0.5)
	_holes = []
	for row in grid:
		for col in grid:
			_holes.append(
				Rect2(
					origin + Vector2(col * cell, row * cell) + Vector2(cell * 0.08, cell * 0.08),
					Vector2.ONE * (cell * 0.84)
				)
			)
	if _stage != null:
		# Erst die Kamera stellen, dann die Hügel unter die Rechtecke raycasten.
		_stage.frame(view_size)
		_stage.layout(_holes)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0)
	_carrot_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 170.0, vp.y - 42.0)
	_hint_label.size = Vector2(340.0, 34.0)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_carrot_label = Label.new()
	_carrot_label.theme_type_variation = &"CaptionLabel"
	add_child(_carrot_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.carrotGuard.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_pulse += delta
	_spawn_tick(delta)
	_mole_tick(delta)
	if CarrotGuardLogic.is_round_over(
		{"elapsed": elapsed, "carrots": carrots}, float(tune["DURATION_SEC"]), tune
	):
		_finish()
		return
	_stage.sync(moles, king, carrots, _pulse, delta)
	_update_labels()
	queue_redraw()


func _spawn_tick(delta: float) -> void:
	if not king.is_empty():
		return
	next_spawn -= delta
	if next_spawn > 0.0:
		return
	next_spawn = CarrotGuardLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	if CarrotGuardLogic.is_king_due(bonks, kings_spawned):
		_spawn_king()
		return
	var count := 1
	if rng.next() < CarrotGuardLogic.double_chance_at(elapsed, float(tune["DURATION_SEC"]), tune):
		count = 2
	for _i in count:
		var free_holes := _free_holes()
		if free_holes.is_empty():
			return
		var hole: int = free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))]
		(
			moles
			. append(
				{
					"hole": hole,
					"left": CarrotGuardLogic.up_time_at(elapsed, float(tune["DURATION_SEC"]), tune),
					"up": 0.0,
				}
			)
		)


func _spawn_king() -> void:
	kings_spawned += 1
	var free_holes := _free_holes()
	if free_holes.is_empty():
		return
	king = {
		"hole": free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))],
		"hp": int(CarrotGuardLogic.GUARD["KING_TAPS"]),
		"up": 0.0,
	}
	AudioDirector.try_play(self, "gvz_boss")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.8)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 110.0, view_size.y * 0.24),
			I18nService.t("mg.carrotGuard.king"),
			AcTokens.GOLD
		)


func _mole_tick(delta: float) -> void:
	if not king.is_empty():
		king["up"] = minf(1.0, float(king["up"]) + delta / float(tune["POP_SEC"]))
		return
	var kept: Array[Dictionary] = []
	for mole in moles:
		mole["up"] = minf(1.0, float(mole["up"]) + delta / float(tune["POP_SEC"]))
		mole["left"] = float(mole["left"]) - delta
		if float(mole["left"]) > 0.0:
			kept.append(mole)
			continue
		# Entwischt: eine Karotte weg, Kombo futsch.
		var escaped := CarrotGuardLogic.apply_escape({"carrots": carrots, "combo": combo})
		carrots = int(escaped["carrots"])
		combo = int(escaped["combo"])
		AudioDirector.try_play(self, "mg_spill")
		_stage.steal_fx(int(mole["hole"]))
		if ctx.juice != null:
			ctx.juice.shake(0.28)
			ctx.juice.float_text(
				_holes[int(mole["hole"])].get_center(),
				I18nService.t("mg.carrotGuard.steal"),
				AcTokens.DANGER
			)
	moles = kept


func _free_holes() -> Array[int]:
	var used := {}
	for mole in moles:
		used[int(mole["hole"])] = true
	if not king.is_empty():
		used[int(king["hole"])] = true
	var out: Array[int] = []
	for i in _holes.size():
		if not used.has(i):
			out.append(i)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var since := elapsed - last_tap_at
	if not CarrotGuardLogic.accepts_tap_after(
		since, float(CarrotGuardLogic.GUARD["TAP_DEBOUNCE_SEC"])
	):
		return
	last_tap_at = elapsed
	var hole := _hole_at((event as InputEventScreenTouch).position)
	if hole < 0:
		return
	if not king.is_empty() and int(king["hole"]) == hole:
		_tap_king()
		return
	for i in moles.size():
		if int(moles[i]["hole"]) != hole:
			continue
		_bonk(i)
		return
	# Danebengehauen: kein Punktverlust, aber die Kombo ist weg.
	combo = int(CarrotGuardLogic.apply_whiff({"combo": combo})["combo"])
	AudioDirector.try_play(self, "mg_junk", 0.9)


func _bonk(index: int) -> void:
	var hole := int(moles[index]["hole"])
	moles.remove_at(index)
	var result := CarrotGuardLogic.apply_bonk({"score": score, "combo": combo})
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	var pos := _holes[hole].get_center()
	_stage.bonk_fx(hole)
	AudioDirector.try_play(self, "gvz_pop", 1.0 + 0.02 * minf(combo, 10.0))
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % delta, AcTokens.LEAF_DARK)
		ctx.juice.hit_freeze(45)
		if int(result["bonus"]) > 0:
			AudioDirector.try_play(self, "mg_combo")
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.float_text(
				pos - Vector2(0.0, 40.0), I18nService.t("mg.carrotGuard.combo"), AcTokens.PINK
			)
	ctx.report_score(score, delta)


func _tap_king() -> void:
	var result := CarrotGuardLogic.apply_king_tap(
		{"score": score, "combo": combo, "hp": int(king["hp"])}
	)
	var pos := _holes[int(king["hole"])].get_center()
	king["hp"] = int(result["hp"])
	AudioDirector.try_play(self, "gvz_boom")
	if not bool(result["complete"]):
		_stage.king_hit_fx(int(king["hole"]))
		if ctx.juice != null:
			ctx.juice.shake(0.2)
			ctx.juice.float_text(pos, "×%d" % int(result["hp"]), AcTokens.GOLD)
		return
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	_stage.king_down_fx(int(king["hole"]))
	king = {}
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.slowmo(0.4, 260)
		ctx.juice.float_text(pos, I18nService.t("mg.carrotGuard.king_defeated"), AcTokens.GOLD)
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	if carrots <= 0 and ctx.juice != null:
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.4),
			I18nService.t("mg.carrotGuard.empty"),
			AcTokens.DANGER
		)
	ctx.report_end({"score": score, "carrots": carrots, "stolen": int(tune["CARROTS"]) - carrots})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.carrotGuard.stolen",
			{"n": int(tune["CARROTS"]) - carrots, "max": int(tune["ENDLESS_STOLEN"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_carrot_label.text = I18nService.t(
		"mg.carrotGuard.carrots", {"n": carrots, "max": int(tune["CARROTS"])}
	)


func _hole_at(screen: Vector2) -> int:
	for i in _holes.size():
		if _holes[i].has_point(screen):
			return i
	return -1
