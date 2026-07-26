extends MinigameBase
## Schneckenpost (snailMail) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## SnailMailLogic (zahlengleich zum Web): Weg vom Briefkasten zum leuchtenden
## Haus MALEN, danach kriecht die Postschnecke ihn ab. Pfütze = 2 s
## Schneckenhaus + kein Trocken-Bonus, Blumen +1. Zustellung +4 (+2 trocken).
##
## ECHTES 3D-GARTEN-DIORAMA (FB-4, SnailMailStage3D): Häuschen, Bau, Briefkasten,
## Pfützen und Blumen stehen als 3D-Modelle auf einer Sommerwiese, die
## Postschnecke kriecht als 3D-Figur mit Umschlag den gemalten Weg ab, Gooby
## (echtes Rig) wartet am Briefkasten. Alle Anker gehen als project()-Pixel per
## ground_point-Raycast auf den Boden — Eingabe und MECHANIK bleiben
## zahlengleich in SnailMailLogic (Weltkoordinaten unangetastet).

const Logic := preload("res://scripts/minigames/games/snail_mail/snail_mail_logic.gd")
const Stage := preload("res://scripts/minigames/games/snail_mail/snail_mail_stage3d.gd")

## Der gezeichnete Strich wird erst ab dieser Pixel-Distanz weiter abgetastet.
const INPUT_PX_STEP := 5.0
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var deliveries := 0
## Trocken-Lieferserie (nur Anzeige/Feel — Combo-Ton steigt mit).
var dry_streak := 0
var splashes := 0
var flowers_total := 0
var elapsed := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _level: Dictionary = {}
var _path: Dictionary = {}
var _raw: Array = []
var _drawing := false
var _phase := "draw"
var _arc := 0.0
var _retreat := 0.0
var _beat := 0.0
var _wet := false
var _picked: Array[int] = []
var _snail := {"x": 0.0, "y": -2.35, "angle": 1.5707963267948966}
var _ui := 1.0
var _time_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0
var _stage: Node3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SNAIL, ctx.difficulty)
	rng = ctx.rng()
	_stage = Stage.new()
	_stage.name = "Garten3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_next_level()
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
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		# Erst die Kamera stellen, dann alle Anker auf den Boden raycasten.
		_stage.frame(view_size)
		_layout_stage()
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	var ui := clampf(minf(vp.x, vp.y) / DESIGN_SHORT, 0.75, 3.0)
	var pad := 14.0 * ui
	_time_label.position = Vector2(pad, 8.0 * ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * ui))
	_stat_label.position = Vector2(pad, 44.0 * ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * ui))
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * ui))
	# Der Hinweis ist zweizeilig — genug Luft nach unten lassen.
	_hint_label.position = Vector2(pad, vp.y - 64.0 * ui)
	_hint_label.size = Vector2(maxf(120.0, vp.x - pad * 2.0), 56.0 * ui)


