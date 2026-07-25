extends MinigameBase
## Rohr-Wirrwarr (pipeFlow) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## PipeFlowLogic (zahlengleich zum Web, Board-Deals gegen Web-Golddeals
## gepinnt): 5×5-Brett, Antippen dreht eine Kachel 90°, verbundene Leitung vom
## Hahn (oben) zum Sprenger (unten) löst das Rätsel. 90 s; Score = 25·gelöst +
## Tap-Effizienz-Bonus (0–10) − 5 je Leck. Ab Rätsel 3 tropft eine Stelle und
## kostet nach LEAK_SEC fünf Punkte. Endlos endet nach drei Patzern.
## Optik: Kachelbrett auf Papier, Wasser füllt die Leitung in BFS-Reihenfolge.

## Blaupausen-Palette 1:1 aus dem Web (pipeFlow.js `COLORS`): dunkles
## Planblatt, kreideweiße Rohre, Türkis-Wasser, Messing für Hahn & Sprenger.
const WATER := Color("4FD8F7")
const PIPE_BODY := Color("E8F1FB")
const PIPE_EDGE := Color("2B5F9E")
const SHEET := Color("1D4E89")
const SHEET_DEEP := Color("173F70")
const SHEET_LINE := Color(1.0, 1.0, 1.0, 0.10)
const BRASS := Color("F2C14E")
const BRASS_DARK := Color("C79A33")

var tune: Dictionary = {}
var board: Dictionary = {}
var puzzle_no := 0
var solved := 0
var failures := 0
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


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = PipeFlowLogic.apply_difficulty(PipeFlowLogic.PIPE, ctx.difficulty)
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
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_puzzle_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 180.0, view_size.y - 42.0)
		_hint_label.size = Vector2(360.0, 34.0)
	queue_redraw()


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
		AudioDirector.try_play(self, "mg_good", 0.9 + 0.02 * float(fill_depth))
		return
	filling = false
	fill_left = 0.0
	_next_puzzle()


func _apply_leak() -> void:
	leak_applied = true
	failures += 1
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
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
	depths = reach["depths"]
	filling = true
	fill_depth = 0
	fill_left = 0.0
	AudioDirector.try_play(self, "mg_win")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.hit_freeze(70)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 110.0, _grid_origin.y - 6.0),
			I18nService.t("mg.pipeFlow.solved"),
			AcTokens.TEAL_DARK
		)
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), AcTokens.BG_CREAM)
	var grid := int(board["size"])
	var board_px := _cell * grid
	var frame := Rect2(_grid_origin - Vector2(12.0, 12.0), Vector2.ONE * (board_px + 24.0))
	# Steig- und Fallrohr füllen den Raum über/unter dem Brett.
	_draw_feed_pipe(frame)
	_draw_drain_pipe(frame)
	draw_rect(frame, SHEET_DEEP)
	draw_rect(Rect2(frame.position + Vector2(4.0, 4.0), frame.size - Vector2(8.0, 8.0)), SHEET)
	for i in range(1, grid):
		var at := _grid_origin + Vector2.ONE * (_cell * i)
		draw_line(
			Vector2(_grid_origin.x, at.y), Vector2(_grid_origin.x + board_px, at.y), SHEET_LINE, 2.0
		)
		draw_line(
			Vector2(at.x, _grid_origin.y), Vector2(at.x, _grid_origin.y + board_px), SHEET_LINE, 2.0
		)
	draw_rect(frame, AcTokens.INK, false, 3.0)
	var tiles: Array = board["tiles"]
	for i in tiles.size():
		_draw_tile(i, tiles[i])
	_draw_tap(frame)
	_draw_sprinkler(frame)
	if leak_index >= 0 and not leak_applied and not filling:
		_draw_leak()


func _draw_tile(index: int, tile: Dictionary) -> void:
	var grid := int(board["size"])
	var col := index % grid
	var row := index / grid
	var pos := _grid_origin + Vector2(col * _cell, row * _cell)
	var center := pos + Vector2.ONE * (_cell * 0.5)
	var watered := _tile_watered(index)
	var thickness := _cell * 0.3
	var mask := PipeFlowLogic.mask_of(str(tile["shape"]), int(tile["rot"]))
	var fill := WATER if watered else PIPE_BODY
	# Zuerst die dunkle Kontur (Arme + runde Nabe), dann der helle Rohrkern —
	# so wirkt jede Kachel als EIN durchgehendes Rohrstück, nicht als Loch.
	for pass_index in 2:
		var tint := PIPE_EDGE if pass_index == 0 else fill
		var width := thickness + 7.0 if pass_index == 0 else thickness
		for dir in 4:
			if (mask & (1 << dir)) == 0:
				continue
			var step: Vector2i = PipeFlowLogic.DELTA[dir]
			draw_line(center, center + Vector2(step.x, step.y) * (_cell * 0.5), tint, width)
		draw_circle(center, width * 0.5, tint)
	if watered:
		var glow := thickness * 0.5 + 4.0 + sin(_pulse * 8.0) * 2.0
		draw_circle(center, glow, Color(WATER.r, WATER.g, WATER.b, 0.28))
	else:
		# Kreide-Glanzlicht auf dem Rohrrücken.
		draw_circle(
			center - Vector2(thickness * 0.16, thickness * 0.16),
			thickness * 0.16,
			Color(1, 1, 1, 0.7)
		)


## Zulauf: Messinghahn am oberen Bildrand, Steigrohr bis zur Quellspalte.
func _draw_feed_pipe(frame: Rect2) -> void:
	var x := _grid_origin.x + (float(board["srcCol"]) + 0.5) * _cell
	var head_y := maxf(96.0, frame.position.y - 96.0)
	draw_line(Vector2(x, head_y), Vector2(x, frame.position.y + 6.0), PIPE_EDGE, 24.0)
	draw_line(Vector2(x, head_y), Vector2(x, frame.position.y + 6.0), Color("B9C9DC"), 16.0)
	if filling:
		draw_line(Vector2(x, head_y), Vector2(x, frame.position.y + 6.0), WATER, 9.0)


