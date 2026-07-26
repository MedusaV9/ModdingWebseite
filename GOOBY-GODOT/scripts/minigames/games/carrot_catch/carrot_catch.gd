extends MinigameBase
## Möhrenfang (carrotCatch) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## CarrotCatchLogic (zahlengleich zum Web, Bot-zertifiziert): Spawn-Kadenz,
## Junk-Quote 10→30 %, Fallspeed +8 %/10 s (gestuft), Junk −2 + 0.5 s Dizzy,
## 1× goldene Möhre (+10, 1.5× Speed), Endlos endet nach 3 Boden-Möhren.
## Steuerung: Touch-Drag zieht den Korb (Hochkant-optimiert).
##
## ECHTER 3D-OBSTGARTEN (FB-4, CarrotCatchStage3D): Kenney-Food-Modelle fallen
## als 3D-Objekte, Gooby rennt als echtes Rig mit dem Picknickkorb, hinten
## Möhrenbeete, Zaun und Bäume. Die Kamera rahmt EXAKT die 2D-Rechnung
## (Weltbreite 2·WORLD_HALF_W), alle Zahlen bleiben unangetastet. Die 3D-Welt
## hängt unter der Node2D-Wurzel, der MinigameBase-Vertrag bleibt gleich.

const Stage := preload("res://scripts/minigames/games/carrot_catch/carrot_catch_stage3d.gd")

## Sichtbare Welt-Halbbreite in Logik-Einheiten (Web-Kamera ≈ 3.25 bei 390px).
const WORLD_HALF_W := 3.25

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var combo := 0
var missed_carrots := 0
var elapsed := 0.0
var basket_x := 0.0
var target_x := 0.0
var dizzy_until := -1.0
var next_spawn := 0.0
var golden_at := -1.0
var golden_spawned := false
var finished := false
var items: Array[Dictionary] = []

var _time_label: Label
var _combo_label: Label
var _hint_label: Label
var _stage: Node3D
var _framed_vp := Vector2.ZERO


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = CarrotCatchLogic.apply_difficulty(CarrotCatchLogic.CATCH, ctx.difficulty)
	rng = ctx.rng()
	if not bool(tune["ENDLESS"]):
		golden_at = CarrotCatchLogic.golden_spawn_at(rng, float(tune["DURATION_SEC"]), tune)
	next_spawn = CarrotCatchLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_stage = Stage.new()
	_stage.name = "Garten3D"
	add_child(_stage)
	_stage.setup_stage(float(tune["BASKET_HALF_WIDTH"]))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_labels()
	_frame_stage()


## Pflicht-Layouthook: die Kamera folgt dem Viewport-Rect (Canvas-Einheiten).
func apply_view(_size: Vector2) -> void:
	position = Vector2.ZERO
	_frame_stage()


func _frame_stage() -> void:
	var vp := get_viewport_rect().size
	if vp == _framed_vp or vp.x <= 1.0:
		return
	_framed_vp = vp
	_stage.frame(vp, _px_per_unit(vp))


func end() -> void:
	super.end()
	finished = true


