extends MinigameBase
## Hasenhüpfer (bunnyHop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus BunnyHopLogic
## (zahlengleich zum Web, Bot-zertifiziert): Tippen = Hüpfen, Score = passierte
## Tore, Tempo +2 % je Tor, verzeihende Hitbox (70 % der Optik), die Lücke wird
## alle 10 Tore enger. Ab Sekunde 6 kommt Wind: erst Telegraf, dann ein
## 0,4-Bahnen-Schubs — währenddessen zählen Tore doppelt. Eine Berührung
## beendet den Lauf (in JEDEM Modus, wie im Web).
## Optik: Parallax-Hügel, dicke Säulen, Gooby mit wehenden Ohren.

## Sichtbare Welt-Halbhöhe: FLOOR_Y −3.1 bis CEILING_Y 3.9 plus Rand.
const WORLD_HALF_H := 3.9
## Gooby steht bei dieser Bildschirm-Bruchbreite (Web: linkes Drittel).
const GOOBY_X_FRAC := 0.28
## Neue Säulen erscheinen so weit rechts neben dem Bildrand (Web: halfW+1.6).
const SPAWN_MARGIN := 1.6
## Vor dem ersten Hüpfer schwebt Gooby (Web: y = 0.4 + sin(t·3)·0.12).
const HOVER_Y := 0.4
const HOVER_AMP := 0.12

var tune: Dictionary = {}
var rng: GoobyRng
var gates := 0
var score := 0
var elapsed := 0.0
var gooby_y := 0.0
var gooby_vy := 0.0
var pillars: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var scroll := 0.0
var next_pillar_x := INF
var last_gap_center := INF
var last_gust_index := -1
var finished := false
## Web-Parität: Schwerkraft, Scroll UND Kollision warten auf den ERSTEN Tipp,
## damit weder der Countdown noch ein zögernder Spieler Gooby abstürzen lässt.
var started := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _gate_label: Label
var _hint_label: Label
var _pulse := 0.0
var _ear := 0.0
var _clouds: Array[Vector3] = []


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BunnyHopLogic.apply_difficulty(BunnyHopLogic.HOP, ctx.difficulty)
	rng = ctx.rng()
	gooby_y = HOVER_Y
	gooby_vy = 0.0
	for i in 4:
		_clouds.append(Vector3(rng.next(), 0.06 + rng.next() * 0.22, 0.6 + rng.next() * 0.5))
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
		_gate_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 42.0)
		_hint_label.size = Vector2(340.0, 34.0)
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_gate_label = Label.new()
	_gate_label.theme_type_variation = &"CaptionLabel"
	add_child(_gate_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.bunnyHop.hint")
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
	_ear = maxf(0.0, _ear - delta * 3.0)
	if not started:
		# Vorstart-Schweben: kein Scroll, keine Tore, keine Kollision.
		gooby_y = HOVER_Y + sin(elapsed * 3.0) * HOVER_AMP
		_update_labels()
		queue_redraw()
		return
	var speed := BunnyHopLogic.speed_at_gate(gates, tune)
	scroll += speed * delta
	var physics := BunnyHopLogic.step_physics({"y": gooby_y, "vy": gooby_vy}, delta, tune)
	gooby_y = float(physics["y"])
	gooby_vy = float(physics["vy"])
	_gust_tick()
	_pillar_tick()
	_coin_tick()
	if _crashed():
		_crash()
		return
	_update_labels()
	queue_redraw()


## Der eine Windschubs pro Zyklus — exakt beim Übergang in die Böe.
func _gust_tick() -> void:
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) != "gust" or int(phase["index"]) == last_gust_index:
		return
	last_gust_index = int(phase["index"])
	gooby_y = BunnyHopLogic.apply_gust_shift(gooby_y, int(phase["direction"]), tune)
	AudioDirector.try_play(self, "mg_spill", 1.2)
	if ctx.juice != null:
		ctx.juice.shake(0.25)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 110.0, view_size.y * 0.22),
			I18nService.t("mg.bunnyHop.gust"),
			AcTokens.TEAL_DARK
		)


