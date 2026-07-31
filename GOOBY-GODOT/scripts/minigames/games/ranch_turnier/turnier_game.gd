extends MinigameBase
## Turnier-Liga (ranchTurnier) — das Herz des Wettbewerbs-DLC (RW-5,
## IDEAS-1 E1 + IDEAS-3 Kap. 5). Ablauf je Disziplin: Menü (Liga-Panel,
## Klassenwahl, 7 Disziplinen) → deutsche Einweisung mit Starterfeld →
## 3D-Lauf (RcompLauf, RW-2s Reitphysik) → Endstand + Belohnung →
## Siegerehrung mit Podium/Konfetti bei Platz 1–3. Bots sind VOR dem
## Spielerlauf fertig simuliert (RanchCompTurnier, kein Gummiband);
## Liga-Punkte/Gold/XP/Schleifen/Trophäen bucht `verbuche` additiv nach
## `ranch.comp` + economy. Der beste Lauf reitet als Geist mit.

enum Phase { MENU, EINWEISUNG, LAUF, ERGEBNIS, ZEREMONIE }

const INK := Color("#3B3630")
const CREME := Color("#FFF6E8")
const GOLD := Color("#F2B04C")
const PAPIER := Color("#FFF6E3")
## Wochenplan-Seed (fest, damit der Turniertag auf allen Geräten gleich
## fällt — offline-first, IDEAS-1 E1).
const TURNIERTAG_SEED := 777
## Session-Punkte: Grundwert + Liga-Punkte × Faktor (Platz 1 = 120).
const SCORE_BASIS := 20
const SCORE_JE_LIGA_PUNKT := 10
## W14/GAMESQA Intro-Beat: Arena steht 1,5 s mit Disziplin-Callout, dann Startschuss.
const INTRO_S := 1.5

var phase := Phase.MENU
var session_score := 0
var finished := false
var view_size := Vector2(844.0, 390.0)

var lauf: RcompLauf
var hud: RcompHud

var _balance: Dictionary = {}
var _plan: Dictionary = {}
var _disziplin := "springen"
var _klasse := "holz"
var _geist_an := true
var _gespielt: Dictionary = {}
var _bots: Array = []
var _stand: Array = []
var _pferd_id := ""
var _pferd: Dictionary = {}
var _menu: Control
var _panel: Control
var _intro_left := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	_balance = RanchCompKatalog.load_balance()
	_plan = RanchCompLiga.turniertag_plan(
		_balance, Time.get_date_string_from_system(), TURNIERTAG_SEED
	)
	_lade_pferd()
	_zeige_menu()
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
	# Controls unter einer Node2D-Wurzel erben KEINE Viewport-Anker —
	# Vollbild-Schalen bekommen ihre Größe deshalb explizit (Muster
	# RcompLevelSelect._fit_viewport). W14: hud gehört dazu, sonst liegen
	# Zeit-Panel und Callouts unsichtbar außerhalb des Bildes.
	for control: Control in [_menu, _panel, hud]:
		if control != null and is_instance_valid(control):
			control.position = Vector2.ZERO
			control.size = view_size


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished or _intro_left <= 0.0:
		return
	_intro_left -= delta
	if _intro_left <= 0.0 and lauf != null and phase == Phase.LAUF:
		lauf.starte()
		AudioDirector.try_play(self, "mg_go")


func _game_state() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _lade_pferd() -> void:
	var bestes := RanchCompTurnier.bestes_pferd(_game_state())
	_pferd_id = str(bestes.get("id", ""))
	_pferd = bestes.get("pferd") if bestes.get("pferd") is Dictionary else {}


func _pferd_name() -> String:
	var pferd_name := str(_pferd.get("name", ""))
	return pferd_name if not pferd_name.is_empty() else I18nService.t("rcomp.menu.leihpferd")


func _pferd_level() -> int:
	return maxi(1, int(_num(_pferd.get("level"), 1.0)))


## ------------------------------------------------------------------- Menü


func _zeige_menu() -> void:
	phase = Phase.MENU
	_teardown_lauf()
	_teardown_panel()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_lade_pferd()
	_menu = _baue_menu()
	add_child(_menu)


