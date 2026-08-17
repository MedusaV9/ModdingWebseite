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
## (hot-seat/Multi-Touch). W15 NETZ-COOP (coop_netz/**): dieselben Coop-
## Level über zwei Geräte — deterministischer Lockstep (GobnomLockstep)
## über GobnomNetSession; Einladung im Level-Select (GobnomNetzPanel, nur
## online + Freund). Ohne Verbindung bleibt ALLES beim lokalen Hot-Seat.
## Punkte laufen NUR über ctx.report_score/report_end (Award macht der Host);
## jeder Levelsieg meldet einen Coin-Chunk (E10-P1-3-Muster wie GvZ).
##
## ECHTE 3D-CANDYLAND-BÜHNE (FB-4, GobnomStage3D): das Puzzle spielt auf einer
## senkrechten Ebene vor einer Zuckerwatte-Wiese — Bonbon, Seile, Blasen,
## Ventilatoren, Stachelbretter und Gläser sind echte Meshes, Gooby (echtes
## Rig) wartet als Fänger. Alle Anker gehen als _to_screen-Pixel per
## wall_point-Raycast auf die Ebene — Schnitte und Taps bleiben EXAKT unter
## dem Finger, die MECHANIK (GobnomLogic) bleibt zahlengleich.

const Stage := preload("res://scripts/minigames/games/gobnom/gobnom_stage3d.gd")

const TICK_SEC := 1.0 / 60.0
const BANNER_SEC := 2.2
## G5 P36 Intro-Beat (mg-audit-b §2 P2): Kamerafahrt Regal→Seil, 1,5 s wie
## der W14-Kanon (gvz/carrot_catch) — Sim UND Eingabe warten solange.
const INTRO_S := 1.5
const SWIPE_TRAIL_MAX := 14
const TAP_RADIUS := 34.0

## Testschalter: GameState-Double VOR setup() setzen (Muster W2a RoomBase).
var game_state_override: Object
## Testschalter: NetClient-Double VOR setup() setzen (sonst /root/Net).
var net_override: Object

## Netz-Coop (W15): Session (Protokoll) — _netz-Interna stehen unten bei
## den privaten Vars; _netz == null ⇒ lokaler Hot-Seat-Pfad wie bisher.
var netz_session: GobnomNetSession

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
## Rest des Intro-Beats (s): >0 ⇒ Kamerafahrt läuft, Sim/Eingabe gegated.
var _intro_left := 0.0
var _run_score := 0
var _last_reported := 0
var _banner_text := ""
var _banner_hint := ""
var _banner_until := 0.0
## Glas-Zähler im HUD-Chip: letzter Stand + Pop-Startzeit (Sammel-Feier).
var _jars_seen := 0
var _jar_pop := -10.0
## Schnitt-Serie fürs Audio (MG-Audit B §2): Pitch-Treppe, rein Präsentation.
var _cut_streak := 0
## Aktive Zeiger: index → {mode: swipe|anchor|none, player, last, points, rope}.
var _pointers: Dictionary = {}
var _select_screen: GobnomLevelSelect
var _overlay: Control
var _font: Font
var _font_bold: Font
var _stage: Node3D
## Netz-Coop-Interna (W15): Lockstep-Treiber + UI-Zustand.
var _netz: GobnomLockstep
var _netz_active := false
var _netz_waiting := false
var _netz_panel: GobnomNetzPanel
var _netz_partner_cursor := Vector2.ZERO
var _netz_partner_cursor_at := -10.0
var _netz_cursor_sent_at := -10.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	GobnomProgress.register_slice()
	balance = GobnomData.load_balance(null)
	campaign = GobnomData.load_campaign()
	coop_levels = GobnomData.load_coop()
	_font = ThemeService.font(600)
	_font_bold = ThemeService.font(800)
	_stage = Stage.new()
	_stage.name = "Candyland3D"
	_stage.to_px = _to_screen
	add_child(_stage)
	_stage.setup_stage()
	_stage.visible = false
	if ctx != null and ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_setup_netz()
	_build_select_screen()
	queue_redraw()


