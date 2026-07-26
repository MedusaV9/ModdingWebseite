extends MinigameBase
## Hasenhüpfer (bunnyHop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus BunnyHopLogic
## (zahlengleich zum Web, Bot-zertifiziert): Tippen = Hüpfen, Score = passierte
## Tore, Tempo +2 % je Tor, verzeihende Hitbox (70 % der Optik), die Lücke wird
## alle 10 Tore enger. Ab Sekunde 6 kommt Wind: erst Telegraf, dann ein
## 0,4-Bahnen-Schubs — währenddessen zählen Tore doppelt. Eine Berührung
## beendet den Lauf (in JEDEM Modus, wie im Web).
##
## ECHTE 3D-HECKENLANDSCHAFT (FB-4, BunnyHopStage3D): Gooby flattert als
## echtes Rig durch 3D-Heckensäulen mit Blätterkronen, dahinter Parallax-Hügel
## und Wolken. Die Kamera rahmt die Spielebene EXAKT wie die 2D-Rechnung
## (set_half_height), Spawn/Kollision bleiben zahlengleich. Nur der
## Wind-Telegraf bleibt als 2D-Overlay. Die 3D-Welt hängt unter der
## Node2D-Wurzel, der MinigameBase-Vertrag bleibt unberührt.

const Stage := preload("res://scripts/minigames/games/bunny_hop/bunny_hop_stage3d.gd")

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
var _stage: Node3D
var _pulse := 0.0
var _ear := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BunnyHopLogic.apply_difficulty(BunnyHopLogic.HOP, ctx.difficulty)
	rng = ctx.rng()
	gooby_y = HOVER_Y
	gooby_vy = 0.0
	# RNG-Parität mit der 2D-Fassung: die vier Wolken-Würfe (je 3 Züge) bleiben
	# im Seed-Strom, sonst verschieben sich alle späteren Lücken-Zentren.
	for _i in 4 * 3:
		rng.next()
	_stage = Stage.new()
	_stage.name = "Hecke3D"
	add_child(_stage)
	_stage.setup_stage(float(tune["FLOOR_Y"]))
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
		_sync_stage(delta)
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
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


func _sync_stage(delta: float) -> void:
	_stage.sync(
		pillars,
		coins,
		_gooby_world_x(),
		gooby_y,
		gooby_vy,
		scroll,
		float(tune["PILLAR_HALF_W"]),
		0.04,
		_pulse,
		delta
	)


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
				_stage.gooby_screen() + Vector2(40.0, 0.0),
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
				_stage.coin_fx(cx, float(coin["y"]))
				if ctx.juice != null:
					ctx.juice.float_text(
						_stage.gooby_screen() + Vector2(30.0, -30.0), "+1", AcTokens.GOLD
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
	_stage.crash_fx()
	_sync_stage(0.0)
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
	_stage.hop_fx()
	AudioDirector.try_play(self, "gvz_pop", 1.1)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": BunnyHopLogic.final_hop_score(score, tune), "gates": gates})


func _update_labels() -> void:
	if _time_label == null:
		return
	# HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
	# Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0)
	_gate_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 170.0, vp.y - 42.0)
	_hint_label.size = Vector2(340.0, 34.0)
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


## Nur noch HUD-Overlay: der Wind-Telegraf bleibt 2D — er ist eine WARNUNG,
## keine Kulisse, und muss in jeder Kameralage sofort lesbar sein.
func _draw() -> void:
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) != "none":
		_draw_wind(str(phase["phase"]), int(phase["direction"]))


func _draw_wind(phase: String, direction: int) -> void:
	var vp := get_viewport_rect().size
	var alpha := 0.3 if phase == "telegraph" else 0.55
	var tint := AcTokens.YELLOW if phase == "telegraph" else AcTokens.TEAL
	for i in 6:
		var y := vp.y * (0.14 + i * 0.13)
		var wobble := sin(_pulse * 6.0 + i) * 16.0
		var length := 60.0 + wobble
		var from := Vector2(vp.x * 0.62, y)
		draw_line(
			from,
			from + Vector2(length, -18.0 * direction),
			Color(tint.r, tint.g, tint.b, alpha),
			5.0
		)