func _baue_menu() -> Control:
	var comp := RanchCompState.lese(_game_state())
	var wurzel := _vollbild_control()
	var hintergrund := ColorRect.new()
	hintergrund.color = PAPIER
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wurzel.add_child(hintergrund)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for seite in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % seite, 14)
	wurzel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 10)
	spalte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spalte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(spalte)
	_menu_kopf(spalte)
	_menu_liga_panel(spalte, comp)
	_menu_klassen_wahl(spalte, comp)
	_menu_disziplinen(spalte, comp)
	_menu_fuss(spalte)
	return wurzel


func _menu_kopf(spalte: VBoxContainer) -> void:
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("rcomp.menu.title")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 30)
	titel.add_theme_color_override("font_color", INK)
	spalte.add_child(titel)
	var unter := Label.new()
	unter.theme_type_variation = &"SoftLabel"
	unter.text = I18nService.t("rcomp.menu.untertitel")
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spalte.add_child(unter)


func _menu_liga_panel(spalte: VBoxContainer, comp: Dictionary) -> void:
	var panel := PanelContainer.new()
	spalte.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var klasse := str(comp.get("klasse", "holz"))
	var liga := Label.new()
	liga.theme_type_variation = &"HeadlineLabel"
	liga.add_theme_font_size_override("font_size", 20)
	liga.text = I18nService.t(
		"rcomp.menu.liga", {"klasse": I18nService.t("rcomp.klasse.%s" % klasse)}
	)
	box.add_child(liga)
	var schwelle := RanchCompLiga.aufstieg_ab(_balance, klasse)
	var punkte := int(_num((comp.get("punkte") as Dictionary).get(klasse), 0.0))
	var fortschritt := Label.new()
	fortschritt.theme_type_variation = &"CaptionLabel"
	if schwelle > 0:
		fortschritt.text = I18nService.t("rcomp.menu.punkte", {"n": punkte, "ziel": schwelle})
	else:
		fortschritt.text = I18nService.t("rcomp.menu.punkte_dach")
	box.add_child(fortschritt)
	var balken := ProgressBar.new()
	balken.max_value = 1.0
	balken.value = RanchCompLiga.aufstieg_fortschritt(_balance, klasse, punkte)
	balken.show_percentage = false
	balken.custom_minimum_size = Vector2(0.0, 12.0)
	box.add_child(balken)
	var pferd := Label.new()
	pferd.theme_type_variation = &"CaptionLabel"
	pferd.text = I18nService.t("rcomp.menu.pferd", {"name": _pferd_name(), "level": _pferd_level()})
	box.add_child(pferd)
	var bilanz := Label.new()
	bilanz.theme_type_variation = &"CaptionLabel"
	bilanz.text = (
		I18nService
		. t(
			"rcomp.menu.bilanz",
			{
				"schleifen": (comp.get("schleifen") as Dictionary).size(),
				"trophaeen": (comp.get("trophaeen") as Array).size(),
				"siege": int(_num(comp.get("siege"), 0.0)),
			}
		)
	)
	box.add_child(bilanz)
	var heute: Array = _plan.get("disziplinen", [])
	if not heute.is_empty():
		var namen: Array[String] = []
		for id: Variant in heute:
			namen.append(I18nService.t("rcomp.disziplin.%s" % str(id)))
		var banner := Label.new()
		banner.theme_type_variation = &"CaptionLabel"
		banner.add_theme_color_override("font_color", GOLD.darkened(0.25))
		banner.text = "%s  ·  %s" % [I18nService.t("rcomp.menu.turniertag"), " · ".join(namen)]
		banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(banner)


