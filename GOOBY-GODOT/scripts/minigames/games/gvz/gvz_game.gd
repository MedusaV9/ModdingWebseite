extends MinigameBase
## GvZ-Spielszene (W3b) im W2d-Minigame-Contract: Level-Select → Gefecht →
## Sieg/Niederlage, alles über der PUREN Simulation (GvzLogic — die Szene
## rendert nur State und ruft Aktions-Funktionen). Querformat bevorzugt,
## Hochkant skaliert das Grid. Steuerung: Karte antippen ODER ziehen
## (Drag-Ghost), Klecks antippen = einsammeln, Schaufel entfernt Türme.
## Punkte laufen NUR über ctx.report_score/report_end (Award macht der Host).
## Feedback (W4-P1): JuiceKit an Gefechts-Momenten (Shake/Freeze/Bloom bei
## Welle/Boss/Mäher/Boom, Slowmo beim Boss-Auftritt) + AudioDirector-SFX.
##
## FB-4: das Gefecht spielt auf einer ECHTEN 3D-Bühne (gvz_stage3d.gd) —
## Rasen, Türme, Zombies, Boss, Projektile, Drops, Mäher und Nebelwand sind
## Meshes, per ground_point-Raycast EXAKT unter dem 2D-Grid verankert. Die
## 2D-Schicht rendert nur noch HUD (Karten, Zähler, Balken, Banner, Ghost).
## Das löst auch das E4-P1-Backlog (~850 immediate-mode Draw-Calls): die
## GvzArt-Figuren zeichnen jetzt nur noch die Karten-Icons.

const Stage := preload("res://scripts/minigames/games/gvz/gvz_stage3d.gd")

const TICK_SEC := 0.05
const CARD_W := 56.0
const CARD_H := 62.0
const TOP_PAD := 6.0
const MOWER_GUTTER := 44.0
const BANNER_SEC := 2.2

## W13/GVZ (P5-Report G18): Meilenstein-Siege feuern Event-Hooks über den
## bestehenden Sticker-Mechanismus (Doc G §4.4 „1× Sticker bei L5/10/15“).
## L15 = gvz_kampagne → Sticker „Garten gerettet!“ (stickers.json); die
## Hooks gvz_l5/gvz_l10 warten auf ihre Katalog-Sticker (Request an den
## Orchestrator — der Katalog ist auf 141 Einträge + Assets verplombt).
const MILESTONE_HOOKS := {5: "gvz_l5", 10: "gvz_l10", 15: "gvz_kampagne"}
## Run-Stats der puren Sim (GvzLogic state.stats) → achievements.counters
## (exakt die Counter-Keys der 6 GvZ-Sticker-Conds in stickers.json).
const STAT_COUNTERS := {
	"drops_collected": "gvzNutella",
	"eis_placed": "gvzEisEinsaetze",
	"bert_placed": "gvzBertEinsaetze",
	"moehren_shots": "gvzMoehrenSchuesse",
}

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
## Banner-Stil ("info" | "wave" | "huge" | "boss") + Startzeit für den Punch.
var _banner_kind := "info"
var _banner_start := 0.0
## Nutella-Zähler: letzter Stand + Pop-Startzeit (Zähler feiert Änderungen).
var _nutella_seen := -1
var _nutella_pop := -10.0
var _last_run_score := 0
var _prev_zombie_pos: Dictionary = {}
var _select_screen: GvzLevelSelect
var _overlay: Control
var _font: Font
var _font_bold: Font
var _stage: Node3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	GvzProgress.register_slice()
	balance = GvzData.load_balance(null)
	levels = GvzData.load_levels()
	_font = ThemeService.font(600)
	_font_bold = ThemeService.font(800)
	_stage = Stage.new()
	_stage.name = "Vorgarten3D"
	add_child(_stage)
	_stage.setup_stage()
	_stage.visible = false
	if ctx != null and ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_select_screen()
	queue_redraw()


