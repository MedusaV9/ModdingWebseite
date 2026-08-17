class_name ReiseApp
extends VBoxContainer
## Reise-Flow-UI (W3a CITY, Doc E §3/§4): Ziel-Liste → Bestätigungs-Dialog
## (Preis, Dauer, WARNUNG „Gooby ist dann 3 Tage weg!“, NUTZEN „Er bringt
## Souvenirs & Postkarten mit!“) → Taxi-Bestellung (REALE Wartezeit,
## TaxiLogic-Timestamps, Notifications) → Einsteigen im 60-s-Fenster →
## Reise-Cutscene. Rückkehr: Abholen → souvenirCoins + Postkarten-Flag.
##
## W13B (Doc H §2.4, reine Optik über der unveränderten reise_logic):
## über der Ziel-Liste klappert eine Split-Flap-ABFLUGTAFEL (`flap_board.gd`,
## Zeilen „Ziel | Abflug | Status“), und nach dem Einsteigen schiebt sich
## ein BOARDING-PASS (`boarding_pass.gd`, Gate 3¾, Sitz 1A, Barcode-Gag)
## dazwischen — erst der „Gute Reise!“-Knopf startet die BESTEHENDE
## Abflug-Cutscene (identischer Aufruf wie zuvor).
##
## G4/P16 (ui-reisen HOCH 5 + MITTEL 6/10): Inhalt baut auf der REALEN
## Sheet-Breite (`inhalt_breite()` = sheet_width − chrome_width) statt auf
## Festbreiten 420/380; alle Aktions-Knöpfe sind SquishButtons ≥ 52·f und
## halten den physischen Touch-Floor; die Ziel-Liste zeigt den
## Weltengooby-Fortschritt (n/9-Kapsel + ✔-Stempel je bereistem Ziel).
## Sounds nach Audio-Grammatik: Outcome schlägt Press (`ui_buy`/`ui_coins`
## nach Erfolg); Einsteigen bleibt stumm (der Boarding-Pass spielt ui_open).
##
## Geld-Story: Reisepreis + Taxi (10) werden beim BUCHEN abgebucht;
## verpasstes Taxi erstattet Preis + 5, Storno erstattet Preis + 8.

const Economy := preload("res://scripts/logic/economy.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const CutsceneScene := preload("res://scenes/city/reise_cutscene.tscn")

## Mindesthöhe der Aktions-Knöpfe in Design-px (skaliert mit f, nie unter
## dem physischen Touch-Floor — ui-reisen HOCH 5).
const KNOPF_HOEHE := 52.0
## Fallback-Inhaltsbreite in Design-px (Tests bauen die App ohne Sheet).
const BASIS_BREITE := 420.0
## Unterkante der Breitenklemme (nie schmaler bauen).
const MIN_BREITE := 220.0

## Geteilter Notification-Planer (M1: In-App-Banner-Pfad, s. Service-Doku).
static var notifs := CityNotificationService.new()

var gs: Object
var sheet: PanelSheet
## Tests: ersetzt BoardingPass.oeffne — Callable(ziel_id, on_gute_reise).
var boarding_oeffner := Callable()

var _box: VBoxContainer
var _tick_akku := 0.0
## Aktive Bestätigungs-Ansicht ("" = keine) — überlebt ein Resize-Rerender.
var _confirm_ziel := ""


## Reise-Sheet öffnen (Host = beliebige Szene; eigener CanvasLayer).
static func oeffne(host: Node, game_state: Object) -> ReiseApp:
	var layer := CanvasLayer.new()
	layer.name = "ReiseAppLayer"
	host.add_child(layer)
	var app := ReiseApp.new()
	app.gs = game_state
	app.sheet = PanelSheetScene.instantiate()
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	app.sheet.theme = ThemeService.theme()
	layer.add_child(app.sheet)
	app.sheet.set_title(I18nService.t("travel.titel"))
	app.sheet.add_content(app)
	app.sheet.closed.connect(func() -> void: layer.queue_free())
	# open() ERST nach dem ersten Layout-Pass: die Einfeder-Animation liest
	# position.y — im Instanzierungs-Frame ist der Rect noch nicht gelegt und
	# die Offsets verkanten (Sheet wird schirmhoch).
	app.sheet.open.call_deferred()
	return app


func _ready() -> void:
	# Root = VBoxContainer (min-Höhe propagiert zum PanelSheet); _box = self.
	custom_minimum_size = Vector2(inhalt_breite(), 0.0)
	add_theme_constant_override("separation", 10)
	_box = self
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_viewport_resized)
	_render()


