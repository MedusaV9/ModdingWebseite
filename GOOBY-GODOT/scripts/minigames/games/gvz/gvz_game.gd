extends MinigameBase
## GvZ-Spielszene (W3b) im W2d-Minigame-Contract: Level-Select → Gefecht →
## Sieg/Niederlage, alles über der PUREN Simulation (GvzLogic — die Szene
## rendert nur State und ruft Aktions-Funktionen). Querformat bevorzugt,
## Hochkant skaliert das Grid. Steuerung: Karte antippen ODER ziehen
## (Drag-Ghost), Klecks antippen = einsammeln, Schaufel entfernt Türme.
## Punkte laufen NUR über ctx.report_score/report_end (Award macht der Host).
## Feedback (W4-P1): JuiceKit an Gefechts-Momenten + AudioDirector-SFX.
##
## FB-4: das Gefecht spielt auf einer ECHTEN 3D-Bühne (gvz_stage3d.gd) —
## Figuren sind Meshes, per ground_point-Raycast unterm 2D-Grid verankert;
## die 2D-Schicht rendert nur HUD — seit G5/P26 gezeichnet von gvz_hud.gd
## (diese Datei behält Layout-Mathe + Eingabe, der HUD liest über die
## HUD-API hud_resource()/_card_info()/netz_hud_info()).
## W16/G4: Kartenleiste + Zähler hängen an der UNTERKANTE (Daumenzone),
## Karten stehen auf dem Touch-Floor (>=48 pt), Boss-Bar oben mittig.
##
## G5/P26 NETZ-PVP (pvp_netz/**): 1-gegen-1 Goobys vs. Zombies übers Netz —
## GvzNetSession (Protokoll) + GvzPvpLockstep (deterministische Sim) nach
## dem GOB-NOM-Muster (W15). _netz == null ⇒ lokale Kampagne wie bisher.

const Stage := preload("res://scripts/minigames/games/gvz/gvz_stage3d.gd")

const TICK_SEC := 0.05
const CARD_W := 56.0
const CARD_H := 62.0
const TOP_PAD := 6.0
const MOWER_GUTTER := 72.0  # W14: 44 px schnitten die Mäher-Goobys links ab.
const INTRO_S := 1.5  # W14 Intro-Beat: Establishing + Ziel-Banner, dann Sim.

## W13/GVZ (P5-Report G18, Doc G §4.4): Meilenstein-Siege feuern Sticker-
## Hooks — L15 „Garten gerettet!“, L5/L10 „Zaunheld“/„Nutella-Kommandant“.
const MILESTONE_HOOKS := {5: "gvz_l5", 10: "gvz_l10", 15: "gvz_kampagne"}
## Run-Stats (GvzLogic state.stats) → Counter-Keys der GvZ-Sticker-Conds.
const STAT_COUNTERS := {
	"drops_collected": "gvzNutella",
	"eis_placed": "gvzEisEinsaetze",
	"bert_placed": "gvzBertEinsaetze",
	"moehren_shots": "gvzMoehrenSchuesse",
}

## Testschalter: GameState-Double VOR setup() setzen (Muster W2a RoomBase).
var game_state_override: Object
## Testschalter: NetClient-Double VOR setup() setzen (Muster gobnom/W15).
var net_override: Object

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
## Netz-PvP (P26): Session (Protokoll) — _netz-Interna stehen unten bei den
## privaten Vars; netz_session == null ⇒ offline, nur lokale Kampagne.
var netz_session: GvzNetSession

