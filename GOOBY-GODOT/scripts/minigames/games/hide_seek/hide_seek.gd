extends MinigameBase
## Guck-guck-Garten (hideSeek) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## HideSeekLogic (zahlengleich zum Web): 3×4-Versteckraster, Tierchen lugen
## periodisch hervor, Tipp aufs richtige Versteck +2, geräumte Welle +3,
## 60 s (Endlos: bis 3 abgelaufene Wellen).
##
## ECHTE 3D-BÜHNE (HideSeekGarden3D): Gooby ist der SUCHER und schaut von vorn
## unten in den Garten, die Verstecke sind Nature-Kit-Requisiten auf einem
## Hang, dahinter Bäume, Zaun, Brunnen und Laterne. Das Raster wird weiterhin
## in Bildschirmpixeln gerechnet (getestet) und auf den Hang zurückgestrahlt.

const Logic := preload("res://scripts/minigames/games/hide_seek/hide_seek_logic.gd")
const Garden := preload("res://scripts/minigames/games/hide_seek/hide_seek_garden3d.gd")

## Pastellfarben der Tierchen (eine je Verstecker, zyklisch).
const CRITTER_COLORS: Array[Color] = [
	Color(1.0, 0.66, 0.78),
	Color(0.5, 0.83, 0.76),
	Color(1.0, 0.85, 0.48),
	Color(0.73, 0.66, 1.0),
	Color(1.0, 0.69, 0.54),
]
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var wave := 0
var expired := 0
var found_total := 0
var elapsed := 0.0
var wave_t := 0.0
var wave_sec := 13.0
var serve_t := 0.0
var phase := "play"
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

## spot index → {"found": bool, "peek_t": float, "next_peek": float, "color": int}
var _critters: Dictionary = {}
var _hidden: Dictionary = {}
var _shake: PackedFloat32Array = PackedFloat32Array()
var _stage: Node3D
var _ui := 1.0
var _time_label: Label
var _wave_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SEEK, ctx.difficulty)
	rng = ctx.rng()
	_shake.resize(Logic.spot_count(tune))
	_build_stage()
	_build_hud()
	_start_wave(0)
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## 3D-Bühne unter die Node2D-Wurzel hängen (Godot rendert 3D hinter 2D).
func _build_stage() -> void:
	_stage = Garden.new()
	_stage.name = "Garden3D"
	add_child(_stage)
	_stage.setup_stage(Logic.spot_count(tune))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.world_env


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	_layout_stage()
	_layout_hud()
	queue_redraw()