func _process(delta: float) -> void:
	_tick_akku += delta
	if _tick_akku < 1.0:
		return
	_tick_akku = 0.0
	_tick()


func now_ms() -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Dev-Harness: Wartezeit via AppSettings-Debug-Key `debug.taxi_warte_s`
## verkürzbar (Tests/Demos), sonst rand 300–600 s (Doc E §4).
func warte_s() -> int:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null:
		var debug := int(settings.get_setting("debug.taxi_warte_s", 0))
		if debug > 0:
			return debug
	return randi_range(TaxiLogic.WARTE_MIN_S, TaxiLogic.WARTE_MAX_S)


## G4/P16: reale Inhaltsbreite — Sheet-Breite minus Sheet-Chrome
## (FIX1-Regel „Breite abfragen statt erzwingen“). Ohne Sheet (Tests,
## Direkteinbau) fällt sie auf die skalierte Basisbreite zurück.
func inhalt_breite() -> float:
	var vp := get_viewport()
	if vp == null:
		return BASIS_BREITE
	var f := UiScale.for_viewport(vp)
	var canvas := Vector2(vp.get_visible_rect().size)
	if sheet == null or not is_instance_valid(sheet) or not sheet.is_inside_tree():
		return clampf(canvas.x - 48.0, MIN_BREITE, BASIS_BREITE * f)
	var insets := UiScale.safe_insets_canvas(vp)
	var breite := PanelSheetLayout.sheet_width(canvas, insets, f) - sheet.chrome_width()
	return maxf(breite, MIN_BREITE)


## ------------------------------------------------------------ Zeit-Tick


func _tick() -> void:
	if gs == null:
		return
	var vorher := CityState.taxi_slice(gs)
	var res := TaxiLogic.tick(vorher, now_ms())
	for ereignis: Dictionary in res["events"]:
		match str(ereignis["typ"]):
			"wartet":
				_zeige_toast(I18nService.t("travel.taxi.da"))
			"verpasst":
				_verpasst(str(vorher["zielId"]), int(ereignis["erstattung"]))
	if not res["events"].is_empty() or TaxiLogic.warte_rest_s(res["slice"], now_ms()) > 0:
		CityState.save_taxi_slice(gs, res["slice"])
		_render()
	for faellig: Dictionary in notifs.faellige(now_ms()):
		_zeige_toast(str(faellig["text"]))


func _verpasst(ziel_id: String, taxi_erstattung: int) -> void:
	notifs.storniere_gruppe("taxi.")
	var preis := int(Vacation.CATALOG.get(ziel_id, {}).get("price", 0))
	gs.update(
		func(state: Dictionary) -> void:
			Economy.award(state["economy"], preis + taxi_erstattung, "erstattung")
	)
	_zeige_toast(I18nService.t("travel.taxi.verpasst"))


## ---------------------------------------------------------------- Views


## Rotation/Resize: Breite nachziehen und die AKTUELLE Ansicht neu bauen
## (eine offene Bestätigung bleibt offen statt zur Liste zu springen).
func _on_viewport_resized() -> void:
	custom_minimum_size = Vector2(inhalt_breite(), 0.0)
	if not _confirm_ziel.is_empty():
		_render_confirm(_confirm_ziel)
		return
	_render()


func _render() -> void:
	_confirm_ziel = ""
	for kind in _box.get_children():
		kind.queue_free()
	if gs == null:
		return
	var vac := Vacation.slice_of(gs.state())
	var phase := Vacation.phase_at(vac, now_ms())
	if phase == Vacation.PHASE_AWAY:
		_render_weg(vac)
	elif phase == Vacation.PHASE_RETURN_READY or phase == Vacation.PHASE_OVERDUE:
		_render_abholen(phase == Vacation.PHASE_OVERDUE)
	else:
		var taxi := CityState.taxi_slice(gs)
		match str(taxi["state"]):
			TaxiLogic.STATE_GERUFEN:
				_render_taxi_wartet(taxi)
			TaxiLogic.STATE_WARTET:
				_render_taxi_da(taxi)
			_:
				_render_ziele()
	_skaliere_schriften()