## Pflicht-Layouthook: Kamera stellen und alle Ebenen-Anker neu raycasten.
func apply_view(size: Vector2) -> void:
	if _stage == null:
		return
	_stage.frame(size)
	if not state.is_empty():
		_stage.layout_level(state, balance)


func start() -> void:
	super.start()
	queue_redraw()


func end() -> void:
	super.end()
	ended = true
	if netz_session != null:
		netz_session.leave()


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
	_netz_active = false
	_netz = null
	state = GobnomLogic.new_run(level, balance, seed_value)
	_enter_play(level)


## Gemeinsamer Spielstart-Rest (lokal UND Netz): Bühne, Banner, Select weg.
## with_intro=false überspringt den Establish-Beat (Netz-Rejoin mitten im
## Lauf ist Aufholjagd, kein Rundenstart).
func _enter_play(level: Dictionary, with_intro := true) -> void:
	phase = "play"
	_accum = 0.0
	_run_score = 0
	_cut_streak = 0
	_pointers = {}
	_stage.visible = true
	_stage.frame(get_viewport_rect().size)
	_stage.layout_level(state, balance)
	# G5 P36 Intro-Beat: Kamera startet am Regal (Reduced Motion: sofort
	# Spielpose) — _process zählt _intro_left herunter und gated die Sim.
	_intro_left = INTRO_S if with_intro else 0.0
	_stage.establish(0.0 if with_intro and not _rm() else 1.0)
	var tag_key := "gobnom.hud.coop_level" if _is_coop() else "gobnom.hud.level"
	var hint_key := "gobnom.intro.%s" % str(level.get("intro", ""))
	_banner_hint = I18nService.t(hint_key) if I18nService.has_key(hint_key) else ""
	_show_banner(I18nService.t(tag_key, {"n": level_id}))
	if _select_screen != null:
		_select_screen.visible = false
	_clear_overlay()
	queue_redraw()


func back_to_select() -> void:
	_netz_active = false
	_netz = null
	_netz_waiting = false
	phase = "select"
	state = {}
	_stage.visible = false
	_clear_overlay()
	if _select_screen != null:
		_select_screen.visible = true
		_select_screen.refresh()
	queue_redraw()


func finish_session() -> void:
	if netz_session != null:
		netz_session.leave()
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
		if _intro_left > 0.0:
			# G5 P36 Intro-Beat: Kamera fährt vom Regal zum Seil, Sim und
			# Lockstep-Pump warten — rein präsentational (Wandzeit), Tick-
			# Zahlen/Seeds/Inputs bleiben unberührt; Partner-Frames puffern
			# derweil über _on_netz_frame, der Start-Fence ging schon raus.
			_intro_left = maxf(0.0, _intro_left - minf(delta, 0.25))
			_stage.establish(1.0 if _rm() else 1.0 - _intro_left / INTRO_S)
		else:
			_accum += minf(delta, 0.25)
			if _netz_active:
				_netz_pump()
			else:
				while _accum >= TICK_SEC and not GobnomLogic.is_over(state):
					_accum -= TICK_SEC
					_consume_events(GobnomLogic.step(state))
			_report_live_score()
			if GobnomLogic.is_over(state):
				_on_run_over()
	_sync_stage(delta)
	queue_redraw()


## Netz-Coop-Takt: Wandzeit-Ticks in den Lockstep pumpen (die Sim rechnet
## nur, solange der Partner-Fence vorliegt), fällige Frames/Hashes senden.
func _netz_pump() -> void:
	var stalled := false
	while _accum >= TICK_SEC and not GobnomLogic.is_over(state):
		_accum -= TICK_SEC
		var result := _netz.advance()
		if bool(result["stepped"]):
			_consume_events(result["events"])
		else:
			stalled = true
	_netz_waiting = stalled and not GobnomLogic.is_over(state)
	# Aufhol-Deckel: beim Warten läuft keine Zeitschuld auf.
	_accum = minf(_accum, TICK_SEC * 8.0)
	if _netz.desynced:
		_on_netz_desync(_netz.desync_tick)
		return
	var frame := _netz.take_frame()
	if not frame.is_empty():
		netz_session.send_frame(frame)
	for entry: Dictionary in _netz.take_hashes():
		netz_session.send_hash(int(entry["t"]), str(entry["h"]))


