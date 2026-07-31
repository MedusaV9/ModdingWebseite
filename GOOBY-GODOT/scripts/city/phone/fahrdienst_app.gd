class_name FahrdienstApp
extends VBoxContainer
## Taxi- UND Guber-App im IGohbie (Doc E §4): dieselbe TaxiLogic-Maschine,
## unterschiedliche Preise, Wartezeiten und Umgangsformen — `dienst` schaltet
## um (Fahrdienst.TAXI / Fahrdienst.GUBER). Rufen kostet sofort, Storno und
## verpasster Wagen erstatten anteilig (Fahrdienst.erstattung).
##
## Bei 0 Energie ist der Wagen der Rettungsweg nach Hause: Einsteigen fährt
## über den SceneRouter heim (`home/living`) — Fahren kostet nie Energie.

signal gerufen(dienst: String)
signal eingestiegen(dienst: String)

const Economy := preload("res://scripts/logic/economy.gd")
const ZIEL := "zuhause"

var gs: Object
var dienst := Fahrdienst.TAXI
## Tests injizieren eine feste Uhr (< 0 = echte Systemzeit).
var now_ms_override := -1
## Tests injizieren die Lokalzeit-Stunde für den Guber-Surge (< 0 = System).
var stunde_override := -1.0

var _tick_akku := 0.0


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func _process(delta: float) -> void:
	_tick_akku += delta
	if _tick_akku < 1.0:
		return
	_tick_akku = 0.0
	_tick()


func now_ms() -> int:
	if now_ms_override >= 0:
		return now_ms_override
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Lokalzeit-Stunde (0–23,99) für den Guber-Surge — gleiche Quelle wie
## city_scene._stunde (Systemuhr), für Tests injizierbar.
func stunde_lokal() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	if gs == null:
		return
	var fremd := Fahrdienst.blockiert_durch(gs, dienst)
	if not fremd.is_empty():
		_baue_belegt(fremd)
		return
	var slice := CityState.taxi_slice(gs)
	match str(slice["state"]):
		TaxiLogic.STATE_GERUFEN:
			_baue_unterwegs(slice)
		TaxiLogic.STATE_WARTET:
			_baue_wartet(slice)
		_:
			_baue_bestellen()


## ---------------------------------------------------------------- Views


func _baue_bestellen() -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("phone.%s.slogan" % dienst), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t("phone.%s.pitch" % dienst), "CaptionLabel")
	if Fahrdienst.ist_rettungsweg(gs):
		CitySheetBausteine.label(karte, I18nService.t("phone.fahrdienst.rettung"), "CaptionLabel")
	# Surge-Gag (W13B, Doc E §4): zu Stoßzeiten entschuldigt sich Guber
	# vornehm — und verlangt 45 statt 30 Münzen.
	if dienst == Fahrdienst.GUBER and Fahrdienst.ist_stosszeit(stunde_lokal()):
		CitySheetBausteine.label(karte, I18nService.t("phone.guber.surge"), "CaptionLabel")
	CitySheetBausteine.coins_zeile(self, _coins())
	var preis := Fahrdienst.kosten_zur_stunde(dienst, stunde_lokal())
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("phone.fahrdienst.rufen").format({"preis": preis})
	btn.disabled = _coins() < preis
	btn.pressed.connect(_on_rufen)
	add_child(btn)


func _baue_unterwegs(slice: Dictionary) -> void:
	var rest := TaxiLogic.warte_rest_s(slice, now_ms())
	CitySheetBausteine.label(self, I18nService.t("phone.%s.unterwegs" % dienst), "HeadlineLabel")
	CitySheetBausteine.label(
		self,
		I18nService.t("phone.fahrdienst.countdown").format(
			{"min": rest / 60, "s": "%02d" % (rest % 60)}
		)
	)
	var storno := Button.new()
	storno.theme_type_variation = "GhostButton"
	storno.text = I18nService.t("phone.fahrdienst.storno").format(
		{"zurueck": Fahrdienst.erstattung_fuer(Fahrdienst.bezahlter_preis(gs, dienst), false)}
	)
	storno.pressed.connect(_on_storno)
	add_child(storno)


func _baue_wartet(slice: Dictionary) -> void:
	CitySheetBausteine.label(self, I18nService.t("phone.%s.da" % dienst), "HeadlineLabel")
	CitySheetBausteine.label(
		self,
		I18nService.t("phone.fahrdienst.fenster").format(
			{"s": TaxiLogic.fenster_rest_s(slice, now_ms())}
		)
	)
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("phone.fahrdienst.einsteigen")
	btn.pressed.connect(_on_einsteigen)
	add_child(btn)