func _render_ziele() -> void:
	var coins := int(gs.get_value("economy.coins", 0))
	# G4/P16 (ui-reisen MITTEL 10): kleine Fortschritts-Kapsel über der
	# Tafel — die 9/9-Weltengooby-Jagd ist am Buchungsort sichtbar.
	_fortschritts_kapsel()
	# W13B: Split-Flap-Abflugtafel ÜBER der Liste — klappert beim Öffnen/
	# Neurendern durch (Reduced Motion springt sofort, s. flap_board.gd).
	var tafel := FlapBoard.new()
	tafel.name = "Abflugtafel"
	_box.add_child(tafel)
	var breite := inhalt_breite()
	tafel.setze_verfuegbare_breite(breite, UiScale.for_viewport(get_viewport()))
	tafel.set_zeilen(_tafel_zeilen(coins))
	# W20/P3 (Befund B12 „Spalten stark gespreizt"): das dunkle Board klemmt
	# an seine Rasterbreite und sitzt zentriert, statt mit leerem rechten
	# Drittel die volle Sheet-Breite zu fluten (Kapsel-Muster oben).
	tafel.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	tafel.custom_minimum_size = Vector2(minf(tafel.raster_breite_px(), breite), 0.0)
	_label(I18nService.t("travel.ziel_waehlen"), "HeadlineLabel")
	var besucht: Dictionary = Vacation.slice_of(gs.state()).get("visited", {})
	for ziel_id in ReiseLogic.ZIELE:
		var info := ReiseLogic.bestaetigung(ziel_id, coins)
		var stempel := "  ✔" if bool(besucht.get(ziel_id, false)) else ""
		var btn := _knopf(
			"%s — %d ᴳ%s" % [I18nService.t(str(info["name_key"])), int(info["preis"]), stempel],
			"AccentButton"
		)
		btn.disabled = not bool(info["kann_zahlen"])
		btn.pressed.connect(_on_ziel_gewaehlt.bind(ziel_id))
		_box.add_child(btn)


## Weltengooby-Pass-Kapsel (KEIN Button — der 9-Knöpfe-Vertrag der
## Ziel-Liste bleibt stehen): „🌍 n/9 Ziele bereist“.
func _fortschritts_kapsel() -> void:
	var besucht: Dictionary = Vacation.slice_of(gs.state()).get("visited", {})
	var kapsel := PanelContainer.new()
	kapsel.name = "FortschrittKapsel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.FROST
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	kapsel.add_theme_stylebox_override("panel", sb)
	# Zentrierung im Sheet-Scroller: EXPAND|SHRINK_CENTER (FB3-Muster).
	kapsel.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	var text := Label.new()
	text.name = "FortschrittText"
	text.theme_type_variation = "CaptionLabel"
	text.text = I18nService.t(
		"g4travel.ziele.fortschritt", {"n": besucht.size(), "max": ReiseLogic.ZIELE.size()}
	)
	kapsel.add_child(text)
	_box.add_child(kapsel)


## Board-Zeilen „Ziel | Abflug | Status“ aus dem unveränderten Katalog.
func _tafel_zeilen(coins: int) -> Array:
	var zeilen: Array = []
	for ziel_id in ReiseLogic.ZIELE:
		var info := ReiseLogic.bestaetigung(ziel_id, coins)
		(
			zeilen
			. append(
				{
					"ziel": I18nService.t(str(info["name_key"])),
					"abflug":
					I18nService.t(
						"reisepass.tafel.abflug_wert",
						{"tage": int(info["tage"]), "preis": int(info["preis"])}
					),
					"status":
					I18nService.t(FlapBoard.status_key(ziel_id, bool(info["kann_zahlen"]))),
				}
			)
		)
	return zeilen


func _on_ziel_gewaehlt(ziel_id: String) -> void:
	# Ansichtswechsel zur Bestätigung (Auswahl-Klang; Knopf ist bei
	# „zu teuer“ disabled, der Druck darf also klingen).
	AudioDirector.try_play(self, "ui_chip")
	_render_confirm(ziel_id)


