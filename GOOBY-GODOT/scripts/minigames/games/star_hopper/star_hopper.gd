extends MinigameBase
## Sternenhüpfer (starHopper) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## StarHopperLogic/StarHopperBot (zahlengleich zum Web): 3 Bahnen, Tempo +5 %
## alle 10 s, Meteore mit 70-%-Hitbox, Sterne +3 / goldene Karotten +10,
## Schild ab Score 60, angekündigte Meteorschauer, Wurmloch-Tor, ein Treffer
## beendet die Runde. Score = Meter/10 + Aufsammler.
##
## ECHTE 3D-BÜHNE (StarHopperStage): Gooby sitzt als Pilot auf einem Kenney-
## Speeder, der Blick läuft den drei Bahnen entlang nach vorn, Meteore sind
## Space-Kit-Felsen, dahinter zieht ein Sternenfeld mit Parallaxe vorbei.
## Der MinigameBase-Vertrag bleibt: Node2D-Wurzel, 3D-Welt als Kind, HUD in 2D.

const Logic := preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd")
const Bot := preload("res://scripts/minigames/games/star_hopper/star_hopper_bot.gd")
const Stage := preload("res://scripts/minigames/games/star_hopper/star_hopper_stage.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const HintFeel := preload("res://scripts/minigames/hint_feel.gd")

## Sichtbare Strecke oberhalb des Schiffs (m) — das ist die Vorwarnzeit.
const VIEW_AHEAD_M := 62.0
## Bildschirmanteil (von unten), auf dem das Schiff sitzt.
const SHIP_ANCHOR := 0.22
## Mindest-Wischweg (px) für einen Zwei-Bahn-Wechsel.
const SWIPE_MIN_PX := 40.0
## W14 Forgiveness: auf breiten Screens skaliert der Wischweg mit (8 % Breite),
## sonst werden unruhige Tipper zu ungewollten Zwei-Bahn-Sprüngen.
const SWIPE_MIN_FRAC := 0.08
## W14 Intro-Beat (s): Kamera schwebt ein + Ziel-Einblendung, Sim wartet.
const INTRO_S := 1.5
## W16 M10: Tempo-Striche — [[Tempo m/s, Striche/s], …] (SpeedLines-Rampe).
const STREAK_RATE: Array = [[11.0, 0.0], [14.0, 4.0], [19.0, 11.0]]
## W16 Befund 6: Tick-Abstand (s) des Countdown-Sounds in der Schauer-Warnung.
const WARN_TICK_SEC := 0.33
## W21: nach so vielen Sim-Sekunden blendet der Steuer-Hinweis aus
## (M6-Kanon, deliveryRush-Muster — vorher stand er die ganze Runde).
const HINT_FADE_SEC := 7.0

const STAR_COLOR := Color(1.0, 0.88, 0.4)
const GOLD_COLOR := Color(1.0, 0.62, 0.2)

var tune: Dictionary = {}
var rng: GoobyRng
var traveled := 0.0
var elapsed := 0.0
var lane := 1
var lane_visual := 1.0
var pickup_points := 0
var score := 0
var shielded := false
var shield_spawned := false
var invuln := 0.0
var wormhole_left := 0.0
var wormhole_spawned := false
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _stream: Callable
var _rows: Array[Dictionary] = []
var _meteors: Array[Dictionary] = []
var _pickups: Array[Dictionary] = []
var _next_row_m := 30.0
var _shower_at := 0.0
var _shower_lanes: Dictionary = {}
var _shower_state := "idle"
var _shower_left := 0.0
var _shower_drop := 0.0
var _stage: Node3D
var _pop := 0.0
var _roll := 0.0
var _touch_from := Vector2.ZERO
var _flash := 0.0
var _flash_text := ""
var _intro_left := 0.0
## Eigene große Aufsammel-Popups (Pos, Text, Farbe, Restzeit) — das kleine
## JuiceKit-float_text ging im Weltraum unter.
var _popups: Array[Dictionary] = []
var _ui := 1.0
var _streaks: MultiMeshInstance3D
var _speed_prev := -1.0
var _speed_steps := 0
var _warn_tick := 0.0
var _dist_label: Label
var _state_label: Label
var _hint_label: Label
## W21: Milchglas-Plate hinter dem Steuer-Hinweis (deliveryRush-Muster) —
## die nackte Lavendel-Schrift lag unlesbar über den hellblauen Bahnen.
var _hint_plate := StyleBoxFlat.new()
## W21/P5: Kit-Plates — Frost-Pille hinter Distanz/Status, Banner-Standard.
var _hud_plate := StyleBoxFlat.new()
var _banner_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.HOPPER, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
	_shower_at = float(tune["SHOWER_EVERY_SEC"])
	_build_stage()
	_build_streaks()
	_build_hud()
	_fit_viewport()
	_intro_left = INTRO_S
	_flash_text = I18nService.t("mg.starHopper.intro")
	_flash = INTRO_S + 0.6
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## 3D-Bühne unter die Node2D-Wurzel hängen (Godot rendert 3D hinter 2D).
func _build_stage() -> void:
	_stage = Stage.new()
	_stage.name = "Stage3D"
	add_child(_stage)
	_stage.setup_stage(tune["LANE_X"])
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.world_env


## W16 M10: Tempo-Striche an der Kamera (geteiltes SpeedLines-Kit, 1 Draw-
## Call) — city_drive/runner-Muster; Update läuft in _sync_tempo_feel.
func _build_streaks() -> void:
	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 18, Vector2(2.4, 3.5), Vector2(4.0, 9.0))
	_streaks.set("enabled", not _reduced_motion())


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = MgHudKit.ui_scale(view_size)
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
	_layout_hud()
	queue_redraw()


