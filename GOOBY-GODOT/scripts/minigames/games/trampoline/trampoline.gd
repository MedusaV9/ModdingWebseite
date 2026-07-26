extends MinigameBase
## Trampolin-Tricks (trampoline) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## TrampolineLogic (zahlengleich zum Web, Bot-zertifiziert): Tippen im
## schrumpfenden Landefenster gibt Boost, Wischen in der Luft macht
## Salto/Drehung/Schraube (Punkte × Höhenfaktor 1–3), Fenster verpasst =
## Po-Landung und die Höhe fällt auf BASE_VY zurück. Alle drei Trickarten in
## EINEM Flug zahlen +12. 60 s; Endlos endet nach drei Bruchlandungen.
##
## ECHTE 3D-TURNHALLE (FB-4, TrampolineStage3D): Gooby springt als echtes Rig
## metergenau über einem Sprungtuch mit Federn, Tricks drehen ihn im Raum,
## die Höhenmarken ×2/×3 leuchten beim Erreichen. Nur das Landefenster bleibt
## als 2D-Ring-Overlay über der Figur (Skill-Check-Lesbarkeit). Die 3D-Welt
## hängt unter der Node2D-Wurzel, der MinigameBase-Vertrag bleibt unberührt.

const Stage := preload("res://scripts/minigames/games/trampoline/trampoline_stage3d.gd")

## Mindest-Wischlänge in Pixeln, damit eine Geste als Trick zählt.
const SWIPE_MIN_PX := 44.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var height := 0.0
var vy := 0.0
var apex := 0.0
var airborne := true
var failures := 0
var stagger_left := 0.0
var armed := ""
var trick_chain: Dictionary = {}
var tricking := 0.0
var trick_spin := 0.0
var last_trick := ""
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _trick_label: Label
var _hint_label: Label
var _stage: Node3D
var _swipe_from := Vector2.ZERO
var _swiping := false
var _pulse := 0.0
var _shock := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = TrampolineLogic.apply_difficulty(TrampolineLogic.TRAMP, ctx.difficulty)
	rng = ctx.rng()
	vy = float(tune["BASE_VY"])
	apex = TrampolineLogic.apex_for(vy, float(tune["GRAVITY"]))
	trick_chain = TrampolineLogic.create_trick_chain()
	_stage = Stage.new()
	_stage.name = "Halle3D"
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
		_stage.apply_size(view_size)
	_update_labels()
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_trick_label = Label.new()
	_trick_label.theme_type_variation = &"CaptionLabel"
	add_child(_trick_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.trampoline.hint")
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
	_shock = maxf(0.0, _shock - delta * 2.2)
	tricking = maxf(0.0, tricking - delta)
	if tricking > 0.0:
		trick_spin += delta * 9.0
	if stagger_left > 0.0:
		stagger_left = maxf(0.0, stagger_left - delta)
		if stagger_left <= 0.0:
			_launch(float(tune["BASE_VY"]))
	else:
		_flight_tick(delta)
	if TrampolineLogic.endless_should_end(failures, tune):
		_finish()
		return
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_stage.sync(
		height, vy, stagger_left, tricking, trick_spin, last_trick, apex, _shock, _pulse, delta
	)
	_update_labels()
	queue_redraw()


func _flight_tick(delta: float) -> void:
	var g := float(tune["GRAVITY"])
	var previous := height
	vy -= g * delta
	height += vy * delta
	if not TrampolineLogic.crossed_mat(previous, height, vy):
		return
	# Mattenkontakt: die scharfgestellte Aktion genau einmal verbrauchen.
	var consumed := TrampolineLogic.consume_landing_action(armed)
	armed = str(consumed["armed"])
	var action := str(consumed["action"])
	height = 0.0
	_shock = 1.0
	if action == "butt":
		_butt_landing()
		return
	var next_vy := TrampolineLogic.next_bounce_vy(
		TrampolineLogic.apex_for(vy, g) * 0.0 + absf(vy), action, tune
	)
	if action == "boost":
		AudioDirector.try_play(self, "mg_perfect")
		_stage.boost_fx()
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.6)
			ctx.juice.float_text(
				_gooby_screen() - Vector2(0.0, 40.0),
				I18nService.t("mg.trampoline.boost"),
				AcTokens.TEAL_DARK
			)
	else:
		AudioDirector.try_play(self, "gvz_place", 0.95)
	_launch(next_vy)


func _butt_landing() -> void:
	failures += 1
	stagger_left = float(tune["BUTT_STAGGER_SEC"])
	airborne = false
	vy = 0.0
	AudioDirector.try_play(self, "mg_spill")
	_stage.butt_fx()
	if ctx.juice != null:
		ctx.juice.shake(0.45)
		ctx.juice.hit_freeze(90)
		ctx.juice.float_text(_gooby_screen(), I18nService.t("mg.trampoline.butt"), AcTokens.DANGER)