## Jeden Frame: Bonbon, Seile, Blasen und Swipe-Spuren an die 3D-Bühne.
func _sync_stage(delta: float) -> void:
	if _stage == null or state.is_empty():
		return
	var swipe_pts: Array = []
	for index: Variant in _pointers:
		var pointer: Dictionary = _pointers[index]
		if str(pointer["mode"]) != "swipe":
			continue
		for p: Variant in pointer["points"]:
			swipe_pts.append(Vector2(p))
	_stage.sync_state(state, GobnomLogic.candy_pos(state), swipe_pts, delta)


func _consume_events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event["kind"]):
			"cut":
				_stage.cut_fx(Vector2(event["at"]))
				_cut_streak += 1
				AudioDirector.try_play(self, "mg_combo", FeelSfx.combo_pitch(_cut_streak))
			"jar":
				var at := Vector2(event["at"])
				_stage.jar_fx(at)
				var jars := maxi(1, int(state.get("jars_taken", 1)))
				AudioDirector.try_play(self, "gvz_collect", FeelSfx.combo_pitch(jars))
				if ctx != null and ctx.juice != null:
					ctx.juice.float_text(
						_to_screen(at), I18nService.t("gobnom.hud.jar"), GobnomArt.STAR_GOLD
					)
					if int(state["jars_taken"]) >= 3:
						ctx.juice.bloom_pulse(0.5, 300)
			"pop":
				_stage.pop_fx(Vector2(event["at"]))
				AudioDirector.try_play(self, "gvz_balloon")
			"catch":
				_stage.pop_fx(GobnomLogic.candy_pos(state))
				AudioDirector.try_play(self, "ui_chip")
			"puff":
				_stage.puff_fx(GobnomLogic.candy_pos(state))
				AudioDirector.try_play(self, "mg_spill", 1.2)
				if bool(event["hit"]) and ctx != null and ctx.juice != null:
					ctx.juice.shake(0.25)
			"shoot":
				_stage.cut_fx(GobnomLogic.candy_pos(state))
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
				_stage.confetti_fx(GobnomLogic.candy_pos(state))


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
	# Netz-Coop: Ergebnis idempotent an den Server melden (beide Sims sind
	# identisch — der Award läuft trotzdem je LOKAL über den Normal-Pfad).
	if _netz_active and netz_session != null:
		netz_session.report_result(
			str(state["outcome"]), int(state["jars_taken"]), int(state["tick"])
		)
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
				ctx.juice.confetti(70)
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
	# _intro_left: während des Establish-Beats nimmt das Spiel nichts an
	# (hide_seek/pancake-Muster) — gilt lokal UND im Netz-Coop.
	if not is_active() or phase != "play" or _intro_left > 0.0 or state.is_empty():
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
	if _netz_active:
		_netz_pointer_down(index, world)
		return
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
	if _netz_active:
		_netz_pointer_move(pointer, world)
		return
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


## ── Netz-Coop-Eingabe: NUR die eigene Hälfte, Aktionen laufen als geplante
## Lockstep-Inputs (Tick + Seite) statt direkt in die Sim ─────────────────


func _netz_pointer_down(index: int, world: Vector2) -> void:
	_netz_send_cursor(world)
	if GobnomLogic.side_of(state, world) != _netz.side:
		# Fremde Hälfte: freundlich abblocken (das Sim-Gate würde die Aktion
		# ohnehin deterministisch auf beiden Geräten verweigern).
		AudioDirector.try_play(self, "ui_error")
		if ctx != null and ctx.juice != null:
			ctx.juice.float_text(
				_to_screen(world), I18nService.t("gobnom.hud.wrong_side"), Color("#E0655F")
			)
		_pointers[index] = {"mode": "none", "player": _netz.side}
		return
	var rail_rope := _rail_anchor_at(world)
	if rail_rope >= 0:
		_pointers[index] = {"mode": "anchor", "player": _netz.side, "rope": rail_rope}
		return
	if _netz_tap_element(world):
		_pointers[index] = {"mode": "none", "player": _netz.side}
		return
	_pointers[index] = {"mode": "swipe", "player": _netz.side, "last": world, "points": [world]}