func _build_labels() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.position = Vector2(16, 10)
	add_child(_time_label)
	_combo_label = Label.new()
	_combo_label.theme_type_variation = &"CaptionLabel"
	_combo_label.position = Vector2(16, 48)
	add_child(_combo_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.carrotCatch.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	var vp := get_viewport_rect().size
	var ppu := _px_per_unit(vp)
	# Korb folgt dem Drag-Ziel (außer während Dizzy).
	if elapsed >= dizzy_until:
		basket_x = lerpf(basket_x, target_x, minf(1.0, delta * 14.0))
	var half := _visible_half_w(vp, ppu)
	basket_x = clampf(basket_x, -half + 0.5, half - 0.5)
	_spawn_tick(vp)
	_move_items(vp, ppu, delta)
	if CarrotCatchLogic.is_catch_round_over(
		{"elapsed": elapsed, "missedCarrots": missed_carrots}, tune
	):
		_finish()
		return
	_frame_stage()
	_stage.sync(items, basket_x, elapsed < dizzy_until, vp, ppu, elapsed, delta)
	_update_labels()


func _spawn_tick(vp: Vector2) -> void:
	if not golden_spawned and golden_at >= 0.0 and elapsed >= golden_at:
		golden_spawned = true
		(
			items
			. append(
				{
					"kind": "golden",
					"key": "carrot",
					"value": int(tune["GOLDEN_POINTS"]),
					"x": CarrotCatchLogic.spawn_x_for_roll(rng.next(), _visible_half_w_default(vp)),
					"y": -30.0,
				}
			)
		)
	next_spawn -= get_process_delta_time()
	if next_spawn > 0.0:
		return
	next_spawn = CarrotCatchLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var item := CarrotCatchLogic.roll_item(rng, elapsed, tune)
	item["x"] = CarrotCatchLogic.spawn_x_for_roll(rng.next(), _visible_half_w_default(vp))
	item["y"] = -30.0
	items.append(item)


func _move_items(vp: Vector2, ppu: float, delta: float) -> void:
	var basket_y := vp.y - 130.0
	var kept: Array[Dictionary] = []
	for item in items:
		var speed := CarrotCatchLogic.item_fall_speed(elapsed, str(item["kind"]), tune)
		item["y"] = float(item["y"]) + speed * ppu * delta
		var y := float(item["y"])
		if y >= basket_y and y < basket_y + 46.0:
			if CarrotCatchLogic.basket_catches_x(float(item["x"]), basket_x, tune):
				_catch(item, vp)
				continue
		if y > vp.y + 30.0:
			if bool(tune["ENDLESS"]) and item["kind"] == "good" and item["key"] == "carrot":
				missed_carrots += 1
				# Verpasste Möhre = ein Endlos-Leben weg: fühlbar machen.
				AudioDirector.try_play(self, "mg_spill", 0.85)
				if ctx.juice != null:
					ctx.juice.shake(0.25)
			continue
		kept.append(item)
	items = kept


func _catch(item: Dictionary, vp: Vector2) -> void:
	var res := CarrotCatchLogic.apply_catch_state({"score": score, "combo": combo}, item)
	var delta := int(res["delta"])
	score = int(res["score"])
	combo = int(res["combo"])
	var pos := Vector2(vp.x * 0.5 + float(item["x"]) * _px_per_unit(vp), vp.y - 190.0)
	var kind := str(item["kind"])
	if kind == "golden":
		AudioDirector.try_play(self, "mg_golden")
	elif kind == "good":
		AudioDirector.try_play(self, "mg_good")
	else:
		AudioDirector.try_play(self, "mg_junk")
	if kind == "junk" or kind == "rotten":
		_stage.junk_fx()
	else:
		_stage.catch_fx(kind == "golden")
	if ctx.juice != null:
		if kind == "golden":
			ctx.juice.float_text(pos, "+%d" % int(item["value"]), Color(1.0, 0.78, 0.1))
			ctx.juice.slowmo(0.35, 350)
			ctx.juice.bloom_pulse(0.8)
		elif kind == "good":
			ctx.juice.float_text(pos, "+%d" % int(item["value"]), Color(0.42, 0.6, 0.36))
		else:
			ctx.juice.float_text(pos, I18nService.t("mg.carrotCatch.yuck"), Color(0.8, 0.3, 0.25))
			ctx.juice.shake(0.4)
			ctx.juice.hit_freeze(80)
		if CarrotCatchLogic.combo_milestone(combo):
			AudioDirector.try_play(self, "mg_combo", 1.0 + 0.03 * minf(combo, 20.0))
			ctx.juice.bloom_pulse(0.4)
			ctx.juice.float_text(
				pos - Vector2(0, 42),
				I18nService.t("mg.game.streak", {"n": combo}),
				Color(0.95, 0.45, 0.66)
			)
	if kind == "junk" or kind == "rotten":
		dizzy_until = elapsed + float(tune["DIZZY_SEC"])
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	var final_score := CarrotCatchLogic.final_catch_score(score, tune)
	ctx.report_end({"score": final_score, "missedCarrots": missed_carrots, "elapsed": elapsed})


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	var vp := get_viewport_rect().size
	var ppu := _px_per_unit(vp)
	if event is InputEventScreenTouch and event.pressed:
		target_x = (event.position.x - vp.x * 0.5) / ppu
	elif event is InputEventScreenDrag:
		target_x = (event.position.x - vp.x * 0.5) / ppu


func _update_labels() -> void:
	var vp := get_viewport_rect().size
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.carrotCatch.missed",
			{"n": missed_carrots, "max": int(tune["ENDLESS_MISSED_CARROTS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if combo > 1:
		_combo_label.text = I18nService.t("mg.game.streak", {"n": combo})
	else:
		_combo_label.text = ""
	_hint_label.position = Vector2(vp.x * 0.5 - 140, vp.y - 52)
	_hint_label.size = Vector2(280, 40)


func _px_per_unit(vp: Vector2) -> float:
	return vp.x / (WORLD_HALF_W * 2.0)


## Halbbreite in Einheiten, die der aktuelle Viewport wirklich zeigt.
func _visible_half_w(vp: Vector2, ppu: float) -> float:
	return vp.x * 0.5 / ppu


func _visible_half_w_default(vp: Vector2) -> float:
	return _visible_half_w(vp, _px_per_unit(vp))