## Alle Level-Anker (Häuser, Pfützen, Blumen, Briefkasten, Feld) als
## project()-Pixel an die Bühne geben — dort raycastet layout_level sie auf
## den Boden. Nach jedem apply_view UND jedem Levelwechsel aufrufen.
func _layout_stage() -> void:
	if _stage == null or _level.is_empty():
		return
	var houses_px: Array = []
	var houses: Array = _level["houses"]
	var target := int(_level["targetIdx"])
	for i in houses.size():
		var h: Dictionary = houses[i]
		var door := Logic.door_of(h, tune)
		(
			houses_px
			. append(
				{
					"px": project(float(h["x"]), float(h["y"])),
					"door_px": project(float(door["x"]), float(door["y"])),
					"kind": str(h.get("kind", "house")),
					"target": i == target,
				}
			)
		)
	var puddles_px: Array = []
	for p: Dictionary in _level["puddles"]:
		(
			puddles_px
			. append(
				{
					"px": project(float(p["x"]), float(p["y"])),
					"edge_px": project(float(p["x"]) + float(p["r"]), float(p["y"])),
				}
			)
		)
	var flowers_px: Array = []
	for f: Dictionary in _level["flowers"]:
		flowers_px.append(project(float(f["x"]), float(f["y"])))
	var post: Dictionary = _level["post"]
	var half_w := float(tune["FIELD_HALF_W"])
	var tl := project(-half_w, float(tune["FIELD_Y_MAX"]))
	var br := project(half_w, float(tune["FIELD_Y_MIN"]))
	_stage.layout_level(
		houses_px,
		puddles_px,
		flowers_px,
		project(float(post["x"]), float(post["y"])),
		Rect2(tl, br - tl)
	)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	match _phase:
		"retreat":
			_retreat = maxf(0.0, _retreat - delta)
			if _retreat <= 0.0:
				_phase = "follow"
		"follow":
			_follow(delta)
		"beat":
			_beat = maxf(0.0, _beat - delta)
			if _beat <= 0.0:
				_next_level()
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## Jeden Frame: Schnecke, (Vorschau-)Weg und gepflückte Blumen an die Bühne.
func _sync_stage(delta: float) -> void:
	if _stage == null or _level.is_empty():
		return
	var pts: Array = []
	if not _path.is_empty():
		pts = _path["pts"]
	elif _drawing and _raw.size() >= 2:
		var preview := Logic.smooth_path(_raw, tune)
		if not preview.is_empty():
			pts = preview["pts"]
	var path_px: Array[Vector2] = []
	for pt: Dictionary in pts:
		path_px.append(project(float(pt["x"]), float(pt["y"])))
	var gone: Array[bool] = []
	var flowers: Array = _level["flowers"]
	for i in flowers.size():
		gone.append(_picked.has(i))
	_stage.sync(
		project(float(_snail["x"]), float(_snail["y"])),
		float(_snail["angle"]),
		_phase,
		path_px,
		gone,
		elapsed,
		delta
	)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _phase != "draw":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(world_from(event.position))
		elif _drawing:
			_drawing = false
			_commit_stroke()
	elif event is InputEventScreenDrag and _drawing:
		_extend_stroke(event.position)


## Weltkoordinate → Bildschirmpixel.
func project(wx: float, wy: float) -> Vector2:
	var s := _world_scale()
	return Vector2(view_size.x * 0.5 + wx * s, _field_center_y() - wy * s)


## Bildschirmpixel → Weltkoordinate (die EINE Eingabe-Grenze).
func world_from(px: Vector2) -> Dictionary:
	var s := _world_scale()
	return {"x": (px.x - view_size.x * 0.5) / s, "y": (_field_center_y() - px.y) / s}


func _world_scale() -> float:
	var half_w := float(tune["FIELD_HALF_W"])
	var span_y := float(tune["FIELD_Y_MAX"]) - float(tune["FIELD_Y_MIN"])
	return minf(view_size.x * 0.94 / (half_w * 2.0), view_size.y * 0.82 / span_y)


func _field_center_y() -> float:
	return view_size.y * (0.54 if not landscape else 0.52)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.snailMail.hint")
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


func _next_level() -> void:
	_level = Logic.generate_level(rng, deliveries, tune)
	_path = {}
	_raw = []
	_arc = 0.0
	_wet = false
	_picked = []
	_phase = "draw"
	var post: Dictionary = _level["post"]
	_snail = {"x": float(post["x"]), "y": float(post["y"]), "angle": PI * 0.5}
	_layout_stage()


func _begin_stroke(world: Dictionary) -> void:
	if not Logic.starts_at_post(world, tune):
		AudioDirector.try_play(self, "ui_error")
		_set_banner(I18nService.t("mg.snailMail.start_at_post"))
		return
	_drawing = true
	_raw = [world]
	AudioDirector.try_play(self, "ui_chip", 1.3)


func _extend_stroke(px: Vector2) -> void:
	if _raw.size() >= int(tune["MAX_INPUT_POINTS"]):
		return
	var world := world_from(px)
	var last: Dictionary = _raw[_raw.size() - 1]
	var dx := float(world["x"]) - float(last["x"])
	var dy := float(world["y"]) - float(last["y"])
	if sqrt(dx * dx + dy * dy) * _world_scale() < INPUT_PX_STEP:
		return
	_raw.append(world)