func _render_confirm(ziel_id: String) -> void:
	_confirm_ziel = ziel_id
	for kind in _box.get_children():
		kind.queue_free()
	var info := ReiseLogic.bestaetigung(ziel_id, int(gs.get_value("economy.coins", 0)))
	var name := I18nService.t(str(info["name_key"]))
	_label(
		I18nService.t("travel.confirm.titel").format({"ziel": name, "tage": int(info["tage"])}),
		"HeadlineLabel"
	)
	_label(I18nService.t("travel.confirm.preis").format({"preis": int(info["preis"])}), "")
	_label(I18nService.t("travel.confirm.warnung").format({"tage": int(info["tage"])}), "")
	_label(I18nService.t("travel.confirm.nutzen"), "CaptionLabel")
	_label(I18nService.t("travel.confirm.taxi_hinweis"), "CaptionLabel")
	var buchen := _knopf(I18nService.t("travel.confirm.buchen"), "PrimaryButton")
	buchen.pressed.connect(_on_buchen.bind(ziel_id))
	_box.add_child(buchen)
	var doch_nicht := _knopf(I18nService.t("travel.confirm.doch_nicht"), "GhostButton")
	doch_nicht.pressed.connect(_on_doch_nicht)
	_box.add_child(doch_nicht)
	_skaliere_schriften()


func _on_doch_nicht() -> void:
	AudioDirector.try_play(self, "ui_back")
	_render()


func _render_taxi_wartet(taxi: Dictionary) -> void:
	var rest := TaxiLogic.warte_rest_s(taxi, now_ms())
	_label(I18nService.t("travel.taxi.gerufen"), "HeadlineLabel")
	_label(
		I18nService.t("travel.taxi.countdown").format(
			{"min": rest / 60, "s": "%02d" % (rest % 60)}
		),
		""
	)
	var storno := _knopf(I18nService.t("travel.taxi.storno"), "GhostButton")
	storno.pressed.connect(_on_storno)
	_box.add_child(storno)


func _render_taxi_da(taxi: Dictionary) -> void:
	_label(I18nService.t("travel.taxi.da"), "HeadlineLabel")
	var rest := TaxiLogic.fenster_rest_s(taxi, now_ms())
	_label(I18nService.t("travel.taxi.fenster").format({"s": rest}), "")
	var einsteigen := _knopf(I18nService.t("travel.taxi.einsteigen"), "PrimaryButton")
	einsteigen.pressed.connect(_on_einsteigen)
	_box.add_child(einsteigen)


func _render_weg(vac: Dictionary) -> void:
	var rest_ms := maxi(0, int(vac["returnAt"]) - now_ms())
	_label(I18nService.t("travel.weg.titel"), "HeadlineLabel")
	_label(I18nService.t("travel.weg.rest").format({"tage": ceili(rest_ms / 86400000.0)}), "")
	# W15/URLAUB (additiv): solange Gooby VOR ORT ist, kann man ihn dort
	# besuchen — reine Ansicht, keine Phasen-Änderung (UrlaubsBesuch).
	if UrlaubsBesuch.verfuegbar(gs.state(), now_ms()):
		var besuchen := _knopf(I18nService.t("urlaub.knopf.besuchen"), "PrimaryButton")
		besuchen.name = "GoobyBesuchen"
		besuchen.pressed.connect(_on_gooby_besuchen)
		_box.add_child(besuchen)


func _render_abholen(overdue: bool) -> void:
	_label(I18nService.t("travel.abholen.titel"), "HeadlineLabel")
	if overdue:
		_label(I18nService.t("travel.abholen.overdue"), "CaptionLabel")
	var btn := _knopf(I18nService.t("travel.abholen.knopf"), "PrimaryButton")
	btn.pressed.connect(_on_abholen.bind(overdue))
	_box.add_child(btn)


## --------------------------------------------------------------- Actions


func _on_buchen(ziel_id: String) -> void:
	var info := ReiseLogic.bestaetigung(ziel_id, int(gs.get_value("economy.coins", 0)))
	if info.is_empty() or not bool(info["kann_zahlen"]):
		return
	var res := TaxiLogic.rufen(CityState.taxi_slice(gs), now_ms(), warte_s(), ziel_id)
	if not bool(res["ok"]):
		return
	var gesamt := int(info["preis"]) + int(res["kosten"])
	# GDScript-Lambdas capturen lokale Werte PER KOPIE — ein bool käme nie
	# zurück (Taxi würde nie gespeichert). Dictionary teilt die Referenz.
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			zahlung["ok"] = Economy.spend(state["economy"], gesamt, "reise")
	)
	if not bool(zahlung["ok"]):
		return
	# Outcome schlägt Press: erst die GELUNGENE Münz-Ausgabe klingt.
	AudioDirector.try_play(self, "ui_buy")
	Haptics.success(self)
	CityState.save_taxi_slice(gs, res["slice"])
	for notif: Dictionary in res["notifications"]:
		notifs.plane(str(notif["id"]), I18nService.t(str(notif["text_key"])), int(notif["at_ms"]))
	_zeige_toast(I18nService.t("travel.taxi.bestellt"))
	_render()