func _pillar_tick() -> void:
	var gooby_x := _gooby_world_x()
	for pillar in pillars:
		if bool(pillar["passed"]) or float(pillar["x"]) - scroll > gooby_x:
			continue
		pillar["passed"] = true
		gates += 1
		var gusting := str(BunnyHopLogic.gust_phase_at(elapsed, tune)["phase"]) == "gust"
		var points := BunnyHopLogic.gate_points(gusting)
		score += points
		AudioDirector.try_play(self, "mg_good", 1.0 + 0.01 * minf(gates, 20.0))
		if ctx.juice != null:
			ctx.juice.float_text(
				Vector2(view_size.x * GOOBY_X_FRAC + 40.0, _to_screen_y(gooby_y) - 40.0),
				"+%d" % points,
				AcTokens.GOLD if gusting else AcTokens.LEAF_DARK
			)
			if gusting:
				ctx.juice.bloom_pulse(0.5)
		if BunnyHopLogic.gap_narrows_at_gate(gates, tune):
			AudioDirector.try_play(self, "mg_combo")
			if ctx.juice != null:
				ctx.juice.float_text(
					Vector2(view_size.x * 0.5 - 70.0, view_size.y * 0.3),
					I18nService.t("mg.bunnyHop.narrow"),
					AcTokens.PINK
				)
		ctx.report_score(BunnyHopLogic.final_hop_score(score, tune), points)
	# Passierte Säulen entsorgen und Nachschub setzen.
	var kept: Array[Dictionary] = []
	for pillar in pillars:
		if float(pillar["x"]) - scroll > -2.0:
			kept.append(pillar)
	pillars = kept
	_spawn_due_pillars()


## Web-Parität: die nächste Säule wird erst geboren, wenn ihr Slot in den
## Rand-Streifen rechts vom Bild rutscht — nie ein Vorrat auf Halde.
func _spawn_due_pillars() -> void:
	var edge := _view_width_world() + SPAWN_MARGIN
	if not is_finite(next_pillar_x):
		next_pillar_x = edge
	while next_pillar_x - scroll < edge:
		_spawn_pillar()


func _spawn_pillar() -> void:
	var gap := BunnyHopLogic.gap_at_gate(gates, tune)
	var center := BunnyHopLogic.roll_gap_center(rng, gap, last_gap_center, tune)
	last_gap_center = center
	var at_x := next_pillar_x
	next_pillar_x += float(tune["PILLAR_SPACING_X"])
	pillars.append({"x": at_x, "gapCenterY": center, "gapHeight": gap, "passed": false})
	if BunnyHopLogic.coin_spawns(rng.next(), tune):
		coins.append({"x": at_x, "y": center, "taken": false})


func _coin_tick() -> void:
	var gooby_x := _gooby_world_x()
	var kept: Array[Dictionary] = []
	for coin in coins:
		var cx := float(coin["x"]) - scroll
		if cx < -2.0:
			continue
		if not bool(coin["taken"]) and absf(cx - gooby_x) < 0.42:
			if absf(float(coin["y"]) - gooby_y) < 0.5:
				coin["taken"] = true
				score += 1
				AudioDirector.try_play(self, "gvz_collect")
				if ctx.juice != null:
					ctx.juice.float_text(
						Vector2(_to_screen_x(cx), _to_screen_y(float(coin["y"]))),
						"+1",
						AcTokens.GOLD
					)
				ctx.report_score(BunnyHopLogic.final_hop_score(score, tune), 1)
				continue
		kept.append(coin)
	coins = kept


func _crashed() -> bool:
	var gooby_x := _gooby_world_x()
	for pillar in pillars:
		var local := {
			"x": float(pillar["x"]) - scroll,
			"gapCenterY": pillar["gapCenterY"],
			"gapHeight": pillar["gapHeight"]
		}
		if BunnyHopLogic.collides({"x": gooby_x, "y": gooby_y}, local, tune):
			return true
	return false


func _crash() -> void:
	AudioDirector.try_play(self, "mg_lose")
	if ctx.juice != null:
		ctx.juice.shake(0.6)
		ctx.juice.hit_freeze(120)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 40.0, view_size.y * 0.4),
			I18nService.t("mg.bunnyHop.crash"),
			AcTokens.DANGER
		)
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	started = true
	gooby_vy = float(tune["HOP_VY"])
	_ear = 1.0
	AudioDirector.try_play(self, "gvz_pop", 1.1)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": BunnyHopLogic.final_hop_score(score, tune), "gates": gates})


func _update_labels() -> void:
	_time_label.text = I18nService.t("mg.bunnyHop.gates", {"n": gates})
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) == "telegraph":
		_gate_label.text = I18nService.t("mg.bunnyHop.gust_warn")
	elif str(phase["phase"]) == "gust":
		_gate_label.text = I18nService.t("mg.bunnyHop.gust")
	else:
		_gate_label.text = ""


func _ppu() -> float:
	return view_size.y / (WORLD_HALF_H * 2.0 + 0.6)


## Sichtbare Weltbreite in Welteinheiten (x=0 ist der linke Bildrand).
func _view_width_world() -> float:
	return view_size.x / _ppu()


func _gooby_world_x() -> float:
	return view_size.x * GOOBY_X_FRAC / _ppu()


func _to_screen_x(world_x: float) -> float:
	return world_x * _ppu()


func _to_screen_y(world_y: float) -> float:
	return view_size.y * 0.5 - world_y * _ppu()


