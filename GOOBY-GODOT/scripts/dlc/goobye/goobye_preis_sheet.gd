class_name GoobyePreisSheet
extends VBoxContainer
## Preis-Schieber des „Goo und Bye“ (G6/GOOBYE-B, Doc §2.2/§4.4) — Inhalt
## fürs PanelSheet nach dem Wochenmarkt-Muster (MarktStandSheet): EIN
## Slider je WARENGRUPPE (±30 % um den Richtwert, Balance preis_spanne),
## daneben der „Richtwert“-Knopf (der „empfohlene Preis“-Default, §2.5).
## Jede Zeile rechnet ehrlich vor: Beispiel-Ware mit echtem Stückpreis und
## Marge, dazu die Kundenlust als WORTE statt Excel (griff_chance-Stufen).
## Oben steht der Tagestrend („Heute lieben alle …!“) — dieselbe
## deterministische Wahrheit wie in der Sim (GoobyeMarkttag.tagestrend).
## Gespeichert wird je Gruppe in dlc.goobye.preise (GoobyeState) — der
## nächste Markttag liest die Faktoren über GoobyePreis.ware_faktoren.

const SLIDER_SCHRITT := 0.05

var gs: Object = null
var trend_gruppe := ""


## Werksbauer: Felder setzen, Aufbau läuft in _ready (im Sheet-Baum).
static func neu(game_state: Object, trend: String) -> GoobyePreisSheet:
	var sheet := GoobyePreisSheet.new()
	sheet.gs = game_state
	sheet.trend_gruppe = trend
	return sheet


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_baue_trend()
	var preise := GoobyeState.preise_von(gs)
	for gruppe: Dictionary in GoobyeKatalog.gruppen():
		_baue_gruppen_zeile(gruppe, float(preise.get(str(gruppe["id"]), 1.0)))


## Tagestrend-Banner (§4.4): heute greifen alle bei EINER Gruppe öfter zu.
func _baue_trend() -> void:
	if trend_gruppe.is_empty():
		return
	var banner := Label.new()
	banner.name = "TrendBanner"
	banner.theme_type_variation = &"HeadlineLabel"
	banner.text = I18nService.t("dlc_goobye.preise.trend", {"gruppe": _gruppen_name(trend_gruppe)})
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(banner)
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.preise.trend_hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hinweis)


## Eine Warengruppen-Zeile: Kopf, Beispiel-Rechnung, Kundenlust, Slider.
func _baue_gruppen_zeile(gruppe: Dictionary, faktor: float) -> void:
	var gruppe_id := str(gruppe["id"])
	var kopf := Label.new()
	kopf.name = "Kopf_" + gruppe_id
	kopf.text = _gruppen_name(gruppe_id)
	if gruppe_id == trend_gruppe:
		kopf.text += " ★"
	add_child(kopf)
	var beispiel := Label.new()
	beispiel.name = "Beispiel_" + gruppe_id
	beispiel.theme_type_variation = &"CaptionLabel"
	beispiel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(beispiel)
	var lust := Label.new()
	lust.name = "Lust_" + gruppe_id
	lust.theme_type_variation = &"CaptionLabel"
	add_child(lust)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	add_child(zeile)
	var spanne := GoobyeKatalog.preis_spanne()
	var slider := HSlider.new()
	slider.name = "Schieber_" + gruppe_id
	slider.min_value = 1.0 - spanne
	slider.max_value = 1.0 + spanne
	slider.step = SLIDER_SCHRITT
	slider.value = GoobyePreis.faktor_begrenzen(faktor)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	slider.value_changed.connect(
		func(wert: float) -> void:
			GoobyeState.preis_faktor_setzen(gs, gruppe_id, wert)
			_zeige_rechnung(gruppe_id, beispiel, lust, GoobyePreis.faktor_begrenzen(wert))
	)
	zeile.add_child(slider)
	var richtwert := SquishButton.new()
	richtwert.name = "Richtwert_" + gruppe_id
	richtwert.theme_type_variation = &"BtnGhost"
	richtwert.text = I18nService.t("dlc_goobye.preise.richtwert")
	richtwert.focus_mode = Control.FOCUS_NONE
	richtwert.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	richtwert.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_chip")
			slider.value = 1.0
	)
	zeile.add_child(richtwert)
	_zeige_rechnung(gruppe_id, beispiel, lust, GoobyePreis.faktor_begrenzen(faktor))


## Beispiel-Rechnung (erste Ware der Gruppe) + Kundenlust in Worten.
func _zeige_rechnung(gruppe_id: String, beispiel: Label, lust: Label, faktor: float) -> void:
	var waren := GoobyeKatalog.waren_der_gruppe(gruppe_id)
	if waren.is_empty():
		beispiel.text = ""
	else:
		var ware: Dictionary = waren[0]
		beispiel.text = (
			I18nService
			. t(
				"dlc_goobye.preise.beispiel",
				{
					"prozent": _prozent_text(faktor),
					"name": I18nService.t(str(ware.get("name_key", ""))),
					"preis": GoobyePreis.verkaufspreis(ware, faktor),
					"marge": GoobyePreis.marge(ware, faktor),
				}
			)
		)
	lust.text = I18nService.t("dlc_goobye.preise." + _lust_key(faktor))


func _lust_key(faktor: float) -> String:
	var chance := GoobyePreis.griff_chance(faktor)
	if chance >= 0.999:
		return "lust_hoch"
	if chance >= 0.7:
		return "lust_mittel"
	return "lust_niedrig"


func _prozent_text(faktor: float) -> String:
	var prozent := roundi((faktor - 1.0) * 100.0)
	if prozent == 0:
		return "±0 %"
	return "%+d %%" % prozent


func _gruppen_name(gruppe_id: String) -> String:
	return I18nService.t("dlc_goobye.gruppe." + gruppe_id)