func _menu_klassen_wahl(spalte: VBoxContainer, comp: Dictionary) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	spalte.add_child(zeile)
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = I18nService.t("rcomp.menu.klasse_wahl")
	zeile.add_child(label)
	var wahl := OptionButton.new()
	wahl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var liga_klasse := str(comp.get("klasse", "holz"))
	var level := _pferd_level()
	var beste_erlaubte := 0
	for i in RanchCompKatalog.KLASSEN.size():
		var id: String = RanchCompKatalog.KLASSEN[i]
		var text := I18nService.t("rcomp.klasse.%s" % id)
		var erlaubt := RanchCompLiga.start_erlaubt(_balance, liga_klasse, id, level)
		if not erlaubt:
			if RanchCompKatalog.klasse_index(id) > RanchCompKatalog.klasse_index(liga_klasse):
				text += " — %s" % I18nService.t("rcomp.menu.gesperrt_liga")
			else:
				var ab := int(_num(RanchCompKatalog.klasse(_balance, id).get("ab_level"), 1.0))
				text += " — %s" % I18nService.t("rcomp.menu.gesperrt_level", {"level": ab})
		wahl.add_item(text, i)
		wahl.set_item_metadata(i, id)
		wahl.set_item_disabled(i, not erlaubt)
		if erlaubt:
			beste_erlaubte = i
	if not RanchCompLiga.start_erlaubt(_balance, liga_klasse, _klasse, level):
		_klasse = str(RanchCompKatalog.KLASSEN[beste_erlaubte])
	wahl.select(RanchCompKatalog.klasse_index(_klasse))
	wahl.item_selected.connect(
		func(index: int) -> void:
			_klasse = str(wahl.get_item_metadata(index))
			AudioDirector.try_play(self, "ui_confirm")
	)
	zeile.add_child(wahl)
	var geist := CheckBox.new()
	geist.text = I18nService.t("rcomp.menu.geist")
	geist.button_pressed = _geist_an
	geist.toggled.connect(func(an: bool) -> void: _geist_an = an)
	zeile.add_child(geist)


func _menu_disziplinen(spalte: VBoxContainer, comp: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2 if view_size.x >= view_size.y else 1
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	spalte.add_child(grid)
	var heute: Array = _plan.get("disziplinen", [])
	var schleifen: Dictionary = comp.get("schleifen") if comp.get("schleifen") is Dictionary else {}
	for disziplin in RanchCompKatalog.DISZIPLINEN:
		var knopf := Button.new()
		knopf.custom_minimum_size = Vector2(0.0, 58.0)
		knopf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		knopf.add_theme_font_size_override("font_size", 17)
		var zeilen: Array[String] = [I18nService.t("rcomp.disziplin.%s" % disziplin)]
		var extras: Array[String] = []
		if heute.has(disziplin):
			extras.append(I18nService.t("rcomp.menu.bonus"))
		var schl_key := RanchCompLiga.schleifen_key(disziplin, _klasse)
		if schleifen.has(schl_key):
			extras.append(
				I18nService.t(
					"rcomp.menu.schleife", {"platz": int(_num(schleifen.get(schl_key), 0.0))}
				)
			)
		if _gespielt.has(disziplin):
			extras.append(
				I18nService.t(
					"rcomp.menu.gespielt", {"platz": int(_num(_gespielt.get(disziplin), 0.0))}
				)
			)
			knopf.disabled = true
		if not extras.is_empty():
			zeilen.append(" · ".join(extras))
		knopf.text = "\n".join(zeilen)
		knopf.pressed.connect(_zeige_einweisung.bind(disziplin))
		grid.add_child(knopf)


func _menu_fuss(spalte: VBoxContainer) -> void:
	var fertig := Button.new()
	fertig.text = I18nService.t("rcomp.menu.fertig")
	fertig.custom_minimum_size = Vector2(160.0, 48.0)
	fertig.size_flags_horizontal = Control.SIZE_SHRINK_END
	fertig.pressed.connect(_finish_session)
	spalte.add_child(fertig)


func _finish_session() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "ui_back")
	ctx.report_end({"score": session_score})


## ------------------------------------------------------------- Einweisung


