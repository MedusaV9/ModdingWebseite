extends MinigameBase
## GvZ-Spielszene (W3b) im W2d-Minigame-Contract: Level-Select → Gefecht →
## Sieg/Niederlage, alles über der PUREN Simulation (GvzLogic — die Szene
## rendert nur State und ruft Aktions-Funktionen). Querformat bevorzugt,
## Hochkant skaliert das Grid. Steuerung: Karte antippen ODER ziehen
## (Drag-Ghost), Klecks antippen = einsammeln, Schaufel entfernt Türme.
## Punkte laufen NUR über ctx.report_score/report_end (Award macht der Host).

const TICK_SEC := 0.05
const CARD_W := 56.0
const CARD_H := 62.0
const TOP_PAD := 6.0
const MOWER_GUTTER := 44.0
const BANNER_SEC := 2.2

## Testschalter: GameState-Double VOR setup() setzen (Muster W2a RoomBase).
var game_state_override: Object

var balance: Dictionary = {}
var levels: Array = []
var phase := "select"
var state: Dictionary = {}
var level_id := 0
var attempt := 0
var session_score := 0
var selected_card := ""
var drag_pos := Vector2.ZERO
var dragging := false
var ended := false

var _accum := 0.0
var _banner_text := ""
var _banner_until := 0.0
var _last_run_score := 0
var _prev_zombie_pos: Dictionary = {}
var _poofs: Array = []
var _select_screen: GvzLevelSelect
var _overlay: Control
var _font: Font
var _font_bold: Font


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	GvzProgress.register_slice()
	balance = GvzData.load_balance(null)
	levels = GvzData.load_levels()
	_font = ThemeService.font(600)
	_font_bold = ThemeService.font(800)
	_build_select_screen()
	queue_redraw()


func start() -> void:
	super.start()
	queue_redraw()


func end() -> void:
	super.end()
	ended = true


## ── Phasen-Wechsel ───────────────────────────────────────────────────────


func open_level(id: int) -> void:
	level_id = id
	attempt += 1
	var level := GvzData.level_by_id(levels, id)
	var seed_value := ctx.run_seed + id * 1009 + attempt * 131 if ctx != null else id
	var opts := {"goldi": GvzProgress.goldi_unlocked(_game_state())}
	state = GvzLogic.new_run(level, balance, _difficulty(), seed_value, opts)
	phase = "battle"
	selected_card = ""
	dragging = false
	_accum = 0.0
	_last_run_score = 0
	_prev_zombie_pos = {}
	_poofs = []
	_show_banner(I18nService.t("gvz.hud.level", {"n": id}))
	if _select_screen != null:
		_select_screen.visible = false
	_clear_overlay()
	queue_redraw()


func back_to_select() -> void:
	phase = "select"
	state = {}
	_clear_overlay()
	if _select_screen != null:
		_select_screen.visible = true
		_select_screen.refresh()
	queue_redraw()


func finish_session() -> void:
	if ended or ctx == null:
		return
	ended = true
	(
		ctx
		. report_end(
			{
				"score": session_score,
				"stars": GvzProgress.total_stars(_game_state()),
				"levels": GvzProgress.max_unlocked(_game_state()) - 1,
			}
		)
	)


## ── Simulation ───────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if not is_active() or phase != "battle" or state.is_empty():
		return
	_accum += minf(delta, 0.25)
	while _accum >= TICK_SEC and not GvzLogic.is_over(state):
		_accum -= TICK_SEC
		_remember_zombie_positions()
		var events := GvzLogic.tick(state)
		_consume_events(events)
	_decay_poofs(delta)
	_report_live_score()
	if GvzLogic.is_over(state):
		_on_run_over()
	queue_redraw()


