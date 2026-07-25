extends MinigameBase
## Trampolin-Tricks (trampoline) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## TrampolineLogic (zahlengleich zum Web, Bot-zertifiziert): Tippen im
## schrumpfenden Landefenster gibt Boost, Wischen in der Luft macht
## Salto/Drehung/Schraube (Punkte × Höhenfaktor 1–3), Fenster verpasst =
## Po-Landung und die Höhe fällt auf BASE_VY zurück. Alle drei Trickarten in
## EINEM Flug zahlen +12. 60 s; Endlos endet nach drei Bruchlandungen.
## Optik: Seitenansicht mit Sprungtuch, Höhenmarken und Trick-Bannern.

## Welt-Halbhöhe in Metern, die der Viewport zeigt (Apex bleibt < 4 m).
const WORLD_H := 4.6
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
		_trick_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 190.0, view_size.y - 40.0)
		_hint_label.size = Vector2(380.0, 34.0)
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
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.trampoline.fails", {"n": failures, "max": int(tune["ENDLESS_FAILURE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_trick_label.text = "×%d" % TrampolineLogic.height_multiplier(apex)


func _ppu() -> float:
	return (view_size.y - 200.0) / WORLD_H


func _mat_y() -> float:
	return view_size.y - (128.0 if not landscape else 88.0)


## Gooby skaliert mit dem Viewport, sonst ist er auf großen Schirmen verloren.
func _gooby_radius() -> float:
	return clampf(maxf(view_size.x, view_size.y) * 0.05, 26.0, 62.0)


func _gooby_screen() -> Vector2:
	return Vector2(view_size.x * 0.5, _mat_y() - height * _ppu() - _gooby_radius())


func _draw() -> void:
	_draw_hall()
	_draw_window_gauge()
	_draw_mat()
	_draw_gooby()


## Turnhalle in Seitenansicht: Wandpaneele, Sprossenwand, Wimpelkette und ein
## Dielenboden geben dem Sprung überhaupt erst einen Maßstab.
func _draw_hall() -> void:
	var floor_y := _mat_y() + 40.0
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("F6E4C8"))
	draw_rect(Rect2(0.0, 0.0, view_size.x, floor_y), Color("FBEFDC"))
	# Obere Wandzone mit Fensterband.
	var band := floor_y * 0.3
	draw_rect(Rect2(0.0, 0.0, view_size.x, band), Color("D9ECF7"))
	draw_line(Vector2(0.0, band), Vector2(view_size.x, band), Color("B9CEDD"), 3.0)
	var win := view_size.x / 4.0
	for i in 4:
		var rect := Rect2(win * float(i) + 14.0, band * 0.3, win - 28.0, band * 0.5)
		draw_rect(rect, Color("EAF6FC"))
		draw_rect(rect, Color("B9CEDD"), false, 3.0)
		draw_line(
			rect.position + Vector2(rect.size.x * 0.5, 0.0),
			rect.position + Vector2(rect.size.x * 0.5, rect.size.y),
			Color("B9CEDD"),
			2.0
		)
	_draw_bunting(band)
	# Wandpaneele + Wimpel-Banner brechen die sonst leere Hallenwand auf.
	var wain := floor_y - 132.0
	draw_rect(Rect2(0.0, wain, view_size.x, floor_y - wain), Color("F2DFC2"))
	draw_line(Vector2(0.0, wain), Vector2(view_size.x, wain), Color(0.72, 0.58, 0.42, 0.55), 3.0)
	for i in 7:
		var px := (float(i) + 0.5) / 7.0 * view_size.x
		draw_line(Vector2(px, band + 4.0), Vector2(px, wain), Color(0.78, 0.66, 0.5, 0.22), 8.0)
	var banner := Rect2(view_size.x * 0.5 - 132.0, band + 78.0, 264.0, 62.0)
	draw_rect(banner, AcTokens.PINK)
	draw_rect(banner, AcTokens.INK, false, 3.0)
	draw_string(
		ThemeService.font(800),
		banner.position + Vector2(30.0, 43.0),
		"GOOBY GYM",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		28,
		AcTokens.WHITE
	)
	# Sprossenwand links — klassische Turnhallen-Silhouette.
	var bars_top := band + 60.0
	var bars_bottom := wain - 10.0
	draw_rect(Rect2(14.0, bars_top, 14.0, bars_bottom - bars_top), Color("C79A6B"))
	draw_rect(Rect2(92.0, bars_top, 14.0, bars_bottom - bars_top), Color("C79A6B"))
	var rung := bars_top + 18.0
	while rung < bars_bottom:
		draw_line(Vector2(18.0, rung), Vector2(104.0, rung), Color("D9B487"), 8.0)
		rung += 40.0
	_draw_tier_lines()
	# Dielenboden.
	draw_rect(Rect2(0.0, floor_y, view_size.x, view_size.y - floor_y), Color("E0C398"))
	draw_line(Vector2(0.0, floor_y), Vector2(view_size.x, floor_y), AcTokens.INK, 3.0)
	var plank := 34.0
	var py := floor_y + plank
	while py < view_size.y:
		draw_line(Vector2(0.0, py), Vector2(view_size.x, py), Color(0.72, 0.58, 0.42, 0.5), 2.0)
		py += plank