## Oberkante des Blumenbeets am unteren Bildrand.
func _bed_y() -> float:
	return view_size.y - (132.0 if not landscape else 76.0)


func _draw_drain_pipe(frame: Rect2) -> void:
	var x := _grid_origin.x + (float(board["goalCol"]) + 0.5) * _cell
	var bed_y := _bed_y()
	draw_line(Vector2(x, frame.end.y - 6.0), Vector2(x, bed_y), PIPE_EDGE, 24.0)
	draw_line(Vector2(x, frame.end.y - 6.0), Vector2(x, bed_y), Color("B9C9DC"), 16.0)
	if filling:
		draw_line(Vector2(x, frame.end.y - 6.0), Vector2(x, bed_y), WATER, 9.0)


func _draw_tap(frame: Rect2) -> void:
	var x := _grid_origin.x + (float(board["srcCol"]) + 0.5) * _cell
	var y := maxf(100.0, frame.position.y - 104.0)
	var s := clampf(_cell * 0.42, 30.0, 52.0)
	# Wandkonsole + Messing-Handrad; es dreht sich, sobald Wasser läuft.
	draw_rect(Rect2(x - s * 1.5, y - s * 1.1, s * 3.0, s * 0.4), Color("9FB1C6"))
	draw_rect(Rect2(x - s * 1.5, y - s * 1.1, s * 3.0, s * 0.4), AcTokens.INK, false, 3.0)
	var body := Rect2(x - s * 0.72, y - s * 0.7, s * 1.44, s * 0.95)
	draw_rect(body, BRASS)
	draw_rect(body, AcTokens.INK, false, 3.0)
	var hub := Vector2(x, y - s * 1.5)
	var spin: float = _pulse * 5.0 if filling else 0.0
	for i in 3:
		var a := spin + TAU * float(i) / 3.0
		draw_line(hub, hub + Vector2(cos(a), sin(a)) * s * 0.9, BRASS_DARK, 9.0)
		draw_line(hub, hub + Vector2(cos(a), sin(a)) * s * 0.9, BRASS, 5.0)
	draw_circle(hub, s * 0.32, BRASS_DARK)
	draw_arc(hub, s * 0.32, 0.0, TAU, 16, AcTokens.INK, 3.0)


## Ablauf: Sprenger im Blumenbeet — das Ziel wird so als Ort lesbar.
func _draw_sprinkler(_frame: Rect2) -> void:
	var x := _grid_origin.x + (float(board["goalCol"]) + 0.5) * _cell
	var bed_y := _bed_y()
	draw_rect(Rect2(0.0, bed_y, view_size.x, view_size.y - bed_y), Color("8FD06C"))
	draw_rect(Rect2(0.0, bed_y + 34.0, view_size.x, view_size.y - bed_y - 34.0), Color("6E4A32"))
	draw_line(Vector2(0.0, bed_y), Vector2(view_size.x, bed_y), AcTokens.INK, 3.0)
	draw_line(Vector2(0.0, bed_y + 34.0), Vector2(view_size.x, bed_y + 34.0), Color("533826"), 3.0)
	var tints: Array[Color] = [AcTokens.PINK, AcTokens.YELLOW, AcTokens.TEAL, AcTokens.WHITE]
	for i in 8:
		var fx := (float(i) + 0.5) / 8.0 * view_size.x
		if absf(fx - x) < 52.0:
			continue
		draw_line(Vector2(fx, bed_y + 30.0), Vector2(fx, bed_y - 8.0), Color("4E8F3C"), 4.0)
		for k in 5:
			var a := float(k) * TAU / 5.0
			draw_circle(
				Vector2(fx, bed_y - 10.0) + Vector2(cos(a), sin(a)) * 9.0,
				7.0,
				tints[i % tints.size()]
			)
		draw_circle(Vector2(fx, bed_y - 10.0), 6.0, AcTokens.YELLOW)
	# Sprengerkopf auf einem Messingfuß.
	var head := Rect2(x - 30.0, bed_y - 40.0, 60.0, 44.0)
	draw_rect(head, AcTokens.TEAL)
	draw_rect(head, AcTokens.INK, false, 3.0)
	draw_rect(Rect2(x - 40.0, bed_y - 6.0, 80.0, 14.0), BRASS)
	draw_rect(Rect2(x - 40.0, bed_y - 6.0, 80.0, 14.0), AcTokens.INK, false, 3.0)
	if not filling:
		return
	for i in 7:
		var a := -PI * 0.92 + float(i) * (PI * 0.84 / 6.0)
		var reach := 56.0 + sin(_pulse * 9.0 + float(i)) * 16.0
		var from := Vector2(x, bed_y - 40.0)
		draw_line(
			from,
			from + Vector2(cos(a), sin(a)) * reach,
			Color(WATER.r, WATER.g, WATER.b, 0.85),
			5.0
		)


func _draw_leak() -> void:
	var center := _cell_center(leak_index)
	var due := float(tune["LEAK_SEC"])
	var ratio := clampf(puzzle_elapsed / maxf(0.35, due), 0.0, 1.0)
	draw_arc(center, _cell * 0.42, -PI * 0.5, -PI * 0.5 + TAU * ratio, 26, AcTokens.DANGER, 4.0)
	var drop := fmod(_pulse * 40.0, _cell * 0.5)
	draw_circle(center + Vector2(0.0, drop), 4.0, WATER)