func _consume_events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event["kind"]):
			"wave":
				var key := "gvz.hud.huge_wave" if bool(event["huge"]) else "gvz.hud.wave"
				_show_banner(I18nService.t(key, {"n": int(event["n"])}))
				if ctx != null and ctx.juice != null and bool(event["huge"]):
					ctx.juice.shake(0.35)
			"boss_enter":
				_show_banner(I18nService.t("gvz.hud.boss"))
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.6)
			"boss_phase":
				_show_banner(I18nService.t("gvz.hud.boss_phase", {"n": int(event["phase"])}))
				if ctx != null and ctx.juice != null:
					ctx.juice.hit_freeze(110)
					ctx.juice.shake(0.5)
			"mower":
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.55)
			"die":
				_spawn_poof(int(event["id"]), "die")
			"pop":
				_spawn_poof(int(event["id"]), "pop")
			"collect":
				if ctx != null and ctx.juice != null:
					var at := _cell_center(int(event["lane"]), int(event["col"]))
					ctx.juice.float_text(
						at, "+%d" % int(event["amount"]), GvzArt.NUTELLA.lightened(0.35)
					)
			"blast":
				(
					_poofs
					. append(
						{
							"pos": _cell_center(int(event["lane"]), int(event["col"])),
							"ttl": 0.35,
							"kind": "blast",
						}
					)
				)
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.3)


func _report_live_score() -> void:
	if ctx == null or state.is_empty():
		return
	var run_score := int(state["score"])
	if run_score != _last_run_score:
		ctx.report_score(session_score + run_score, run_score - _last_run_score)
		_last_run_score = run_score


func _on_run_over() -> void:
	if phase != "battle":
		return
	if str(state["outcome"]) == "won":
		var mowers_used := 0
		for lane: Variant in state["mowers"]:
			if bool(state["mowers"][lane]["used"]):
				mowers_used += 1
		var stars := GvzProgress.stars_for(mowers_used)
		var booking := GvzProgress.record_win(_game_state(), level_id, stars, int(state["score"]))
		var total := GvzProgress.final_score(
			int(state["score"]), level_id, stars, bool(booking["first_clear"]), balance
		)
		session_score += total
		if ctx != null:
			ctx.report_score(session_score, total - _last_run_score)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
		phase = "won"
		_build_end_overlay(true, stars, total, bool(booking["first_clear"]))
	else:
		phase = "lost"
		if ctx != null and ctx.juice != null:
			ctx.juice.shake(0.7)
		_build_end_overlay(false, 0, 0, false)
	queue_redraw()


## ── Eingabe (Gefecht) ────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or phase != "battle" or state.is_empty():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.position)
		else:
			_touch_up(event.position)
	elif event is InputEventScreenDrag:
		drag_pos = event.position
		queue_redraw()


func _touch_down(at: Vector2) -> void:
	var card := _card_at(at)
	if card != "":
		selected_card = card if selected_card != card else ""
		dragging = selected_card != ""
		drag_pos = at
		queue_redraw()
		return
	if _collect_drop_at(at):
		return
	if selected_card != "":
		_apply_card(at)
		return


func _touch_up(at: Vector2) -> void:
	if dragging:
		dragging = false
		if _cell_at(at).x >= 0 and selected_card != "":
			_apply_card(at)
		queue_redraw()


func _apply_card(at: Vector2) -> void:
	var cell := _cell_at(at)
	if cell.x < 0:
		return
	if selected_card == "shovel":
		if GvzLogic.remove_tower(state, cell.y, cell.x):
			selected_card = ""
		queue_redraw()
		return
	var placed := GvzLogic.place_tower(state, selected_card, cell.y, cell.x)
	if bool(placed["ok"]):
		selected_card = ""
	elif ctx != null and ctx.juice != null:
		var key := "gvz.hud.reason_%s" % str(placed["reason"])
		if I18nService.has_key(key):
			ctx.juice.float_text(at - Vector2(0, 30), I18nService.t(key), GvzArt.BERRY_RED)
	queue_redraw()


func _collect_drop_at(at: Vector2) -> bool:
	var best_id := -1
	var best_d := 40.0
	for drop: Dictionary in state["drops"]:
		var pos := _cell_center(int(drop["lane"]), int(drop["col"]))
		var d := pos.distance_to(at)
		if d < best_d:
			best_d = d
			best_id = int(drop["id"])
	if best_id < 0:
		return false
	GvzLogic.collect_drop(state, best_id)
	queue_redraw()
	return true


## ── Layout ───────────────────────────────────────────────────────────────


func _view_size() -> Vector2:
	return get_viewport_rect().size


func _card_list() -> Array:
	if state.is_empty():
		return []
	var out: Array = []
	if _conveyor_active() and not bool(state["mods"].get("conveyor_hybrid", false)):
		for type: Variant in state["conveyor"]["queue"]:
			out.append(str(type))
	else:
		out = GvzLogic.available_towers(state)
	out.append("shovel")
	return out