func _netz_pointer_move(pointer: Dictionary, world: Vector2) -> void:
	_netz_send_cursor(world)
	match str(pointer["mode"]):
		"anchor":
			var rope_id := int(pointer["rope"])
			_netz.schedule("slide", rope_id, _rail_t_for(rope_id, world))
		"swipe":
			var last := Vector2(pointer["last"])
			for rope_id: int in _netz.ropes_crossed(last, world):
				_netz.schedule("cut", rope_id)
				if ctx != null and ctx.juice != null:
					ctx.juice.hit_freeze(45)
			pointer["last"] = world
			var points: Array = pointer["points"]
			points.append(world)
			while points.size() > SWIPE_TRAIL_MAX:
				points.pop_front()


## Tap im Netz-Coop: Element finden wie lokal, aber als Aktion planen.
func _netz_tap_element(world: Vector2) -> bool:
	for bubble: Dictionary in state["bubbles"]:
		if bool(bubble["popped"]):
			continue
		var at := GobnomLogic.candy_pos(state) if bool(bubble["holds"]) else Vector2(bubble["pos"])
		if world.distance_to(at) <= float(bubble["r"]) + 18.0:
			_netz.schedule("pop", int(bubble["id"]))
			return true
	for cushion: Dictionary in state["cushions"]:
		if world.distance_to(Vector2(cushion["pos"])) <= TAP_RADIUS:
			_netz.schedule("puff", int(cushion["id"]))
			return true
	for fan: Dictionary in state["fans"]:
		if bool(fan["toggleable"]) and world.distance_to(Vector2(fan["pos"])) <= TAP_RADIUS:
			_netz.schedule("fan", int(fan["id"]))
			return true
	return false


## Eigenen Cursor gedrosselt (10 Hz) an den Partner senden.
func _netz_send_cursor(world: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _netz_cursor_sent_at < 0.1:
		return
	_netz_cursor_sent_at = now
	netz_session.send_cursor(world)


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


## Die Bühne rendert die Welt in 3D; 2D bleiben nur Select-Hintergrund,
## HUD-Chip, Banner und die Abdunklung der Endscreens.
func _draw() -> void:
	var vp := get_viewport_rect().size
	if phase == "select" or state.is_empty():
		draw_rect(Rect2(Vector2.ZERO, vp), AcTokens.BG_CREAM)
		return
	_draw_hud()
	_draw_banner()
	if _netz_active:
		_draw_netz_overlay()
	if phase != "play":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.29, 0.23, 0.21, 0.35))


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
	if taken != _jars_seen:
		if taken > _jars_seen:
			_jar_pop = Time.get_ticks_msec() / 1000.0
		_jars_seen = taken
	var pop := maxf(0.0, 1.0 - (Time.get_ticks_msec() / 1000.0 - _jar_pop) / 0.4)
	for i in 3:
		var at := chip.position + Vector2(104.0 + float(i) * 20.0, 24.0)
		if i < taken:
			# Das zuletzt gefangene Glas poppt golden auf.
			var s := 8.0 * (1.0 + 0.5 * pop) if i == taken - 1 else 8.0
			if i == taken - 1 and pop > 0.0:
				draw_circle(at, s + 4.0, Color(1.0, 0.83, 0.3, 0.35 * pop))
			GobnomArt.draw_jar(self, at, s, 0, false)
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