func _zeige_einweisung(disziplin: String) -> void:
	if not running or finished or phase != Phase.MENU:
		return
	phase = Phase.EINWEISUNG
	_disziplin = disziplin
	AudioDirector.try_play(self, "ui_confirm")
	_bots = RanchCompTurnier.bots_simulieren(_balance, disziplin, _klasse, _lauf_seed())
	if _menu != null:
		_menu.visible = false
	_panel = _vollbild_control()
	var dim := ColorRect.new()
	dim.color = Color(0.16, 0.13, 0.1, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var mitte := _mitte_panel(_panel)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.add_theme_font_size_override("font_size", 24)
	titel.text = (
		I18nService
		. t(
			"rcomp.einweisung.titel",
			{
				"disziplin": I18nService.t("rcomp.disziplin.%s" % disziplin),
				"klasse": I18nService.t("rcomp.klasse.%s" % _klasse),
			}
		)
	)
	mitte.add_child(titel)
	var regeln := Label.new()
	regeln.theme_type_variation = &"SoftLabel"
	regeln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	regeln.custom_minimum_size = Vector2(minf(view_size.x - 120.0, 560.0), 0.0)
	regeln.text = I18nService.t("rcomp.regeln.%s" % disziplin)
	mitte.add_child(regeln)
	var richtzeit := RanchCompKatalog.richtzeit_s(_balance, disziplin, _klasse)
	if richtzeit > 0.0:
		var zeit := Label.new()
		zeit.theme_type_variation = &"CaptionLabel"
		zeit.text = I18nService.t("rcomp.einweisung.richtzeit", {"s": "%.0f" % richtzeit})
		mitte.add_child(zeit)
	var feld := Label.new()
	feld.theme_type_variation = &"CaptionLabel"
	feld.text = I18nService.t("rcomp.einweisung.starterfeld")
	mitte.add_child(feld)
	for bot: Variant in _bots:
		if not (bot is Dictionary):
			continue
		var starter := Label.new()
		starter.theme_type_variation = &"CaptionLabel"
		starter.text = "· %s" % _starter_name(bot)
		mitte.add_child(starter)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 12)
	zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	mitte.add_child(zeile)
	var zurueck := Button.new()
	zurueck.text = I18nService.t("rcomp.einweisung.zurueck")
	zurueck.custom_minimum_size = Vector2(140.0, 48.0)
	zurueck.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			_zeige_menu()
	)
	zeile.add_child(zurueck)
	var los := Button.new()
	los.text = I18nService.t("rcomp.einweisung.los")
	los.custom_minimum_size = Vector2(180.0, 48.0)
	los.pressed.connect(_starte_lauf)
	zeile.add_child(los)
	add_child(_panel)


## ------------------------------------------------------------------- Lauf


func _starte_lauf() -> void:
	if not running or finished or phase != Phase.EINWEISUNG:
		return
	phase = Phase.LAUF
	_teardown_panel()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	var gs := _game_state()
	var cfg := {
		"disziplin": _disziplin,
		"klasse": _klasse,
		"seed": _lauf_seed(),
		"balance": _balance,
		"pferd": _pferd,
		"zuschauer": 14 + RanchCompKatalog.klasse_index(_klasse) * 5,
	}
	if _geist_an:
		cfg["geist_b64"] = str(RanchCompState.geist(gs, _disziplin).get("b64", ""))
	if _disziplin == "rennen":
		cfg["bots"] = _bots
	if _disziplin == "schau":
		var gear: Variant = null
		if gs != null and not _pferd_id.is_empty():
			gear = gs.get_value("ranch.wirtschaft.gear.equippedByHorse.%s" % _pferd_id, null)
		var basis := RcompRichterSchau.basis_aus_pferd(_pferd, gear)
		cfg["pflege"] = _num(basis.get("pflege"), 70.0)
		cfg["stil"] = _num(basis.get("stil"), 40.0)
	lauf = RcompLauf.new()
	add_child(lauf)
	lauf.baue(cfg)
	lauf.apply_size(view_size)
	lauf.lauf_fertig.connect(_on_lauf_fertig)
	hud = RcompHud.new()
	hud.lauf = lauf
	add_child(hud)
	hud.position = Vector2.ZERO
	hud.size = view_size
	_intro_left = INTRO_S
	hud.zeige_callout(I18nService.t("rcomp.disziplin.%s" % _disziplin))
	AudioDirector.try_play(self, "ui_confirm")


## Deterministischer Lauf-Seed: Run-Seed + Disziplin + bisherige Teilnahmen
## (jeder Anlauf würfelt neu, bleibt aber reproduzierbar).
func _lauf_seed() -> int:
	var comp := RanchCompState.lese(_game_state())
	var idx := maxi(0, RanchCompKatalog.DISZIPLINEN.find(_disziplin))
	return ctx.run_seed + idx * 1009 + int(_num(comp.get("teilnahmen"), 0.0)) * 8117


func _teardown_lauf() -> void:
	_intro_left = 0.0
	for node: Node in [hud, lauf]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	hud = null
	lauf = null


func _teardown_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


## --------------------------------------------------------------- Ergebnis


