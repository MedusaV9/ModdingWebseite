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
## Geld-Story: Reisepreis + Taxi (10) werden beim BUCHEN abgebucht;
## verpasstes Taxi erstattet Preis + 5, Storno erstattet Preis + 8.

const Economy := preload("res://scripts/logic/economy.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const CutsceneScene := preload("res://scenes/city/reise_cutscene.tscn")

## Geteilter Notification-Planer (M1: In-App-Banner-Pfad, s. Service-Doku).
static var notifs := CityNotificationService.new()

var gs: Object
var sheet: PanelSheet
## Tests: ersetzt BoardingPass.oeffne — Callable(ziel_id, on_gute_reise).
var boarding_oeffner := Callable()

var _box: VBoxContainer
var _tick_akku := 0.0


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
	custom_minimum_size = Vector2(420.0, 0.0)
	add_theme_constant_override("separation", 10)
	_box = self
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


func _render() -> void:
	for kind in _box.get_children():
		kind.queue_free()
	if gs == null:
		return
	var vac := Vacation.slice_of(gs.state())
	var phase := Vacation.phase_at(vac, now_ms())
	if phase == Vacation.PHASE_AWAY:
		_render_weg(vac)
		return
	if phase == Vacation.PHASE_RETURN_READY or phase == Vacation.PHASE_OVERDUE:
		_render_abholen(phase == Vacation.PHASE_OVERDUE)
		return
	var taxi := CityState.taxi_slice(gs)
	match str(taxi["state"]):
		TaxiLogic.STATE_GERUFEN:
			_render_taxi_wartet(taxi)
		TaxiLogic.STATE_WARTET:
			_render_taxi_da(taxi)
		_:
			_render_ziele()


func _render_ziele() -> void:
	var coins := int(gs.get_value("economy.coins", 0))
	# W13B: Split-Flap-Abflugtafel ÜBER der Liste — klappert beim Öffnen/
	# Neurendern durch (Reduced Motion springt sofort, s. flap_board.gd).
	var tafel := FlapBoard.new()
	tafel.name = "Abflugtafel"
	_box.add_child(tafel)
	tafel.set_zeilen(_tafel_zeilen(coins))
	_label(I18nService.t("travel.ziel_waehlen"), "HeadlineLabel")
	for ziel_id in ReiseLogic.ZIELE:
		var info := ReiseLogic.bestaetigung(ziel_id, coins)
		var btn := Button.new()
		btn.theme_type_variation = "AccentButton"
		btn.text = "%s — %d ᴳ" % [I18nService.t(str(info["name_key"])), int(info["preis"])]
		btn.disabled = not bool(info["kann_zahlen"])
		btn.pressed.connect(_render_confirm.bind(ziel_id))
		_box.add_child(btn)


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


func _render_confirm(ziel_id: String) -> void:
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
	var buchen := Button.new()
	buchen.theme_type_variation = "PrimaryButton"
	buchen.text = I18nService.t("travel.confirm.buchen")
	buchen.pressed.connect(_on_buchen.bind(ziel_id))
	_box.add_child(buchen)
	var doch_nicht := Button.new()
	doch_nicht.theme_type_variation = "GhostButton"
	doch_nicht.text = I18nService.t("travel.confirm.doch_nicht")
	doch_nicht.pressed.connect(func() -> void: _render())
	_box.add_child(doch_nicht)


func _render_taxi_wartet(taxi: Dictionary) -> void:
	var rest := TaxiLogic.warte_rest_s(taxi, now_ms())
	_label(I18nService.t("travel.taxi.gerufen"), "HeadlineLabel")
	_label(
		I18nService.t("travel.taxi.countdown").format(
			{"min": rest / 60, "s": "%02d" % (rest % 60)}
		),
		""
	)
	var storno := Button.new()
	storno.theme_type_variation = "GhostButton"
	storno.text = I18nService.t("travel.taxi.storno")
	storno.pressed.connect(_on_storno)
	_box.add_child(storno)


func _render_taxi_da(taxi: Dictionary) -> void:
	_label(I18nService.t("travel.taxi.da"), "HeadlineLabel")
	var rest := TaxiLogic.fenster_rest_s(taxi, now_ms())
	_label(I18nService.t("travel.taxi.fenster").format({"s": rest}), "")
	var einsteigen := Button.new()
	einsteigen.theme_type_variation = "PrimaryButton"
	einsteigen.text = I18nService.t("travel.taxi.einsteigen")
	einsteigen.pressed.connect(_on_einsteigen)
	_box.add_child(einsteigen)


func _render_weg(vac: Dictionary) -> void:
	var rest_ms := maxi(0, int(vac["returnAt"]) - now_ms())
	_label(I18nService.t("travel.weg.titel"), "HeadlineLabel")
	_label(I18nService.t("travel.weg.rest").format({"tage": ceili(rest_ms / 86400000.0)}), "")
	# W15/URLAUB (additiv): solange Gooby VOR ORT ist, kann man ihn dort
	# besuchen — reine Ansicht, keine Phasen-Änderung (UrlaubsBesuch).
	if UrlaubsBesuch.verfuegbar(gs.state(), now_ms()):
		var besuchen := Button.new()
		besuchen.name = "GoobyBesuchen"
		besuchen.theme_type_variation = "PrimaryButton"
		besuchen.text = I18nService.t("urlaub.knopf.besuchen")
		besuchen.pressed.connect(_on_gooby_besuchen)
		_box.add_child(besuchen)


func _render_abholen(overdue: bool) -> void:
	_label(I18nService.t("travel.abholen.titel"), "HeadlineLabel")
	if overdue:
		_label(I18nService.t("travel.abholen.overdue"), "CaptionLabel")
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("travel.abholen.knopf")
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
	if boarding_oeffner.is_valid():
		boarding_oeffner.call(ziel_id, _on_gute_reise.bind(ziel_id))
		return
	BoardingPass.oeffne(get_tree().root, ziel_id, now_ms(), _on_gute_reise.bind(ziel_id))


func _on_gute_reise(ziel_id: String) -> void:
	sheet.close()
	_spiele_cutscene(ziel_id)


func _spiele_cutscene(ziel_id: String) -> void:
	var cutscene: Node = CutsceneScene.instantiate()
	cutscene.ziel_id = ziel_id
	var wurzel := get_tree().root
	cutscene.fertig.connect(_on_cutscene_fertig.bind(cutscene, ziel_id))
	wurzel.add_child(cutscene)


func _on_cutscene_fertig(cutscene: Node, ziel_id: String) -> void:
	cutscene.queue_free()
	var res := ReiseLogic.buchen(Vacation.slice_of(gs.state()), ziel_id, now_ms())
	if bool(res["ok"]):
		gs.set_value("vacation", res["vacation"])
	CityState.save_taxi_slice(gs, TaxiLogic.abgeschlossen(CityState.taxi_slice(gs)))
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and not router.is_busy():
		router.goto(&"home/living", {})


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


func _label(text: String, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Start-Breite VOR add_child setzen: Autowrap rechnet die Min-Höhe an der
	# AKTUELLEN Breite — bei 0 explodiert sie (1 Zeichen/Zeile) und das Sheet
	# wächst per grow_vertical schirmhoch und schrumpft nie zurück.
	label.custom_minimum_size = Vector2(380.0, 0.0)
	label.size = Vector2(380.0, 0.0)
	if not variation.is_empty():
		label.theme_type_variation = variation
	_box.add_child(label)


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