func _launch(next_vy: float) -> void:
	vy = next_vy
	height = 0.0
	airborne = true
	apex = TrampolineLogic.apex_for(vy, float(tune["GRAVITY"]))
	armed = ""
	trick_chain = TrampolineLogic.create_trick_chain()
	trick_spin = 0.0


func _time_to_impact() -> float:
	if not airborne:
		return INF
	# `vy` geht VORZEICHENBEHAFTET hinein (Web: `timeToImpact(this.h, this.vy)`).
	# Mit dem gedrehten Vorzeichen kam immer rund 1 s heraus, wodurch
	# `classify_landing_tap` ausnahmslos "ignore" lieferte — der Boost war
	# schlicht nicht erreichbar.
	return TrampolineLogic.time_to_impact(height, vy, float(tune["GRAVITY"]))


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or stagger_left > 0.0:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_swiping = true
			_swipe_from = touch.position
			_tap_landing()
		elif _swiping:
			_swiping = false
			_resolve_swipe(touch.position - _swipe_from)
	elif event is InputEventScreenDrag and _swiping:
		var drag := event as InputEventScreenDrag
		if (drag.position - _swipe_from).length() >= SWIPE_MIN_PX:
			_swiping = false
			_resolve_swipe(drag.position - _swipe_from)


## Tippen im Fallen: im Fenster Boost, in der Urteilszone Po-Landung.
func _tap_landing() -> void:
	if vy > 0.0:
		return
	var verdict := TrampolineLogic.classify_landing_tap(_time_to_impact(), apex, tune)
	if verdict == "ignore":
		return
	armed = verdict
	AudioDirector.try_play(self, "ui_tick", 1.2 if verdict == "boost" else 0.85)


func _resolve_swipe(delta: Vector2) -> void:
	if delta.length() < SWIPE_MIN_PX:
		return
	if not TrampolineLogic.can_trick(airborne, _time_to_impact(), tricking > 0.0, tune):
		return
	var kind := "twist"
	if absf(delta.x) > absf(delta.y):
		kind = "flip" if delta.x < 0.0 else "spin"
	var mult := TrampolineLogic.height_multiplier(apex)
	var points := TrampolineLogic.trick_points(kind, mult)
	score += points
	tricking = 0.3
	last_trick = kind
	_stage.trick_fx()
	AudioDirector.try_play(self, "mg_combo", 0.95 + 0.06 * float(mult))
	if ctx.juice != null:
		ctx.juice.float_text(
			_gooby_screen() - Vector2(0.0, 46.0),
			"%s +%d" % [I18nService.t("mg.trampoline.%s" % kind), points],
			AcTokens.PINK if mult < 3 else AcTokens.GOLD
		)
	var chained := TrampolineLogic.record_trick(trick_chain, kind)
	if bool(chained["triggered"]):
		var bonus := int(chained["bonus"])
		score += bonus
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.slowmo(0.35, 280)
			ctx.juice.float_text(
				_gooby_screen() - Vector2(0.0, 84.0),
				I18nService.t("mg.trampoline.combo"),
				AcTokens.GOLD
			)
		points += bonus
	ctx.report_score(score, points)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "failures": failures, "elapsed": elapsed})


func _update_labels() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0)
	_trick_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 190.0, vp.y - 40.0)
	_hint_label.size = Vector2(380.0, 34.0)
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.trampoline.fails", {"n": failures, "max": int(tune["ENDLESS_FAILURE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_trick_label.text = "×%d" % TrampolineLogic.height_multiplier(apex)


## Gooby skaliert mit dem Viewport, sonst ist er auf großen Schirmen verloren.
func _gooby_radius() -> float:
	return clampf(maxf(view_size.x, view_size.y) * 0.05, 26.0, 62.0)


func _gooby_screen() -> Vector2:
	return _stage.gooby_screen()


## Nur noch HUD-Overlay: das Landefenster als Ring um die 3D-Figur — der
## Skill-Check bleibt damit pixelscharf lesbar, egal wie die Kamera steht.
func _draw() -> void:
	_draw_window_gauge()


## Landefenster als Ring um Gooby, sobald er fällt — das ist der Skill-Check.
func _draw_window_gauge() -> void:
	if not airborne or vy > 0.0 or finished:
		return
	var tti := _time_to_impact()
	var window := TrampolineLogic.window_sec_for(apex, tune)
	var zone := float(tune["JUDGE_ZONE_SEC"])
	if tti > zone * 1.6:
		return
	var pos := _gooby_screen()
	var ring := _gooby_radius() * 1.7
	var ratio := clampf(1.0 - tti / maxf(0.05, zone), 0.0, 1.0)
	var inside := tti <= window
	var tint := AcTokens.LEAF if inside else AcTokens.YELLOW
	draw_arc(pos, ring, -PI * 0.5, -PI * 0.5 + TAU * ratio, 30, tint, 6.0)
	draw_arc(pos, ring, 0.0, TAU, 30, Color(0.4, 0.32, 0.28, 0.18), 3.0)
