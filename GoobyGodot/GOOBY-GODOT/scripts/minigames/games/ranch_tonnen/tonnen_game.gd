extends MinigameBase
## Tonnenrennen (ranchTonnen) — Arcade-Ableger des Turnier-Tonnenrennens
## (RW-5, Kap. 5.2 Nr. 7): Kleeblatt um 3 Tonnen mit RW-2s Reitphysik,
## 10 Läufe mit sinkender Idealzeit (RanchCompArcade), Anrempeln kostet
## 5 s (Doc-Formel via RcompRichterTonnen). Fortschritt additiv in
## `ranch.comp.arcade.tonnen`; der beste Lauf reitet als Geist mit
## (geteilt mit dem Turnier — gleicher Kurs!).

const SPIEL := "tonnen"
const ENDE_WARTE_S := 2.2
## W14/GAMESQA Intro-Beat: Arena steht 1,5 s mit Ziel-Callout, dann Startschuss.
const INTRO_S := 1.5

var level_id := 0
var session_score := 0
var finished := false
var level_running := false
var view_size := Vector2(844.0, 390.0)

var lauf: RcompLauf
var hud: RcompHud
var _select: RcompLevelSelect
var _balance: Dictionary = {}
var _ende_timer := 0.0
var _intro_left := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	_balance = RanchCompKatalog.load_balance()
	_build_select()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


func pause() -> void:
	super.pause()
	if lauf != null:
		lauf.set_pausiert(true)


func resume() -> void:
	super.resume()
	if lauf != null:
		lauf.set_pausiert(false)


func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	if lauf != null:
		lauf.apply_size(view_size)
	# W14: HUD unter Node2D-Wurzel erbt KEINE Viewport-Anker → explizit größen,
	# sonst liegen Zeit-Panel und Callouts (Start/Ziel) unsichtbar außerhalb.
	if hud != null and is_instance_valid(hud):
		hud.position = Vector2.ZERO
		hud.size = view_size


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	if _intro_left > 0.0:
		_intro_left -= delta
		if _intro_left <= 0.0 and lauf != null:
			_starte_lauf()
		return
	if not level_running and _ende_timer > 0.0:
		_ende_timer -= delta
		if _ende_timer <= 0.0:
			_zeige_select()


## ------------------------------------------------------------ Level-Wahl


func _build_select() -> void:
	_select = RcompLevelSelect.new()
	_select.spiel = SPIEL
	_select.title_key = "mg.ranchTonnen.title"
	_select.hint_key = "mg.ranchTonnen.hint"
	_select.game_state = _game_state()
	_select.level_chosen.connect(_on_level_chosen)
	_select.done_pressed.connect(_finish_session)
	add_child(_select)


func _game_state() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _zeige_select() -> void:
	_teardown_lauf()
	if _select != null:
		_select.game_state = _game_state()
		_select.refresh()
		_select.visible = true


func _finish_session() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": session_score})


## ------------------------------------------------------------- Lauf


func _on_level_chosen(id: int) -> void:
	if not running or finished:
		return
	level_id = id
	_select.visible = false
	var gs := _game_state()
	var bestes := RanchCompTurnier.bestes_pferd(gs)
	lauf = RcompLauf.new()
	add_child(lauf)
	(
		lauf
		. baue(
			{
				"disziplin": "tonnen",
				"klasse": "holz",
				"seed": ctx.run_seed + id * 7919,
				"balance": _balance,
				"pferd": bestes.get("pferd", {}),
				"ideal_s": RanchCompArcade.tonnen_ideal_s(id),
				"zuschauer": 14,
				"geist_b64": str(RanchCompState.geist(gs, SPIEL).get("b64", "")),
			}
		)
	)
	lauf.apply_size(view_size)
	lauf.lauf_fertig.connect(_on_lauf_fertig)
	hud = RcompHud.new()
	hud.lauf = lauf
	add_child(hud)
	hud.position = Vector2.ZERO
	hud.size = view_size
	level_running = true
	_intro_left = INTRO_S
	hud.zeige_callout(I18nService.t("mg.ranchTonnen.intro", {"n": id}))
	AudioDirector.try_play(self, "ui_confirm")


## Nach dem Intro-Beat: Startschuss (die Idealzeit tickt ab jetzt).
func _starte_lauf() -> void:
	lauf.starte()
	hud.zeige_callout(I18nService.t("mg.ranchTonnen.level", {"n": level_id}))
	AudioDirector.try_play(self, "mg_go")


func _teardown_lauf() -> void:
	level_running = false
	_intro_left = 0.0
	for node: Node in [hud, lauf]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	hud = null
	lauf = null


func _on_lauf_fertig(ergebnis: Dictionary) -> void:
	level_running = false
	_ende_timer = ENDE_WARTE_S
	var wertung := float(ergebnis.get("wert", 999.0))
	var ideal := RanchCompArcade.tonnen_ideal_s(level_id)
	var stars := RanchCompArcade.sterne(wertung, ideal)
	var gs := _game_state()
	if stars <= 0:
		if hud != null:
			hud.zeige_callout(I18nService.t("mg.ranchTonnen.zu_langsam"), RcompHud.ROSA)
		AudioDirector.try_play(self, "mg_spill")
		return
	var first := not RanchCompState.arcade_cleared(gs, SPIEL, level_id)
	var score := RanchCompArcade.score(stars, wertung, ideal, first)
	RanchCompState.arcade_win(gs, SPIEL, level_id, stars, int(round(wertung * 10.0)), true)
	(
		RanchCompState
		. geist_speichern(
			gs,
			SPIEL,
			{
				"b64": str(ergebnis.get("geist_b64", "")),
				"wert": wertung,
				"zeit_s": float(ergebnis.get("zeit_s", 0.0)),
				"datum": Time.get_date_string_from_system(),
				"pferd": str(RanchCompTurnier.bestes_pferd(gs).get("id", "")),
			},
			true
		)
	)
	session_score += score
	ctx.report_score(session_score, score)
	ctx.report_coin_chunk(score)
	AudioDirector.try_play(self, "mg_win")
	if hud != null:
		hud.zeige_callout(
			I18nService.t("mg.ranchTonnen.geschafft", {"s": "%.1f" % wertung, "stars": stars})
		)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
		if stars >= 3:
			ctx.juice.confetti(60)
