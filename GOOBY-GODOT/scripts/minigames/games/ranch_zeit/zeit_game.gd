extends MinigameBase
## Zeitrennen (ranchZeit) — Arcade-Umsetzung von IDEAS-1 E2: quer über
## die Wiese durch Flaggentore, gegen die Uhr UND gegen den eigenen
## Geist (RW-5-Geisterlauf, Kap. 5.3). 10 feste Strecken (RanchCompArcade,
## fester Kurs-Seed — nur so bleibt der Geist vergleichbar), ausgelassene
## Tore kosten 8 s (Doc-Formel via RcompRichterGelaende). Fortschritt
## additiv in `ranch.comp.arcade.zeit`, Geist je Strecke.

const SPIEL := "zeit"
const ENDE_WARTE_S := 2.2

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


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	if not level_running and _ende_timer > 0.0:
		_ende_timer -= delta
		if _ende_timer <= 0.0:
			_zeige_select()


## ------------------------------------------------------------ Level-Wahl


func _build_select() -> void:
	_select = RcompLevelSelect.new()
	_select.spiel = SPIEL
	_select.title_key = "mg.ranchZeit.title"
	_select.hint_key = "mg.ranchZeit.hint"
	_select.tile_prefix = "S"
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
	var geist_key := RanchCompArcade.zeit_geist_key(id)
	var geist := RanchCompState.geist(gs, geist_key)
	lauf = RcompLauf.new()
	add_child(lauf)
	(
		lauf
		. baue(
			{
				"disziplin": "zeit",
				"klasse": "holz",
				"seed": RanchCompArcade.ZEIT_KURS_SEED,
				"balance": _balance,
				"pferd": bestes.get("pferd", {}),
				"route": RanchCompArcade.zeit_route(id),
				"ziel_s": RanchCompArcade.zeit_ziel_s(id),
				"zuschauer": 6,
				"geist_b64": str(geist.get("b64", "")),
			}
		)
	)
	lauf.apply_size(view_size)
	lauf.lauf_fertig.connect(_on_lauf_fertig)
	hud = RcompHud.new()
	hud.lauf = lauf
	add_child(hud)
	level_running = true
	lauf.starte()
	if geist.is_empty():
		hud.zeige_callout(I18nService.t("mg.ranchZeit.level", {"n": id}))
	else:
		hud.zeige_callout(
			I18nService.t("mg.ranchZeit.geist_zeit", {"s": "%.1f" % float(geist.get("wert", 0.0))}),
			RcompHud.TEAL
		)
	AudioDirector.try_play(self, "ui_confirm")


func _teardown_lauf() -> void:
	level_running = false
	for node: Node in [hud, lauf]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	hud = null
	lauf = null


func _on_lauf_fertig(ergebnis: Dictionary) -> void:
	level_running = false
	_ende_timer = ENDE_WARTE_S
	var wertung := float(ergebnis.get("wert", 999.0))
	var ziel := RanchCompArcade.zeit_ziel_s(level_id)
	var stars := RanchCompArcade.sterne(wertung, ziel)
	var gs := _game_state()
	if stars <= 0:
		if hud != null:
			hud.zeige_callout(I18nService.t("mg.ranchZeit.zu_langsam"), RcompHud.ROSA)
		AudioDirector.try_play(self, "mg_spill")
		return
	var first := not RanchCompState.arcade_cleared(gs, SPIEL, level_id)
	var score := RanchCompArcade.score(stars, wertung, ziel, first)
	RanchCompState.arcade_win(gs, SPIEL, level_id, stars, int(round(wertung * 10.0)), true)
	var geist_neu := (
		RanchCompState
		. geist_speichern(
			gs,
			RanchCompArcade.zeit_geist_key(level_id),
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
		var text := I18nService.t("mg.ranchZeit.geschafft", {"s": "%.1f" % wertung, "stars": stars})
		if geist_neu:
			text += " · " + I18nService.t("mg.ranchZeit.neuer_geist")
		hud.zeige_callout(text)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
		if stars >= 3 or geist_neu:
			ctx.juice.confetti(60)
