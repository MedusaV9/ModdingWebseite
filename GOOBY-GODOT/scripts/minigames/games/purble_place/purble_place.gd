extends MinigameBase
## Tortenwerkstatt (purblePlace) — Spiel-Szene. Die MECHANIK-Zahlen kommen
## ausnahmslos aus `PurblePlaceLogic` (zahlengleich zum Web): 6-m-Band, das der
## SPIELER mit ◀/▶ treibt, Zutaten als physische Tropfen (0,45 s Fall, Fangfenster
## ±0,24 m), Ofentunnel mit grünem Fenster 2,25–3,0 s und Versand bei 5,95 ± 0,3.
## 210 s (Endlos: bis 3 abgelehnte/abgelaufene Torten).
##
## 2D statt three.js: das Web war bereits eine feste SEITENANSICHT auf ein
## gerades Band — als flacher Sticker-Schnitt ist das nicht nur billiger,
## sondern LESBARER (Fangfenster und Ofenzone sind exakte Pixelstrecken statt
## perspektivisch verzerrt). Die Bandkoordinate s wird linear projiziert, damit
## §G1.5-Meter und Bildschirmpixel sich 1:1 entsprechen.

const Logic := preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd")
const Bakery := preload("res://scripts/minigames/games/purble_place/purble_place_bakery.gd")
const Cake := preload("res://scripts/minigames/games/purble_place/purble_place_cake.gd")

## §G1.4-Kamerafenster: 3,2 m schmal / 3,6 m ab 412 px Breite.
const REQ_WINDOW_NARROW := 3.2
const REQ_WINDOW_WIDE := 3.6
const WIDE_PX := 412.0
## Die Kamera folgt der Arbeitsform, geklemmt auf ±1,4 m um die Bandmitte.
const CAM_CLAMP := 1.4
const CAM_K := 5.0
## Vertikales Weltbudget der Bühne (Schiene 1,15 m + Luft + Boden).
const STAGE_METERS := 2.6
## Meter unter der Bandoberkante (Rollen, Beine, Dielenboden).
const BELOW_BELT := 0.55
## Kurze Kante des Entwurfsformats (390×844) — Basis der UI-Skala.
const DESIGN_SHORT := 390.0

## Tastenbelegung: Düsen ohne Maus.
const KEY_STATIONS := {
	KEY_Q: "teig.vanilla",
	KEY_W: "teig.chocolate",
	KEY_E: "teig.strawberry",
	KEY_A: "guss.white",
	KEY_S: "guss.pink",
	KEY_D: "guss.chocolate",
	KEY_Y: "deko.cherry",
	KEY_X: "deko.sprinkles",
	KEY_C: "deko.berries",
	KEY_F: "kerzen",
}
const KEY_SHAPES := {KEY_1: "round", KEY_2: "square", KEY_3: "heart"}

## Kleiderfarben der wartenden Gäste (nach Auftrags-Id durchgereicht).
const QUEUE_TINTS: Array[Color] = [
	Color(0.55, 0.75, 0.9),
	Color(0.95, 0.66, 0.55),
	Color(0.62, 0.82, 0.6),
	Color(0.82, 0.68, 0.92),
	Color(0.96, 0.82, 0.5),
]

var tune: Dictionary = {}
var line: Dictionary = {}
var view_size := Vector2(390.0, 844.0)
var landscape := false
var finished := false
## Dev-Autoplay (Web-Gegenstück zu `?autoplay=1`): der §G1.9-Bot bedient die
## Werkstatt selbst. Wird nur von Werkzeugen gesetzt, nie im echten Lauf.
var autoplay := false

var _bot: PurblePlaceBot

