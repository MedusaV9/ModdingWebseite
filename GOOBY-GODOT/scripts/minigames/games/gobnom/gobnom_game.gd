extends MinigameBase
## GOB-NOM-Spielszene (Doc G §5, „Cut the Rope“-Pendant) im W2d-Minigame-
## Contract: Level-Select (Kampagne + Coop) → Physik-Puzzle → Sieg/Niederlage,
## alles über der PUREN Simulation (GobnomLogic — die Szene rendert nur State
## und ruft Aktions-Funktionen). Querformat bevorzugt; die Welt (960×540)
## wird über einen Letterbox-Transform skaliert, Hochkant funktioniert also
## automatisch mit. Steuerung: Swipen = Seile schneiden (kreuzt die Linie ein
## Seil, ist es durch), Antippen = Blase platzen / Kissen puffen / Ventilator
## schalten, Schiebe-Anker ziehen. Coop (Doc G §5.4): Bildschirmhälften sind
## getönt markiert, jede Berührung handelt als Spieler ihrer Hälfte
## (hot-seat/Multi-Touch; Netz-Coop = Backlog-Hook, siehe README im Ordner).
## Punkte laufen NUR über ctx.report_score/report_end (Award macht der Host);
## jeder Levelsieg meldet einen Coin-Chunk (E10-P1-3-Muster wie GvZ).

const TICK_SEC := 1.0 / 60.0
const BANNER_SEC := 2.2
const SWIPE_TRAIL_MAX := 14
const TAP_RADIUS := 34.0

## Testschalter: GameState-Double VOR setup() setzen (Muster W2a RoomBase).
var game_state_override: Object

var balance: Dictionary = {}
var campaign: Array = []
var coop_levels: Array = []
var phase := "select"
var state: Dictionary = {}
var track := "campaign"
var level_id := 0
var attempt := 0
var session_score := 0
var ended := false

var _accum := 0.0
var _run_score := 0
var _last_reported := 0
var _banner_text := ""
var _banner_hint := ""
var _banner_until := 0.0
## Aktive Zeiger: index → {mode: swipe|anchor|none, player, last, points, rope}.
var _pointers: Dictionary = {}
var _sparks: Array = []
var _select_screen: GobnomLevelSelect
var _overlay: Control
var _font: Font
var _font_bold: Font


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	GobnomProgress.register_slice()
	balance = GobnomData.load_balance(null)
	campaign = GobnomData.load_campaign()
	coop_levels = GobnomData.load_coop()
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


func open_level(level_track: String, id: int) -> void:
	track = level_track
	level_id = id
	attempt += 1
	var levels := coop_levels if track == GobnomProgress.TRACK_COOP else campaign
	var level := GobnomData.level_by_id(levels, id)
	var seed_value := id
	if ctx != null:
		seed_value = ctx.run_seed + id * 1009 + attempt * 131
		if track == GobnomProgress.TRACK_COOP:
			seed_value += 500_017
	state = GobnomLogic.new_run(level, balance, seed_value)
	phase = "play"
	_accum = 0.0
	_run_score = 0
	_pointers = {}
	_sparks = []
	var tag_key := "gobnom.hud.coop_level" if _is_coop() else "gobnom.hud.level"
	var hint_key := "gobnom.intro.%s" % str(level.get("intro", ""))
	_banner_hint = I18nService.t(hint_key) if I18nService.has_key(hint_key) else ""
	_show_banner(I18nService.t(tag_key, {"n": id}))
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
	var gs := _game_state()
	var stars := (
		GobnomProgress.total_stars(gs, GobnomProgress.TRACK_CAMPAIGN)
		+ GobnomProgress.total_stars(gs, GobnomProgress.TRACK_COOP)
	)
	var levels := (
		GobnomProgress.cleared_count(gs, GobnomProgress.TRACK_CAMPAIGN)
		+ GobnomProgress.cleared_count(gs, GobnomProgress.TRACK_COOP)
	)
	ctx.report_end({"score": session_score, "stars": stars, "levels": levels})


## ── Simulation ───────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if not is_active() or state.is_empty():
		return
	if phase == "play":
		_accum += minf(delta, 0.25)
		while _accum >= TICK_SEC and not GobnomLogic.is_over(state):
			_accum -= TICK_SEC
			_consume_events(GobnomLogic.step(state))
		_report_live_score()
		if GobnomLogic.is_over(state):
			_on_run_over()
	_decay_sparks(delta)
	queue_redraw()