## W21/P5: Bedienleiste im Kit-Standard — Distanz/Status als Kit-Chip
## (Frost-Pille, EIN Raster über alle Spiele; vorher 34-px-Headline-Klotz),
## Hinweis mit Typo-MINIMUM (MgHudKit.font_px — nie unter 14 px effektiv).
func _layout_hud() -> void:
	if _dist_label == null:
		return
	var pad := 16.0 * _ui
	MgHudKit.style_chip(_dist_label, _state_label, _ui)
	MgHudKit.layout_chip(_dist_label, _state_label, _ui)
	var hint_w := minf(view_size.x - pad * 2.0, 360.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", MgHudKit.font_px(15.0, _ui))
	# W21 DR-1-Muster: `size` klemmt an der GECACHTEN Umbruch-Mindesthöhe
	# (erstes Layout: Breite ~0 → kilometerhoch, Text unsichtbar) —
	# clamp_size setzt Breite-zuerst + invalidiert den Cache.
	var hint_s := HintFeel.clamp_size(_hint_label, hint_w)
	_hint_label.position = Vector2(
		(view_size.x - hint_s.x) * 0.5, view_size.y - hint_s.y - 6.0 * _ui
	)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_stage.tick(delta)
	# Intro-Beat: Kamera schwebt in die Spielpose, Ziel steht — die Sim
	# (elapsed/traveled) wartet, der Lauf bleibt danach zahlengleich.
	if _intro_left > 0.0:
		_intro_left = maxf(_intro_left - delta, 0.0)
		_stage.establish(1.0 - _intro_left / INTRO_S)
		_flash = maxf(_flash - delta, 0.0)
		_sync_stage()
		queue_redraw()
		return
	elapsed += delta
	invuln = maxf(0.0, invuln - delta)
	_pop = maxf(0.0, _pop - delta)
	_roll = maxf(0.0, _roll - delta)
	_flash = maxf(0.0, _flash - delta)
	_step_popups(delta)
	lane_visual = move_toward(lane_visual, float(lane), delta / float(tune["LANE_CHANGE_SEC"]))
	var dm := Logic.speed_at(elapsed, tune) * delta
	_step_wormhole(delta)
	_advance(dm, delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_step_tempo()
	_sync_tempo_feel(delta)
	_sync_stage()
	_update_labels()
	queue_redraw()


## W16 Befund 2: Der Web-Kick „Tempo +5 % alle 10 s" wird ein sichtbarer
## MOMENT — Popup + Combo-Ton (Pitch steigt je Stufe) + kurzer Glow-Puls.
## Reine Präsentation: die Stufe wird aus Logic.speed_at ABGELESEN.
func _step_tempo() -> void:
	var v := Logic.speed_at(elapsed, tune)
	if _speed_prev < 0.0:
		_speed_prev = v
		return
	if v > _speed_prev + 0.0001:
		_speed_steps += 1
		_flash_text = I18nService.t("mg.starHopper.speed_up")
		_flash = 1.1
		_stage.pulse_glow(0.4)
		if ctx.juice != null:
			ctx.juice.combo_tone(_speed_steps)
	_speed_prev = v


## W16 M10 (Tempo-Gefühl): FOV-Kick Richtung Vmax + Tempo-Striche an der
## Kamera. Reduced Motion schaltet die Striche hart ab (SpeedLines-Regel).
func _sync_tempo_feel(delta: float) -> void:
	var v := Logic.speed_at(elapsed, tune)
	var base := float(tune["BASE_SPEED"])
	var vmax := float(tune["MAX_SPEED"])
	if not is_finite(vmax):
		vmax = float(Logic.HOPPER["MAX_SPEED"])
	var band := clampf((v - base) / maxf(0.001, vmax - base), 0.0, 1.0)
	_stage.set_speed_band(band)
	if _streaks == null:
		return
	_streaks.set("enabled", not _reduced_motion())
	_streaks.call("update", delta, v, SpeedLines.rate_at(v, STREAK_RATE))


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


## Die 3D-Bühne bekommt EINEN Zustandsschnappschuss — sie rechnet nur Optik.
func _sync_stage() -> void:
	(
		_stage
		. sync(
			{
				"traveled": traveled,
				"elapsed": elapsed,
				"lane": lane,
				"lane_visual": lane_visual,
				"speed": Logic.speed_at(elapsed, tune),
				"meteors": _meteors,
				"pickups": _pickups,
				"shielded": shielded,
				"invuln": invuln,
				"pop": _pop,
				"pop_max": float(Logic.HOPPER_JUICE["POP_SEC"]),
				"roll": _roll,
				"roll_max": float(Logic.HOPPER_JUICE["BARREL_ROLL_SEC"]),
				"wormhole_left": wormhole_left,
				"wormhole_max": float(tune["WORMHOLE_SEC"]),
				"shower_state": _shower_state,
				"shower_danger": _shower_lanes.get("danger", []),
			}
		)
	)
	_stage.feel(_mood())


## Gooby-Laune aus dem Spielzustand (Reihenfolge = Dringlichkeit).
func _mood() -> String:
	if finished:
		return "sad"
	if wormhole_left > 0.0 or _roll > 0.0:
		return "ecstatic"
	if invuln > 0.0:
		return "dizzy"
	if _shower_state == "warn":
		return "scared"
	if shielded:
		return "happy"
	return "neutral" if _pop <= 0.0 else "happy"


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_from = event.position
		else:
			_resolve_gesture(event.position)


## Aktueller Score inklusive Streckenpunkte.
func live_score() -> int:
	return Logic.hopper_score(traveled, pickup_points, tune)


func _build_hud() -> void:
	_dist_label = Label.new()
	_dist_label.theme_type_variation = &"HeadlineLabel"
	add_child(_dist_label)
	_state_label = Label.new()
	_state_label.theme_type_variation = &"CaptionLabel"
	add_child(_state_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.starHopper.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# W21/P5: Distanz/Status sitzen als Tinte auf der Kit-Frost-Pille —
	# die Weltraum-Sonderfarben (weiß/hellblau) sind damit Geschichte.
	# W21: Hinweis als Tinte auf Milchglas (deliveryRush.make_hint-Muster) —
	# Lavendel auf hellblauer Bahn war im Playtest w21_mg_star_hopper_quer
	# praktisch unsichtbar (Befund SH-1).
	_hint_label.add_theme_color_override("font_color", Color(0.42, 0.24, 0.16))
	_hint_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.75))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_plate.set_corner_radius_all(12)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Tippen = 1 Bahn, Wischen = 2 Bahnen (Web-Kontrakt).
func _resolve_gesture(to: Vector2) -> void:
	var d := to - _touch_from
	var gesture := {}
	if absf(d.x) >= swipe_threshold_px(view_size.x):
		gesture = {"kind": "swipe", "dir": "left" if d.x < 0.0 else "right"}
	else:
		gesture = {"kind": "tap", "side": "left" if to.x < view_size.x * 0.5 else "right"}
	var next := Logic.lane_after_gesture(lane, gesture, false, tune)
	if next != lane:
		lane = next
		_stage.cheer("hop")
		AudioDirector.try_play(self, "mg_good", 1.15)


## W14 Forgiveness (nur Input-Mapping, PUR für Tests): der Zwei-Bahn-Wisch
## braucht auf breiten Screens mehr Weg, sonst springen unruhige Tipper.
static func swipe_threshold_px(width: float) -> float:
	return maxf(SWIPE_MIN_PX, width * SWIPE_MIN_FRAC)


func _advance(dm: float, delta: float) -> void:
	var before := traveled
	traveled += dm
	_step_showers(delta)
	while traveled + VIEW_AHEAD_M >= _next_row_m:
		_spawn_row()
	_collect(before, dm)
	if invuln <= 0.0:
		_check_hits(before, dm)
	_cull()
	score = live_score()
	ctx.report_score(score, 0)
	if Logic.should_spawn_shield(score, shield_spawned, tune):
		shield_spawned = true
		_pickups.append({"kind": "shield", "lane": lane, "m": traveled + VIEW_AHEAD_M * 0.8})


func _spawn_row() -> void:
	var row := Bot.generate_row(_stream, elapsed, _rows, tune)
	_rows.append(row)
	if _rows.size() > 6:
		_rows.pop_front()
	var at := _next_row_m
	_next_row_m += float(row["gap"])
	for i in int(tune["LANES"]):
		if bool(row["blocked"][i]):
			_meteors.append({"lane": i, "m": at, "spin": rng.next() * TAU, "approach": 0.0})
	var pickup := Logic.roll_pickup(_stream, tune)
	if pickup.is_empty():
		return
	var free: Array[int] = []
	for i in int(tune["LANES"]):
		if not bool(row["blocked"][i]):
			free.append(i)
	if free.is_empty():
		return
	var slot: int = free[mini(free.size() - 1, int(rng.next() * free.size()))]
	_pickups.append(
		{"kind": str(pickup["kind"]), "points": int(pickup["points"]), "lane": slot, "m": at}
	)


func _step_showers(delta: float) -> void:
	match _shower_state:
		"idle":
			if elapsed >= _shower_at:
				_shower_lanes = Logic.pick_shower_lanes(_stream, tune)
				_shower_state = "warn"
				_shower_left = float(tune["SHOWER_TELEGRAPH_SEC"])
				_warn_tick = WARN_TICK_SEC
				AudioDirector.try_play(self, "mg_junk", 0.6)
		"warn":
			_shower_left -= delta
			_step_warn_tick(delta)
			if _shower_left <= 0.0:
				_shower_state = "active"
				_shower_left = float(tune["SHOWER_DURATION_SEC"])
				_shower_drop = 0.0
		"active":
			_shower_left -= delta
			_shower_drop -= delta
			if _shower_drop <= 0.0:
				_shower_drop = float(tune["SHOWER_DROP_EVERY_SEC"])
				for l: int in _shower_lanes["danger"]:
					(
						_meteors
						. append(
							{
								"lane": l,
								"m": traveled + VIEW_AHEAD_M,
								"spin": rng.next() * TAU,
								"approach": float(tune["SHOWER_METEOR_SPEED"]),
							}
						)
					)
			if _shower_left <= 0.0:
				_shower_state = "idle"
				_shower_at = elapsed + float(tune["SHOWER_EVERY_SEC"])


## W16 Befund 6: tickender Countdown WÄHREND der Schauer-Warnung — der Pitch
## steigt, je näher der Schauer rückt (leiser ui_tick, kein neues Audio-Asset;
## vorher blinkte die Warnung nach dem einmaligen mg_junk stumm).
func _step_warn_tick(delta: float) -> void:
	_warn_tick -= delta
	if _warn_tick > 0.0:
		return
	_warn_tick = WARN_TICK_SEC
	var total := maxf(0.001, float(tune["SHOWER_TELEGRAPH_SEC"]))
	var k := clampf(1.0 - _shower_left / total, 0.0, 1.0)
	AudioDirector.try_play(self, "ui_tick", 0.9 + 0.5 * k)


func _step_wormhole(delta: float) -> void:
	if wormhole_left > 0.0:
		var before := float(tune["WORMHOLE_SEC"]) - wormhole_left
		wormhole_left = maxf(0.0, wormhole_left - delta)
		var after := float(tune["WORMHOLE_SEC"]) - wormhole_left
		var awarded := Logic.wormhole_awards(before, after, tune)
		if awarded > 0:
			pickup_points += awarded * int(tune["WORMHOLE_TICK_POINTS"])
			AudioDirector.try_play(self, "mg_combo", 1.2)
		return
	if Logic.should_spawn_wormhole(_stream, elapsed, wormhole_spawned, false, tune):
		wormhole_spawned = true
		wormhole_left = float(tune["WORMHOLE_SEC"])
		_stage.pulse_glow(1.2)
		AudioDirector.try_play(self, "mg_golden")
		_flash_text = I18nService.t("mg.starHopper.wormhole")
		_flash = 1.4
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.slowmo(0.5, 320)


func _collect(before: float, dm: float) -> void:
	var kept: Array[Dictionary] = []
	for p in _pickups:
		var hit := (
			int(p["lane"]) == lane
			and float(p["m"]) >= before - 3.0
			and float(p["m"]) <= before + dm + 3.0
		)
		if not hit:
			kept.append(p)
			continue
		_on_pickup(p)
	_pickups = kept


func _on_pickup(p: Dictionary) -> void:
	var pos := _to_screen(int(p["lane"]), float(p["m"]))
	if str(p["kind"]) == "shield":
		shielded = true
		_stage.pulse_glow(1.0)
		AudioDirector.try_play(self, "mg_golden")
		_flash_text = I18nService.t("mg.starHopper.shield")
		_flash = 1.2
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.9)
			ctx.juice.float_text(pos, _flash_text, Color(0.5, 0.85, 1.0))
		return
	pickup_points += int(p["points"])
	if str(p["kind"]) == "gold":
		_roll = float(Logic.HOPPER_JUICE["BARREL_ROLL_SEC"])
		_stage.cheer("celebrate")
		_stage.spark_at(_stage.ship_position() + Vector3(0.0, 0.4, 0.0), GOLD_COLOR)
		_stage.pulse_glow(0.8)
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.8)
			ctx.juice.hit_freeze(50)
		# W21/P5 Feier-Beat: die Goldmöhre ist DER Beat des Laufs — Gold-
		# Pille + Sparkle (MotionKit/RM-gated) statt kleinem Zahlen-Popup.
		MgHudKit.feier_beat(
			self, view_size, _ui, I18nService.t("mg.hudkit.beat_gold", {"n": int(p["points"])})
		)
	else:
		_pop = float(Logic.HOPPER_JUICE["POP_SEC"])
		_stage.spark_at(_stage.ship_position() + Vector3(0.0, 0.35, 0.0), STAR_COLOR)
		AudioDirector.try_play(self, "mg_good", 1.2)
		_popup_at(pos, "+%d" % int(p["points"]), STAR_COLOR)