var _accum := 0.0
## Intro-Beat-Restzeit (Sekunden): > 0 = Bühne steht, Sim wartet.
var _intro_left := 0.0
var _last_run_score := 0
var _prev_zombie_pos: Dictionary = {}
## W21/P5 Feier-Beat: true, sobald eine Welle Zombies aufs Feld gebracht
## hat — fällt der Zähler danach auf 0, feiert „Welle überstanden!".
var _welle_aktiv := false
var _select_screen: GvzLevelSelect
var _overlay: Control
var _stage: Node3D
## HUD-Zeichner (G5/P26-Split): Karten, Zähler, Balken, Banner, Ghost.
var _hud: GvzHud
## End-Overlay-Bauer (P26-Split, Stufe 2: Sterne-Pop + Icon-Knöpfe).
var _overlay_builder: GvzOverlay
## Netz-PvP-Zustand: Lockstep-Sim, Panel, aktiv-Flag + „warte auf Partner“.
var _netz: GvzPvpLockstep
var _netz_panel: GvzNetzPanel
var _netz_active := false
var _netz_waiting := false
## PvP-Regeln (data/gvz_pvp.json), einmal beim Netz-Setup geladen.
var _pvp: Dictionary = {}


func _init() -> void:
	# HUD-/Overlay-Helfer schon im Konstruktor (nur self-Referenz, kein
	# Tree-Zugriff): Bestands-Tests instanziieren die Szene roh und rufen
	# _build_end_overlay ohne setup(ctx) — vor dem P26-Split war das Overlay
	# inline gebaut und brauchte keine Vorbereitung.
	_hud = GvzHud.new(self)
	_overlay_builder = GvzOverlay.new(self)


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	GvzProgress.register_slice()
	balance = GvzData.load_balance(null)
	levels = GvzData.load_levels()
	_stage = Stage.new()
	_stage.name = "Vorgarten3D"
	add_child(_stage)
	_stage.setup_stage()
	_stage.visible = false
	if ctx != null and ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_setup_netz()
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
	if netz_session != null:
		netz_session.leave()


## ── Phasen-Wechsel ───────────────────────────────────────────────────────


func open_level(id: int) -> void:
	level_id = id
	attempt += 1
	_netz_active = false
	_netz = null
	var level := GvzData.level_by_id(levels, id)
	var seed_value := ctx.run_seed + id * 1009 + attempt * 131 if ctx != null else id
	var opts := {"goldi": GvzProgress.goldi_unlocked(_game_state())}
	state = GvzLogic.new_run(level, balance, _difficulty(), seed_value, opts)
	_enter_battle()
	_show_banner(I18nService.t("gvz.intro.ziel", {"n": id}), "intro")


## Gemeinsamer Gefechts-Start (lokal UND Netz): Bühne an, Select weg.
func _enter_battle() -> void:
	phase = "battle"
	selected_card = ""
	dragging = false
	_accum = 0.0
	_last_run_score = 0
	_prev_zombie_pos = {}
	_welle_aktiv = false
	_intro_left = INTRO_S
	if _select_screen != null:
		_select_screen.visible = false
	if _stage != null:
		_stage.visible = true
		_stage.frame(_view_size())
		_relayout_stage()
		_stage.establish(0.0)
	_clear_overlay()
	queue_redraw()


func back_to_select() -> void:
	phase = "select"
	state = {}
	_netz_active = false
	_netz = null
	_netz_waiting = false
	if _stage != null:
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
	# E11-P1-5: "levels" zählt die WIRKLICH abgeschlossenen Level.
	var gs := _game_state()
	var stars := GvzProgress.total_stars(gs)
	ctx.report_end(
		{"score": session_score, "stars": stars, "levels": GvzProgress.cleared_count(gs)}
	)


## ── Simulation ───────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if not is_active() or phase != "battle" or state.is_empty():
		return
	# Intro-Beat: Kamera schwebt in die Spielpose, Sim läuft (1. Welle kommt spät).
	if _intro_left > 0.0:
		_intro_left = maxf(_intro_left - minf(delta, 0.25), 0.0)
		if _stage != null:
			_stage.establish(1.0 - _intro_left / INTRO_S)
	_accum += minf(delta, 0.25)
	if _netz_active:
		_netz_pump()
	else:
		while _accum >= TICK_SEC and not GvzLogic.is_over(state):
			_accum -= TICK_SEC
			_remember_zombie_positions()
			_consume_events(GvzLogic.tick(state))
		_report_live_score()
		_feier_welle_check()
		if GvzLogic.is_over(state):
			_on_run_over()
	_sync_stage(delta)
	queue_redraw()