func _consume_events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event["kind"]):
			"cut":
				_spawn_spark(Vector2(event["at"]), "cut")
				AudioDirector.try_play(self, "mg_combo", 1.05)
			"jar":
				var at := Vector2(event["at"])
				_spawn_spark(at, "jar")
				AudioDirector.try_play(self, "gvz_collect")
				if ctx != null and ctx.juice != null:
					ctx.juice.float_text(
						_to_screen(at), I18nService.t("gobnom.hud.jar"), GobnomArt.STAR_GOLD
					)
					if int(state["jars_taken"]) >= 3:
						ctx.juice.bloom_pulse(0.5, 300)
			"pop":
				_spawn_spark(Vector2(event["at"]), "pop")
				AudioDirector.try_play(self, "gvz_balloon")
			"catch":
				_spawn_spark(GobnomLogic.candy_pos(state), "pop")
				AudioDirector.try_play(self, "ui_chip")
			"puff":
				AudioDirector.try_play(self, "mg_spill", 1.2)
				if bool(event["hit"]) and ctx != null and ctx.juice != null:
					ctx.juice.shake(0.25)
			"shoot":
				_spawn_spark(GobnomLogic.candy_pos(state), "cut")
				AudioDirector.try_play(self, "mg_combo", 0.85)
			"fan":
				AudioDirector.try_play(self, "ui_toggle")
			"spike":
				AudioDirector.try_play(self, "mg_junk")
				if ctx != null and ctx.juice != null:
					ctx.juice.shake(0.55)
					ctx.juice.hit_freeze(90)
			"denied":
				AudioDirector.try_play(self, "ui_error")
				if ctx != null and ctx.juice != null and _is_coop():
					ctx.juice.float_text(
						_to_screen(GobnomLogic.candy_pos(state)),
						I18nService.t("gobnom.hud.wrong_side"),
						Color("#E0655F")
					)
			"nom":
				_spawn_confetti(GobnomLogic.candy_pos(state))


## Live-Punkte während des Laufs: Gläser zählen sofort (Rest kommt beim Sieg).
func _report_live_score() -> void:
	if ctx == null or state.is_empty():
		return
	var jar_bonus := int((balance.get("score", {}) as Dictionary).get("jar_bonus", 25))
	_run_score = int(state["jars_taken"]) * jar_bonus
	if _run_score != _last_reported:
		ctx.report_score(session_score + _run_score, _run_score - _last_reported)
		_last_reported = _run_score


func _on_run_over() -> void:
	if phase != "play":
		return
	if str(state["outcome"]) == "won":
		var jars := int(state["jars_taken"])
		var stars := GobnomLogic.stars_for(jars)
		var first_clear := not GobnomProgress.is_cleared(_game_state(), track, level_id)
		var total := GobnomProgress.final_score(level_id, jars, first_clear, balance)
		GobnomProgress.record_win(_game_state(), track, level_id, stars, total)
		session_score += total
		AudioDirector.try_play(self, "mg_win")
		if ctx != null:
			ctx.report_score(session_score, total - _last_reported)
			ctx.report_coin_chunk(total)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
				ctx.juice.slowmo(0.5, 350)
		phase = "won"
		_build_end_overlay(true, stars, total, first_clear)
	else:
		phase = "lost"
		AudioDirector.try_play(self, "mg_lose")
		if ctx != null and ctx.juice != null:
			ctx.juice.shake(0.6)
			ctx.juice.hit_freeze(110)
		_build_end_overlay(false, 0, 0, false)
	_last_reported = 0
	queue_redraw()


## ── Eingabe ──────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or phase != "play" or state.is_empty():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointers.erase(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		_pointer_move(event.index, event.position)
		queue_redraw()


func _pointer_down(index: int, screen_pos: Vector2) -> void:
	var world := _to_world(screen_pos)
	var player := _player_for(world)
	# Schiebe-Anker zuerst (greifbar), dann Tap-Elemente, sonst Swipe-Start.
	var rail_rope := _rail_anchor_at(world)
	if rail_rope >= 0:
		_pointers[index] = {"mode": "anchor", "player": player, "rope": rail_rope}
		return
	if _tap_element(world, player):
		_pointers[index] = {"mode": "none", "player": player}
		return
	_pointers[index] = {"mode": "swipe", "player": player, "last": world, "points": [world]}


