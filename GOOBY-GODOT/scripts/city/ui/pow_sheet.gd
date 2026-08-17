class_name PowSheet
extends VBoxContainer
## POW!-Laden-UI (Doc E §2.3): die KAMERA als Gate-Kauf oben (einmalig,
## schaltet den Fotomodus + die IGohbie-Kamera-App frei) und darunter die
## 3 Tagesangebote — deterministisch aus dem Kalendertag (PowAngebote),
## mit Countdown „Neu in 7 h“.
##
## Kauf läuft über die W1d-Economy; gekaufte Waren landen in inventory.items.

signal gekauft(ware_id: String)

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object
## Tests/Screenshots frieren die Zeit ein (< 0 = echte Systemzeit).
var zeit_override := -1


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func unix_s() -> int:
	if zeit_override >= 0:
		return zeit_override
	return int(Time.get_unix_time_from_system())


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.coins_zeile(self, _coins())
	_baue_kamera()
	_baue_angebote()


## ---------------------------------------------------------------- Aufbau


func _baue_kamera() -> void:
	var karte := CitySheetBausteine.karte(self)
	var ware := PowAngebote.kamera_ware()
	CitySheetBausteine.label(karte, I18nService.t("city.pow.kamera_titel"), "HeadlineLabel")
	if PowAngebote.hat_kamera(gs):
		CitySheetBausteine.label(karte, I18nService.t("city.pow.kamera_hast_du"), "CaptionLabel")
		return
	CitySheetBausteine.label(karte, I18nService.t("city.pow.kamera_text"), "CaptionLabel")
	var preis := int(ware.get("preis", 0))
	CitySheetBausteine.kauf_zeile(
		karte,
		str(ware.get("name_de", "?")),
		I18nService.t("city.pow.kamera_gate"),
		CitySheetBausteine.preis_text(preis),
		_coins() >= preis,
		func() -> void: _kaufe(str(ware.get("inventar", "kamera")), preis, "kamera")
	)


func _baue_angebote() -> void:
	var rest_h := int(ceil(float(PowAngebote.rest_s_bis_wechsel(unix_s())) / 3600.0))
	CitySheetBausteine.label(self, I18nService.t("city.pow.angebote_titel"), "HeadlineLabel")
	CitySheetBausteine.label(
		self, I18nService.t("city.pow.angebote_neu").format({"stunden": rest_h}), "CaptionLabel"
	)
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
	for angebot: Dictionary in PowAngebote.angebote(PowAngebote.tag_seed(unix_s())):
		var preis := int(angebot["preis_neu"])
		CitySheetBausteine.kauf_zeile(
			liste,
			str(angebot["name_de"]),
			I18nService.t("city.pow.rabatt").format(
				{"rabatt": int(angebot["rabatt"]), "alt": int(angebot["preis"])}
			),
			CitySheetBausteine.preis_text(preis),
			_coins() >= preis,
			func() -> void: _kaufe(str(angebot["inventar"]), preis, str(angebot["id"]))
		)


## --------------------------------------------------------------- Actions


func _kaufe(inventar_key: String, preis: int, ware_id: String) -> void:
	if gs == null or _coins() < preis:
		return
	# GDScript-Lambdas capturen lokale Werte PER KOPIE — ein bool käme nie
	# zurück (Kamera-Flag/Signal liefen nie). Dictionary teilt die Referenz.
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			zahlung["ok"] = Economy.spend(state["economy"], preis, "pow")
			if bool(zahlung["ok"]):
				var items: Dictionary = state["inventory"]["items"]
				items[inventar_key] = int(items.get(inventar_key, 0)) + 1
	)
	if not bool(zahlung["ok"]):
		return
	if inventar_key == PowAngebote.KAMERA_ITEM:
		CityState.set_flag(gs, "kamera_gekauft", true)
	gekauft.emit(ware_id)
	aktualisiere()


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))