## W14: großes, konturiertes Aufsammel-Popup (das JuiceKit-float_text war im
## dunklen Weltraum zu klein, Audit-Achse d).
func _popup_at(pos: Vector2, text: String, color: Color) -> void:
	_popups.append({"pos": pos, "text": text, "color": color, "t": 0.9})
	if _popups.size() > 6:
		_popups.pop_front()


func _step_popups(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for p in _popups:
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) > 0.0:
			kept.append(p)
	_popups = kept


func _check_hits(before: float, dm: float) -> void:
	var player := {"lane": lane, "m": before}
	for meteor in _meteors:
		if not Logic.sweep_hits_meteor(player, meteor, dm, tune):
			continue
		var result := Logic.resolve_hit(shielded)
		if bool(result["ended"]):
			_stage.spark_at(_stage.ship_position(), Color(1.0, 0.45, 0.25))
			AudioDirector.try_play(self, "mg_lose")
			if ctx.juice != null:
				ctx.juice.shake(0.8)
				ctx.juice.hit_freeze(140)
			_finish()
			return
		shielded = false
		invuln = float(tune["SHIELD_POP_INVULN_SEC"])
		_stage.spark_at(_stage.ship_position(), Color(0.5, 0.85, 1.0))
		_stage.pulse_glow(0.7)
		_flash_text = I18nService.t("mg.starHopper.shield_pop")
		_flash = 1.2
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.5)
			ctx.juice.bloom_pulse(0.7)
		return


