extends MinigameBase
## Rohr-Wirrwarr (pipeFlow) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## PipeFlowLogic (zahlengleich zum Web, Board-Deals gegen Web-Golddeals
## gepinnt): 5×5-Brett, Antippen dreht eine Kachel 90°, verbundene Leitung vom
## Hahn (oben) zum Sprenger (unten) löst das Rätsel. 90 s; Score = 25·gelöst +
## Tap-Effizienz-Bonus (0–10) − 5 je Leck. Ab Rätsel 3 tropft eine Stelle und
## kostet nach LEAK_SEC fünf Punkte. Endlos endet nach drei Patzern.
##
## ECHTES 3D-ROHRPANEL (FB-4, PipeFlowStage3D): das Blaupausen-Brett steht als
## 3D-Panel im Garten, Kacheln sind echte Rohrstücke, Wasser leuchtet als Kern
## durch die Leitung, unten sprüht der Sprenger ins 3D-Beet und Gooby (echtes
## Rig) schaut zu. Eingabe bleibt zahlengleich (Canvas-Rechtecke), 2D bleibt
## nur der Leck-Countdown-Ring. MECHANIK komplett in PipeFlowLogic.

const WATER := Color("4FD8F7")

const Stage := preload("res://scripts/minigames/games/pipe_flow/pipe_flow_stage3d.gd")

var tune: Dictionary = {}
var board: Dictionary = {}
var puzzle_no := 0
var solved := 0
var failures := 0
## Lösungs-Serie ohne Leck (nur Anzeige/Feel — Combo-Ton steigt mit).
var solve_streak := 0
var total_taps := 0
var optimal_taps := 0
var elapsed := 0.0
var puzzle_elapsed := 0.0
var leak_index := -1
var leak_applied := false
var fill_left := 0.0
var filling := false
var fill_depth := 0
var depths: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _puzzle_label: Label
var _hint_label: Label
var _grid_origin := Vector2.ZERO
var _cell := 60.0
var _pulse := 0.0
var _stage: Node3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = PipeFlowLogic.apply_difficulty(PipeFlowLogic.PIPE, ctx.difficulty)
	_stage = Stage.new()
	_stage.name = "Panel3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_next_puzzle()
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
	var grid := int(PipeFlowLogic.PIPE["GRID"])
	var top := 104.0 if not landscape else 60.0
	var bottom := 62.0
	var avail := Vector2(view_size.x - 24.0, maxf(120.0, view_size.y - top - bottom))
	_cell = minf(avail.x, avail.y) / float(grid)
	var board_px := _cell * grid
	# Etwas oberhalb der Mitte: der Rest unten trägt Fallrohr + Sprenger-Beet,
	# damit im Hochformat keine tote Fläche stehen bleibt.
	_grid_origin = Vector2((view_size.x - board_px) * 0.5, top + (avail.y - board_px) * 0.42)
	_layout_stage()
	_layout_hud()
	queue_redraw()