## Netz-PvP-Takt (Muster gobnom/W15): Wandzeit-Ticks in den Lockstep pumpen
## — die Sim rechnet nur, solange der Partner-Fence vorliegt; danach gehen
## fällige Frames/Hashes raus. Das Match-Ende entscheidet der Lockstep
## (Überlebens-Timer ODER Haus-Durchbruch), nicht GvzLogic.is_over.
func _netz_pump() -> void:
	var stalled := false
	while _accum >= TICK_SEC and not _netz.is_match_over():
		_accum -= TICK_SEC
		_remember_zombie_positions()
		var result := _netz.advance()
		if bool(result["stepped"]):
			_consume_events(result["events"])
		else:
			stalled = true
	_netz_waiting = stalled and not _netz.is_match_over()
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
	if _netz.is_match_over():
		_on_netz_over()


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


## W21/P5 Feier-Beat (NUR Präsentation, liest den Sim-State): eine Welle
## brachte Zombies — fällt der Bestand danach auf 0 und der Lauf ist nicht
## vorbei, poppt der Kit-Beat „Welle überstanden!" (MotionKit, RM-gated).
func _feier_welle_check() -> void:
	if not (state["zombies"] as Array).is_empty():
		_welle_aktiv = true
		return
	if _welle_aktiv and phase == "battle" and not GvzLogic.is_over(state):
		_welle_aktiv = false
		MgHudKit.feier_beat(self, _view_size(), _hud.ui(), I18nService.t("mg.hudkit.beat_welle"))


func _on_run_over() -> void:
	if phase != "battle" or _netz_active:
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
			# E10-P1-3: jeder Levelsieg ist eine eigene Coin-Einheit.
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


## PvP-Matchende: der Sieger kommt aus dem Lockstep (Timer ODER Haus-
## Durchbruch). BEWUSST kein Kampagnen-Fortschritt/Coin-Award und keine
## Sticker-Counter (Fairness: beide Sims sind identisch, die Hälfte der
## Aktionen stammt vom Partner) — das Ergebnis geht idempotent an den
## Server (GVZ_RESULT), die Revanche läuft über das wieder freie Panel.
func _on_netz_over() -> void:
	if phase != "battle":
		return
	var won := _netz.winner == _netz.side
	if netz_session != null:
		netz_session.report_result(_netz.winner, int(state["tick"]))
	if won:
		phase = "won"
		_stage.win_fx()
		AudioDirector.try_play(self, "mg_win")
		if ctx != null and ctx.juice != null:
			ctx.juice.bloom_pulse(0.9)
			ctx.juice.confetti(80)
	else:
		phase = "lost"
		_stage.lose_fx()
		AudioDirector.try_play(self, "mg_lose")
		if ctx != null and ctx.juice != null:
			ctx.juice.shake(0.7)
			ctx.juice.hit_freeze(120)
	_build_netz_end_overlay(won)
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
	if _netz_active:
		_apply_card_netz(cell, at)
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
		_reject_feedback(at, str(placed["reason"]))
	queue_redraw()


## Netz-PvP: Aktionen laufen NICHT sofort, sondern über den Lockstep
## (deterministisch bei Tick t auf BEIDEN Geräten). Das Gate wird lokal
## vorgeprüft (sofortiges Feedback); die Wirkung erscheint nach dem
## Input-Delay — die Sim-Gates entscheiden endgültig bei der Ausführung.
func _apply_card_netz(cell: Vector2i, at: Vector2) -> void:
	if _netz_zombie():
		var spawn_check := _netz.can_spawn(selected_card, cell.y)
		if bool(spawn_check["ok"]):
			_netz.schedule_spawn(selected_card, cell.y)
			selected_card = ""
			AudioDirector.try_play(self, "gvz_place")
		else:
			_reject_feedback(at, str(spawn_check["reason"]))
		queue_redraw()
		return
	if selected_card == "shovel":
		_netz.schedule_shovel(cell.y, cell.x)
		selected_card = ""
		AudioDirector.try_play(self, "gvz_shovel")
		queue_redraw()
		return
	var place_check := GvzLogic.can_place(state, selected_card, cell.y, cell.x)
	if bool(place_check["ok"]):
		_netz.schedule_place(selected_card, cell.y, cell.x)
		selected_card = ""
		AudioDirector.try_play(self, "gvz_place")
	else:
		_reject_feedback(at, str(place_check["reason"]))
	queue_redraw()