func _commit_stroke() -> void:
	var path := Logic.smooth_path(_raw, tune)
	if path.is_empty():
		_raw = []
		return
	if Logic.end_house(path, _level, tune) != int(_level["targetIdx"]):
		AudioDirector.try_play(self, "ui_error")
		_set_banner(I18nService.t("mg.snailMail.miss_door"))
		_raw = []
		return
	_path = path
	_arc = 0.0
	_phase = "follow"
	AudioDirector.try_play(self, "ui_confirm")


func _follow(delta: float) -> void:
	var length := float(_path["length"])
	_arc = Logic.advance_arc(_arc, delta, length, tune)
	_snail = Logic.follow_at(_path, _arc)
	var sx := float(_snail["x"])
	var sy := float(_snail["y"])
	if not _wet and Logic.puddle_hit_at(sx, sy, _level["puddles"], tune) >= 0:
		_splash()
		return
	_pick_flowers(sx, sy)
	if _arc >= length:
		_deliver()


func _pick_flowers(sx: float, sy: float) -> void:
	var flowers: Array = _level["flowers"]
	var radius := float(tune["FLOWER_PICK_RADIUS"])
	for i in flowers.size():
		if _picked.has(i):
			continue
		var f: Dictionary = flowers[i]
		var dx := sx - float(f["x"])
		var dy := sy - float(f["y"])
		if sqrt(dx * dx + dy * dy) > radius:
			continue
		_picked.append(i)
		# Jede Blume der Tour klingt einen Halbton höher.
		AudioDirector.try_play(self, "mg_good", 1.2 * FeelSfx.combo_pitch(_picked.size()))
		var pos := project(float(f["x"]), float(f["y"]))
		_stage.flower_fx(pos)
		if ctx.juice != null:
			ctx.juice.float_text(pos, "+%d" % int(tune["FLOWER_PTS"]), Color(1.0, 0.72, 0.85))


func _splash() -> void:
	_wet = true
	dry_streak = 0
	_phase = "retreat"
	_retreat = float(tune["RETREAT_SEC"])
	AudioDirector.try_play(self, "mg_spill")
	_stage.splash_fx(project(float(_snail["x"]), float(_snail["y"])))
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_flash(Color(0.5, 0.65, 0.95, 0.18), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
	_set_banner(I18nService.t("mg.snailMail.splash"))


func _deliver() -> void:
	var points := Logic.delivery_points(_wet, _picked.size(), tune)
	score = Logic.apply_score(score, points)
	deliveries += 1
	flowers_total += _picked.size()
	if _wet:
		splashes += 1
	ctx.report_score(score, points)
	if _wet:
		dry_streak = 0
	else:
		dry_streak += 1
	# Trocken-Serie: jede saubere Lieferung klingt höher.
	AudioDirector.try_play(
		self, "mg_win" if not _wet else "mg_good", FeelSfx.combo_pitch(dry_streak)
	)
	var houses: Array = _level["houses"]
	var door := Logic.door_of(houses[int(_level["targetIdx"])], tune)
	var door_px := project(float(door["x"]), float(door["y"]))
	_stage.deliver_fx(door_px, not _wet)
	if ctx.juice != null:
		var color := Color(0.55, 1.0, 0.7) if not _wet else Color(0.75, 0.86, 1.0)
		ctx.juice.float_text(door_px, "+%d" % points, color)
		ctx.juice.hit_freeze(45)
		if dry_streak >= 2:
			ctx.juice.show_combo(dry_streak)
	_set_banner(
		I18nService.t("mg.snailMail.delivered" if not _wet else "mg.snailMail.delivered_wet")
	)
	if Logic.endless_should_end(splashes, tune):
		_finish()
		return
	_phase = "beat"
	_beat = float(tune["ROUND_BEAT_SEC"])


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
				"deliveries": deliveries,
				"splashes": splashes,
				"flowers": flowers_total,
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.snailMail.splash_count", {"n": splashes, "max": int(tune["ENDLESS_MAX_SPLASHES"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t(
		"mg.snailMail.stats", {"n": deliveries, "flowers": flowers_total}
	)


## Die Bühne rendert den Garten in 3D; als 2D-Overlay bleibt nur der Banner.
func _draw() -> void:
	_draw_banner()


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 380.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.11),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(16, int(24.0 * _ui)),
		Color(0.35, 0.28, 0.2, alpha)
	)