## Pflicht-Layouthook: Kamera stellen und das Zellen-Gitter neu raycasten.
func apply_view(size: Vector2) -> void:
	if _stage == null:
		return
	_stage.frame(size)
	if phase != "select" and not state.is_empty():
		_relayout_stage()


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
	_show_banner(I18nService.t("gvz.hud.level", {"n": id}))
	if _select_screen != null:
		_select_screen.visible = false
	if _stage != null:
		_stage.visible = true
		_stage.frame(_view_size())
		_relayout_stage()
	_clear_overlay()
	queue_redraw()


func back_to_select() -> void:
	phase = "select"
	state = {}
	if _stage != null:
		_stage.visible = false
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
				# E11-P1-5: max_unlocked()-1 meldete nach dem Vollabschluss
				# 14 statt 15 — jetzt zählen die WIRKLICH abgeschlossenen.
				"levels": GvzProgress.cleared_count(_game_state()),
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
	_report_live_score()
	if GvzLogic.is_over(state):
		_on_run_over()
	_sync_stage(delta)
	queue_redraw()


func _consume_events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event["kind"]):
			"wave":
				var huge := bool(event["huge"])
				var key := "gvz.hud.huge_wave" if huge else "gvz.hud.wave"
				_show_banner(I18nService.t(key, {"n": int(event["n"])}), "huge" if huge else "wave")
				AudioDirector.try_play(self, "gvz_wave", 1.15 if not huge else 1.0)
				if ctx != null and ctx.juice != null and huge:
					ctx.juice.shake(0.35)
					ctx.juice.edge_glow(0.55, GvzArt.BERRY_RED)
			"boss_enter":
				_show_banner(I18nService.t("gvz.hud.boss"), "boss")
				AudioDirector.try_play(self, "gvz_boss")
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.6)
					ctx.juice.slowmo(0.45, 400)
					ctx.juice.bloom_pulse(0.5, 500)
					ctx.juice.edge_glow(0.7, GvzArt.BERRY_RED)
			"boss_phase":
				_show_banner(
					I18nService.t("gvz.hud.boss_phase", {"n": int(event["phase"])}), "boss"
				)
				AudioDirector.try_play(self, "gvz_boss", 1.0 + 0.1 * int(event["phase"]))
				if ctx != null and ctx.juice != null:
					ctx.juice.hit_freeze(110)
					ctx.juice.shake(0.5)
			"mower":
				_stage.mower_fx()
				AudioDirector.try_play(self, "gvz_mower")
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.55)
					ctx.juice.hit_freeze(70)
			"die":
				if _prev_zombie_pos.has(int(event["id"])):
					_stage.die_fx(_prev_zombie_pos[int(event["id"])])
				AudioDirector.try_play(self, "gvz_pop")
			"pop":
				if _prev_zombie_pos.has(int(event["id"])):
					_stage.pop_fx(_prev_zombie_pos[int(event["id"])])
				AudioDirector.try_play(self, "gvz_balloon")
			"collect":
				AudioDirector.try_play(self, "gvz_collect")
				if ctx != null and ctx.juice != null:
					var at := _cell_center(int(event["lane"]), int(event["col"]))
					ctx.juice.float_text(
						at, "+%d" % int(event["amount"]), GvzArt.NUTELLA.lightened(0.35)
					)
			"blast":
				_stage.blast_fx(_cell_center(int(event["lane"]), int(event["col"])))
				AudioDirector.try_play(self, "gvz_boom")
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.3)
					ctx.juice.hit_freeze(60)
					ctx.juice.bloom_pulse(0.4, 250)


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
	_book_sticker_progress(str(state["outcome"]) == "won")
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
		_stage.win_fx()
		AudioDirector.try_play(self, "mg_win")
		if ctx != null:
			ctx.report_score(session_score, total - _last_run_score)
			# E10-P1-3: jeder Levelsieg ist eine eigene Coin-Einheit — der
			# Host wendet die Coin-Row pro Chunk an statt pro Session.
			ctx.report_coin_chunk(total)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
				ctx.juice.confetti(80)
		phase = "won"
		_build_end_overlay(true, stars, total, bool(booking["first_clear"]))
	else:
		phase = "lost"
		_stage.lose_fx()
		AudioDirector.try_play(self, "mg_lose")
		if ctx != null and ctx.juice != null:
			ctx.juice.shake(0.7)
			ctx.juice.hit_freeze(120)
		_build_end_overlay(false, 0, 0, false)
	queue_redraw()