## Abgelehnte Aktion: Fehl-Ton + schwebender Grund (nur bekannte Keys).
func _reject_feedback(at: Vector2, reason: String) -> void:
	AudioDirector.try_play(self, "ui_error")
	if ctx != null and ctx.juice != null:
		var key := "gvz.hud.reason_%s" % reason
		if I18nService.has_key(key):
			ctx.juice.float_text(at - Vector2(0, 30), I18nService.t(key), GvzArt.BERRY_RED)


func _collect_drop_at(at: Vector2) -> bool:
	# Zombie-Seite sammelt kein Nutella — ihre Ressource ist der Matsch-Tropf.
	if _netz_zombie():
		return false
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
	if _netz_active:
		_netz.schedule_collect(best_id)
	else:
		GvzLogic.collect_drop(state, best_id)
	queue_redraw()
	return true


## ── Layout ───────────────────────────────────────────────────────────────


func _view_size() -> Vector2:
	return get_viewport_rect().size


func _card_list() -> Array:
	if state.is_empty():
		return []
	# Netz-PvP Zombie-Seite: Beschwör-Karten aus gvz_pvp.json (keine Schaufel).
	if _netz_zombie():
		return _netz.zombie_types()
	var out: Array = []
	if _conveyor_active() and not bool(state["mods"].get("conveyor_hybrid", false)):
		for type: Variant in state["conveyor"]["queue"]:
			out.append(str(type))
	else:
		out = GvzLogic.available_towers(state)
	out.append("shovel")
	return out


## G4 (ui-ranch §2.3): Karten-Pitch (w, h) — nie unter dem Touch-Floor
## (>=48 pt, ScreenShell.metrics kennt die SubViewport-Kette).
## W21/P5: Karten skalieren mit dem MgHudKit-Faktor (die Fix-Pixel-Schuld
## GVZ-1) — auf großen Canvases wachsen Karte, Icon UND Kosten-Label mit.
func _card_dims() -> Vector2:
	var floor_px: float = ScreenShell.metrics(get_viewport())["floor_px"]
	var f := MgHudKit.ui_scale(_view_size())
	return Vector2(maxf(CARD_W * f, floor_px + 4.0), maxf(CARD_H * f, floor_px))


func _card_rows() -> int:
	var cards := _card_list().size()
	var per_row := int((_view_size().x - _card_strip_x() - 6.0) / _card_dims().x)
	return 1 if cards <= per_row else 2


## Linke Startkante der Kartenleiste (rechts neben dem Zähler-Chip, ×f).
func _card_strip_x() -> float:
	return 90.0 * MgHudKit.ui_scale(_view_size())


## Oberkante der Kartenleiste — sie hängt jetzt an der UNTERKANTE (Daumen).
func _card_top() -> float:
	return _view_size().y - TOP_PAD - _card_dims().y * (0.82 * (_card_rows() - 1) + 1.0)


func _card_rect(index: int) -> Rect2:
	var dims := _card_dims()
	var strip_x := _card_strip_x()
	var per_row := maxi(1, int((_view_size().x - strip_x - 6.0) / dims.x))
	var at := Vector2(
		strip_x + (index % per_row) * dims.x, _card_top() + (index / per_row) * (dims.y * 0.82)
	)
	return Rect2(at, Vector2(dims.x - 4.0, dims.y))


func _card_at(at: Vector2) -> String:
	var cards := _card_list()
	for i in cards.size():
		if _card_rect(i).has_point(at):
			return str(cards[i])
	return ""