func _on_lauf_fertig(ergebnis: Dictionary) -> void:
	if finished or phase != Phase.LAUF:
		return
	phase = Phase.ERGEBNIS
	var gs := _game_state()
	var spieler := {
		"wert": _num(ergebnis.get("wert"), 0.0),
		"zeit_s": _num(ergebnis.get("zeit_s"), 0.0),
		"pferd": _pferd_name(),
	}
	_stand = RanchCompTurnier.endstand(_balance, _disziplin, _bots, spieler)
	var platz := RanchCompTurnier.spieler_platz(_stand)
	var heute: Array = _plan.get("disziplinen", [])
	var lohn := (
		RanchCompTurnier
		. belohnung(
			_balance,
			_disziplin,
			_klasse,
			platz,
			{
				"turniertag": heute.has(_disziplin),
				"heim_gold_mult": RanchCompTurnier.heim_gold_mult(gs),
			}
		)
	)
	var bericht := RanchCompTurnier.verbuche(gs, _balance, _disziplin, _klasse, platz, lohn)
	RanchCompTurnier.xp_an_pferd(
		gs, _pferd_id, _num(lohn.get("xp"), 0.0), Time.get_date_string_from_system()
	)
	var geist_neu := (
		RanchCompState
		. geist_speichern(
			gs,
			_disziplin,
			{
				"b64": str(ergebnis.get("geist_b64", "")),
				"wert": _num(ergebnis.get("wert"), 0.0),
				"zeit_s": _num(ergebnis.get("zeit_s"), 0.0),
				"datum": Time.get_date_string_from_system(),
				"pferd": _pferd_id,
			},
			RanchCompKatalog.zeit_gewinnt(_balance, _disziplin)
		)
	)
	_gespielt[_disziplin] = platz
	var punkte := SCORE_BASIS + int(_num(bericht.get("liga_punkte"), 0.0)) * SCORE_JE_LIGA_PUNKT
	session_score += punkte
	ctx.report_score(session_score, punkte)
	_zeige_ergebnis(platz, bericht, geist_neu)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.7)
		ctx.juice.float_text(
			lauf.spieler_screen(),
			I18nService.t("rcomp.ergebnis.gold", {"n": int(_num(bericht.get("gold"), 0.0))}),
			GOLD
		)
	AudioDirector.try_play(self, "mg_win" if platz <= 3 else "mg_good")


func _zeige_ergebnis(platz: int, bericht: Dictionary, geist_neu: bool) -> void:
	_panel = _vollbild_control()
	var mitte := _mitte_panel(_panel)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.add_theme_font_size_override("font_size", 24)
	titel.text = I18nService.t("rcomp.ergebnis.titel")
	mitte.add_child(titel)
	for i in _stand.size():
		var eintrag: Dictionary = _stand[i]
		var zeile := Label.new()
		zeile.theme_type_variation = &"CaptionLabel"
		zeile.text = "%d. %s — %s" % [i + 1, _starter_name(eintrag), _wert_text(eintrag)]
		if bool(eintrag.get("ist_spieler", false)):
			zeile.add_theme_color_override("font_color", GOLD.darkened(0.2))
			zeile.add_theme_font_size_override("font_size", 18)
		mitte.add_child(zeile)
	var lohn_zeile := Label.new()
	lohn_zeile.theme_type_variation = &"CaptionLabel"
	lohn_zeile.text = (
		"  ·  "
		. join(
			[
				I18nService.t("rcomp.ergebnis.gold", {"n": int(_num(bericht.get("gold"), 0.0))}),
				I18nService.t("rcomp.ergebnis.xp", {"n": int(_num(bericht.get("xp"), 0.0))}),
				I18nService.t(
					"rcomp.ergebnis.liga", {"n": int(_num(bericht.get("liga_punkte"), 0.0))}
				),
			]
		)
	)
	mitte.add_child(lohn_zeile)
	var extras: Array[String] = []
	if bool(bericht.get("aufgestiegen", false)):
		extras.append(
			I18nService.t(
				"rcomp.ergebnis.aufstieg",
				{"klasse": I18nService.t("rcomp.klasse.%s" % str(bericht.get("neue_klasse")))}
			)
		)
	if bool(bericht.get("schleife_neu", false)):
		extras.append(
			I18nService.t(
				"rcomp.ergebnis.schleife",
				{"disziplin": I18nService.t("rcomp.disziplin.%s" % _disziplin)}
			)
		)
	if bool(bericht.get("trophaee_neu", false)):
		extras.append(I18nService.t("rcomp.ergebnis.trophaee"))
	if geist_neu:
		extras.append(I18nService.t("rcomp.ergebnis.geist"))
	for extra in extras:
		var label := Label.new()
		label.theme_type_variation = &"CaptionLabel"
		label.add_theme_color_override("font_color", GOLD.darkened(0.25))
		label.text = extra
		mitte.add_child(label)
	var weiter := Button.new()
	weiter.text = I18nService.t("rcomp.ergebnis.weiter")
	weiter.custom_minimum_size = Vector2(180.0, 48.0)
	weiter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	weiter.pressed.connect(_nach_ergebnis.bind(platz))
	mitte.add_child(weiter)
	add_child(_panel)