## Rundenende → Sticker-Verdrahtung (W13/GVZ): Run-Stats in die Counter der
## stickers.json-Conds buchen (Sieg UND Niederlage — gesammelt ist gesammelt),
## Meilenstein-Hook bei L5/10/15-Sieg feuern, RewardHub-Auswertung anstoßen.
func _book_sticker_progress(won: bool) -> void:
	var gs := _game_state()
	if gs == null or not gs.has_method("update"):
		return
	var stats: Dictionary = state.get("stats", {})
	var kills := int(state.get("kills", 0))
	gs.update(
		func(save: Dictionary) -> void:
			if not (save.get("achievements") is Dictionary):
				save["achievements"] = {"unlocked": {}, "counters": {}}
			var achievements: Dictionary = save["achievements"]
			if not (achievements.get("counters") is Dictionary):
				achievements["counters"] = {}
			var counters: Dictionary = achievements["counters"]
			for stat_key: String in STAT_COUNTERS:
				_bump_counter(counters, str(STAT_COUNTERS[stat_key]), int(stats.get(stat_key, 0)))
			_bump_counter(counters, "gvzZombiesGestoppt", kills)
	)
	if won and MILESTONE_HOOKS.has(level_id):
		StickerUnlocks.fire_event_hook(gs, str(MILESTONE_HOOKS[level_id]))
	RewardHub.note_action(gs)


static func _bump_counter(counters: Dictionary, key: String, delta: int) -> void:
	if delta <= 0:
		return
	var raw: Variant = counters.get(key, 0)
	counters[key] = (int(raw) if raw is int or raw is float else 0) + delta


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
			AudioDirector.try_play(self, "gvz_shovel")
			_stage.place_fx(_cell_center(cell.y, cell.x))
		queue_redraw()
		return
	var placed := GvzLogic.place_tower(state, selected_card, cell.y, cell.x)
	if bool(placed["ok"]):
		selected_card = ""
		AudioDirector.try_play(self, "gvz_place")
		_stage.place_fx(_cell_center(cell.y, cell.x))
	else:
		AudioDirector.try_play(self, "ui_error")
		if ctx != null and ctx.juice != null:
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
	# Horizont-Band (MP-G): über der Feld-Oberkante bleibt bewusst Luft für
	# die Nachbarschafts-Kulisse (Haus, Zaun, Gehweg, Bäume). Ohne das Band
	# ragt alles Hohe hinter dem Zaun abgeschnitten aus dem Bildrand.
	top += vp.y * 0.16
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


## ── 3D-Bühne (Layout + Sync) ─────────────────────────────────────────────


## Zellen-Gitter, Nebelwand und Nachtlicht neu an das 2D-Layout koppeln.
func _relayout_stage() -> void:
	if _stage == null or state.is_empty():
		return
	var fog_px := _x_to_px(_fog_start_mm()) if _fog_cols() > 0 else -1.0
	_stage.layout(_field_rect(), bool(state["mods"].get("night", false)), fog_px)