var _cam_s := 3.0
var _ui := 1.0
var _ppm := 100.0
var _window := 3.2
var _stage := Rect2()
var _belt_px := 0.0
var _strip := Rect2()
var _dock_top := 0.0
var _scroll := 0.0
var _cheer := 0.0
var _oven_heat := 0.0
var _last_score := 0
var _press_queue: Array[String] = []
var _spawn_queue: Array[String] = []
var _ship_request := false
var _pedal := 0
var _key_dir := 0
var _flash := 0.0
var _flash_text := ""
var _flash_good := true
var _time_label: Label
var _hint_label: Label
var _nozzle_buttons: Dictionary = {}
var _shape_buttons: Array[Button] = []
var _pedal_left: Button
var _pedal_right: Button
var _ship_button: Button


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.CAKE, ctx.difficulty)
	line = Logic.create_line(ctx.rng(), ctx.difficulty)
	_bot = PurblePlaceBot.new(ctx.rng((ctx.run_seed ^ 0x9E3779B9) & 0xFFFFFFFF))
	# Erst messen, dann bauen: Knopfgrößen und Schriftgrade hängen an _ui.
	_fit_viewport()
	_build_hud()
	_build_dock()
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
	# Der Host rendert die Bühne in einem SubViewport, der ein Vielfaches des
	# 390×844-Entwurfs groß ist — alle Pixelmaße hängen deshalb an _ui.
	_ui = minf(view_size.x, view_size.y) / DESIGN_SHORT
	var dock_h := clampf(view_size.y * (0.30 if not landscape else 0.36), 118.0 * _ui, 250.0 * _ui)
	_dock_top = view_size.y - dock_h
	_strip = Rect2(12.0 * _ui, _dock_top - 30.0 * _ui, view_size.x - 24.0 * _ui, 22.0 * _ui)
	_stage = Rect2(0.0, 0.0, view_size.x, maxf(80.0, _strip.position.y - 6.0 * _ui))

	var req := REQ_WINDOW_WIDE if view_size.x >= WIDE_PX else REQ_WINDOW_NARROW
	_ppm = minf(_stage.size.x / req, _stage.size.y / STAGE_METERS)
	# Nie weiter herauszoomen als das ganze Band plus etwas Rand.
	_ppm = maxf(_ppm, _stage.size.x / 6.4)
	_window = _stage.size.x / _ppm
	_belt_px = _stage.position.y + _stage.size.y - _ppm * BELOW_BELT
	_layout_dock(dock_h)
	if _time_label != null:
		_time_label.position = Vector2(16.0 * _ui, 58.0 * _ui)
		_time_label.add_theme_font_size_override("font_size", int(20.0 * _ui))
		_hint_label.add_theme_font_size_override("font_size", int(13.0 * _ui))
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_cheer = maxf(0.0, _cheer - delta)
	if not is_active() or finished:
		queue_redraw()
		return
	var belt := signi(_pedal + _key_dir)
	var input := {"belt": belt, "press": "", "spawnShape": "", "ship": _ship_request}
	if not _spawn_queue.is_empty():
		input["spawnShape"] = _spawn_queue.pop_front()
	if not _press_queue.is_empty():
		input["press"] = _press_queue.pop_front()
	_ship_request = false
	if autoplay:
		input = _bot.plan(line, delta)
	var before := float(line["beltV"])
	var events := Logic.step_line(line, delta, input)
	_scroll += (before + float(line["beltV"])) * 0.5 * delta
	_handle_events(events)
	_update_camera(delta)
	_update_score()
	_oven_heat = maxf(0.0, _oven_heat - delta * 0.8)
	for pan: Dictionary in line["pans"]:
		if bool(pan["inOven"]):
			_oven_heat = 1.0
	_update_labels()
	_sync_dock()
	if bool(line["over"]):
		_finish()
	elif not bool(tune["ENDLESS"]) and float(line["t"]) >= float(tune["DURATION_SEC"]):
		_finish()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if key.keycode == KEY_LEFT:
		_key_dir = -1 if key.pressed else (1 if _key_dir == 1 else 0)
		return
	if key.keycode == KEY_RIGHT:
		_key_dir = 1 if key.pressed else (-1 if _key_dir == -1 else 0)
		return
	if not key.pressed:
		return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		_ship_request = true
	elif KEY_SHAPES.has(key.keycode):
		_queue_spawn(str(KEY_SHAPES[key.keycode]))
	elif KEY_STATIONS.has(key.keycode):
		_queue_press(str(KEY_STATIONS[key.keycode]))


## Bandmeter → Bildschirmpixel (y zählt Meter über der Bandoberkante).
func project(s: float, y: float) -> Vector2:
	var x := _stage.position.x + (s - (_cam_s - _window * 0.5)) * _ppm
	return Vector2(x, _belt_px - y * _ppm)