func _card_rows() -> int:
	var vp := _view_size()
	var cards := _card_list().size()
	var per_row := int((vp.x - 96.0) / CARD_W)
	return 1 if cards <= per_row else 2


func _card_rect(index: int) -> Rect2:
	var vp := _view_size()
	var per_row := maxi(1, int((vp.x - 96.0) / CARD_W))
	var row := index / per_row
	var col := index % per_row
	return Rect2(
		Vector2(90.0 + col * CARD_W, TOP_PAD + row * (CARD_H * 0.82)), Vector2(CARD_W - 4.0, CARD_H)
	)


func _card_at(at: Vector2) -> String:
	var cards := _card_list()
	for i in cards.size():
		if _card_rect(i).has_point(at):
			return str(cards[i])
	return ""


func _field_rect() -> Rect2:
	var vp := _view_size()
	var top := TOP_PAD + CARD_H * (0.82 * (_card_rows() - 1) + 1.0) + 8.0
	return Rect2(MOWER_GUTTER, top, vp.x - MOWER_GUTTER - 6.0, vp.y - top - 8.0)


func _cell_size() -> Vector2:
	var field := _field_rect()
	return Vector2(field.size.x / GvzLogic.COLS, field.size.y / 5.0)


## Zelle unter einem Punkt als (col, lane); (-1,-1) außerhalb.
func _cell_at(at: Vector2) -> Vector2i:
	var field := _field_rect()
	if not field.has_point(at):
		return Vector2i(-1, -1)
	var cell := _cell_size()
	return Vector2i(
		clampi(int((at.x - field.position.x) / cell.x), 0, GvzLogic.COLS - 1),
		clampi(int((at.y - field.position.y) / cell.y), 0, 4)
	)


func _cell_center(lane: int, col: int) -> Vector2:
	var field := _field_rect()
	var cell := _cell_size()
	return field.position + Vector2((col + 0.5) * cell.x, (lane + 0.5) * cell.y)


func _x_to_px(x: int) -> float:
	var field := _field_rect()
	return field.position.x + float(x) / float(GvzLogic.COLS * GvzLogic.CELL_MM) * field.size.x


## ── Zeichnen ─────────────────────────────────────────────────────────────


func _draw() -> void:
	var vp := _view_size()
	draw_rect(Rect2(Vector2.ZERO, vp), AcTokens.BG_CREAM)
	if phase == "select":
		return
	if state.is_empty():
		return
	_draw_field()
	_draw_drops()
	_draw_towers()
	_draw_zombies()
	_draw_boss()
	_draw_projectiles()
	_draw_poofs()
	_draw_mowers()
	_draw_hud()
	_draw_ghost()
	_draw_banner()
	if phase != "battle":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.29, 0.23, 0.21, 0.35))


func _draw_field() -> void:
	var field := _field_rect()
	var cell := _cell_size()
	var night := bool(state["mods"].get("night", false))
	var base_a := Color("#BCE39B") if not night else Color("#8FAF87")
	var base_b := Color("#ABD689") if not night else Color("#7FA079")
	for lane in 5:
		for col in GvzLogic.COLS:
			var tone := base_a if (lane + col) % 2 == 0 else base_b
			draw_rect(
				Rect2(field.position + Vector2(col * cell.x, lane * cell.y), cell + Vector2.ONE),
				tone
			)
	# Haus-Seite (links): warmer Holz-Steg für die Panik-Goobys.
	draw_rect(Rect2(0, field.position.y, MOWER_GUTTER, field.size.y), Color("#EAD9B0"))
	draw_rect(Rect2(MOWER_GUTTER - 4, field.position.y, 4, field.size.y), GvzArt.WOOD)
	if bool(state["mods"].get("fog", false)):
		var fog_x := _x_to_px(6 * GvzLogic.CELL_MM)
		draw_rect(
			Rect2(fog_x, field.position.y, field.end.x - fog_x, field.size.y),
			Color(0.85, 0.88, 0.92, 0.55)
		)


func _draw_towers() -> void:
	var cell := _cell_size()
	var s := cell.y * 0.86
	var tick := int(state["tick"])
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		var feet := _cell_center(int(tower["lane"]), int(tower["col"])) + Vector2(0, cell.y * 0.4)
		GvzArt.draw_tower(self, str(tower["type"]), feet, s, tick)
		var hp := float(tower["hp"]) / float(tower["max_hp"])
		if hp < 0.99:
			_draw_bar(
				feet + Vector2(-cell.x * 0.3, -cell.y * 0.95), cell.x * 0.6, hp, GvzArt.MELON_GREEN
			)