func _cull() -> void:
	var kept_m: Array[Dictionary] = []
	for meteor in _meteors:
		meteor["m"] = float(meteor["m"]) - float(meteor["approach"]) * get_process_delta_time()
		if float(meteor["m"]) > traveled - 12.0:
			kept_m.append(meteor)
	_meteors = kept_m
	var kept_p: Array[Dictionary] = []
	for p in _pickups:
		if float(p["m"]) > traveled - 8.0:
			kept_p.append(p)
	_pickups = kept_p


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": live_score(), "distance": int(traveled), "pickups": pickup_points})


func _update_labels() -> void:
	_dist_label.text = I18nService.t("mg.starHopper.distance", {"m": int(traveled)})
	if shielded:
		_state_label.text = I18nService.t("mg.starHopper.shield")
	else:
		_state_label.text = I18nService.t(
			"mg.starHopper.speed", {"v": "%.1f" % Logic.speed_at(elapsed, tune)}
		)
	_hint_label.modulate.a = hint_alpha_at(elapsed)


## PURE Sichtbarkeit des Steuer-Hinweises (W21, M6-Kanon — identische
## Formel wie deliveryRush Feel.hint_alpha): voll bis HINT_FADE_SEC−1,2 s,
## dann linear auf 0 bei HINT_FADE_SEC. elapsed wartet im Intro, der Fade
## startet also fair.
static func hint_alpha_at(elapsed_s: float) -> float:
	return clampf((HINT_FADE_SEC - elapsed_s) / 1.2, 0.0, 1.0)