# ── Eingaben ──────────────────────────────────────────────────────────────


func _queue_press(station_id: String) -> void:
	if _press_queue.size() < 3:
		_press_queue.append(station_id)


func _queue_spawn(shape: String) -> void:
	if _spawn_queue.size() < 2:
		_spawn_queue.append(shape)


# ── Simulation ────────────────────────────────────────────────────────────


func _update_camera(delta: float) -> void:
	var focus := float(tune["SPAWN_S"])
	var pans: Array = line["pans"]
	if not pans.is_empty():
		var oldest: Dictionary = pans[0]
		for pan: Dictionary in pans:
			if int(pan["id"]) < int(oldest["id"]):
				oldest = pan
		focus = float(oldest["s"])
	var center := float(tune["BELT_LENGTH_M"]) * 0.5
	var want := clampf(focus, center - CAM_CLAMP, center + CAM_CLAMP)
	if _window >= float(tune["BELT_LENGTH_M"]):
		want = center
	_cam_s += (want - _cam_s) * minf(1.0, CAM_K * delta)


func _update_score() -> void:
	var total := int(line["score"])
	if total != _last_score:
		ctx.report_score(total, total - _last_score)
		_last_score = total


func _handle_events(events: Array) -> void:
	for ev: Dictionary in events:
		match str(ev["type"]):
			"panSpawn":
				AudioDirector.try_play(self, "ui_chip")
			"catch":
				AudioDirector.try_play(self, "mg_good", 1.0 + 0.04 * (int(line["combo"]) % 6))
			"splat":
				_on_splat(ev)
			"buzz":
				AudioDirector.try_play(self, "ui_error")
			"bakeCommit":
				_on_bake(ev)
			"serve":
				_on_serve(ev)
			"reject":
				_on_serve(ev)
			"expire":
				_say(I18nService.t("mg.purblePlace.expired"), false, 1.1)
				AudioDirector.try_play(self, "mg_junk")
				if ctx.juice != null:
					ctx.juice.shake(0.3)
			"ticketNew":
				AudioDirector.try_play(self, "ui_open")
			"trash":
				AudioDirector.try_play(self, "mg_junk")


func _on_splat(ev: Dictionary) -> void:
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.18)
		ctx.juice.float_text(project(float(ev["s"]), 0.35), "-2", Color(0.82, 0.35, 0.3))


func _on_bake(ev: Dictionary) -> void:
	var result := str(ev["result"])
	if result == "perfect":
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.7)
			ctx.juice.float_text(
				project(float(tune["OVEN_END_S"]), 1.2), "+5", Color(0.34, 0.68, 0.4)
			)
		_say(I18nService.t("mg.purblePlace.baked"), true, 0.9)
	elif result == "singed":
		AudioDirector.try_play(self, "mg_junk")
		if ctx.juice != null:
			ctx.juice.shake(0.24)
			ctx.juice.float_text(
				project(float(tune["OVEN_END_S"]), 1.2), "-3", Color(0.82, 0.35, 0.3)
			)
		_say(I18nService.t("mg.purblePlace.singed"), false, 1.1)


func _on_serve(ev: Dictionary) -> void:
	var outcome := str(ev["outcome"])
	var points := int(ev["points"])
	var pos := project(float(tune["SHIP_S"]), 0.9)
	if outcome == "rejected":
		AudioDirector.try_play(self, "mg_junk")
		_say(I18nService.t("mg.purblePlace.rejected"), false, 1.3)
		if ctx.juice != null:
			ctx.juice.shake(0.34)
			ctx.juice.float_text(pos, "%d" % points, Color(0.82, 0.35, 0.3))
		return
	_cheer = 1.0
	if outcome == "perfect":
		AudioDirector.try_play(self, "mg_perfect")
		_say(I18nService.t("mg.purblePlace.perfect", {"n": points}), true, 1.4)
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.hit_freeze(60)
	else:
		AudioDirector.try_play(self, "mg_combo")
		_say(I18nService.t("mg.purblePlace.served", {"n": points}), true, 1.2)
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % points, Color(0.24, 0.6, 0.36))