func _draw_zombies() -> void:
	var cell := _cell_size()
	var s := cell.y * 0.9
	var tick := int(state["tick"])
	for zombie: Dictionary in state["zombies"]:
		if bool(zombie["dead"]):
			continue
		var feet := Vector2(
			_x_to_px(int(zombie["x"])),
			_field_rect().position.y + (int(zombie["lane"]) + 1) * cell.y - 3.0
		)
		GvzArt.draw_zombie(self, str(zombie["type"]), feet, s, tick, zombie)
		var total := int(zombie["hp"]) + int(zombie["armor_hp"])
		var max_total := int(zombie["max_hp"]) + int(zombie.get("armor_hp", 0))
		if total < int(zombie["max_hp"]):
			_draw_bar(
				feet + Vector2(-cell.x * 0.25, -cell.y * 1.02),
				cell.x * 0.5,
				float(total) / float(maxi(1, max_total)),
				GvzArt.BERRY_RED
			)


func _draw_boss() -> void:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return
	var cell := _cell_size()
	var feet := Vector2(
		_x_to_px(int(boss["x"])), _field_rect().position.y + (int(boss["lane"]) + 1) * cell.y - 2.0
	)
	GvzArt.draw_boss(self, feet, cell.y * 1.5, int(state["tick"]), boss)


func _draw_projectiles() -> void:
	var cell := _cell_size()
	for proj: Dictionary in state["projectiles"]:
		var pos := Vector2(
			_x_to_px(int(proj["x"])), _field_rect().position.y + (int(proj["lane"]) + 0.42) * cell.y
		)
		GvzArt.draw_projectile(self, str(proj["kind"]), pos, cell.y)


func _draw_drops() -> void:
	var cell := _cell_size()
	var tick := int(state["tick"])
	for drop: Dictionary in state["drops"]:
		var pos := _cell_center(int(drop["lane"]), int(drop["col"])) + Vector2(0, cell.y * 0.3)
		GvzArt.draw_nutella_drop(self, pos, cell.y * 0.8, tick + int(drop["id"]))


func _draw_mowers() -> void:
	var cell := _cell_size()
	var field := _field_rect()
	for lane: Variant in state["mowers"]:
		var mower: Dictionary = state["mowers"][lane]
		var feet := Vector2(MOWER_GUTTER * 0.5, field.position.y + (int(lane) + 1) * cell.y - 4.0)
		if bool(mower["active"]):
			feet.x = _x_to_px(int(mower["x"]))
			GvzArt.draw_mower(self, feet, cell.y * 0.9, int(state["tick"]), false)
		else:
			GvzArt.draw_mower(self, feet, cell.y * 0.78, int(state["tick"]), bool(mower["used"]))


func _draw_poofs() -> void:
	for poof: Dictionary in _poofs:
		var t := 1.0 - float(poof["ttl"]) / 0.35
		var pos: Vector2 = poof["pos"]
		match str(poof["kind"]):
			"blast":
				draw_arc(pos, 12.0 + t * 34.0, 0, TAU, 20, Color(1.0, 0.7, 0.3, 0.8 - t * 0.8), 6.0)
			"pop":
				draw_arc(
					pos, 6.0 + t * 18.0, 0, TAU, 12, Color(0.95, 0.55, 0.5, 0.9 - t * 0.9), 3.0
				)
			_:
				for i in 4:
					var a := TAU * i / 4.0 + t * 2.0
					var p := pos + Vector2(cos(a), sin(a)) * (6.0 + t * 16.0)
					draw_circle(p, 3.5 - t * 3.0, Color(1, 1, 1, 0.8 - t * 0.8))