func _nach_ergebnis(platz: int) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	if platz <= 3:
		_zeige_zeremonie()
	else:
		_zeige_menu()


func _wert_text(eintrag: Dictionary) -> String:
	var wert := _num(eintrag.get("wert"), 0.0)
	if RanchCompKatalog.zeit_gewinnt(_balance, _disziplin):
		return I18nService.t("rcomp.ergebnis.zeit", {"s": "%.1f" % wert})
	return I18nService.t("rcomp.ergebnis.punkte", {"n": int(round(wert))})


func _starter_name(eintrag: Dictionary) -> String:
	if bool(eintrag.get("ist_spieler", false)):
		return I18nService.t("rcomp.ergebnis.du", {"pferd": str(eintrag.get("pferd", ""))})
	return I18nService.t(
		"rcomp.einweisung.starter",
		{"name": str(eintrag.get("name", "")), "pferd": str(eintrag.get("pferd", ""))}
	)


## ------------------------------------------------------------- Zeremonie


func _zeige_zeremonie() -> void:
	phase = Phase.ZEREMONIE
	_teardown_panel()
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
		hud = null
	if lauf != null:
		lauf.zeremonie(_stand)
	_panel = _vollbild_control()
	var spalte := VBoxContainer.new()
	spalte.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	spalte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spalte.position.y += 14.0
	spalte.add_theme_constant_override("separation", 2)
	_panel.add_child(spalte)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 30)
	titel.add_theme_color_override("font_color", CREME)
	titel.add_theme_color_override("font_outline_color", INK)
	titel.add_theme_constant_override("outline_size", 8)
	titel.text = I18nService.t("rcomp.zeremonie.titel")
	spalte.add_child(titel)
	for i in mini(3, _stand.size()):
		var zeile := Label.new()
		zeile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zeile.add_theme_font_size_override("font_size", 19)
		zeile.add_theme_color_override("font_color", CREME)
		zeile.add_theme_color_override("font_outline_color", INK)
		zeile.add_theme_constant_override("outline_size", 6)
		zeile.text = I18nService.t(
			"rcomp.zeremonie.platz%d" % (i + 1), {"name": _starter_name(_stand[i])}
		)
		spalte.add_child(zeile)
	var weiter := Button.new()
	weiter.text = I18nService.t("rcomp.zeremonie.weiter")
	weiter.custom_minimum_size = Vector2(200.0, 48.0)
	weiter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	weiter.grow_horizontal = Control.GROW_DIRECTION_BOTH
	weiter.position.y -= 64.0
	weiter.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			_zeige_menu()
	)
	_panel.add_child(weiter)
	add_child(_panel)
	if ctx.juice != null:
		ctx.juice.confetti(110)
		ctx.juice.bloom_pulse(0.9)
	AudioDirector.try_play(self, "mg_perfect")


## ----------------------------------------------------------------- Helfer


func _vollbild_control() -> Control:
	var control := Control.new()
	control.position = Vector2.ZERO
	control.size = view_size
	return control


## Zentriertes Panel mit VBox — gemeinsame Schale für Einweisung/Ergebnis.
func _mitte_panel(wurzel: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	wurzel.add_child(panel)
	var margin := MarginContainer.new()
	for seite in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % seite, 16)
	panel.add_child(margin)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 6)
	margin.add_child(spalte)
	return spalte


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
