extends MinigameBase
## Sternenlaterne (lanternFloat) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## LanternFloatLogic (zahlengleich zum Web): Auto-Steigen, Ziehen steuert
## seitlich, Sternenring +2 (jeder 5. golden +5), Glühwürmchen +1, Windböen
## schieben, Wolkenrempler −3 (Endlos: 3 Rempler beenden). 60 s.
##
## ECHTER 3D-NACHTHIMMEL (FB-4, LanternFloatStage3D): eine glühende
## Papierlaterne trägt Gooby (echtes Rig) im Körbchen durch Torus-Ringe,
## Glühwürmchen und 3D-Wolken; drei Sternschichten parallaxieren, der Mond
## glüht hinten. Die Kamera rahmt die Flugebene EXAKT wie die 2D-Projektion
## (set_half_height) — jede Weltmeter-Zahl bleibt erhalten. Nur der
## Böen-Telegraf und das Banner bleiben als 2D-Overlay obenauf.

const Logic := preload("res://scripts/minigames/games/lantern_float/lantern_float_logic.gd")
const Stage := preload("res://scripts/minigames/games/lantern_float/lantern_float_stage3d.gd")

## Sichtbare Welt-Halbhöhe über/unter der Laternenebene.
const HALF_H := 5.4
## Vorlauf, ab dem ein Ring erzeugt wird (Weltmeter über der Laterne).
const SPAWN_LEAD := 11.0
## Wie schnell die Laterne dem Ziehziel folgt (1/s).
const STEER_LERP := 6.5
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Bedienleiste auf Nachthimmel: helle Schrift statt dunkler Tinte.
const HUD_INK := Color(0.96, 0.96, 1.0, 0.96)
const HUD_INK_SOFT := Color(0.84, 0.86, 0.98, 0.9)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var hits := 0
var golds := 0
var fireflies := 0
var bumps := 0
var rings_passed := 0
var elapsed := 0.0
var travel := 0.0
var lantern_x := 0.0
var steer_target := 0.0
var invuln := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

## Ring-Serie ohne Rempler/Fehlpass (nur Anzeige/Feel — Ton steigt mit).
var ring_streak := 0

