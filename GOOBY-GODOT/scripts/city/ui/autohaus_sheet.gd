class_name AutohausSheet
extends VBoxContainer
## Autohaus-UI (Doc E §1.4, USER §D48): CarDef-Liste mit Stats, Farbwahl
## und Kauf. Besessene Wagen lassen sich kostenlos umlackieren und als
## aktives Auto wählen — `AutoKatalog.aktives_auto()` ist der Contract für
## die Fahr-Minispiele (Doc G §6).

signal gekauft(auto_id: String)

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object

## auto_id → aktuell im UI gewählte Farbe (vor dem Kauf).
var _wahl: Dictionary = {}


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.coins_zeile(self, _coins())
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE)
	var aktiv := str(AutoKatalog.aktives_auto(gs).get("id", ""))
	for eintrag: Dictionary in AutoKatalog.autos():
		_baue_auto_karte(liste, eintrag, aktiv)


## ---------------------------------------------------------------- Aufbau


func _baue_auto_karte(liste: Control, eintrag: Dictionary, aktiv_id: String) -> void:
	var id := str(eintrag.get("id", ""))
	var karte := CitySheetBausteine.karte(liste)
	var besitzt := AutoKatalog.besitzt(gs, id)
	var titel := str(eintrag.get("name_de", id))
	if id == aktiv_id:
		titel = "%s — %s" % [titel, I18nService.t("city.autohaus.faehrt_gerade")]
	CitySheetBausteine.label(karte, titel, "HeadlineLabel")
	CitySheetBausteine.label(karte, str(eintrag.get("spruch_de", "")), "CaptionLabel")
	CitySheetBausteine.label(karte, _stats_text(eintrag), "CaptionLabel")
	_baue_farbreihe(karte, eintrag, besitzt)
	if besitzt:
		_baue_besitz_knopf(karte, id, aktiv_id)
		return
	var preis := int(eintrag.get("preis", 0))
	CitySheetBausteine.kauf_zeile(
		karte,
		I18nService.t("city.autohaus.farbe").format({"farbe": _farb_name(id, eintrag)}),
		"",
		CitySheetBausteine.preis_text(preis),
		AutoKatalog.kann_kaufen(gs, id, _farbe(id, eintrag)),
		func() -> void: _kaufe(eintrag)
	)


func _baue_farbreihe(karte: Control, eintrag: Dictionary, besitzt: bool) -> void:
	var id := str(eintrag.get("id", ""))
	var reihe := HBoxContainer.new()
	reihe.add_theme_constant_override("separation", 8)
	karte.add_child(reihe)
	var gewaehlt := _farbe(id, eintrag)
	for hex: String in eintrag.get("farben", []):
		reihe.add_child(
			CitySheetBausteine.farb_knopf(
				Color.from_string(hex, Color.WHITE),
				hex == gewaehlt,
				func() -> void: _waehle_farbe(id, hex, besitzt)
			)
		)


func _baue_besitz_knopf(karte: Control, id: String, aktiv_id: String) -> void:
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton" if id != aktiv_id else "GhostButton"
	btn.disabled = id == aktiv_id
	btn.text = I18nService.t(
		"city.autohaus.im_besitz" if id == aktiv_id else "city.autohaus.fahren"
	)
	btn.pressed.connect(
		func() -> void:
			AutoKatalog.waehle(gs, id)
			aktualisiere()
	)
	karte.add_child(btn)


func _stats_text(eintrag: Dictionary) -> String:
	return (
		I18nService
		. t("city.autohaus.stats")
		. format(
			{
				"tempo": "%.0f" % float(eintrag.get("max_speed", 0.0)),
				"start": "%.0f" % float(eintrag.get("base_speed", 0.0)),
				"lenkung": "%.1f" % float(eintrag.get("steer_rate", 0.0)),
			}
		)
	)


## --------------------------------------------------------------- Actions


func _waehle_farbe(id: String, hex: String, besitzt: bool) -> void:
	_wahl[id] = hex
	if besitzt:
		AutoKatalog.lackieren(gs, id, hex)
	aktualisiere()


func _kaufe(eintrag: Dictionary) -> void:
	var id := str(eintrag.get("id", ""))
	var farbe := _farbe(id, eintrag)
	if not AutoKatalog.kann_kaufen(gs, id, farbe):
		return
	var preis := int(eintrag.get("preis", 0))
	var bezahlt := false
	gs.update(
		func(state: Dictionary) -> void:
			bezahlt = Economy.spend(state["economy"], preis, "autohaus")
	)
	if not bezahlt:
		return
	AutoKatalog.eintragen(gs, id, farbe)
	gekauft.emit(id)
	aktualisiere()


func _farbe(id: String, eintrag: Dictionary) -> String:
	if _wahl.has(id):
		return str(_wahl[id])
	var eigene := AutoKatalog.besitz(gs)
	if eigene.has(id):
		return str(eigene[id])
	var farben: Array = eintrag.get("farben", [])
	return str(farben[0]) if not farben.is_empty() else "#FFF4E6"


func _farb_name(id: String, eintrag: Dictionary) -> String:
	return AutoKatalog.farb_name(_farbe(id, eintrag))


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))
