class_name MarktSheet
extends VBoxContainer
## Wochenmarkt-UI (Doc D §6.3, USER §D51): Ernte verkaufen mit
## Preis-Elastizität. Beim ERSTEN Besuch erklärt eine Karte die Regel
## („Erste-Male-Karte“), danach steht sie kompakt als Info-Schild da.
##
## Verkauf läuft über `MarktPreise.verkaufen()` (pure Logik + Economy).

signal verkauft(ernte_id: String, menge: int)

var gs: Object
## Tests/Screenshots frieren die Zeit ein (< 0 = echte Systemzeit).
var zeit_override := -1
## Erste-Male-Karte zeigen (setzt der Ort beim ersten Besuch).
var erstes_mal := false


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
	_baue_schild()
	CitySheetBausteine.coins_zeile(self, _coins())
	var angebot := MarktPreise.angebot_des_spielers(gs, unix_s())
	if angebot.is_empty():
		CitySheetBausteine.label(self, I18nService.t("city.markt.nichts_dabei"))
		return
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
	for eintrag: Dictionary in angebot:
		_baue_zeile(liste, eintrag)


## ---------------------------------------------------------------- Aufbau


func _baue_schild() -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("city.markt.schild_titel"), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t("city.markt.schild_text"), "CaptionLabel")
	if erstes_mal:
		CitySheetBausteine.label(karte, I18nService.t("city.markt.erstes_mal"), "CaptionLabel")


func _baue_zeile(liste: Control, eintrag: Dictionary) -> void:
	var id := str(eintrag["id"])
	var vorrat := int(eintrag["vorrat"])
	var preis := int(eintrag["preis"])
	var zusatz := I18nService.t("city.markt.vorrat").format({"n": vorrat})
	if preis < int(eintrag["voll"]):
		zusatz = (
			"%s · %s"
			% [zusatz, I18nService.t("city.markt.gedrueckt").format({"voll": int(eintrag["voll"])})]
		)
	var zeile := CitySheetBausteine.kauf_zeile(
		liste,
		"%s — %s" % [str(eintrag["name_de"]), CitySheetBausteine.preis_text(preis)],
		zusatz,
		I18nService.t("city.markt.verkauf_eins"),
		vorrat > 0,
		func() -> void: _verkaufe(id, 1)
	)
	if vorrat <= 1:
		return
	var alle := Button.new()
	alle.theme_type_variation = "PrimaryButton"
	alle.text = I18nService.t("city.markt.verkauf_alle").format({"n": vorrat})
	alle.custom_minimum_size = Vector2(CitySheetBausteine.KNOPF_ZWEIT_BREITE, 0.0)
	alle.pressed.connect(func() -> void: _verkaufe(id, vorrat))
	zeile.add_child(alle)


## --------------------------------------------------------------- Actions


func _verkaufe(id: String, menge: int) -> void:
	var res := MarktPreise.verkaufen(gs, unix_s(), id, menge)
	if not bool(res["ok"]):
		return
	verkauft.emit(id, int(res["menge"]))
	_zeige_toast(
		I18nService.t("city.markt.verkauft").format(
			{"n": int(res["menge"]), "coins": int(res["erloes"])}
		)
	)
	aktualisiere()


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))