## Bühne an die aktuellen Brett-Anker hängen (srcCol/goalCol je Rätsel neu!).
func _layout_stage() -> void:
	if _stage == null or board.is_empty():
		return
	_stage.frame(view_size)
	_stage.layout(
		_grid_origin,
		_cell,
		int(board["size"]),
		int(board["srcCol"]),
		int(board["goalCol"]),
		_bed_y()
	)


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0)
	_puzzle_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 180.0, vp.y - 42.0)
	_hint_label.size = Vector2(360.0, 34.0)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_puzzle_label = Label.new()
	_puzzle_label.theme_type_variation = &"CaptionLabel"
	add_child(_puzzle_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.pipeFlow.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _next_puzzle() -> void:
	puzzle_no += 1
	# Dieselbe Deal-Formel wie der Zertifizierungs-Bot: seed·1009 + Rätselnummer.
	board = PipeFlowLogic.generate_board(ctx.run_seed * 1009 + puzzle_no, tune)
	optimal_taps += int(board["optimalTaps"])
	leak_index = PipeFlowLogic.leak_joint_for(board, puzzle_no, tune)
	leak_applied = false
	puzzle_elapsed = 0.0
	filling = false
	fill_depth = 0
	depths = {}
	_layout_stage()
	_update_labels()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	puzzle_elapsed += delta
	_pulse += delta
	if filling:
		_fill_tick(delta)
	elif leak_index >= 0 and PipeFlowLogic.leak_penalty_due(puzzle_elapsed, leak_applied, tune):
		_apply_leak()
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if PipeFlowLogic.endless_should_end(failures, tune):
		_finish()
		return
	var tiles: Array = board["tiles"]
	var watered: Array[bool] = []
	for i in tiles.size():
		watered.append(_tile_watered(i))
	var leak_pending := leak_index if (leak_index >= 0 and not leak_applied and not filling) else -1
	_stage.sync(tiles, watered, filling, leak_pending, _pulse, delta)
	_update_labels()
	queue_redraw()


## Wasser läuft in BFS-Tiefenschritten durch die verbundene Leitung.
func _fill_tick(delta: float) -> void:
	fill_left -= delta
	if fill_left > 0.0:
		return
	var max_depth := 0
	for value: int in depths.values():
		max_depth = maxi(max_depth, value)
	if fill_depth <= max_depth:
		fill_depth += 1
		fill_left = float(tune["FILL_STEP_SEC"])
		# Wasserlauf klettert hörbar die Tonleiter hoch (Halbton pro Stufe).
		AudioDirector.try_play(self, "mg_good", 0.9 * FeelSfx.combo_pitch(fill_depth))
		return
	filling = false
	fill_left = 0.0
	_next_puzzle()


func _apply_leak() -> void:
	leak_applied = true
	failures += 1
	solve_streak = 0
	_stage.leak_fx(leak_index)
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_flash(Color(0.5, 0.65, 0.95, 0.18), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
		ctx.juice.float_text(
			_cell_center(leak_index), I18nService.t("mg.pipeFlow.leak"), AcTokens.DANGER
		)
	ctx.report_score(_live_score(), -int(tune["LEAK_PENALTY"]))


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or filling:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var index := _cell_at((event as InputEventScreenTouch).position)
	if index < 0:
		return
	var tiles: Array = board["tiles"]
	tiles[index] = PipeFlowLogic.rotate_tile(tiles[index])
	total_taps += 1
	AudioDirector.try_play(self, "ui_chip", 1.0 + 0.04 * float(index % 5))
	var reach := PipeFlowLogic.water_reach(board)
	if bool(reach["solved"]):
		_solve(reach)
	queue_redraw()


func _solve(reach: Dictionary) -> void:
	solved += 1
	solve_streak += 1
	depths = reach["depths"]
	filling = true
	fill_depth = 0
	fill_left = 0.0
	var grid := int(board["size"])
	_stage.solve_fx((grid - 1) * grid + int(board["goalCol"]))
	# Lösungs-Serie ohne Leck: Sieges-Ton klettert pro Puzzle.
	AudioDirector.try_play(self, "mg_win", FeelSfx.combo_pitch(solve_streak))
	if ctx.juice != null:
		var banner_pos := Vector2(view_size.x * 0.5 - 110.0, _grid_origin.y - 6.0)
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.hit_freeze(70)
		ctx.juice.float_text(banner_pos, I18nService.t("mg.pipeFlow.solved"), AcTokens.TEAL_DARK)
		var size := int(board["size"])
		var goal_center := _cell_center((size - 1) * size + int(board["goalCol"]))
		ctx.juice.ring_burst(self, goal_center, AcTokens.TEAL_DARK, 90.0)
		ctx.juice.burst(self, goal_center, Color(0.5, 0.85, 0.95), 16)
		if solve_streak >= 2:
			ctx.juice.show_combo(solve_streak)
	ctx.report_score(_live_score(), int(tune["SOLVE_POINTS"]))


func _live_score() -> int:
	return PipeFlowLogic.pipe_score(solved, total_taps, optimal_taps, tune, failures)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end(
		{"score": _live_score(), "solved": solved, "failures": failures, "taps": total_taps}
	)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.pipeFlow.failures", {"n": failures, "max": int(tune["ENDLESS_FAILURE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_puzzle_label.text = (
		"%s · %s"
		% [
			I18nService.t("mg.pipeFlow.puzzle", {"n": puzzle_no}),
			I18nService.t("mg.pipeFlow.taps", {"n": total_taps}),
		]
	)


func _cell_at(screen: Vector2) -> int:
	var grid := int(board["size"])
	var local := screen - _grid_origin
	if local.x < 0.0 or local.y < 0.0:
		return -1
	var col := int(local.x / _cell)
	var row := int(local.y / _cell)
	if col < 0 or col >= grid or row < 0 or row >= grid:
		return -1
	return row * grid + col


func _cell_center(index: int) -> Vector2:
	var grid := int(board["size"])
	var col := index % grid
	var row := index / grid
	return _grid_origin + Vector2((col + 0.5) * _cell, (row + 0.5) * _cell)


func _tile_watered(index: int) -> bool:
	return filling and depths.has(index) and int(depths[index]) < fill_depth


# Kein 2D-Brett mehr: Panel, Rohre, Hahn, Sprenger, Beet und Gooby rendert
# die 3D-Bühne (PipeFlowStage3D); 2D bleibt nur der Leck-Countdown-Ring.
func _draw() -> void:
	if leak_index >= 0 and not leak_applied and not filling:
		_draw_leak()


## Oberkante des Blumenbeets am unteren Bildrand.
func _bed_y() -> float:
	return view_size.y - (132.0 if not landscape else 76.0)


func _draw_leak() -> void:
	var center := _cell_center(leak_index)
	var due := float(tune["LEAK_SEC"])
	var ratio := clampf(puzzle_elapsed / maxf(0.35, due), 0.0, 1.0)
	draw_arc(center, _cell * 0.42, -PI * 0.5, -PI * 0.5 + TAU * ratio, 26, AcTokens.DANGER, 4.0)
	var drop := fmod(_pulse * 40.0, _cell * 0.5)
	draw_circle(center + Vector2(0.0, drop), 4.0, WATER)