## Jeden Frame: den kompletten Sim-Zustand als Canvas-Pixel-Anker zur Bühne.
func _sync_stage(delta: float) -> void:
	if _stage == null or not _stage.visible or state.is_empty():
		return
	var field := _field_rect()
	var cell := _cell_size()
	var tick := int(state["tick"])
	var fog_mm := _fog_start_mm() if _fog_cols() > 0 else GvzLogic.COLS * GvzLogic.CELL_MM * 2
	var towers: Array = []
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		(
			towers
			. append(
				{
					"key": key,
					"type": tower["type"],
					"lane": tower["lane"],
					"col": tower["col"],
				}
			)
		)
	var zombies: Array = []
	for zombie: Dictionary in state["zombies"]:
		if bool(zombie["dead"]):
			continue
		(
			zombies
			. append(
				{
					"id": zombie["id"],
					"type": zombie["type"],
					"lane": zombie["lane"],
					"px": _lane_px(int(zombie["lane"]), int(zombie["x"]), field, cell),
					"hidden": int(zombie["x"]) >= fog_mm,
					"dig": str(zombie.get("state", "walk")) == "dig",
					"flying": bool(zombie.get("flying", false)),
					"armor": int(zombie.get("armor_hp", 0)) > 0,
					"raged": bool(zombie.get("raged", false)),
					"slow": int(zombie.get("slow_until", 0)) > tick,
					# HP für den Trefferblitz der Bühne (Abfall = Treffer).
					"hp": int(zombie["hp"]) + int(zombie.get("armor_hp", 0)),
				}
			)
		)
	var boss_data := {}
	var boss: Dictionary = state["boss"]
	if not boss.is_empty() and int(boss["hp"]) > 0 and int(boss["x"]) < fog_mm:
		boss_data = {
			"px": _lane_px(int(boss["lane"]), int(boss["x"]), field, cell),
			"lane": boss["lane"],
			"phase": boss.get("phase", 1),
		}
	var projectiles: Array = []
	for proj: Dictionary in state["projectiles"]:
		if int(proj["x"]) >= fog_mm:
			continue
		(
			projectiles
			. append(
				{
					"kind": proj["kind"],
					"lane": proj["lane"],
					"px": _lane_px(int(proj["lane"]), int(proj["x"]), field, cell),
				}
			)
		)
	var drops: Array = []
	for drop: Dictionary in state["drops"]:
		(
			drops
			. append(
				{
					"id": drop["id"],
					"lane": drop["lane"],
					"px": _cell_center(int(drop["lane"]), int(drop["col"])),
				}
			)
		)
	var mowers: Array = []
	for lane: Variant in state["mowers"]:
		var mower: Dictionary = state["mowers"][lane]
		var px := Vector2(MOWER_GUTTER * 0.5, field.position.y + (int(lane) + 0.5) * cell.y)
		if bool(mower["active"]):
			px.x = _x_to_px(int(mower["x"]))
		(
			mowers
			. append(
				{
					"lane": int(lane),
					"active": mower["active"],
					"used": mower["used"],
					"px": px,
				}
			)
		)
	var ghost := {}
	if dragging and selected_card != "" and selected_card != "shovel":
		var at := _cell_at(drag_pos)
		if at.x >= 0:
			ghost = {
				"lane": at.y,
				"col": at.x,
				"ok": bool(GvzLogic.can_place(state, selected_card, at.y, at.x)["ok"]),
			}
	(
		_stage
		. sync(
			{
				"tick": tick,
				"towers": towers,
				"zombies": zombies,
				"boss": boss_data,
				"projectiles": projectiles,
				"drops": drops,
				"mowers": mowers,
				"ghost": ghost,
			},
			delta
		)
	)


## Boden-Anker (Canvas-Pixel) eines Sim-x auf der Bahnmitte.
func _lane_px(lane: int, x_mm: int, field: Rect2, cell: Vector2) -> Vector2:
	return Vector2(_x_to_px(x_mm), field.position.y + (float(lane) + 0.5) * cell.y)


## ── Zeichnen (nur noch HUD — das Feld rendert die 3D-Bühne) ─────────────