## Netz-Coop-Schicht: Partner-Cursor (frisch < 1,5 s, auf der Partner-Seite)
## und der „Warte auf Partner“-Hinweis — mittig (G4), nicht am HUD-Chip.
func _draw_netz_overlay() -> void:
	if phase == "play" and _netz_waiting:
		draw_string(
			_font,
			Vector2(0, 84),
			I18nService.t("gobnom.netz.warte_partner"),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(get_viewport_rect().size.x),
			14,
			Color(0.29, 0.23, 0.21, 0.8)
		)
	var age := Time.get_ticks_msec() / 1000.0 - _netz_partner_cursor_at
	if age > 1.5 or netz_session == null:
		return
	var alpha := clampf(1.5 - age, 0.0, 1.0)
	var at := _to_screen(_netz_partner_cursor)
	var tint := Color("#7A5CC6")
	draw_circle(at, 15.0, Color(tint.r, tint.g, tint.b, 0.22 * alpha))
	draw_arc(at, 15.0, 0.0, TAU, 28, Color(tint.r, tint.g, tint.b, alpha), 2.5)
	draw_circle(at, 4.0, Color(tint.r, tint.g, tint.b, alpha))
	draw_string(
		_font_bold,
		at + Vector2(20, 5),
		netz_session.partner_gooby_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(tint.r, tint.g, tint.b, alpha)
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


## ── UI-Aufbau (Select + Overlays) ────────────────────────────────────────


func _build_select_screen() -> void:
	_select_screen = GobnomLevelSelect.new()
	_select_screen.game_state = _game_state()
	_select_screen.netz_panel = _netz_panel
	_select_screen.level_chosen.connect(_on_level_chosen)
	_select_screen.done_pressed.connect(finish_session)
	add_child(_select_screen)
	# KEINE Anker setzen: unter dem Node2D-Parent wäre das anchorable-Rect
	# 0×0 — der Select bindet sich in _ready() selbst an den Viewport.


## ── Netz-Coop-Verdrahtung (W15) ──────────────────────────────────────────


## Session + Panel nur bauen, wenn es einen NetClient gibt — ohne /root/Net
## (bzw. net_override in Tests) bleibt der komplette Hot-Seat-Pfad unberührt.
func _setup_netz() -> void:
	var net: Object = net_override if net_override != null else get_node_or_null("/root/Net")
	if net == null:
		return
	netz_session = GobnomNetSession.new()
	netz_session.name = "NetzCoop"
	add_child(netz_session)
	netz_session.setup(net)
	netz_session.game_started.connect(_on_netz_start)
	netz_session.frame_received.connect(_on_netz_frame)
	netz_session.hash_received.connect(_on_netz_hash)
	netz_session.cursor_received.connect(_on_netz_cursor)
	netz_session.desync_reported.connect(_on_netz_desync)
	netz_session.result_confirmed.connect(_on_netz_result)
	netz_session.session_aborted.connect(_on_netz_aborted)
	netz_session.peer_connection_changed.connect(_on_netz_peer_changed)
	netz_session.snapshot_received.connect(_on_netz_snapshot)
	_netz_panel = GobnomNetzPanel.new()
	_netz_panel.setup(netz_session)


## Kachel-Klick: gepaart + Coop-Track → Level-Handshake statt Hot-Seat.
func _on_level_chosen(level_track: String, id: int) -> void:
	if level_track == GobnomProgress.TRACK_COOP and netz_session != null:
		if netz_session.is_paired():
			netz_session.choose_level(id)
			if _netz_panel != null:
				_netz_panel.show_vote(id)
			return
	open_level(level_track, id)


## GOBNOM_START: beide Geräte bauen die identische Sim aus Server-Seed.
func _on_netz_start(data: Dictionary) -> void:
	var id := int(data.get("level", 1))
	track = GobnomProgress.TRACK_COOP
	level_id = id
	attempt += 1
	var level := GobnomData.level_by_id(coop_levels, id)
	_netz = GobnomLockstep.new()
	_netz.start(
		level, balance, netz_session.seed_value, netz_session.my_side, netz_session.input_delay
	)
	_netz.hash_ticks = netz_session.hash_every_ticks
	state = _netz.state
	_netz_active = true
	_netz_waiting = false
	_netz_partner_cursor_at = -10.0
	_enter_play(level)
	_show_banner(
		I18nService.t("gobnom.netz.start_banner", {"name": netz_session.partner_gooby_name})
	)
	# Erster Fence sofort raus — der Partner darf die ersten Ticks rechnen.
	netz_session.send_frame(_netz.take_frame(true))


func _on_netz_frame(body: Dictionary) -> void:
	if _netz != null:
		_netz.receive_frame(body)


func _on_netz_hash(tick: int, hash_text: String) -> void:
	if _netz != null:
		_netz.receive_hash(tick, hash_text)


func _on_netz_cursor(pos: Vector2) -> void:
	_netz_partner_cursor = pos
	_netz_partner_cursor_at = Time.get_ticks_msec() / 1000.0
	queue_redraw()


## Desync (lokal ODER vom Server gemeldet): höflicher Abbruch mit Toast
## statt Weiterspielen auf divergenten Welten.
func _on_netz_desync(_tick: int) -> void:
	if not _netz_active:
		return
	if netz_session != null:
		netz_session.leave()
	_netz_abort("gobnom.netz.desync")


## Ergebnis bestätigt: die Session ist verbraucht (der Server erlaubt nach
## 'done' kein neues Level-Voting) — sauber gehen, sonst blockiert die tote
## Paarung serverseitig JEDE neue Einladung (GAME_RUNNING). Nächste Runde =
## neue Einladung über das wieder freie Panel.
func _on_netz_result(_data: Dictionary) -> void:
	if netz_session != null:
		netz_session.leave()
	if _netz_panel != null:
		_netz_panel.refresh()


func _on_netz_aborted(_reason: String, _by: String) -> void:
	if _netz_active:
		_netz_abort("gobnom.netz.abbruch")
	elif _netz_panel != null:
		_netz_panel.refresh()


func _on_netz_peer_changed(down: bool, _wait_ms: int) -> void:
	if not _netz_active or netz_session == null:
		return
	var key := "gobnom.netz.partner_weg" if down else "gobnom.netz.partner_da"
	_show_banner(I18nService.t(key, {"name": netz_session.partner_gooby_name}))
	queue_redraw()


## Eigener Rejoin mitten im Lauf: Snapshot replayen (Seed + Frame-Puffer
## beider Seiten) und nahtlos weiterspielen.
func _on_netz_snapshot(data: Dictionary) -> void:
	if netz_session == null or str(data.get("phase", "")) != "run":
		return
	var id := int(data.get("level", 0))
	if id <= 0:
		return
	track = GobnomProgress.TRACK_COOP
	level_id = id
	var level := GobnomData.level_by_id(coop_levels, id)
	if _netz == null:
		_netz = GobnomLockstep.new()
	_netz.resume(
		level,
		balance,
		int(data.get("seed", 0)),
		netz_session.my_side,
		data.get("frames", {}),
		int(data.get("inputDelay", GobnomLockstep.INPUT_DELAY))
	)
	_netz.hash_ticks = netz_session.hash_every_ticks
	state = _netz.state
	_netz_active = true
	_enter_play(level, false)


func _netz_abort(toast_key: String) -> void:
	_netz_active = false
	_netz = null
	AudioDirector.try_play(self, "ui_error")
	if ctx != null and ctx.juice != null:
		ctx.juice.float_text(
			get_viewport_rect().size * 0.5, I18nService.t(toast_key), Color("#E0655F")
		)
	back_to_select()


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
	# Netz-Coop: Weiter/Nochmal liefe lokal am Partner vorbei — die nächste
	# Runde startet über den Level-Handshake im Select (Panel bleibt gepaart).
	if won and level_id < GobnomProgress.level_count(track) and not _netz_active:
		row.add_child(
			_overlay_button(
				"gobnom.end.next", func() -> void: open_level(str(track), int(level_id) + 1)
			)
		)
	if not won and not _netz_active:
		row.add_child(
			_overlay_button(
				"gobnom.end.retry", func() -> void: open_level(str(track), int(level_id))
			)
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


## Reduced Motion — dieselbe Quelle wie gobnom_stage3d._rm() (UiTheme).
func _rm() -> bool:
	return ThemeService.is_reduced_motion(self)


func _show_banner(text: String) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + BANNER_SEC