func _field_rect() -> Rect2:
	var vp := _view_size()
	# Horizont-Band (MP-G): über der Feld-Oberkante bleibt bewusst Luft für
	# die Nachbarschafts-Kulisse (Haus, Zaun, Gehweg, Bäume); das Feld endet
	# über der Kartenleiste an der Unterkante (G4).
	var top := TOP_PAD + 20.0 + vp.y * 0.16
	return Rect2(MOWER_GUTTER, top, vp.x - MOWER_GUTTER - 6.0, _card_top() - 8.0 - top)


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


## Jeden Frame: der komplette Sim-Zustand als Pixel-Anker zur Bühne —
## das Mapping wohnt seit dem P26-Split in gvz_stage_feed.gd.
func _sync_stage(delta: float) -> void:
	GvzStageFeed.sync(self, delta)


## ── Zeichnen (delegiert an gvz_hud.gd — das Feld rendert die 3D-Bühne) ───


func _draw() -> void:
	var vp := _view_size()
	if phase == "select":
		draw_rect(Rect2(Vector2.ZERO, vp), AcTokens.BG_CREAM)
		return
	if state.is_empty():
		return
	_hud.draw_bars()
	_hud.draw_hud()
	_hud.draw_ghost()
	_hud.draw_banner()
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


## ── HUD-API (gvz_hud.gd liest den Zustand NUR über diese Fenster) ────────


## Ressource fürs Zähler-Chip: Nutella — bzw. Matsch auf der Zombie-Seite.
func hud_resource() -> int:
	if _netz_zombie():
		return _netz.matsch
	return int(state["nutella"])


## Karten-Metadaten für HUD + Ghost: Kosten, Cooldown, Zombie-Flag.
func _card_info(type: String) -> Dictionary:
	if type == "shovel":
		return {"cost": 0, "cooldown_left": 0, "cooldown_total": 1, "zombie": false}
	if _netz_zombie():
		return {
			"cost": _netz.zombie_cost(type),
			"cooldown_left": _netz.zombie_cooldown_left(type),
			"cooldown_total": _netz.zombie_cooldown_ticks(type),
			"zombie": true,
		}
	return {
		"cost": GvzLogic.tower_cost(state, type),
		"cooldown_left": GvzLogic.cooldown_left(state, type),
		"cooldown_total": int(balance["towers"].get(type, {}).get("cooldown_ticks", 1)),
		"zombie": false,
	}


## Netz-Status fürs HUD: Überlebens-Timer + „Warte auf Partner“-Hinweis.
func netz_hud_info() -> Dictionary:
	if not _netz_active or _netz == null:
		return {"active": false}
	return {
		"active": true,
		"seconds_left": _netz.seconds_left(),
		"waiting": _netz_waiting and phase == "battle",
	}


## ── UI-Aufbau (Select + Overlays) ────────────────────────────────────────


func _build_select_screen() -> void:
	_select_screen = GvzLevelSelect.new()
	_select_screen.game_state = _game_state()
	_select_screen.netz_panel = _netz_panel
	_select_screen.level_chosen.connect(open_level)
	_select_screen.done_pressed.connect(finish_session)
	add_child(_select_screen)
	# B11 (W13/GVZ): KEIN FULL_RECT — der Select bindet sich an den Viewport.


## End-Overlays (Stufe 2: Sterne-Pop + Icon-Knöpfe) baut gvz_overlay.gd.
func _build_end_overlay(won: bool, stars: int, total: int, first_clear: bool) -> void:
	_overlay_builder.build_end(won, stars, total, first_clear)


func _build_netz_end_overlay(won: bool) -> void:
	_overlay_builder.build_netz_end(won)


func _clear_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


## ── Netz-PvP-Verdrahtung (G5/P26, Muster gobnom/W15) ─────────────────────