func _draw() -> void:
	var vp := _view_size()
	if phase == "select":
		draw_rect(Rect2(Vector2.ZERO, vp), AcTokens.BG_CREAM)
		return
	if state.is_empty():
		return
	_draw_bars()
	_draw_hud()
	_draw_ghost()
	_draw_banner()
	if phase != "battle":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.29, 0.23, 0.21, 0.35))


## Nebel-Spalten des Levels (E11-P1-4: L11 liefert mods.fog_cols=3, der alte
## Renderer prüfte nur mods.fog — die Mechanik war funktional tot). Legacy-
## `fog: true` zählt als 3 Spalten. 0 = kein Nebel.
func _fog_cols() -> int:
	var mods: Dictionary = state["mods"]
	var cols := int(mods.get("fog_cols", 0))
	if cols <= 0 and bool(mods.get("fog", false)):
		cols = 3
	return clampi(cols, 0, GvzLogic.COLS)


## x-Position (Milli-Zellen), ab der der Nebel beginnt (rechte Feldseite).
func _fog_start_mm() -> int:
	return (GvzLogic.COLS - _fog_cols()) * GvzLogic.CELL_MM


## HP-Balken als 2D-Overlay über den 3D-Figuren (gleiche Anker wie vor dem
## Umbau; Zombies hinter der Nebelwand bleiben — wie ihre Figuren — verdeckt).
func _draw_bars() -> void:
	var cell := _cell_size()
	var field := _field_rect()
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		var feet := _cell_center(int(tower["lane"]), int(tower["col"])) + Vector2(0, cell.y * 0.4)
		var hp := float(tower["hp"]) / float(tower["max_hp"])
		if hp < 0.99:
			_draw_bar(
				feet + Vector2(-cell.x * 0.3, -cell.y * 0.95), cell.x * 0.6, hp, GvzArt.MELON_GREEN
			)
	var fog_mm := _fog_start_mm() if _fog_cols() > 0 else GvzLogic.COLS * GvzLogic.CELL_MM * 2
	for zombie: Dictionary in state["zombies"]:
		if bool(zombie["dead"]) or int(zombie["x"]) >= fog_mm:
			continue
		var feet := Vector2(
			_x_to_px(int(zombie["x"])), field.position.y + (int(zombie["lane"]) + 1) * cell.y - 3.0
		)
		var total := int(zombie["hp"]) + int(zombie["armor_hp"])
		var max_total := int(zombie["max_hp"]) + int(zombie.get("armor_hp", 0))
		if total < int(zombie["max_hp"]):
			_draw_bar(
				feet + Vector2(-cell.x * 0.25, -cell.y * 1.02),
				cell.x * 0.5,
				float(total) / float(maxi(1, max_total)),
				GvzArt.BERRY_RED
			)