func _say(text: String, good: bool, secs: float) -> void:
	_flash_text = text
	_flash_good = good
	_flash = secs


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win" if int(line["score"]) >= 120 else "mg_lose")
	(
		ctx
		. report_end(
			{
				"score": int(line["score"]),
				"cakesServed": int(line["cakesServed"]),
				"perfectCakes": int(line["perfectCakes"]),
				"rejected": int(line["rejected"]),
				"expired": int(line["expired"]),
			}
		)
	)


# ── HUD + Dock ────────────────────────────────────────────────────────────


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.purblePlace.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	_update_labels()


func _build_dock() -> void:
	for st: Dictionary in Logic.STATIONS:
		if not bool(st["drop"]):
			continue
		var id := str(st["id"])
		var button := _make_button(
			I18nService.t("mg.purblePlace.btn.%s" % id), Bakery.nozzle_color(st)
		)
		button.pressed.connect(_queue_press.bind(id))
		add_child(button)
		_nozzle_buttons[id] = button
	for shape: String in Logic.SHAPES:
		var button := _make_button(
			I18nService.t("mg.purblePlace.btn.%s" % shape), Color(0.62, 0.79, 0.92)
		)
		button.pressed.connect(_queue_spawn.bind(shape))
		add_child(button)
		_shape_buttons.append(button)
	_ship_button = _make_button(I18nService.t("mg.purblePlace.btn.versand"), Color(0.55, 0.82, 0.6))
	_ship_button.pressed.connect(func() -> void: _ship_request = true)
	add_child(_ship_button)
	_pedal_left = _make_button("◀", Color(0.98, 0.85, 0.62))
	_pedal_right = _make_button("▶", Color(0.98, 0.85, 0.62))
	for entry: Array in [[_pedal_left, -1], [_pedal_right, 1]]:
		var button: Button = entry[0]
		var dir: int = entry[1]
		button.button_down.connect(func() -> void: _pedal = dir)
		button.button_up.connect(func() -> void: _pedal = 0 if _pedal == dir else _pedal)
		add_child(button)


