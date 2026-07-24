extends MinigameBase
## Teestube (teaParty) — Spiel-Szene. Die MECHANIK-Zahlen kommen 1:1 aus
## TeaPartyLogic (zahlengleich zum Web, Bot-zertifiziert): Halten gießt
## (FILL_RATE), Loslassen im Band punktet (perfect +6 / good +3), Überlauf/
## daneben = Spill, jeder 3. Perfect in Folge +2, Kadenz zieht an. 60 s
## (Endlos: bis 3 Spills). Optik: AC-Pastell + Gooby-Cameo (2D-Vektor) +
## JuiceKit (float_text, bloom bei Perfect, shake/hit_freeze bei Spill).
## Hochkant-Design (390×844-Basis), skaliert über die Viewport-Größe.

const TEA_COLOR := Color(0.78, 0.5, 0.2)
const CUP_COLOR := Color(0.99, 0.97, 0.94)
const BAND_COLOR := Color(0.42, 0.72, 0.42, 0.45)
const PERFECT_COLOR := Color(1.0, 0.72, 0.2, 0.85)

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
var _gooby_bounce := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = TeaPartyLogic.apply_difficulty(TeaPartyLogic.TEA, ctx.difficulty)
	rng = ctx.rng()
	band = TeaPartyLogic.roll_band(rng, tune)
	_build_labels()
	queue_redraw()


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


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_gooby_bounce = maxf(0.0, _gooby_bounce - delta * 3.0)
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
	_update_labels()
	queue_redraw()


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
	var vp := get_viewport_rect().size
	var cup_pos := Vector2(vp.x * 0.5, vp.y * 0.62)
	if res["result"] == "perfect":
		streak += 1
		var bonus := TeaPartyLogic.streak_bonus_at(streak, tune)
		score = TeaPartyLogic.apply_score(score, bonus)
		_gooby_bounce = 1.0
		if ctx.juice != null:
			var text := "+%d" % (points + bonus)
			ctx.juice.float_text(cup_pos, text, Color(1.0, 0.72, 0.2))
			ctx.juice.bloom_pulse(0.6)
			if bonus > 0:
				ctx.juice.float_text(
					cup_pos - Vector2(0, 40),
					I18nService.t("mg.teaParty.streak_bonus"),
					Color(0.95, 0.45, 0.66)
				)
	elif res["result"] == "good":
		streak = 0
		if ctx.juice != null:
			ctx.juice.float_text(cup_pos, "+%d" % points, Color(0.42, 0.6, 0.36))
	else:
		streak = 0
		spills += 1
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


func _draw() -> void:
	var vp := get_viewport_rect().size
	# Stube: Pastell-Wand + Holzboden + Tisch.
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.93, 0.96, 0.9))
	draw_rect(Rect2(0, vp.y * 0.78, vp.x, vp.y * 0.22), Color(0.85, 0.72, 0.55))
	draw_rect(Rect2(vp.x * 0.1, vp.y * 0.7, vp.x * 0.8, 18), Color(0.72, 0.55, 0.38))
	draw_rect(Rect2(vp.x * 0.16, vp.y * 0.7 + 18, 16, vp.y * 0.1), Color(0.62, 0.46, 0.3))
	draw_rect(Rect2(vp.x * 0.84 - 16, vp.y * 0.7 + 18, 16, vp.y * 0.1), Color(0.62, 0.46, 0.3))
	_draw_gooby(Vector2(vp.x * 0.82, vp.y * 0.28), 46.0 + _gooby_bounce * 8.0)
	_draw_cup(vp)
	_draw_teapot(vp)


func _draw_cup(vp: Vector2) -> void:
	var w := vp.x * 0.36
	var h := vp.y * 0.26
	var x := vp.x * 0.5 - w * 0.5 + cup_slide * vp.x * 0.6
	var y := vp.y * 0.7 - h
	# Tee-Füllung (level 0..1 von unten), dann Becherwand + Henkel.
	var fill_h := clampf(level, 0.0, 1.1) * h
	draw_rect(Rect2(x + 6, y + h - fill_h, w - 12, fill_h), TEA_COLOR)
	draw_rect(Rect2(x, y, 6, h), CUP_COLOR)
	draw_rect(Rect2(x + w - 6, y, 6, h), CUP_COLOR)
	draw_rect(Rect2(x, y + h - 6, w, 6), CUP_COLOR)
	draw_arc(Vector2(x + w + 10, y + h * 0.5), 22.0, -PI * 0.5, PI * 0.5, 16, CUP_COLOR, 8.0)
	# Zielband (good) + Perfect-Ring auf Becherhöhe.
	var center := float(band.get("center", 0.7))
	var half := float(band.get("half", 0.075))
	var perfect := float(band.get("perfectHalf", 0.028))
	var band_y := y + h - (center + half) * h
	draw_rect(Rect2(x - 14, band_y, w + 28, 2.0 * half * h), BAND_COLOR)
	var ring_y := y + h - (center + perfect) * h
	draw_rect(Rect2(x - 18, ring_y, w + 36, 2.0 * perfect * h), PERFECT_COLOR)


func _draw_teapot(vp: Vector2) -> void:
	var pos := Vector2(vp.x * 0.5, vp.y * 0.24)
	var tilt := 0.5 if holding else 0.0
	# Kanne: Bauch + Deckel + Tülle; gießt beim Halten einen Strahl.
	draw_set_transform(pos, tilt, Vector2.ONE)
	draw_circle(Vector2.ZERO, 46.0, Color(0.95, 0.45, 0.66))
	draw_circle(Vector2(0, -40), 14.0, Color(0.85, 0.35, 0.56))
	draw_rect(Rect2(-70, -12, 34, 14), Color(0.95, 0.45, 0.66))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if holding:
		var stream_x := pos.x - 62.0
		draw_rect(Rect2(stream_x, pos.y, 8, vp.y * 0.7 - pos.y - 10), TEA_COLOR)


func _draw_gooby(pos: Vector2, r: float) -> void:
	# Gooby-Cameo (2D-Vektor-Platzhalter im Stil des W1c-Previews; das echte
	# W1b-3D-Rig ist im 2D-SubViewport bewusst nicht eingebettet).
	draw_circle(pos + Vector2(-r * 0.45, -r * 1.1), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(r * 0.45, -r * 1.1), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos, r, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-r * 0.32, -r * 0.1), r * 0.1, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(r * 0.32, -r * 0.1), r * 0.1, Color(0.2, 0.16, 0.14))
	draw_arc(pos + Vector2(0, r * 0.25), r * 0.3, 0.3, PI - 0.3, 12, Color(0.2, 0.16, 0.14), 3.0)
