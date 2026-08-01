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
##
## W17/G5-Politur (NUR Präsentation, Paket P29): Intro-Beat 1,5 s mit
## See-Totale (establish, Sim + Eingabe gegated, RNG-Strom unangetastet),
## Böen-WINDLAYER aus einem vorhandenen Ambience-SFX (leise beim Telegraph,
## stark beim Blasen — cityDrive-Muster), Sieg-Feier mit Banner + Konfetti
## (RM-gegated), Hint-Fade nach ~6 s, Banner/Böentext auf Plate bzw. mit
## Kontur und `_ui`-skaliert (M9-Rest), Q2-Gate am Stage-Burst.

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
## W17/G5 M1: Intro-Beat (s) — See-Totale via establish, die Sim wartet.
const INTRO_S := 1.5
## Böen-Windlayer: vorhandenes Ambience-SFX (kein neues File) — leise beim
## Telegraph, stark beim Blasen. Nur Ton, Reduced Motion bleibt unberührt.
const WIND_SFX_ID := "ranch_ambience_wind"
## Banner-Tinte/-Kontur auf der Milchglas-Plate (M7).
const INK := Color(0.32, 0.24, 0.28)
const RIM := Color(1.0, 0.99, 0.94, 0.85)

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
## W17/G5: Intro-Restzeit (M1) und Schau-Uhr — die Bühne atmet auch im
## Beat weiter, die Sim-Uhr `elapsed` nicht.
var _intro_left := 0.0
var _show_time := 0.0
## Böen-Windlayer (eigener Player: AudioDirector-Loops können keinen
## Live-Pitch) + weicher Mix-Verlauf 0..1.
var _wind: AudioStreamPlayer
var _wind_mix := 0.0
var _banner_plate := StyleBoxFlat.new()


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
	_build_wind()
	_fill_rings()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)
	# W17/G5 M1: Intro-Beat — Sim-Uhr und Eingabe warten, der RNG-Strom
	# bleibt unangetastet (die Ringe sind längst gewürfelt, _fill_rings
	# zieht erst NACH dem Beat weiter, wenn travel wieder steigt).
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.lanternFloat.intro"), INTRO_S + 0.7)