func _pointer_move(index: int, screen_pos: Vector2) -> void:
	if not _pointers.has(index):
		return
	var pointer: Dictionary = _pointers[index]
	var world := _to_world(screen_pos)
	match str(pointer["mode"]):
		"anchor":
			var player := _player_for(world)
			GobnomLogic.move_anchor(
				state, int(pointer["rope"]), _rail_t_for(int(pointer["rope"]), world), player
			)
		"swipe":
			var last := Vector2(pointer["last"])
			var player := _player_for(last)
			var cut_ids := GobnomLogic.cut_segment(state, last, world, player)
			for rope_id: Variant in cut_ids:
				if ctx != null and ctx.juice != null:
					ctx.juice.hit_freeze(45)
			pointer["last"] = world
			var points: Array = pointer["points"]
			points.append(world)
			while points.size() > SWIPE_TRAIL_MAX:
				points.pop_front()


## Tap auf Blase/Kissen/Ventilator ausführen (true = getroffen).
func _tap_element(world: Vector2, player: String) -> bool:
	for bubble: Dictionary in state["bubbles"]:
		if bool(bubble["popped"]):
			continue
		var at := GobnomLogic.candy_pos(state) if bool(bubble["holds"]) else Vector2(bubble["pos"])
		if world.distance_to(at) <= float(bubble["r"]) + 18.0:
			GobnomLogic.pop_bubble(state, int(bubble["id"]), player)
			return true
	for cushion: Dictionary in state["cushions"]:
		if world.distance_to(Vector2(cushion["pos"])) <= TAP_RADIUS:
			GobnomLogic.puff_cushion(state, int(cushion["id"]), player)
			return true
	for fan: Dictionary in state["fans"]:
		if bool(fan["toggleable"]) and world.distance_to(Vector2(fan["pos"])) <= TAP_RADIUS:
			GobnomLogic.toggle_fan(state, int(fan["id"]), player)
			return true
	return false


## Rope-Id eines greifbaren Schiebe-Ankers unter dem Punkt (-1 = keiner).
func _rail_anchor_at(world: Vector2) -> int:
	for rope: Dictionary in state["ropes"]:
		if bool(rope["cut"]) or not (rope.get("rail") is Dictionary):
			continue
		if world.distance_to(Vector2(rope["anchor"])) <= 30.0:
			return int(rope["id"])
	return -1


## Schienen-Parameter t (0..1) für einen Weltpunkt (Projektion auf die Schiene).
func _rail_t_for(rope_id: int, world: Vector2) -> float:
	for rope: Dictionary in state["ropes"]:
		if int(rope["id"]) != rope_id or not (rope.get("rail") is Dictionary):
			continue
		var rail: Dictionary = rope["rail"]
		var from := Vector2(rail["from"])
		var span := Vector2(rail["to"]) - from
		if span.length_squared() < 0.001:
			return 0.0
		return clampf((world - from).dot(span) / span.length_squared(), 0.0, 1.0)
	return 0.0


func _player_for(world: Vector2) -> String:
	if not _is_coop():
		return GobnomLogic.PLAYER_SOLO
	return GobnomLogic.side_of(state, world)


## ── Welt-Transform ───────────────────────────────────────────────────────


func _world_size() -> Vector2:
	var world: Dictionary = balance.get("world", {})
	return Vector2(float(world.get("w", 960.0)), float(world.get("h", 540.0)))


func _world_scale() -> float:
	var vp := get_viewport_rect().size
	var world := _world_size()
	return minf(vp.x / world.x, vp.y / world.y)


func _world_offset() -> Vector2:
	return (get_viewport_rect().size - _world_size() * _world_scale()) * 0.5


func _to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _world_offset()) / _world_scale()


func _to_screen(world_pos: Vector2) -> Vector2:
	return world_pos * _world_scale() + _world_offset()


## ── Zeichnen ─────────────────────────────────────────────────────────────


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), AcTokens.BG_CREAM)
	if phase == "select" or state.is_empty():
		return
	draw_set_transform(_world_offset(), 0.0, Vector2.ONE * _world_scale())
	_draw_world_bg()
	_draw_clouds()
	_draw_rails_and_shooters()
	_draw_spikes()
	_draw_mouth()
	_draw_jars()
	_draw_cushions_and_fans()
	_draw_ropes()
	_draw_bubbles()
	_draw_candy()
	_draw_sparks()
	_draw_swipes()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	_draw_banner()
	if phase != "play":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.29, 0.23, 0.21, 0.35))