func _draw_hud() -> void:
	# Nutella-Zähler — poppt bei jeder Änderung (die Ressource FEIERT Zuwachs).
	var nutella := int(state["nutella"])
	if nutella != _nutella_seen:
		if _nutella_seen >= 0:
			_nutella_pop = Time.get_ticks_msec() / 1000.0
		_nutella_seen = nutella
	var pop := maxf(0.0, 1.0 - (Time.get_ticks_msec() / 1000.0 - _nutella_pop) / 0.3)
	var counter := Rect2(6, TOP_PAD, 78, CARD_H)
	_rounded(
		counter, AcTokens.PAPER if pop <= 0.0 else AcTokens.PAPER.lerp(GvzArt.STAR_GOLD, pop * 0.35)
	)
	GvzArt.draw_nutella_drop(
		self, counter.position + Vector2(22, 44), 34 * (1.0 + 0.25 * pop), int(state["tick"])
	)
	draw_string(
		_font_bold,
		counter.position + Vector2(38, 38),
		str(nutella),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int(17 * (1.0 + 0.2 * pop)),
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


## Drag-Feedback: das Karten-Icon folgt dem Finger (UI-Schicht); die grüne/
## rote Zell-Markierung rendert die 3D-Bühne (_sync_stage → ghost).
func _draw_ghost() -> void:
	if not dragging or selected_card == "" or selected_card == "shovel":
		return
	GvzArt.draw_tower(self, selected_card, drag_pos + Vector2(0, 20), 44.0, 0)


## Wellen-Banner mit WUCHT: schlägt groß ein (Punch-Skalierung), Farbe nach
## Gefahr (Welle sand, Riesenwelle/Boss berry-rot), Mini-Zombies flankieren
## den Text, am Ende blendet es weich aus.
func _draw_banner() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _banner_text == "" or now > _banner_until:
		return
	var vp := _view_size()
	var t := now - _banner_start
	var punch := maxf(0.0, 1.0 - t / 0.3)
	var s := 1.0 + 0.5 * punch * punch
	var fade := clampf((_banner_until - now) / 0.35, 0.0, 1.0)
	var danger := _banner_kind == "huge" or _banner_kind == "boss"
	var w := (340.0 if danger else 300.0) * s
	var h := (54.0 if danger else 44.0) * s
	var rect := Rect2(vp.x * 0.5 - w * 0.5, vp.y * 0.32 - (h - 44.0) * 0.5, w, h)
	var fill := Color(0.29, 0.23, 0.21, 0.8)
	if _banner_kind == "huge":
		fill = Color(0.62, 0.2, 0.16, 0.88)
	elif _banner_kind == "boss":
		fill = Color(0.42, 0.14, 0.3, 0.9)
	fill.a *= fade
	_rounded(rect, fill)
	if danger:
		draw_rect(rect.grow(-1.5), Color(1.0, 0.83, 0.3, 0.85 * fade), false, 2.5)
	if _banner_kind != "info":
		var icon_s := h * 0.42
		var horde := 3 if _banner_kind == "huge" else 1
		for i in horde:
			var offset := icon_s * (0.4 + 1.1 * float(i))
			GvzArt.draw_zombie(
				self,
				"schlurfi",
				rect.position + Vector2(-offset - 6.0, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 3
			)
			GvzArt.draw_zombie(
				self,
				"schlurfi",
				rect.position + Vector2(w + offset + 6.0, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 5 + 2
			)
	draw_string(
		_font_bold,
		rect.position + Vector2(0, h * 0.5 + 8.0 * s),
		_banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x),
		int((26 if danger else 22) * s),
		Color(1.0, 1.0, 1.0, fade)
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
	# B11-Fix (W13/GVZ): KEIN FULL_RECT-Preset mehr — unter dem Node2D-Parent
	# (MinigameBase) ist das Anchor-Rect 0×0, und Anker+size-Setzung auf
	# demselben Node warf „Nodes with non-equal opposite anchors …“. Der
	# Select-Screen bindet sich selbst an den Viewport (_fit_viewport in
	# _ready + size_changed, GOB-NOM-Muster) — Anker bleiben gleichseitig.


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
	button.pressed.connect(func() -> void: AudioDirector.try_play(button, "ui_click"))
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


func _show_banner(text: String, kind := "info") -> void:
	_banner_text = text
	_banner_kind = kind
	_banner_start = Time.get_ticks_msec() / 1000.0
	_banner_until = _banner_start + BANNER_SEC


## Letzte Pixel-Anker der Zombies (die Sim entfernt Tote im selben Tick —
## die 3D-FX für die "die"/"pop"-Events brauchen die Position davor).
func _remember_zombie_positions() -> void:
	_prev_zombie_pos = {}
	for zombie: Dictionary in state["zombies"]:
		_prev_zombie_pos[int(zombie["id"])] = Vector2(
			_x_to_px(int(zombie["x"])),
			_field_rect().position.y + (int(zombie["lane"]) + 0.6) * _cell_size().y
		)