var _rings: Array[Dictionary] = []
var _next_index := 0
var _next_y := 0.0
var _stage: Node3D
var _ui := 1.0
var _time_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.LANTERN, ctx.difficulty)
	rng = ctx.rng()
	_next_y = Logic.ring_spacing_at(0.0, tune)
	# RNG-Parität mit der 2D-Fassung: die 60 Sternen-Würfe (je 3 Züge) bleiben
	# im Seed-Strom, sonst verschieben sich alle späteren Ring-/Wolken-Würfe.
	for _i in 60 * 3:
		rng.next()
	_stage = Stage.new()
	_stage.name = "Nachthimmel3D"
	add_child(_stage)
	_stage.setup_stage(float(tune["RING_RADIUS"]), float(tune["CLOUD_HALF_W"]))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fill_rings()
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
		_stage.frame(view_size, _world_scale(), landscape)
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_ui = clampf(minf(vp.x, vp.y) / DESIGN_SHORT, 0.75, 3.0)
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_stat_label.position = Vector2(pad, 44.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(vp.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - 46.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	invuln = maxf(0.0, invuln - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	travel += float(tune["RISE_SPEED"]) * delta
	_steer(delta)
	_fill_rings()
	_check_pass()
	_stage.sync(_rings, travel, lantern_x, invuln, elapsed, delta)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch and event.pressed:
		steer_target = Logic.steer_target_from(_normalized_x(event.position.x), tune)
	elif event is InputEventScreenDrag:
		steer_target = Logic.steer_target_from(_normalized_x(event.position.x), tune)


func _world_scale() -> float:
	var half_w := float(tune["HALF_W"])
	return minf(view_size.x / (half_w * 2.2), view_size.y / (HALF_H * 1.6))


func _normalized_x(px: float) -> float:
	return clampf((px - view_size.x * 0.5) / (view_size.x * 0.5), -1.0, 1.0)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_color", HUD_INK)
	add_child(_time_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	_stat_label.add_theme_color_override("font_color", HUD_INK_SOFT)
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.lanternFloat.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_color_override("font_color", HUD_INK_SOFT)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _steer(delta: float) -> void:
	var phase_info := Logic.gust_phase_at(elapsed, tune)
	lantern_x = lerpf(lantern_x, steer_target, minf(1.0, STEER_LERP * delta))
	if str(phase_info["phase"]) == "push":
		var gust: Dictionary = phase_info["gust"]
		lantern_x += int(gust["dir"]) * float(tune["GUST_FORCE"]) * delta
	lantern_x = Logic.clamp_lantern_x(lantern_x, tune)


## Ringe (samt Glühwürmchen- und Wolkenplatz) bis zum Sichtvorlauf auffüllen.
func _fill_rings() -> void:
	while _next_y < travel + SPAWN_LEAD:
		var ring := Logic.roll_ring(rng, _next_index, tune)
		ring["y"] = _next_y
		ring["done"] = false
		ring["firefly"] = rng.next() < float(tune["FIREFLY_CHANCE"])
		ring["firefly_x"] = (
			(rng.next() * 2.0 - 1.0) * (float(tune["HALF_W"]) - float(tune["RING_MARGIN"]))
		)
		ring["firefly_done"] = false
		var cloud := Logic.roll_cloud(rng, _next_index, tune)
		ring["cloud"] = cloud
		ring["cloud_done"] = false
		_rings.append(ring)
		_next_index += 1
		_next_y += Logic.ring_spacing_at(elapsed, tune)


func _check_pass() -> void:
	var keep: Array[Dictionary] = []
	for ring in _rings:
		var y := float(ring["y"])
		# Glühwürmchen sitzt auf halber Höhe VOR dem Ring.
		if not bool(ring["firefly_done"]) and bool(ring["firefly"]) and travel >= y - 1.6:
			ring["firefly_done"] = true
			if absf(lantern_x - float(ring["firefly_x"])) <= float(tune["FIREFLY_RADIUS"]):
				_award(int(tune["FIREFLY_PTS"]), float(ring["firefly_x"]), y - 1.6, false)
				fireflies += 1
		var cloud: Dictionary = ring["cloud"]
		if not bool(ring["cloud_done"]) and bool(cloud["present"]) and travel >= y - 0.8:
			ring["cloud_done"] = true
			if Logic.cloud_hit(lantern_x, cloud, tune) and invuln <= 0.0:
				_bump()
		if not bool(ring["done"]) and travel >= y:
			ring["done"] = true
			rings_passed += 1
			if Logic.ring_hit(lantern_x, ring, tune):
				hits += 1
				if bool(ring["gold"]):
					golds += 1
				_award(int(ring["points"]), float(ring["x"]), y, bool(ring["gold"]))
			else:
				# Ring verpasst: Serie endet leise (kein Malus — nur Feedback).
				ring_streak = 0
				if ctx.juice != null:
					ctx.juice.show_combo(0)
		if y > travel - 3.0:
			keep.append(ring)
	_rings = keep


func _award(points: int, wx: float, wy: float, gold: bool) -> void:
	var prev := score
	score = Logic.apply_score(score, points)
	ctx.report_score(score, score - prev)
	ring_streak += 1
	# Serie klettert hörbar: +1 Halbton pro Ring in Folge.
	AudioDirector.try_play(
		self, "mg_golden" if gold else "mg_good", FeelSfx.combo_pitch(ring_streak)
	)
	_stage.award_fx(wx, wy - travel, gold)
	if ctx.juice != null:
		var pos: Vector2 = _stage.to_screen(wx, wy - travel)
		var color := Color(1.0, 0.82, 0.35) if gold else Color(0.72, 0.92, 1.0)
		ctx.juice.float_text(pos, "+%d" % points, color)
		ctx.juice.ring_burst(self, pos, color, 90.0 if gold else 64.0)
		ctx.juice.burst(self, pos, color, 18 if gold else 10)
		if ring_streak >= 3:
			ctx.juice.show_combo(ring_streak)
		if gold:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.hit_freeze(45)
		else:
			ctx.juice.bloom_pulse(0.35)


func _bump() -> void:
	bumps += 1
	ring_streak = 0
	invuln = float(tune["BUMP_INVULN_SEC"])
	AudioDirector.try_play(self, "mg_spill")
	_stage.bump_fx()
	if ctx.juice != null:
		ctx.juice.shake(0.35)
		ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
	if bool(tune["ENDLESS"]):
		_set_banner(
			I18nService.t(
				"mg.lanternFloat.bump_count", {"n": bumps, "max": int(tune["ENDLESS_MAX_BUMPS"])}
			)
		)
		if Logic.endless_should_end(bumps, tune):
			_finish()
		return
	var prev := score
	score = Logic.apply_score(score, -int(tune["BUMP_PENALTY"]))
	ctx.report_score(score, score - prev)
	_set_banner(I18nService.t("mg.lanternFloat.bump", {"n": int(tune["BUMP_PENALTY"])}))


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	(
		ctx
		. report_end(
			{
				"score": score,
				"rings": rings_passed,
				"hits": hits,
				"golds": golds,
				"fireflies": fireflies,
				"bumps": bumps,
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.3


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.lanternFloat.bump_count", {"n": bumps, "max": int(tune["ENDLESS_MAX_BUMPS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t("mg.lanternFloat.stats", {"hits": hits, "gold": golds})


## Nur noch HUD-Overlay: der Böen-Telegraf ist eine WARNUNG, keine Kulisse,
## und muss in jeder Kameralage sofort lesbar sein — das Banner ebenso.
func _draw() -> void:
	_draw_gust()
	_draw_banner()


func _draw_gust() -> void:
	var info := Logic.gust_phase_at(elapsed, tune)
	var phase := str(info["phase"])
	if phase == "idle":
		return
	var vp := get_viewport_rect().size
	var gust: Dictionary = info["gust"]
	var dir := int(gust["dir"])
	var alpha := 0.35 if phase == "telegraph" else 0.75
	for i in 7:
		var y := vp.y * (0.12 + 0.11 * i)
		var x0 := vp.x * (0.1 if dir > 0 else 0.9)
		var x1 := x0 + dir * vp.x * 0.22 * (0.6 + 0.4 * sin(elapsed * 6.0 + i))
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.8, 0.92, 1.0, alpha * 0.5), 3.0)
	if phase == "telegraph":
		var font := ThemeService.font(800)
		draw_string(
			font,
			Vector2(vp.x * 0.5 - 160.0, vp.y * 0.2),
			I18nService.t("mg.lanternFloat.gust"),
			HORIZONTAL_ALIGNMENT_CENTER,
			320.0,
			26,
			Color(0.85, 0.95, 1.0, 0.9)
		)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	draw_string(
		font,
		Vector2(vp.x * 0.5 - 180.0, vp.y * 0.38),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		360.0,
		30,
		Color(1.0, 0.86, 0.7, alpha)
	)