## Bahn + Streckenmeter → Bildschirmpixel (über die 3D-Kamera projiziert).
func _to_screen(lane_i: int, m: float) -> Vector2:
	return _to_screen_f(float(lane_i), m)


func _to_screen_f(lane_f: float, m: float) -> Vector2:
	if _stage == null:
		return view_size * 0.5
	var z := -(m - traveled) * Stage.WU_PER_M
	return _stage.to_screen(Vector3(_stage.lane_pos(lane_f), 0.3, z))


## Die WELT lebt in der 3D-Bühne — 2D bleibt nur, was Schrift ist.
func _draw() -> void:
	MgHudKit.draw_chip(self, _hud_plate, _dist_label, _state_label, _ui)
	_draw_hint_plate()
	if _shower_state == "warn":
		_draw_shower_warning()
	_draw_flash()
	_draw_popups()


## W21: Milchglas hinter dem Hinweis (unter dem Label gemalt — Kinder-
## Canvas-Items liegen über dem Eltern-_draw, deliveryRush-Muster).
func _draw_hint_plate() -> void:
	var alpha := hint_alpha_at(elapsed)
	if alpha <= 0.0 or _hint_label == null:
		return
	_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * alpha)
	draw_style_box(_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size))


func _draw_popups() -> void:
	for p in _popups:
		var t := float(p["t"])
		var rise := (0.9 - t) * 46.0 * _ui
		var color: Color = p["color"]
		color.a = clampf(t / 0.35, 0.0, 1.0)
		var at: Vector2 = p["pos"] + Vector2(-60.0 * _ui, -rise)
		var font := ThemeService.font(800)
		var outline := Color(0.1, 0.08, 0.2, color.a)
		var width := 120.0 * _ui
		var size := MgHudKit.font_px(30.0, _ui)
		draw_string_outline(
			font,
			at,
			str(p["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			width,
			size,
			maxi(3, int(6.0 * _ui)),
			outline
		)
		draw_string(font, at, str(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _draw_shower_warning() -> void:
	var pulse := 0.3 + 0.3 * sin(elapsed * 26.0)
	var alpha := clampf(0.6 + pulse, 0.0, 1.0)
	var font := ThemeService.font(800)
	var at := Vector2(0.0, view_size.y * 0.16)
	var text := I18nService.t("mg.starHopper.shower")
	var size := MgHudKit.font_px(26.0, _ui)
	# W21: dunkler Saum wie bei den Aufsammel-Popups — die nackte rote
	# Schrift ging vor hellen Planeten/Nebeln unter.
	draw_string_outline(
		font,
		at,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		size,
		maxi(3, int(6.0 * _ui)),
		Color(0.1, 0.08, 0.2, alpha)
	)
	draw_string(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, view_size.x, size, Color(1.0, 0.5, 0.45, alpha)
	)


## W21/P5: der Flash läuft über den Kit-Banner-Standard — Milchglas-Plate,
## Tinte + Saum, Umbruch (der SH-2-Wrap-Vertrag lebt jetzt in
## MgHudKit.banner_wrap_width); vorher stand nackte Gold-Schrift im All.
func _draw_flash() -> void:
	MgHudKit.draw_banner(self, _banner_plate, view_size, _ui, _flash_text, _flash)
