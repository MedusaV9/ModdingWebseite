extends MinigameBase
## Teestube (teaParty) — Spiel-Szene. Die MECHANIK-Zahlen kommen 1:1 aus
## TeaPartyLogic (zahlengleich zum Web, Bot-zertifiziert): Halten gießt
## (FILL_RATE), Loslassen im Band punktet (perfect +6 / good +3), Überlauf/
## daneben = Spill, jeder 3. Perfect in Folge +2, Kadenz zieht an. 60 s
## (Endlos: bis 3 Spills). JuiceKit (float_text, hit_freeze/bloom bei Perfect,
## shake/hit_freeze bei Spill) + SFX über AudioDirector.
##
## ECHTE 3D-STUBE (FB-4, TeaPartyStage3D): Gooby steht als Gastgeber am Tisch,
## die Kanne kippt beim Gießen, der Tee steigt als echter Zylinder in der
## Glastasse und das Zielband liegt als Glasring UM die Tasse. Die 3D-Welt
## hängt unter der Node2D-Wurzel (Godot rendert 3D hinter den CanvasItems),
## der MinigameBase-Vertrag bleibt unberührt.

const Stage := preload("res://scripts/minigames/games/tea_party/tea_party_stage3d.gd")

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var cups := 0
var spills := 0
var streak := 0
var elapsed := 0.0
var level := 0.0
var band: Dictionary = {}
var holding := false
var serving := true
var serve_left := 0.6
var cup_slide := 1.0
var finished := false

var _time_label: Label
var _streak_label: Label
var _hint_label: Label
var _stage: Node3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = TeaPartyLogic.apply_difficulty(TeaPartyLogic.TEA, ctx.difficulty)
	rng = ctx.rng()
	band = TeaPartyLogic.roll_band(rng, tune)
	_stage = Stage.new()
	_stage.name = "Stube3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_labels()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func start() -> void:
	super.start()
	serving = true
	serve_left = 0.5


func end() -> void:
	super.end()
	finished = true


func _build_labels() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.position = Vector2(16, 10)
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	_streak_label.position = Vector2(16, 48)
	add_child(_streak_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.teaParty.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(size)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if serving:
		serve_left -= delta
		cup_slide = clampf(serve_left / 0.4, 0.0, 1.0)
		if serve_left <= 0.0:
			serving = false
			cup_slide = 0.0
	elif holding:
		level = TeaPartyLogic.fill_after(level, delta, tune)
		if level >= float(tune["OVERFLOW_LEVEL"]):
			_release()
	_stage.sync(level, band, holding, cup_slide, delta)
	_update_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or serving:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			holding = true
		elif holding:
			_release()


func _release() -> void:
	holding = false
	var res := TeaPartyLogic.pour_result(level, band, tune)
	var points := int(res["points"])
	score = TeaPartyLogic.apply_score(score, points)
	var cup_pos: Vector2 = _stage.cup_screen()
	if res["result"] == "perfect":
		streak += 1
		var bonus := TeaPartyLogic.streak_bonus_at(streak, tune)
		score = TeaPartyLogic.apply_score(score, bonus)
		_stage.celebrate()
		# Steigende Tonhöhe belohnt die Serie hörbar (ab 8er-Kette gedeckelt).
		AudioDirector.try_play(self, "mg_perfect", 1.0 + 0.06 * minf(streak - 1, 7.0))
		if ctx.juice != null:
			var text := "+%d" % (points + bonus)
			ctx.juice.float_text(cup_pos, text, Color(1.0, 0.72, 0.2))
			ctx.juice.hit_freeze(45)
			ctx.juice.bloom_pulse(0.6)
			if bonus > 0:
				AudioDirector.try_play(self, "mg_combo")
				ctx.juice.bloom_pulse(0.9)
				ctx.juice.float_text(
					cup_pos - Vector2(0, 40),
					I18nService.t("mg.teaParty.streak_bonus"),
					Color(0.95, 0.45, 0.66)
				)
	elif res["result"] == "good":
		streak = 0
		_stage.cheer()
		AudioDirector.try_play(self, "mg_good")
		if ctx.juice != null:
			ctx.juice.float_text(cup_pos, "+%d" % points, Color(0.42, 0.6, 0.36))
	else:
		streak = 0
		spills += 1
		_stage.groan()
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.float_text(cup_pos, I18nService.t("mg.teaParty.spill"), Color(0.8, 0.3, 0.25))
			ctx.juice.shake(0.35)
			ctx.juice.hit_freeze(70)
	ctx.report_score(score, points)
	if TeaPartyLogic.endless_should_end(spills, tune):
		_finish()
		return
	# Nächste Tasse: Band neu würfeln, Kadenz aus der Logik.
	level = 0.0
	band = TeaPartyLogic.roll_band(rng, tune)
	cups += 1
	serving = true
	serve_left = TeaPartyLogic.serve_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "cups": cups, "spills": spills})


func _update_labels() -> void:
	var vp := get_viewport_rect().size
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.teaParty.spills", {"spills": spills, "max": int(tune["ENDLESS_MAX_SPILLS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if streak > 0:
		_streak_label.text = I18nService.t("mg.game.streak", {"n": streak})
	else:
		_streak_label.text = ""
	_hint_label.position = Vector2(vp.x * 0.5 - 140, vp.y - 60)
	_hint_label.size = Vector2(280, 40)