func _draw() -> void:
	_draw_sky()
	for pillar in pillars:
		_draw_pillar(pillar)
	for coin in coins:
		_draw_coin(coin)
	_draw_gooby()
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) != "none":
		_draw_wind(str(phase["phase"]), int(phase["direction"]))


func _draw_sky() -> void:
	var floor_y := _to_screen_y(float(tune["FLOOR_Y"]))
	# Himmel als Verlauf in schmalen Bändern — oben kühler, am Horizont heller.
	var bands := 14
	for i in bands:
		var t := float(i) / float(bands - 1)
		var band := Color("A9D9F0").lerp(Color("E7F5FB"), t)
		draw_rect(
			Rect2(
				0.0, floor_y * float(i) / float(bands), view_size.x, floor_y / float(bands) + 1.0
			),
			band
		)
	_draw_sun()
	for cloud in _clouds:
		_draw_cloud(cloud, floor_y)
	# Parallax-Hügel: zwei Ketten, die AUF dem Horizont sitzen statt ihn zu
	# überdecken — sonst frisst der Hügelrücken die halbe Spielfläche.
	for layer in 2:
		var speed := 0.14 + layer * 0.2
		var step := 260.0 - layer * 70.0
		var radius := 108.0 - layer * 30.0
		var crest := floor_y - (58.0 - layer * 22.0)
		var tint := Color("8FC98A") if layer == 0 else Color("A8D89C")
		var offset := fmod(scroll * speed * _ppu(), step)
		var count := int(view_size.x / step) + 3
		for i in count:
			draw_circle(Vector2(-offset + i * step - step, crest + radius), radius, tint)
	draw_rect(Rect2(0.0, floor_y, view_size.x, view_size.y - floor_y), Color("8FD06C"))
	draw_rect(Rect2(0.0, floor_y, view_size.x, 10.0), Color("6DB54E"))
	draw_line(Vector2(0.0, floor_y), Vector2(view_size.x, floor_y), AcTokens.INK, 3.0)
	_draw_grass_tufts(floor_y)


func _draw_sun() -> void:
	var at := Vector2(view_size.x * 0.84, view_size.y * 0.12)
	for i in 8:
		var a := float(i) / 8.0 * TAU + _pulse * 0.25
		draw_line(
			at + Vector2.RIGHT.rotated(a) * 46.0,
			at + Vector2.RIGHT.rotated(a) * 62.0,
			Color(1.0, 0.85, 0.44, 0.65),
			5.0
		)
	draw_circle(at, 38.0, Color("FFE49A"))
	draw_circle(at, 30.0, Color("FFD166"))


func _draw_cloud(cloud: Vector3, floor_y: float) -> void:
	var drift := fmod(cloud.x - scroll * 0.05, 1.2)
	if drift < -0.2:
		drift += 1.2
	var at := Vector2(drift * view_size.x, floor_y * cloud.y)
	var r := 26.0 * cloud.z
	var tint := Color(1.0, 1.0, 1.0, 0.85)
	draw_circle(at, r, tint)
	draw_circle(at + Vector2(r * 0.85, r * 0.18), r * 0.78, tint)
	draw_circle(at + Vector2(-r * 0.85, r * 0.22), r * 0.66, tint)


func _draw_grass_tufts(floor_y: float) -> void:
	var step := 46.0
	var offset := fmod(scroll * _ppu(), step)
	var count := int(view_size.x / step) + 2
	for i in count:
		var x := -offset + i * step
		draw_line(Vector2(x, floor_y + 4.0), Vector2(x - 5.0, floor_y - 11.0), Color("5FA344"), 3.0)
		draw_line(
			Vector2(x + 7.0, floor_y + 4.0), Vector2(x + 11.0, floor_y - 9.0), Color("5FA344"), 3.0
		)


## Säule = Heckenpfosten mit Blätterkrone an der Lücke (Web: Zaun + Baumkrone).
func _draw_pillar(pillar: Dictionary) -> void:
	var x := _to_screen_x(float(pillar["x"]) - scroll)
	var half := float(tune["PILLAR_HALF_W"]) * _ppu()
	var gap_top := _to_screen_y(float(pillar["gapCenterY"]) + float(pillar["gapHeight"]) * 0.5)
	var gap_bottom := _to_screen_y(float(pillar["gapCenterY"]) - float(pillar["gapHeight"]) * 0.5)
	var ground := _to_screen_y(float(tune["FLOOR_Y"]))
	var passed := bool(pillar["passed"])
	var body := Color("7FB964") if not passed else Color("A9C79B")
	var slat := Color("6AA351") if not passed else Color("98B78B")
	var columns: Array[Rect2] = [
		Rect2(x - half, -12.0, half * 2.0, gap_top + 12.0),
		Rect2(x - half, gap_bottom, half * 2.0, ground - gap_bottom),
	]
	for rect in columns:
		if rect.size.y <= 0.0:
			continue
		draw_rect(rect, body)
		# Lattenstruktur, damit die Säule nicht als Farbklotz liest.
		var y := rect.position.y + 18.0
		while y < rect.position.y + rect.size.y - 6.0:
			draw_line(Vector2(rect.position.x + 4.0, y), Vector2(rect.end.x - 4.0, y), slat, 2.0)
			y += 26.0
		draw_rect(rect, AcTokens.INK, false, 3.0)
	# Blätterkronen kappen die Lücke, ohne in die Öffnung zu ragen.
	_draw_crown(Vector2(x, gap_top - 4.0), half, passed)
	_draw_crown(Vector2(x, gap_bottom + 4.0), half, passed)