func _draw_hud() -> void:
	# Nutella-Zähler.
	var counter := Rect2(6, TOP_PAD, 78, CARD_H)
	_rounded(counter, AcTokens.PAPER)
	GvzArt.draw_nutella_drop(self, counter.position + Vector2(22, 44), 34, int(state["tick"]))
	draw_string(
		_font_bold,
		counter.position + Vector2(38, 38),
		str(state["nutella"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		17,
		AcTokens.INK
	)
	var cards := _card_list()
	var queue: Array = state["conveyor"].get("queue", []) if _conveyor_active() else []
	var conveyor_only := (
		_conveyor_active() and not bool(state["mods"].get("conveyor_hybrid", false))
	)
	for i in cards.size():
		_draw_card(str(cards[i]), _card_rect(i), conveyor_only or queue.has(str(cards[i])))
	if _conveyor_active() and not conveyor_only:
		_draw_conveyor_strip(queue)
	_draw_boss_bar()


func _draw_card(type: String, rect: Rect2, from_belt: bool) -> void:
	var cost := GvzLogic.tower_cost(state, type) if type != "shovel" else 0
	var cooldown := GvzLogic.cooldown_left(state, type) if type != "shovel" else 0
	var affordable := type == "shovel" or from_belt or int(state["nutella"]) >= cost
	var fill := AcTokens.PAPER if affordable and cooldown == 0 else AcTokens.PAPER_SHADE
	_rounded(rect, fill)
	if selected_card == type:
		draw_rect(rect, AcTokens.PINK, false, 3.0)
	if type == "shovel":
		_draw_shovel_icon(rect.get_center())
	else:
		GvzArt.draw_tower(
			self, type, rect.get_center() + Vector2(0, rect.size.y * 0.28), rect.size.y * 0.6, 0
		)
		var label := "◦%d" % cost if not from_belt else I18nService.t("gvz.hud.free")
		draw_string(
			_font,
			rect.position + Vector2(4, 14),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(rect.size.x) - 8,
			11,
			AcTokens.INK if affordable else GvzArt.BERRY_RED
		)
	if cooldown > 0 and not from_belt:
		var total := int(balance["towers"].get(type, {}).get("cooldown_ticks", 1))
		var left := float(cooldown) / float(maxi(1, total))
		draw_rect(
			Rect2(rect.position, Vector2(rect.size.x, rect.size.y * left)),
			Color(0.29, 0.23, 0.21, 0.35)
		)


func _draw_shovel_icon(at: Vector2) -> void:
	draw_line(at + Vector2(-8, -14), at + Vector2(8, 6), GvzArt.WOOD, 5.0)
	var points := PackedVector2Array(
		[at + Vector2(4, 2), at + Vector2(16, 10), at + Vector2(8, 18)]
	)
	draw_colored_polygon(points, GvzArt.METAL)


func _draw_conveyor_strip(queue: Array) -> void:
	var vp := _view_size()
	var w := 34.0
	var x := vp.x - 8.0 - w * maxf(1.0, float(queue.size()))
	var strip := Rect2(x, TOP_PAD + CARD_H + 2.0, w * maxf(1.0, float(queue.size())), 30.0)
	_rounded(strip, Color("#D8CBB4"))
	for i in queue.size():
		var center := strip.position + Vector2(w * (i + 0.5), 22.0)
		GvzArt.draw_tower(self, str(queue[i]), center, 24.0, 0)
		if i == 0:
			draw_rect(
				Rect2(strip.position + Vector2(w * i, 0), Vector2(w, 30.0)),
				AcTokens.LEAF,
				false,
				2.0
			)


func _draw_boss_bar() -> void:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return
	var vp := _view_size()
	var rect := Rect2(vp.x * 0.3, vp.y - 18.0, vp.x * 0.4, 10.0)
	_rounded(rect, AcTokens.PAPER)
	var frac := float(boss["hp"]) / float(maxi(1, int(boss["max_hp"])))
	draw_rect(
		Rect2(
			rect.position + Vector2(1, 1), Vector2((rect.size.x - 2.0) * frac, rect.size.y - 2.0)
		),
		GvzArt.BERRY_RED
	)


func _draw_ghost() -> void:
	if not dragging or selected_card == "" or selected_card == "shovel":
		return
	var cell := _cell_at(drag_pos)
	var size := _cell_size()
	if cell.x >= 0:
		var ok := bool(GvzLogic.can_place(state, selected_card, cell.y, cell.x)["ok"])
		var tone := Color(0.5, 0.9, 0.5, 0.35) if ok else Color(0.9, 0.4, 0.4, 0.35)
		var top_left := _cell_center(cell.y, cell.x) - size * 0.5
		draw_rect(Rect2(top_left, size), tone)
		GvzArt.draw_tower(
			self,
			selected_card,
			_cell_center(cell.y, cell.x) + Vector2(0, size.y * 0.4),
			size.y * 0.8,
			0
		)
	else:
		GvzArt.draw_tower(self, selected_card, drag_pos + Vector2(0, 20), 44.0, 0)


func _draw_banner() -> void:
	if _banner_text == "" or Time.get_ticks_msec() / 1000.0 > _banner_until:
		return
	var vp := _view_size()
	var rect := Rect2(vp.x * 0.5 - 150.0, vp.y * 0.32, 300.0, 44.0)
	_rounded(rect, Color(0.29, 0.23, 0.21, 0.8))
	draw_string(
		_font_bold,
		rect.position + Vector2(0, 30),
		_banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x),
		22,
		Color.WHITE
	)


func _draw_bar(at: Vector2, width: float, frac: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 4.0)), Color(0.29, 0.23, 0.21, 0.4))
	draw_rect(Rect2(at, Vector2(width * clampf(frac, 0.0, 1.0), 4.0)), color)