## Session + Panel nur bauen, wenn es einen NetClient gibt — ohne /root/Net
## (bzw. net_override in Tests) bleibt der komplette Kampagnen-Pfad unberührt.
func _setup_netz() -> void:
	var net: Object = net_override if net_override != null else get_node_or_null("/root/Net")
	if net == null:
		return
	_pvp = GvzPvpLockstep.load_pvp()
	netz_session = GvzNetSession.new()
	netz_session.name = "NetzPvp"
	add_child(netz_session)
	netz_session.setup(net)
	netz_session.game_started.connect(_on_netz_start)
	netz_session.frame_received.connect(_on_netz_frame)
	netz_session.hash_received.connect(_on_netz_hash)
	netz_session.desync_reported.connect(_on_netz_desync)
	netz_session.result_confirmed.connect(_on_netz_result)
	netz_session.session_aborted.connect(_on_netz_aborted)
	netz_session.peer_connection_changed.connect(_on_netz_peer_changed)
	_netz_panel = GvzNetzPanel.new()
	_netz_panel.setup(netz_session)


## GVZ_START: beide Geräte bauen die identische PvP-Sim aus dem Server-Seed.
func _on_netz_start(_data: Dictionary) -> void:
	attempt += 1
	level_id = 0
	_netz = GvzPvpLockstep.new()
	_netz.start(
		balance, _pvp, netz_session.seed_value, netz_session.my_side, netz_session.input_delay
	)
	_netz.hash_ticks = netz_session.hash_every_ticks
	state = _netz.state
	_netz_active = true
	_netz_waiting = false
	_enter_battle()
	_show_banner(
		I18nService.t("gvz.netz.start_banner", {"name": netz_session.partner_gooby_name}), "intro"
	)
	# Erster Fence sofort raus — der Partner darf die ersten Ticks rechnen.
	netz_session.send_frame(_netz.take_frame(true))


func _on_netz_frame(body: Dictionary) -> void:
	if _netz != null:
		_netz.receive_frame(body)


func _on_netz_hash(tick: int, hash_text: String) -> void:
	if _netz != null:
		_netz.receive_hash(tick, hash_text)


## Desync (lokal ODER vom Server gemeldet): höflicher Abbruch mit Toast
## statt Weiterspielen auf divergenten Welten.
func _on_netz_desync(_tick: int) -> void:
	if not _netz_active:
		return
	if netz_session != null:
		netz_session.leave()
	_netz_abort("gvz.netz.desync")


## Ergebnis bestätigt: die Session ist verbraucht — sauber gehen, sonst
## blockiert die tote Paarung serverseitig JEDE neue Herausforderung.
func _on_netz_result(_data: Dictionary) -> void:
	if netz_session != null:
		netz_session.leave()
	if _netz_panel != null:
		_netz_panel.refresh()


func _on_netz_aborted(_reason: String, _by: String) -> void:
	if _netz_active:
		_netz_abort("gvz.netz.abbruch")
	elif _netz_panel != null:
		_netz_panel.refresh()


func _on_netz_peer_changed(down: bool, _wait_ms: int) -> void:
	if not _netz_active or netz_session == null:
		return
	var key := "gvz.netz.partner_weg" if down else "gvz.netz.partner_da"
	_show_banner(I18nService.t(key, {"name": netz_session.partner_gooby_name}))
	queue_redraw()


func _netz_abort(toast_key: String) -> void:
	_netz_active = false
	_netz = null
	AudioDirector.try_play(self, "ui_error")
	if ctx != null and ctx.juice != null:
		ctx.juice.float_text(_view_size() * 0.5, I18nService.t(toast_key), GvzArt.BERRY_RED)
	back_to_select()


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


## Spiele ich im Netz-Match die Zombie-Seite? (Karten/Matsch/kein Sammeln.)
func _netz_zombie() -> bool:
	return _netz_active and _netz != null and _netz.side == GvzPvpLockstep.SIDE_ZOMBIE


func _show_banner(text: String, kind := "info") -> void:
	_hud.show_banner(text, kind)


## Letzte Pixel-Anker der Zombies (die Sim entfernt Tote im selben Tick —
## die 3D-FX für die "die"/"pop"-Events brauchen die Position davor).
func _remember_zombie_positions() -> void:
	_prev_zombie_pos = {}
	for zombie: Dictionary in state["zombies"]:
		_prev_zombie_pos[int(zombie["id"])] = Vector2(
			_x_to_px(int(zombie["x"])),
			_field_rect().position.y + (int(zombie["lane"]) + 0.6) * _cell_size().y
		)