func _draw_crown(at: Vector2, half: float, passed: bool) -> void:
	var leaf := Color("6DB54E") if not passed else Color("9EC090")
	var spots: Array[Vector2] = [
		Vector2(-half * 0.7, 0.0), Vector2(half * 0.7, 0.0), Vector2(0.0, 0.0)
	]
	for spot in spots:
		draw_circle(at + spot, half * 0.82, leaf)
	for spot in spots:
		draw_arc(at + spot, half * 0.82, 0.0, TAU, 18, AcTokens.INK, 2.5)


func _draw_coin(coin: Dictionary) -> void:
	var pos := Vector2(_to_screen_x(float(coin["x"]) - scroll), _to_screen_y(float(coin["y"])))
	var wobble := sin(_pulse * float(BunnyHopLogic.HOP_JUICE["COIN_WOBBLE_HZ"]) * TAU) * 0.4 + 0.6
	draw_circle(pos, 13.0, AcTokens.GOLD)
	draw_arc(pos, 13.0, 0.0, TAU, 18, AcTokens.INK, 2.5)
	draw_line(
		pos + Vector2(0.0, -7.0 * wobble), pos + Vector2(0.0, 7.0 * wobble), Color("C9932E"), 3.0
	)


func _draw_gooby() -> void:
	var pos := Vector2(view_size.x * GOOBY_X_FRAC, _to_screen_y(gooby_y))
	var r := float(tune["BODY_HALF_H"]) * _ppu()
	var tilt := clampf(gooby_vy * 0.1, -0.5, 0.5)
	# Bodenschatten verankert den Hüpfer über dem Rasen.
	var ground := _to_screen_y(float(tune["FLOOR_Y"]))
	var shrink := clampf(1.0 - (ground - pos.y) / (view_size.y * 0.7), 0.3, 1.0)
	draw_set_transform(Vector2(pos.x, ground - 4.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, r * 0.85 * shrink, Color(0.29, 0.23, 0.21, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fur := Color("FFE9BE")
	var fur_dark := Color("F3D49B")
	# Ohren sitzen AM Kopf und legen sich beim Hüpfer nach hinten.
	var lay := -tilt * 0.5 - _ear * 0.35
	for side in [-1.0, 1.0]:
		var root := pos + Vector2(side * r * 0.42, -r * 0.78)
		var tip := root + Vector2(side * r * 0.5 + lay * r * 1.1, -r * 0.95)
		draw_line(root, tip, fur, r * 0.34)
		draw_circle(tip, r * 0.17, fur)
	# Hinterläufe + Puschelschwanz, damit Gooby nicht nur ein Kopf ist.
	draw_circle(pos + Vector2(-r * 0.72, r * 0.52), r * 0.34, fur_dark)
	draw_circle(pos + Vector2(r * 0.3, r * 0.78), r * 0.3, fur_dark)
	draw_circle(pos, r, fur)
	draw_arc(pos, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_circle(pos + Vector2(r * 0.1, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(pos + Vector2(r * 0.5, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(pos + Vector2(r * 0.3, r * 0.04), r * 0.08, AcTokens.PINK)
	draw_arc(pos + Vector2(r * 0.28, r * 0.2), r * 0.28, 0.3, PI - 0.3, 10, AcTokens.INK, 2.4)
	draw_circle(pos + Vector2(-r * 0.55, r * 0.3), r * 0.2, Color(1.0, 0.72, 0.74, 0.55))


func _draw_wind(phase: String, direction: int) -> void:
	var alpha := 0.3 if phase == "telegraph" else 0.55
	var tint := AcTokens.YELLOW if phase == "telegraph" else AcTokens.TEAL
	for i in 6:
		var y := view_size.y * (0.14 + i * 0.13)
		var wobble := sin(_pulse * 6.0 + i) * 16.0
		var length := 60.0 + wobble
		var from := Vector2(view_size.x * 0.62, y)
		draw_line(
			from,
			from + Vector2(length, -18.0 * direction),
			Color(tint.r, tint.g, tint.b, alpha),
			5.0
		)