func _on_storno() -> void:
	var taxi := CityState.taxi_slice(gs)
	var ziel_id := str(taxi["zielId"])
	var res := TaxiLogic.storno(taxi)
	if not bool(res["ok"]):
		return
	AudioDirector.try_play(self, "ui_back")
	notifs.storniere_gruppe("taxi.")
	var preis := int(Vacation.CATALOG.get(ziel_id, {}).get("price", 0))
	gs.update(
		func(state: Dictionary) -> void:
			Economy.award(state["economy"], preis + int(res["erstattung"]), "erstattung")
	)
	CityState.save_taxi_slice(gs, res["slice"])
	_zeige_toast(I18nService.t("travel.taxi.storniert"))
	_render()


func _on_einsteigen() -> void:
	var taxi := CityState.taxi_slice(gs)
	var res := TaxiLogic.einsteigen(taxi, now_ms())
	if not bool(res["ok"]):
		_render()
		return
	notifs.storniere_gruppe("taxi.")
	CityState.save_taxi_slice(gs, res["slice"])
	var ziel_id := str(res["slice"]["zielId"])
	# W13B: Boarding-Pass dazwischenschieben — das Sheet bleibt offen
	# (hält diese Instanz am Leben), erst „Gute Reise!“ schließt es und
	# startet die BESTEHENDE Cutscene (identische Sequenz wie zuvor).
	# Der Knopf bleibt STUMM: das Boarding-Pass-Overlay spielt ui_open
	# (Grammatik: Öffnen klingt nur über das Panel, kein Doppel-Klang).
	if boarding_oeffner.is_valid():
		boarding_oeffner.call(ziel_id, _on_gute_reise.bind(ziel_id))
		return
	BoardingPass.oeffne(get_tree().root, ziel_id, now_ms(), _on_gute_reise.bind(ziel_id))


func _on_gute_reise(ziel_id: String) -> void:
	sheet.close()
	starte_abflug_cutscene(get_tree().root, ziel_id, gs)


## W18/4-B8: Abschluss-Verdrahtung STATISCH — „Gute Reise!“ schließt das
## Sheet, dessen closed-Signal den ReiseAppLayer (samt dieser Instanz) per
## queue_free() abbaut. Ein Instanz-Handler am fertig-Signal feuerte danach
## ins Leere: Geld weg, kein Urlaub, Route klemmt, Geister-Flugzeug blieb.
## Die statischen Callables leben auf dem Skript (überleben die App), die
## Cutscene trägt den Abschluss-Latch als Meta (buchen GENAU einmal), und
## tree_exiting erstattet, wenn die Cutscene UNFERTIG stirbt (App-Kill):
## kein Geldverlust ohne Leistung — entweder buchen+reisen oder Erstattung.
static func starte_abflug_cutscene(wurzel: Node, ziel_id: String, game_state: Object) -> Node:
	var cutscene: Node = CutsceneScene.instantiate()
	cutscene.ziel_id = ziel_id
	cutscene.fertig.connect(_schliesse_reise_ab.bind(cutscene, game_state))
	cutscene.tree_exiting.connect(_erstatte_falls_unfertig.bind(cutscene, game_state))
	wurzel.add_child(cutscene)
	return cutscene


static func _schliesse_reise_ab(cutscene: Node, game_state: Object) -> void:
	if bool(cutscene.get_meta("reise_abgeschlossen", false)):
		return
	cutscene.set_meta("reise_abgeschlossen", true)
	var ziel_id := str(cutscene.get("ziel_id"))
	var res := ReiseLogic.buchen(
		Vacation.slice_of(game_state.state()), ziel_id, _jetzt_ms(game_state)
	)
	if bool(res["ok"]):
		game_state.set_value("vacation", res["vacation"])
	else:
		# Buchung unmöglich (z. B. schon verreist): Geld zurück statt weg.
		_erstatte(game_state, ziel_id)
	CityState.save_taxi_slice(game_state, TaxiLogic.abgeschlossen(CityState.taxi_slice(game_state)))
	var router := cutscene.get_node_or_null("/root/SceneRouter")
	if router != null and not router.is_busy():
		router.goto(&"home/living", {})
	cutscene.queue_free()