## Raster (Bildschirmpixel) auf den Gartenhang zurückstrahlen.
func _layout_stage() -> void:
	if _stage == null:
		return
	_stage.apply_size(view_size)
	var centers: Array[Vector2] = []
	for i in Logic.spot_count(tune):
		centers.append(spot_center(i))
	_stage.layout(centers, _cell_size(), view_size)


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_wave_label.position = Vector2(pad, 44.0 * _ui)
	_wave_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 48.0 * _ui)
	_hint_label.size = Vector2(hint_w, 42.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	for i in _shake.size():
		_shake[i] = maxf(0.0, _shake[i] - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if phase == "serve":
		serve_t -= delta
		if serve_t <= 0.0:
			phase = "play"
			_start_wave(wave + 1)
		_sync_stage(delta)
		_update_labels()
		queue_redraw()
		return
	wave_t += delta
	if wave_t >= wave_sec:
		_expire_wave()
		_sync_stage(delta)
		_update_labels()
		queue_redraw()
		return
	_tick_peeks(delta)
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## Die 3D-Bühne bekommt nur Optik-Zustand: Aufsteig-Anteil je Versteck (0..1),
## Wackler der angetippten Requisiten und Goobys Laune.
func _sync_stage(delta: float) -> void:
	if _stage == null:
		return
	var total := Logic.spot_count(tune)
	var rises: Array[float] = []
	rises.resize(total)
	for i in total:
		rises[i] = _rise_of(i)
		_stage.wobble(i, _shake[i] if i < _shake.size() else 0.0)
	_stage.sync(rises, elapsed)
	_stage.feel(_mood())
	_stage.tick(delta)


## Aufsteig-Anteil eines Tierchens (identisch zur alten 2D-Kurve).
func _rise_of(spot: int) -> float:
	if not _critters.has(spot):
		return 0.0
	var critter: Dictionary = _critters[spot]
	if bool(critter["found"]):
		return 1.0
	var peek := float(critter["peek_t"])
	if peek <= 0.0:
		return 0.0
	var k := sin(PI * maxf(0.0, 1.0 - peek / float(tune["PEEK_DURATION_SEC"])))
	return 0.12 + k * 0.76


## Gooby-Laune aus dem Spielzustand (Reihenfolge = Dringlichkeit).
func _mood() -> String:
	if finished:
		return "sad"
	if phase == "serve":
		return "ecstatic" if _hidden.is_empty() else "sad"
	if wave_t > wave_sec * 0.8:
		return "scared"
	for spot: int in _critters:
		if float((_critters[spot] as Dictionary)["peek_t"]) > 0.0:
			return "ecstatic"
	return "happy"


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "play":
		return
	if event is InputEventScreenTouch and event.pressed:
		var spot := _spot_at(event.position)
		if spot >= 0:
			_tap_spot(spot)


## Raster-Geometrie: Spalten/Zeilen tauschen in Landscape (rein visuell).
func grid_dims() -> Vector2i:
	var cols := int(tune["COLS"])
	var rows := int(tune["ROWS"])
	return Vector2i(rows, cols) if landscape else Vector2i(cols, rows)


## Bildschirm-Mittelpunkt eines Verstecks.
func spot_center(spot: int) -> Vector2:
	var dims := grid_dims()
	var col := spot % dims.x
	var row := spot / dims.x
	var cell := _cell_size()
	var origin := _grid_origin(cell, dims)
	return origin + Vector2((col + 0.5) * cell.x, (row + 0.55) * cell.y)


## Das Raster nimmt nur die OBEREN zwei Drittel ein — das untere Drittel
## gehört Gooby, der als Sucher im Vordergrund der 3D-Bühne steht.
func _cell_size() -> Vector2:
	var dims := grid_dims()
	var usable := Vector2(view_size.x * 0.9, view_size.y * (0.46 if landscape else 0.48))
	return Vector2(usable.x / dims.x, usable.y / dims.y)


func _grid_origin(cell: Vector2, dims: Vector2i) -> Vector2:
	var w := cell.x * dims.x
	return Vector2((view_size.x - w) * 0.5, view_size.y * (0.16 if landscape else 0.14))


func _spot_at(pos: Vector2) -> int:
	var total := Logic.spot_count(tune)
	var cell := _cell_size()
	var reach := minf(cell.x, cell.y) * 0.55
	for i in total:
		if pos.distance_to(spot_center(i)) <= reach:
			return i
	return -1


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_wave_label = Label.new()
	_wave_label.theme_type_variation = &"CaptionLabel"
	add_child(_wave_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.hideSeek.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf der Wiese — heller Text mit weichem Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.16, 0.28, 0.14, 0.42))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _start_wave(index: int) -> void:
	wave = index
	wave_sec = Logic.wave_sec_for(wave, tune)
	wave_t = 0.0
	_hidden.clear()
	_critters.clear()
	var spots := Logic.roll_hiders(rng, wave, tune)
	for i in spots.size():
		var spot: int = spots[i]
		_hidden[spot] = true
		_critters[spot] = {
			"found": false,
			"peek_t": 0.0,
			"next_peek": elapsed + 0.6 + rng.next() * float(tune["PEEK_EVERY_SEC"]),
			"color": i % CRITTER_COLORS.size(),
		}
	if wave > 0:
		_set_banner(I18nService.t("mg.hideSeek.wave_new", {"n": spots.size()}))


func _tick_peeks(delta: float) -> void:
	for spot: int in _critters:
		var critter: Dictionary = _critters[spot]
		if bool(critter["found"]) or not _hidden.has(spot):
			continue
		if float(critter["peek_t"]) > 0.0:
			critter["peek_t"] = float(critter["peek_t"]) - delta
			if float(critter["peek_t"]) <= 0.0:
				critter["peek_t"] = 0.0
				critter["next_peek"] = (
					elapsed + float(tune["PEEK_EVERY_SEC"]) * (0.75 + rng.next() * 0.5)
				)
		elif elapsed >= float(critter["next_peek"]):
			critter["peek_t"] = float(tune["PEEK_DURATION_SEC"])
			AudioDirector.try_play(self, "ui_tick", 1.2)
			# Entdeckungsmoment ankündigen: goldenes Aufblitzen am Versteck,
			# damit das Auge hinspringt, bevor das Tierchen wieder abtaucht.
			if _stage != null:
				_stage.alert(spot)


func _tap_spot(spot: int) -> void:
	if spot < 0 or spot >= _shake.size():
		return
	_shake[spot] = 0.35
	var pos := spot_center(spot)
	if not _hidden.has(spot):
		AudioDirector.try_play(self, "ui_chip")
		if _stage != null:
			_stage.poof(spot, Color(0.72, 0.78, 0.56))
		if ctx.juice != null:
			ctx.juice.float_text(pos, I18nService.t("mg.hideSeek.empty"), Color(0.54, 0.5, 0.66))
		return
	_hidden.erase(spot)
	var critter: Dictionary = _critters[spot]
	critter["found"] = true
	critter["peek_t"] = 0.0
	found_total += 1
	var prev := score
	score = Logic.apply_score(score, int(tune["FIND_PTS"]))
	if score != prev:
		ctx.report_score(score, score - prev)
	AudioDirector.try_play(self, "mg_good", 1.08)
	if _stage != null:
		_stage.poof(spot, CRITTER_COLORS[int(critter["color"])])
		# Gefunden! Das Tierchen macht Freudensprünge statt nur dazustehen.
		_stage.celebrate(spot)
		_stage.pulse_glow(0.5)
	if ctx.juice != null:
		ctx.juice.float_text(
			pos,
			"+%d %s" % [int(tune["FIND_PTS"]), I18nService.t("mg.hideSeek.found")],
			Color(0.18, 0.55, 0.34)
		)
		ctx.juice.hit_freeze(40)
		ctx.juice.bloom_pulse(0.4)
	if _hidden.is_empty():
		_clear_wave()


func _clear_wave() -> void:
	var prev := score
	score = Logic.apply_score(score, int(tune["WAVE_BONUS"]))
	if score != prev:
		ctx.report_score(score, score - prev)
	AudioDirector.try_play(self, "mg_perfect")
	_set_banner(I18nService.t("mg.hideSeek.wave_clear", {"n": int(tune["WAVE_BONUS"])}))
	if _stage != null:
		_stage.cheer("wave")
		_stage.pulse_glow(0.95)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.shake(0.12)
	phase = "serve"
	serve_t = float(tune["SERVE_SEC"])


func _expire_wave() -> void:
	expired += 1
	AudioDirector.try_play(self, "mg_spill")
	_set_banner(I18nService.t("mg.hideSeek.expired"))
	for spot: int in _critters:
		(_critters[spot] as Dictionary)["peek_t"] = 0.0
	if ctx.juice != null:
		ctx.juice.shake(0.28)
	if Logic.endless_should_end(expired, tune):
		_finish()
		return
	phase = "serve"
	serve_t = float(tune["SERVE_SEC"])


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "waves": wave + 1, "found": found_total, "expired": expired})


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.hideSeek.expired_count", {"n": expired, "max": int(tune["ENDLESS_MAX_EXPIRED"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_wave_label.text = I18nService.t("mg.hideSeek.wave", {"n": wave + 1, "left": _hidden.size()})


## Nur noch HUD: Garten, Verstecke und Tierchen sind 3D (Garden3D).
func _draw() -> void:
	_draw_timer_bar()
	_draw_banner()


func _draw_timer_bar() -> void:
	var frac := maxf(0.0, 1.0 - wave_t / maxf(0.001, wave_sec))
	var w := view_size.x * 0.72
	var x := (view_size.x - w) * 0.5
	var y := view_size.y * (0.13 if landscape else 0.115)
	draw_rect(Rect2(x, y, w, 12.0), Color(1.0, 1.0, 1.0, 0.5), true)
	var col := Color(0.96, 0.55, 0.43) if frac < 0.3 else Color(0.35, 0.79, 0.73)
	draw_rect(Rect2(x, y, w * frac, 12.0), col, true)
	draw_rect(Rect2(x, y, w, 12.0), Color(0.35, 0.3, 0.3, 0.35), false, 2.0)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	# Breite mit _ui skalieren — fest 380 px schnitt „Neue Welle: 4 verstecken
	# sich" auf großen Bildschirmen mitten im Wort ab.
	var w := minf(view_size.x * 0.92, 460.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.36),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		32,
		Color(0.32, 0.24, 0.28, alpha)
	)