func _rounded(rect: Rect2, color: Color) -> void:
	draw_rect(rect, GvzArt.OUTLINE.lerp(color, 0.7))
	draw_rect(rect.grow(-1.5), color)


## ── UI-Aufbau (Select + Overlays) ────────────────────────────────────────


func _build_select_screen() -> void:
	_select_screen = GvzLevelSelect.new()
	_select_screen.game_state = _game_state()
	_select_screen.level_chosen.connect(open_level)
	_select_screen.done_pressed.connect(finish_session)
	add_child(_select_screen)
	_select_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_screen.size = _view_size()


func _build_end_overlay(won: bool, stars: int, total: int, first_clear: bool) -> void:
	_clear_overlay()
	_overlay = VBoxContainer.new()
	_overlay.add_theme_constant_override("separation", 10)
	add_child(_overlay)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("gvz.end.win" if won else "gvz.end.lose")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(title)
	var info := Label.new()
	info.theme_type_variation = &"CaptionLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if won:
		info.text = (
			"%s\n%s"
			% [
				"★".repeat(stars) + "☆".repeat(3 - stars),
				I18nService.t("gvz.end.score", {"n": total}),
			]
		)
		if first_clear:
			info.text += "\n" + I18nService.t("gvz.end.first_clear")
	else:
		info.text = I18nService.t("gvz.end.lose_hint")
	_overlay.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(row)
	if won and level_id < GvzProgress.LEVEL_COUNT:
		row.add_child(_overlay_button("gvz.end.next", func() -> void: open_level(level_id + 1)))
	if not won:
		row.add_child(_overlay_button("gvz.end.retry", func() -> void: open_level(level_id)))
	row.add_child(_overlay_button("gvz.end.select", back_to_select))
	var vp := _view_size()
	_overlay.position = Vector2(vp.x * 0.5 - 170.0, vp.y * 0.3)
	_overlay.size = Vector2(340.0, 170.0)


func _overlay_button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = I18nService.t(key)
	button.custom_minimum_size = Vector2(104, 48)
	button.pressed.connect(action)
	return button


func _clear_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


## ── Helfer ───────────────────────────────────────────────────────────────


func _game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _difficulty() -> String:
	if ctx == null:
		return "normal"
	return ctx.difficulty if balance.get("difficulty", {}).has(ctx.difficulty) else "normal"


func _conveyor_active() -> bool:
	return not (state["conveyor"] as Dictionary).is_empty()


func _show_banner(text: String) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + BANNER_SEC


func _remember_zombie_positions() -> void:
	_prev_zombie_pos = {}
	for zombie: Dictionary in state["zombies"]:
		_prev_zombie_pos[int(zombie["id"])] = Vector2(
			_x_to_px(int(zombie["x"])),
			_field_rect().position.y + (int(zombie["lane"]) + 0.6) * _cell_size().y
		)


func _spawn_poof(id: int, kind: String) -> void:
	if not _prev_zombie_pos.has(id):
		return
	_poofs.append({"pos": _prev_zombie_pos[id], "ttl": 0.35, "kind": kind})


func _decay_poofs(delta: float) -> void:
	for i in range(_poofs.size() - 1, -1, -1):
		_poofs[i]["ttl"] = float(_poofs[i]["ttl"]) - delta
		if float(_poofs[i]["ttl"]) <= 0.0:
			_poofs.remove_at(i)