func end() -> void:
	super.end()
	finished = true
	if _wind != null:
		_wind.stop()


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
	_show_time += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	# W17/G5 M1: Intro-Beat — die Kamera hebt aus der See-Totale in die
	# Spielpose, die Bühne atmet auf der Schau-Uhr; elapsed/travel warten,
	# der Lauf bleibt zahlengleich (Crosscheck-Vertrag unberührt).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_stage.sync(_rings, travel, lantern_x, invuln, _show_time, delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	invuln = maxf(0.0, invuln - delta)
	_sync_wind(delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	travel += float(tune["RISE_SPEED"]) * delta
	_steer(delta)
	_fill_rings()
	_check_pass()
	_stage.sync(_rings, travel, lantern_x, invuln, _show_time, delta)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0:
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


## Böen-Windlayer aus einem VORHANDENEN Ambience-SFX (cityDrive-Muster,
## kein neues File): eigener Player, weil AudioDirector-Loops keinen
## Live-Pitch können — Lautstärke/Pitch folgen in _sync_wind der Böenphase.
## Bus "Sfx" ⇒ Nutzer-Regler und Limiter gelten; headless bleibt er still.
func _build_wind() -> void:
	var path := SfxMap.path(WIND_SFX_ID)
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = (load(path) as AudioStream).duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_wind = AudioStreamPlayer.new()
	_wind.bus = &"Sfx"
	_wind.stream = stream
	_wind.volume_db = -60.0
	add_child(_wind)


## Der Wind ist jetzt HÖRBAR angekündigt (Audit §6: Telegraph war stumm):
## leise beim Telegraph, kräftig beim Blasen, danach klingt er weich aus.
## Reiner Ton — Reduced Motion bleibt unberührt (nur Bewegung ist gegated).
func _sync_wind(delta: float) -> void:
	if _wind == null:
		return
	_wind.stream_paused = not is_active() or finished
	if not _wind.playing and not _wind.stream_paused:
		_wind.play()
	var target := 0.0
	match str(Logic.gust_phase_at(elapsed, tune)["phase"]):
		"telegraph":
			target = 0.45
		"push":
			target = 1.0
	_wind_mix = lerpf(_wind_mix, target, minf(1.0, 6.0 * delta))
	_wind.volume_db = lerpf(-44.0, -10.0, _wind_mix)
	_wind.pitch_scale = 0.9 + 0.35 * _wind_mix


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
	_stage.award_fx(wx, wy - travel, gold, _reduced_motion())
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
	if _wind != null:
		_wind.stop()
	# W17/G5 M8: die durchgestandene Fahrt endete vorher STUMM (Audit §6
	# „Sieg ohne Feier“) — jetzt Endton, Sieg-Band und Feier am Körbchen.
	AudioDirector.try_play(self, end_sfx_for(bool(tune["ENDLESS"]), score))
	if not bool(tune["ENDLESS"]) and score > 0:
		_set_banner(I18nService.t("mg.lanternFloat.win", {"hits": hits}), 2.2)
		_stage.celebrate(_reduced_motion())
		if ctx.juice != null:
			ctx.juice.win_moment()
	queue_redraw()
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


## Endton-Wahl (PUR für Tests, M8): die Endlos-Fahrt endet immer über den
## dritten Rempler (mg_lose), die Zeitfahrt feiert jeden gepunkteten Lauf.
static func end_sfx_for(endless: bool, score_now: int) -> String:
	return "mg_lose" if endless or score_now <= 0 else "mg_win"


func _set_banner(text: String, seconds := 1.3) -> void:
	_banner = text
	_banner_t = seconds


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.lanternFloat.bump_count", {"n": bumps, "max": int(tune["ENDLESS_MAX_BUMPS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t("mg.lanternFloat.stats", {"hits": hits, "gold": golds})
	_hint_label.modulate.a = _hint_alpha()


## W17/G5 M6: der Hinweis blendet ~5 s nach dem Beat aus — die Nacht gehört
## dann ganz der Bühne (`elapsed` startet erst NACH dem Intro).
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 5.0) / 1.5, 0.0, 1.0)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


## Nur noch HUD-Overlay: der Böen-Telegraf ist eine WARNUNG, keine Kulisse,
## und muss in jeder Kameralage sofort lesbar sein — das Banner ebenso.
func _draw() -> void:
	_draw_gust()
	_draw_banner()


## W17/G5 M9: Böentext skaliert mit `_ui` und bekommt eine dunkle Kontur —
## hell auf hellem Mondhimmel war die Warnung sonst flau.
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
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.8, 0.92, 1.0, alpha * 0.5), 3.0 * _ui)
	if phase == "telegraph":
		var font := ThemeService.font(800)
		var w := 320.0 * _ui
		var fs := int(26.0 * _ui)
		var at := Vector2((vp.x - w) * 0.5, vp.y * 0.2)
		var text := I18nService.t("mg.lanternFloat.gust")
		draw_string_outline(
			font,
			at,
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			w,
			fs,
			int(5.0 * _ui),
			Color(0.07, 0.08, 0.2, 0.85)
		)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.85, 0.95, 1.0))


## W17/G5 M7/M9: Banner mittig auf Milchglas-Plate mit Kontur statt nacktem
## Schriftzug — lange Übersetzungen brechen um (carrot_catch-Muster).
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var fs := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text := font.get_multiline_string_size(_banner, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	var top := vp.y * 0.34
	var pad := Vector2(18.0, 10.0) * _ui
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	draw_style_box(
		_banner_plate, Rect2(Vector2((vp.x - text.x) * 0.5, top) - pad, text + pad * 2.0)
	)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(fs))
	draw_multiline_string_outline(
		font,
		at,
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		fs,
		-1,
		int(5.0 * _ui),
		Color(RIM, RIM.a * alpha)
	)
	draw_multiline_string(
		font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, Color(INK, alpha)
	)