## Cutscene stirbt VOR dem Abschluss (queue_free/Szenen-Abbau/App-Kill):
## Reisepreis + Taxi-Grundgebühr zurück, Taxi-Slice aufräumen.
static func _erstatte_falls_unfertig(cutscene: Node, game_state: Object) -> void:
	if bool(cutscene.get_meta("reise_abgeschlossen", false)):
		return
	cutscene.set_meta("reise_abgeschlossen", true)
	_erstatte(game_state, str(cutscene.get("ziel_id")))
	CityState.save_taxi_slice(game_state, TaxiLogic.abgeschlossen(CityState.taxi_slice(game_state)))


static func _erstatte(game_state: Object, ziel_id: String) -> void:
	var preis := int(Vacation.CATALOG.get(ziel_id, {}).get("price", 0))
	game_state.update(
		func(state: Dictionary) -> void:
			Economy.award(state["economy"], preis + TaxiLogic.KOSTEN, "erstattung")
	)


static func _jetzt_ms(game_state: Object) -> int:
	if game_state != null and "clock" in game_state and game_state.clock != null:
		return int(game_state.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## W15/URLAUB (additiv): Besuchs-Reise starten — Sheet zu, Route über
## UrlaubsBesuch (space → bestehende Raumstation), Rückweg = Router-back.
func _on_gooby_besuchen() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or router.is_busy():
		return
	AudioDirector.try_play(self, "ui_click")
	sheet.close()
	UrlaubsBesuch.besuche(gs, router, now_ms())


func _on_abholen(overdue: bool) -> void:
	var res := ReiseLogic.abholen(Vacation.slice_of(gs.state()), now_ms())
	if not bool(res["ok"]):
		return
	# Outcome: Souvenir-Münzen kommen REIN (ui_coins) + Belohnungs-Haptik.
	AudioDirector.try_play(self, "ui_coins")
	Haptics.success(self)
	gs.update(
		func(state: Dictionary) -> void:
			if overdue:
				Economy.spend(state["economy"], Vacation.TAXI_FEE, "taxiAbholung")
			Economy.award(state["economy"], int(res["souvenir_coins"]), "souvenir")
			state["vacation"] = res["vacation"]
			state["gooby"]["stats"]["energy"] = Vacation.PICKUP_STAT_FILL
	)
	if int(res["postkarten"]) > 0:
		CityState.set_flag(gs, "postkarten_neu", true)
	_zeige_toast(
		I18nService.t("travel.abholen.fertig").format({"coins": int(res["souvenir_coins"])})
	)
	_render()


## ---------------------------------------------------------------- Helfer


## Aktions-Knopf im AC-Look: SquishButton (Squish + Tap-Haptik zentral),
## Mindesthöhe 52·f und physischer Touch-Floor (ui-reisen HOCH 5).
func _knopf(text: String, variation: String) -> SquishButton:
	var btn := SquishButton.new()
	btn.theme_type_variation = variation
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var m := ScreenShell.metrics(get_viewport())
	btn.custom_minimum_size = Vector2(0.0, roundf(KNOPF_HOEHE * float(m["f"])))
	ScreenShell.touch_target(btn, m)
	return btn


func _label(text: String, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Start-Breite VOR add_child setzen: Autowrap rechnet die Min-Höhe an der
	# AKTUELLEN Breite — bei 0 explodiert sie (1 Zeichen/Zeile) und das Sheet
	# wächst per grow_vertical schirmhoch und schrumpft nie zurück.
	# G4/P16: Breite = reale Inhaltsbreite statt Festwert 380.
	var breite := inhalt_breite()
	label.custom_minimum_size = Vector2(breite, 0.0)
	label.size = Vector2(breite, 0.0)
	if not variation.is_empty():
		label.theme_type_variation = variation
	_box.add_child(label)


## Theme-Schriften des frischen Inhalts mit UiScale skalieren (FlapBoard-
## Zeilen tragen META_FONT_SKIP und skalieren ihre Schrift selbst).
func _skaliere_schriften() -> void:
	var vp := get_viewport()
	if vp != null:
		ScreenShell.scale_fonts(self, UiScale.for_viewport(vp))


func _zeige_toast(text: String) -> void:
	ToastLayer.zeige(self, text)