func _draw_world_bg() -> void:
	var world := _world_size()
	# Pastell-Himmel + Boden-Wiese (Sticker-Bühne).
	draw_rect(Rect2(Vector2.ZERO, world), Color("#EAF4FB"))
	draw_rect(Rect2(0, world.y - 26.0, world.x, 26.0), Color("#BCE39B"))
	draw_rect(Rect2(0, world.y - 26.0, world.x, 4.0), Color("#A8D083"))
	if _is_coop():
		_draw_coop_split(world)


## Coop: Hälften tönen (A rosa / B mint) + gestrichelte Grenze + Labels.
func _draw_coop_split(world: Vector2) -> void:
	var split: Dictionary = state["split"]
	var at := float(split.get("at", 480.0))
	var vertical := str(split.get("axis", "x")) == "x"
	var rect_a := Rect2(0, 0, at, world.y) if vertical else Rect2(0, 0, world.x, at)
	var rect_b := (
		Rect2(at, 0, world.x - at, world.y) if vertical else Rect2(0, at, world.x, world.y - at)
	)
	draw_rect(rect_a, Color(0.96, 0.63, 0.6, 0.07))
	draw_rect(rect_b, Color(0.55, 0.78, 0.52, 0.07))
	var steps := 14
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := t0 + 0.5 / float(steps)
		var p0 := Vector2(at, world.y * t0) if vertical else Vector2(world.x * t0, at)
		var p1 := Vector2(at, world.y * t1) if vertical else Vector2(world.x * t1, at)
		draw_line(p0, p1, Color(0.29, 0.23, 0.21, 0.4), 3.0)
	var label_a := rect_a.get_center() - Vector2(10, -10)
	var label_b := rect_b.get_center() - Vector2(10, -10)
	var tint_a := Color(0.9, 0.5, 0.5, 0.35)
	var tint_b := Color(0.4, 0.65, 0.4, 0.35)
	draw_string(_font_bold, label_a, "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, tint_a)
	draw_string(_font_bold, label_b, "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, tint_b)


func _draw_clouds() -> void:
	var tick := int(state["tick"])
	for cloud: Dictionary in state["clouds"]:
		var rect := Rect2(
			float(cloud["x"]), float(cloud["y"]), float(cloud["w"]), float(cloud["h"])
		)
		GobnomArt.draw_cloud(self, rect, tick)


func _draw_rails_and_shooters() -> void:
	for rope: Dictionary in state["ropes"]:
		if rope.get("rail") is Dictionary:
			var rail: Dictionary = rope["rail"]
			GobnomArt.draw_rail(self, Vector2(rail["from"]), Vector2(rail["to"]))
	for shooter: Dictionary in state["shooters"]:
		GobnomArt.draw_shooter(
			self, Vector2(shooter["pos"]), float(shooter["r"]), bool(shooter["fired"])
		)


func _draw_spikes() -> void:
	for spike: Dictionary in state["spikes"]:
		var rect := Rect2(
			float(spike["x"]), float(spike["y"]), float(spike["w"]), float(spike["h"])
		)
		GobnomArt.draw_spikes(self, rect)


func _draw_mouth() -> void:
	var mood := "open"
	if phase == "won" or str(state["outcome"]) == "won":
		mood = "nom"
	elif GobnomLogic.is_over(state):
		mood = "sad"
	var mouth := Vector2((state["mouth"] as Dictionary)["pos"])
	GobnomArt.draw_gooby_mouth(self, mouth, 130.0, int(state["tick"]), mood)


func _draw_jars() -> void:
	var tick := int(state["tick"])
	for jar: Dictionary in state["jars"]:
		GobnomArt.draw_jar(self, Vector2(jar["pos"]), 22.0, tick, bool(jar["taken"]))


func _draw_cushions_and_fans() -> void:
	var tick := int(state["tick"])
	for cushion: Dictionary in state["cushions"]:
		var ready := int(cushion["charges"]) != 0 and tick >= int(cushion["ready_tick"])
		GobnomArt.draw_cushion(
			self,
			Vector2(cushion["pos"]),
			Vector2(cushion["dir"]),
			tick,
			ready,
			_owner_tint(str(cushion.get("owner", "any")))
		)
	for fan: Dictionary in state["fans"]:
		GobnomArt.draw_fan(
			self,
			Vector2(fan["pos"]),
			Vector2(fan["dir"]),
			tick,
			bool(fan["on"]),
			(
				_owner_tint(str(fan.get("owner", "any")))
				if bool(fan["toggleable"])
				else Color.TRANSPARENT
			)
		)


func _draw_ropes() -> void:
	var candy := GobnomLogic.candy_pos(state)
	for rope: Dictionary in state["ropes"]:
		if bool(rope["cut"]):
			continue
		GobnomArt.draw_rope(self, Vector2(rope["anchor"]), candy, float(rope["rest"]))
		GobnomArt.draw_anchor(
			self, Vector2(rope["anchor"]), _owner_tint(str(rope.get("owner", "any")))
		)


func _draw_bubbles() -> void:
	var tick := int(state["tick"])
	for bubble: Dictionary in state["bubbles"]:
		if bool(bubble["popped"]):
			continue
		var holds := bool(bubble["holds"])
		var at := GobnomLogic.candy_pos(state) if holds else Vector2(bubble["pos"])
		GobnomArt.draw_bubble(self, at, float(bubble["r"]), tick, holds)


func _draw_candy() -> void:
	if str(state["outcome"]) == "won":
		return
	var physics: Dictionary = balance.get("physics", {})
	GobnomArt.draw_candy(
		self, GobnomLogic.candy_pos(state), float(physics.get("candy_r", 14.0)), int(state["tick"])
	)


func _draw_sparks() -> void:
	for spark: Dictionary in _sparks:
		var t := 1.0 - float(spark["ttl"]) / float(spark["ttl_max"])
		var pos := Vector2(spark["pos"])
		match str(spark["kind"]):
			"cut":
				for i in 5:
					var a := TAU * float(i) / 5.0 + t * 3.0
					var p := pos + Vector2(cos(a), sin(a)) * (4.0 + t * 22.0)
					draw_circle(p, 3.0 - t * 2.6, Color(1.0, 0.85, 0.4, 0.9 - t * 0.9))
			"jar":
				draw_arc(pos, 8.0 + t * 26.0, 0, TAU, 16, Color(1.0, 0.83, 0.3, 0.9 - t * 0.9), 4.0)
			"pop":
				draw_arc(pos, 6.0 + t * 20.0, 0, TAU, 14, Color(0.6, 0.8, 0.95, 0.9 - t * 0.9), 3.0)
			"confetti":
				var vel := Vector2(spark["vel"])
				var p := pos + vel * t + Vector2(0, 260.0) * t * t
				draw_circle(p, 4.0 - t * 2.5, Color(spark["color"], 1.0 - t))


func _draw_swipes() -> void:
	for index: Variant in _pointers:
		var pointer: Dictionary = _pointers[index]
		if str(pointer["mode"]) != "swipe":
			continue
		var points: Array = pointer["points"]
		if points.size() < 2:
			continue
		var line := PackedVector2Array()
		for p: Variant in points:
			line.append(Vector2(p))
		draw_polyline(line, Color(1, 1, 1, 0.85), 5.0)
		draw_polyline(line, Color(0.98, 0.62, 0.71, 0.9), 2.5)


func _draw_hud() -> void:
	var chip := Rect2(8, 8, 168, 44)
	draw_rect(chip, GobnomArt.OUTLINE.lerp(AcTokens.PAPER, 0.7))
	draw_rect(chip.grow(-1.5), AcTokens.PAPER)
	var tag_key := "gobnom.hud.coop_level" if _is_coop() else "gobnom.hud.level"
	draw_string(
		_font_bold,
		chip.position + Vector2(10, 28),
		I18nService.t(tag_key, {"n": level_id}),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		AcTokens.INK
	)
	var taken := int(state["jars_taken"])
	for i in 3:
		var at := chip.position + Vector2(104.0 + float(i) * 20.0, 24.0)
		if i < taken:
			GobnomArt.draw_jar(self, at, 8.0, 0, false)
		else:
			draw_circle(at, 7.0, Color(0.29, 0.23, 0.21, 0.15))
	var cuts := GobnomLogic.cuts_left(state)
	if cuts >= 0:
		draw_string(
			_font,
			chip.position + Vector2(10, 60),
			I18nService.t("gobnom.hud.cuts", {"n": cuts}),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			AcTokens.INK
		)


func _draw_banner() -> void:
	if _banner_text == "" or Time.get_ticks_msec() / 1000.0 > _banner_until:
		return
	var vp := get_viewport_rect().size
	var rect := Rect2(vp.x * 0.5 - 170.0, vp.y * 0.24, 340.0, 60.0 if _banner_hint != "" else 44.0)
	draw_rect(rect, Color(0.29, 0.23, 0.21, 0.8))
	draw_string(
		_font_bold,
		rect.position + Vector2(0, 28),
		_banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x),
		20,
		Color.WHITE
	)
	if _banner_hint != "":
		draw_string(
			_font,
			rect.position + Vector2(0, 50),
			_banner_hint,
			HORIZONTAL_ALIGNMENT_CENTER,
			int(rect.size.x),
			14,
			Color(1, 1, 1, 0.85)
		)


func _owner_tint(owner_tag: String) -> Color:
	if not _is_coop():
		return Color.TRANSPARENT
	match owner_tag:
		"a":
			return Color(0.96, 0.63, 0.6, 0.30)
		"b":
			return Color(0.55, 0.78, 0.52, 0.30)
		_:
			return Color.TRANSPARENT


## ── UI-Aufbau (Select + Overlays) ────────────────────────────────────────


func _build_select_screen() -> void:
	_select_screen = GobnomLevelSelect.new()
	_select_screen.game_state = _game_state()
	_select_screen.level_chosen.connect(open_level)
	_select_screen.done_pressed.connect(finish_session)
	add_child(_select_screen)
	# KEINE Anker setzen: unter dem Node2D-Parent wäre das anchorable-Rect
	# 0×0 — der Select bindet sich in _ready() selbst an den Viewport.


func _build_end_overlay(won: bool, stars: int, total: int, first_clear: bool) -> void:
	_clear_overlay()
	_overlay = VBoxContainer.new()
	_overlay.add_theme_constant_override("separation", 10)
	add_child(_overlay)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("gobnom.end.win" if won else "gobnom.end.lose")
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
				I18nService.t("gobnom.end.score", {"n": total}),
			]
		)
		if first_clear:
			info.text += "\n" + I18nService.t("gobnom.end.first_clear")
	else:
		info.text = I18nService.t("gobnom.end.lose_hint")
	_overlay.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(row)
	if won and level_id < GobnomProgress.level_count(track):
		row.add_child(
			_overlay_button("gobnom.end.next", func() -> void: open_level(track, level_id + 1))
		)
	if not won:
		row.add_child(
			_overlay_button("gobnom.end.retry", func() -> void: open_level(track, level_id))
		)
	row.add_child(_overlay_button("gobnom.end.select", back_to_select))
	var vp := get_viewport_rect().size
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