func _draw_bunting(band: float) -> void:
	var flags := 9
	var tints: Array[Color] = [AcTokens.PINK, AcTokens.YELLOW, AcTokens.TEAL, AcTokens.LEAF]
	var sag := 22.0
	for i in flags:
		var t := (float(i) + 0.5) / float(flags)
		var x := t * view_size.x
		var y := band + 6.0 + sin(t * PI) * sag
		draw_colored_polygon(
			PackedVector2Array([Vector2(x - 13.0, y), Vector2(x + 13.0, y), Vector2(x, y + 26.0)]),
			tints[i % tints.size()]
		)
	var line := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		line.append(Vector2(t * view_size.x, band + 6.0 + sin(t * PI) * sag))
	draw_polyline(line, AcTokens.INK_SOFT, 2.5)


## Höhenmarken der Punkte-Stufen ×2 und ×3 als Kreide-Bänder mit Chip.
func _draw_tier_lines() -> void:
	var tiers: Array[float] = [
		float(TrampolineLogic.TRAMP["TIER2_APEX"]), float(TrampolineLogic.TRAMP["TIER3_APEX"])
	]
	for tier in tiers:
		var y := _mat_y() - tier * _ppu()
		var is_top := tier > float(TrampolineLogic.TRAMP["TIER2_APEX"])
		var tint := AcTokens.GOLD if is_top else AcTokens.TEAL
		var reached := apex >= tier
		draw_dashed_line(
			Vector2(118.0, y),
			Vector2(view_size.x - 74.0, y),
			Color(tint.r, tint.g, tint.b, 0.85 if reached else 0.4),
			3.0,
			12.0
		)
		var chip := Rect2(view_size.x - 68.0, y - 16.0, 52.0, 32.0)
		draw_rect(chip, tint if reached else AcTokens.PAPER)
		draw_rect(chip, AcTokens.INK, false, 3.0)
		draw_string(
			ThemeService.font(700),
			chip.position + Vector2(13.0, 23.0),
			"×3" if is_top else "×2",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			20,
			AcTokens.INK
		)


## Landefenster als Ring um Gooby, sobald er fällt — das ist der Skill-Check.
func _draw_window_gauge() -> void:
	if not airborne or vy > 0.0:
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