func _baue_belegt(fremd: String) -> void:
	CitySheetBausteine.label(self, I18nService.t("phone.fahrdienst.belegt_titel"), "HeadlineLabel")
	CitySheetBausteine.label(
		self,
		I18nService.t("phone.fahrdienst.belegt").format(
			{"dienst": I18nService.t("phone.app.%s" % fremd)}
		),
		"CaptionLabel"
	)


## --------------------------------------------------------------- Actions


func _tick() -> void:
	if gs == null or not Fahrdienst.blockiert_durch(gs, dienst).is_empty():
		return
	var vorher := CityState.taxi_slice(gs)
	if str(vorher["state"]) == TaxiLogic.STATE_IDLE:
		return
	var res := TaxiLogic.tick(vorher, now_ms())
	for ereignis: Dictionary in res["events"]:
		if str(ereignis["typ"]) == "verpasst":
			_verpasst()
	CityState.save_taxi_slice(gs, res["slice"])
	aktualisiere()


func _verpasst() -> void:
	ReiseApp.notifs.storniere_gruppe("taxi.")
	var zurueck := Fahrdienst.erstattung_fuer(Fahrdienst.bezahlter_preis(gs, dienst), true)
	gs.update(
		func(state: Dictionary) -> void: Economy.award(state["economy"], zurueck, "erstattung")
	)
	Fahrdienst.merke_dienst(gs, "")
	_zeige_toast(I18nService.t("phone.fahrdienst.verpasst"))


func _on_rufen() -> void:
	var preis := Fahrdienst.kosten_zur_stunde(dienst, stunde_lokal())
	var res := TaxiLogic.rufen(CityState.taxi_slice(gs), now_ms(), _warte_s(), ZIEL)
	if not bool(res["ok"]):
		return
	# GDScript-Lambdas capturen lokale Werte PER KOPIE — ein bool käme nie
	# zurück (Taxi bliebe idle, Geld trotzdem weg). Dictionary teilt die Referenz.
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			zahlung["ok"] = Economy.spend(state["economy"], preis, dienst)
	)
	if not bool(zahlung["ok"]):
		return
	CityState.save_taxi_slice(gs, res["slice"])
	Fahrdienst.merke_dienst(gs, dienst)
	Fahrdienst.merke_preis(gs, preis)
	for notif: Dictionary in res["notifications"]:
		ReiseApp.notifs.plane(
			str(notif["id"]), I18nService.t(str(notif["text_key"])), int(notif["at_ms"])
		)
	gerufen.emit(dienst)
	_zeige_toast(I18nService.t("phone.%s.bestellt" % dienst))
	aktualisiere()


func _on_storno() -> void:
	var res := TaxiLogic.storno(CityState.taxi_slice(gs))
	if not bool(res["ok"]):
		return
	ReiseApp.notifs.storniere_gruppe("taxi.")
	var zurueck := Fahrdienst.erstattung_fuer(Fahrdienst.bezahlter_preis(gs, dienst), false)
	gs.update(
		func(state: Dictionary) -> void: Economy.award(state["economy"], zurueck, "erstattung")
	)
	CityState.save_taxi_slice(gs, res["slice"])
	Fahrdienst.merke_dienst(gs, "")
	_zeige_toast(I18nService.t("phone.fahrdienst.storniert"))
	aktualisiere()


func _on_einsteigen() -> void:
	var res := TaxiLogic.einsteigen(CityState.taxi_slice(gs), now_ms())
	if not bool(res["ok"]):
		aktualisiere()
		return
	ReiseApp.notifs.storniere_gruppe("taxi.")
	CityState.save_taxi_slice(gs, TaxiLogic.abgeschlossen(res["slice"]))
	Fahrdienst.merke_dienst(gs, "")
	eingestiegen.emit(dienst)
	_zeige_toast(I18nService.t("phone.%s.fahrt" % dienst))
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and not router.is_busy():
		router.goto(&"home/living", {})
	aktualisiere()


## Dev-Harness: `debug.<dienst>_warte_s` verkürzt die Wartezeit.
func _warte_s() -> int:
	var debug := 0
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null:
		debug = int(settings.get_setting(str(Fahrdienst.def(dienst).get("debug_key", "")), 0))
	return Fahrdienst.warte_s(dienst, debug, randf())


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