func _make_button(text: String, tint: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", int(13.0 * _ui))
	var dark := tint.get_luminance() < 0.55
	button.add_theme_color_override(
		"font_color", Color(1.0, 0.98, 0.96) if dark else Color(0.24, 0.18, 0.16)
	)
	button.add_theme_color_override(
		"font_hover_color", Color(1.0, 0.98, 0.96) if dark else Color(0.24, 0.18, 0.16)
	)
	button.add_theme_color_override(
		"font_pressed_color", Color(1.0, 0.98, 0.96) if dark else Color(0.24, 0.18, 0.16)
	)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.48))
	button.add_theme_stylebox_override("normal", _box(tint))
	button.add_theme_stylebox_override("hover", _box(tint.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _box(tint.darkened(0.18)))
	button.add_theme_stylebox_override("focus", _box(tint))
	button.add_theme_stylebox_override("disabled", _box(tint.lerp(Color(0.85, 0.83, 0.82), 0.75)))
	return button


func _box(tint: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.set_corner_radius_all(int(14.0 * _ui))
	box.border_color = tint.darkened(0.3)
	box.set_border_width_all(int(2.0 * _ui))
	box.content_margin_left = 2.0 * _ui
	box.content_margin_right = 2.0 * _ui
	return box


## Zwei Dock-Reihen: oben die Düsen, die die Bühne gerade zeigt (in Bandreihen-
## folge, damit links/rechts im Dock links/rechts am Band bedeutet), unten die
## Pedale außen und Formen + Versand in der Mitte.
func _layout_dock(dock_h: float) -> void:
	if _ship_button == null:
		return
	var pad := 8.0 * _ui
	var row1_h := clampf(dock_h * 0.26, 46.0 * _ui, 62.0 * _ui)
	var row2_h := clampf(dock_h * 0.34, 56.0 * _ui, 84.0 * _ui)
	var row1_y := _dock_top + pad
	var row2_y := _dock_top + dock_h - row2_h - pad

	var shown: Array[Dictionary] = []
	for st: Dictionary in Logic.STATIONS:
		if not bool(st["drop"]):
			continue
		var x := project(float(st["s"]), 0.0).x
		var button: Button = _nozzle_buttons[str(st["id"])]
		button.visible = x > _stage.position.x and x < _stage.position.x + _stage.size.x
		if button.visible:
			shown.append(st)
	var cell := _stage.size.x / maxi(1, shown.size())
	for i in shown.size():
		var button: Button = _nozzle_buttons[str(shown[i]["id"])]
		button.size = Vector2(minf(cell - 6.0 * _ui, 132.0 * _ui), row1_h)
		button.position = Vector2(cell * (i + 0.5) - button.size.x * 0.5, row1_y)

	var pedal_w := clampf(view_size.x * 0.19, 68.0 * _ui, 112.0 * _ui)
	_pedal_left.size = Vector2(pedal_w, row2_h)
	_pedal_left.position = Vector2(pad, row2_y)
	_pedal_right.size = Vector2(pedal_w, row2_h)
	_pedal_right.position = Vector2(view_size.x - pedal_w - pad, row2_y)
	var inner_x := pad * 2.0 + pedal_w
	var inner_cell := (view_size.x - inner_x * 2.0) / 4.0
	for i in _shape_buttons.size():
		var button := _shape_buttons[i]
		button.size = Vector2(inner_cell - 6.0 * _ui, row2_h)
		button.position = Vector2(inner_x + inner_cell * i + 3.0 * _ui, row2_y)
	_ship_button.size = Vector2(inner_cell - 6.0 * _ui, row2_h)
	_ship_button.position = Vector2(inner_x + inner_cell * 3.0 + 3.0 * _ui, row2_y)

	# Der Hinweis lebt in der Lücke zwischen den Dock-Reihen; ist dort kein
	# Platz (Querformat), bleibt er aus — die Knöpfe sprechen für sich.
	var gap_top := row1_y + row1_h + 6.0 * _ui
	var gap_h := row2_y - gap_top - 4.0 * _ui
	_hint_label.visible = gap_h >= 26.0 * _ui
	_hint_label.position = Vector2(16.0 * _ui, gap_top)
	_hint_label.size = Vector2(view_size.x - 32.0 * _ui, gap_h)


## Knopfzustände je Frame: Sperrzeiten grauen die Düsen aus, der Formentrichter
## kennt Deckel und Mindestabstand, der Versand braucht eine Form in der Zone.
func _sync_dock() -> void:
	var lockouts: Dictionary = line["lockouts"]
	for id: String in _nozzle_buttons:
		(_nozzle_buttons[id] as Button).disabled = float(lockouts.get(id, 0.0)) > 0.0
	var can: bool = bool(Logic.can_spawn(line)["ok"])
	for button: Button in _shape_buttons:
		button.disabled = not can
	_ship_button.disabled = not _ship_armed()
	_layout_dock(view_size.y - _dock_top)


func _ship_armed() -> bool:
	var ship_s := float(tune["SHIP_S"])
	for pan: Dictionary in line["pans"]:
		if (
			absf(float(pan["s"]) - ship_s) <= float(tune["SHIP_HALF_M"]) + Logic.EPS
			and pan["bake"] != null
		):
			return true
	return false


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		var fails := int(line["rejected"]) + int(line["expired"])
		_time_label.text = I18nService.t(
			"mg.purblePlace.fails", {"n": fails, "max": int(tune["ENDLESS_FAIL_COUNT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(line["t"]))))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})


# ── Zeichnen ──────────────────────────────────────────────────────────────


func _draw() -> void:
	var project_fn := Callable(self, "project")
	Bakery.draw_backdrop(self, _stage, _belt_px, _ppm)
	Bakery.draw_sign(
		self,
		Rect2(
			_stage.position.x,
			_stage.position.y + _stage.size.y * 0.045,
			_stage.size.x,
			maxf(46.0, _queue_top() - _stage.position.y - 26.0)
		),
		I18nService.t("mg.purblePlace.title"),
		ThemeService.font(800)
	)
	_draw_queue()
	Bakery.draw_oven(
		self, project_fn, _ppm, float(tune["OVEN_START_S"]), float(tune["OVEN_END_S"]), _oven_heat
	)
	Bakery.draw_spawn(
		self, project_fn, _ppm, float(tune["SPAWN_S"]), bool(Logic.can_spawn(line)["ok"])
	)
	Bakery.draw_ship(
		self, project_fn, _ppm, float(tune["SHIP_S"]), float(tune["SHIP_HALF_M"]), _ship_armed()
	)
	Bakery.draw_belt(self, _stage, project_fn, _ppm, _scroll)
	for splat: Dictionary in line["splats"]:
		Bakery.draw_splat(self, project_fn, _ppm, splat, float(tune["SPLAT_TTL_SEC"]))
	_draw_pans()
	_draw_oven_pane()
	Bakery.draw_nozzles(self, project_fn, _ppm, Logic.STATIONS, line["lockouts"])
	_draw_drops()
	_draw_catch_hint()
	Bakery.draw_gooby(
		self,
		Vector2(_stage.position.x + _ppm * 0.44, _stage.position.y + _stage.size.y - _ppm * 0.4),
		_ppm * 0.26,
		_cheer
	)
	# Alles unterhalb der Bühne wieder zudecken (die Bühne kennt kein Clipping).
	draw_rect(
		Rect2(0.0, _stage.position.y + _stage.size.y, view_size.x, view_size.y),
		Color(0.98, 0.94, 0.9)
	)
	Bakery.draw_overview(self, _strip, line, tune, _cam_s, _window)
	_draw_flash()


func _draw_pans() -> void:
	for pan: Dictionary in line["pans"]:
		var w := _ppm * 0.6
		var base := project(float(pan["s"]), 0.0)
		draw_circle(Vector2(base.x, base.y + 2.0), w * 0.44, Color(0.0, 0.0, 0.0, 0.16))
		Cake.draw_cake(self, Vector2(base.x, base.y - w * 0.17), w, pan)
		if float(pan["bakeT"]) > 0.01 and pan["bake"] == null:
			_draw_bake_meter(Vector2(base.x, base.y - w * 0.72 - _ppm * 0.34), w * 1.25, pan)


## Backuhr über der Form: grünes Fenster 2,25–3,0 s, Verkohlung am rechten Rand.
func _draw_bake_meter(at: Vector2, w: float, pan: Dictionary) -> void:
	var singe := float(tune["SINGE_SEC"])
	var h := maxf(6.0, _ppm * 0.075)
	var rect := Rect2(at - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(rect, Color(0.99, 0.96, 0.92))
	var g0 := float(tune["BAKE_GREEN_START_SEC"]) / singe
	var g1 := float(tune["BAKE_GREEN_END_SEC"]) / singe
	draw_rect(
		Rect2(rect.position + Vector2(w * g0, 0.0), Vector2(w * (g1 - g0), h)),
		Color(0.45, 0.79, 0.46)
	)
	var frac := clampf(float(pan["bakeT"]) / singe, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(w * frac, h)), Color(0.95, 0.55, 0.26, 0.85))
	draw_rect(rect, Color(0.5, 0.38, 0.32), false, 2.0)
	draw_line(
		Vector2(rect.position.x + w * frac, rect.position.y - 3.0),
		Vector2(rect.position.x + w * frac, rect.position.y + h + 3.0),
		Color(0.25, 0.2, 0.2),
		2.5
	)


## Vordere Ofenscheibe: liegt ÜBER den Formen, damit sie im Tunnel verschwinden.
func _draw_oven_pane() -> void:
	var left := project(float(tune["OVEN_START_S"]), 0.0)
	var right := project(float(tune["OVEN_END_S"]), 0.0)
	var h := _ppm * 0.62
	var pane := Rect2(left.x, left.y - h, right.x - left.x, h)
	draw_rect(pane, Color(1.0, 0.55, 0.24, 0.22 + 0.14 * _oven_heat))
	for i in 4:
		var x := pane.position.x + pane.size.x * (float(i) + 0.5) / 4.0
		draw_line(
			Vector2(x, pane.position.y),
			Vector2(x, pane.position.y + pane.size.y),
			Color(0.65, 0.38, 0.26, 0.55),
			maxf(2.0, _ppm * 0.022)
		)


func _draw_drops() -> void:
	var now := float(line["t"])
	for drop: Dictionary in line["drops"]:
		var st := Logic.station(str(drop["station"]))
		if st.is_empty():
			continue
		var frac := (now - float(drop["firedAt"])) / maxf(0.001, float(tune["FALL_SEC"]))
		Bakery.draw_drop(self, Callable(self, "project"), _ppm, st, frac)


## Fangfenster der Form, die als nächstes unter eine Düse läuft (§G1.5-Lehre).
func _draw_catch_hint() -> void:
	var half := float(tune["CATCH_HALF_M"])
	for pan: Dictionary in line["pans"]:
		var s := float(pan["s"])
		var a := project(s - half, 0.0)
		var b := project(s + half, 0.0)
		draw_rect(Rect2(a.x, a.y - 3.0, b.x - a.x, 4.0), Color(1.0, 1.0, 1.0, 0.5))
		for x in [a.x, b.x]:
			draw_line(
				Vector2(float(x), a.y - 8.0),
				Vector2(float(x), a.y + 2.0),
				Color(1.0, 1.0, 1.0, 0.72),
				2.0
			)


## Wartende Gäste über der Theke — jeder hält seine Wunschtorte in einer
## Sprechblase; Geduldsbalken und Gesicht kippen mit der Restzeit. Reicht die
## Wandhöhe nicht (Querformat), fallen die Gäste weg und die Blasen rücken als
## kompakte Kartenreihe nach oben links.
func _draw_queue() -> void:
	var tickets: Array = line["tickets"]
	var slots := int(tune["MAX_TICKETS"])
	var floor_y := _belt_px - _ppm * 1.62
	var top := _queue_top()
	var font := ThemeService.font(700)
	if floor_y - top < 190.0 * _ui:
		_draw_compact_tickets(tickets, slots, font)
		return
	var counter_h := maxf(12.0, _ppm * 0.16)
	Bakery.draw_counter(self, Rect2(_stage.position.x, floor_y, _stage.size.x, counter_h))
	var cell := _stage.size.x / slots
	var card_w := minf(cell - 16.0 * _ui, 158.0 * _ui)
	var card_h := card_w * 1.16
	var body_h := clampf(floor_y - (top + card_h + 20.0 * _ui), 46.0 * _ui, 168.0 * _ui)
	for i in mini(slots, tickets.size()):
		var cx := _stage.position.x + cell * (i + 0.5)
		var ticket: Dictionary = tickets[i]
		var tint: Color = QUEUE_TINTS[int(ticket["id"]) % QUEUE_TINTS.size()]
		var mood := clampf(
			float(ticket["remain"]) / maxf(0.001, float(ticket["patience"])), 0.0, 1.0
		)
		Bakery.draw_customer(self, Vector2(cx, floor_y + counter_h * 0.35), body_h, tint, mood)
		Cake.draw_ticket_card(
			self,
			Rect2(
				Vector2(cx - card_w * 0.5, floor_y - body_h - card_h - 14.0 * _ui),
				Vector2(card_w, card_h)
			),
			ticket,
			font,
			i == 0,
			true
		)


func _draw_compact_tickets(tickets: Array, slots: int, font: Font) -> void:
	var card_w := clampf(view_size.x * 0.13, 70.0 * _ui, 130.0 * _ui)
	var card_h := card_w * 1.16
	var pad := 8.0 * _ui
	var board := Rect2(
		Vector2(14.0 * _ui, 56.0 * _ui), Vector2(slots * (card_w + pad) + pad, card_h + pad * 2.0)
	)
	draw_rect(board, Color(0.87, 0.71, 0.53, 0.92))
	draw_rect(board, Color(0.66, 0.5, 0.36), false, 3.0 * _ui)
	for i in mini(slots, tickets.size()):
		Cake.draw_ticket_card(
			self,
			Rect2(board.position + Vector2(pad + i * (card_w + pad), pad), Vector2(card_w, card_h)),
			tickets[i],
			font,
			i == 0
		)


func _queue_top() -> float:
	return clampf(_belt_px - _ppm * 4.4, 96.0 * _ui, _belt_px - _ppm * 2.4)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_flash * 1.6, 0.0, 1.0)
	var col := Color(0.19, 0.55, 0.32, alpha) if _flash_good else Color(0.84, 0.31, 0.28, alpha)
	draw_string(
		font,
		Vector2(view_size.x * 0.5 - 180.0 * _ui, _belt_px - _ppm * 1.05),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		360.0 * _ui,
		int(26.0 * _ui),
		col
	)