func _draw_mat() -> void:
	var y := _mat_y()
	var dip := _shock * 20.0
	var left := Vector2(view_size.x * 0.14, y)
	var right := Vector2(view_size.x * 0.86, y)
	var mid := Vector2(view_size.x * 0.5, y + dip)
	# Fallschatten: verankert den Sprung über der Matte.
	var drop := clampf(1.0 - height / 3.6, 0.22, 1.0)
	draw_set_transform(Vector2(mid.x, y + 6.0), 0.0, Vector2(1.0, 0.24))
	draw_circle(Vector2.ZERO, _gooby_radius() * 1.5 * drop, Color(0.29, 0.23, 0.21, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Rahmen + Federn.
	for side in [left, right]:
		draw_line(side, side + Vector2(0.0, 78.0), AcTokens.INK, 12.0)
		draw_line(side, side + Vector2(0.0, 78.0), Color("B07A50"), 7.0)
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var top := left.lerp(right, t)
		var sag := sin(t * PI) * dip
		draw_line(Vector2(top.x, y + sag), Vector2(top.x, y + 16.0), Color("A9B4BD"), 3.0)
	var cloth := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		cloth.append(Vector2(lerpf(left.x, right.x, t), y + sin(t * PI) * dip))
	draw_polyline(cloth, AcTokens.INK, 11.0)
	draw_polyline(cloth, AcTokens.TEAL, 7.0)
	for side in [left, right]:
		draw_circle(side, 9.0, AcTokens.INK)
		draw_circle(side, 5.5, AcTokens.YELLOW)
	if _shock > 0.05:
		var r := (1.0 - _shock) * float(TrampolineLogic.TRAMP_JUICE["SHOCKWAVE_SCALE"]) * 40.0
		draw_arc(mid, r, 0.0, TAU, 26, Color(0.35, 0.79, 0.72, _shock * 0.5), 4.0)


func _draw_gooby() -> void:
	var pos := _gooby_screen()
	var r := _gooby_radius()
	var angle := trick_spin if tricking > 0.0 else 0.0
	# Flugspur: drei verblassende Nachbilder unterhalb des Aufstiegs.
	if airborne and absf(vy) > 1.2:
		for i in range(1, 4):
			var trail := pos + Vector2(0.0, signf(vy) * float(i) * r * 0.55)
			draw_circle(trail, r * (1.0 - float(i) * 0.2), Color(1.0, 0.93, 0.74, 0.16))
	var fur := Color(0.99, 0.91, 0.7)
	var fur_dark := Color(0.95, 0.83, 0.61)
	draw_set_transform(pos, angle, Vector2.ONE)
	if stagger_left > 0.0:
		draw_circle(Vector2(0.0, r * 0.5), r * 1.05, fur)
	else:
		# Arme und Beine: im Steigen gestreckt, im Fallen angezogen.
		var tuck := -1.0 if vy > 0.0 else 0.45
		for side in [-1.0, 1.0]:
			draw_line(
				Vector2(side * r * 0.62, r * 0.5),
				Vector2(side * r * 1.02, r * 0.5 + tuck * r * 0.7),
				fur_dark,
				r * 0.26
			)
			draw_line(
				Vector2(side * r * 0.3, r * 1.05),
				Vector2(side * r * 0.44, r * 1.05 + absf(tuck) * r * 0.55),
				fur_dark,
				r * 0.28
			)
		# Ohren AM Kopf verwurzelt und in Flugrichtung nachziehend.
		var lay := clampf(-vy * 0.06, -0.5, 0.5)
		for side in [-1.0, 1.0]:
			var ear_root := Vector2(side * r * 0.42, -r * 0.74)
			var ear_tip := ear_root + Vector2(side * r * 0.4 + lay * r * 0.9, -r * 0.98)
			draw_line(ear_root, ear_tip, fur_dark, r * 0.32)
			draw_circle(ear_tip, r * 0.16, fur_dark)
		# Rumpf: sichtbar unter dem Kopf, nicht als Geisterkreis dahinter.
		var belly := Vector2(0.0, r * 0.72)
		draw_circle(belly, r * 0.66, fur)
		draw_arc(belly, r * 0.66, 0.15, PI - 0.15, 18, AcTokens.INK, 3.0)
		draw_circle(belly + Vector2(0.0, r * 0.08), r * 0.36, Color(1.0, 0.96, 0.85))
		draw_circle(Vector2.ZERO, r, fur)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(side * r * 0.6, r * 0.24), r * 0.17, Color(1.0, 0.72, 0.74, 0.5))
	draw_circle(Vector2(-r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(Vector2(r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	var mouth := 0.34 if stagger_left <= 0.0 else 0.18
	draw_arc(Vector2(0.0, r * 0.16), r * mouth, 0.3, PI - 0.3, 12, AcTokens.INK, 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if stagger_left > 0.0:
		draw_arc(pos + Vector2(0.0, -r * 1.5), 16.0, 0.0, TAU, 14, AcTokens.YELLOW, 3.0)