func _is_coop() -> bool:
	return not state.is_empty() and bool(state["coop"])


func _show_banner(text: String) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + BANNER_SEC


func _spawn_spark(pos: Vector2, kind: String) -> void:
	_sparks.append({"pos": pos, "kind": kind, "ttl": 0.4, "ttl_max": 0.4})


## Sieg-Konfetti (rein visuell — deterministische Fächer-Winkel, kein RNG).
func _spawn_confetti(pos: Vector2) -> void:
	var colors := [GobnomArt.CANDY_PINK, GobnomArt.STAR_GOLD, Color("#8FD0EA"), Color("#A8D083")]
	for i in 18:
		var a := -PI * 0.9 + PI * 0.8 * float(i) / 17.0
		(
			_sparks
			. append(
				{
					"pos": pos,
					"kind": "confetti",
					"vel": Vector2(cos(a), sin(a)) * (140.0 + 40.0 * float(i % 3)),
					"color": colors[i % colors.size()],
					"ttl": 1.1,
					"ttl_max": 1.1,
				}
			)
		)


func _decay_sparks(delta: float) -> void:
	for i in range(_sparks.size() - 1, -1, -1):
		_sparks[i]["ttl"] = float(_sparks[i]["ttl"]) - delta
		if float(_sparks[i]["ttl"]) <= 0.0:
			_sparks.remove_at(i)
