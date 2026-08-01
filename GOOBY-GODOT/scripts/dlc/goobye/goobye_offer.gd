class_name GoobyeOffer
extends RefCounted
## Das „Goo und Bye“-Kauf-Angebot (G5/P24) — RanchOffer als Code-Vorlage
## (Doc §7.2), aber Welle A ohne eigene Anreise-Szene: der Kauf passiert
## DIREKT im Sheet („Schlüssel übernehmen“), danach geht es sofort in den
## Laden. „Später“ merkt sich den Stand (dlc.goobye.angebotVerschoben);
## das Angebot bleibt über den DLC-Hub erreichbar.
##
## Sound nach AUDIO-GRAMMATIK: der Kauf-Ausgang steht erst NACH dem Druck
## fest — der Druck bleibt stumm, der AUSGANG klingt (ui_buy/ui_error).

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Meta-Keys am zurückgegebenen Sheet (Tests drücken die Knöpfe darüber).
const META_KAUFEN := "goobye_kaufen_button"
const META_SPAETER := "goobye_spaeter_button"
const META_HINWEIS := "goobye_hinweis_label"

## Tests: Navigation nach dem Kauf abschaltbar.
static var auto_navigate := true


## Baut + öffnet das Angebot-Sheet (zeigt NICHT, wenn gekauft oder Level
## zu niedrig — fail-closed wie RanchOffer.zeige).
static func zeige(host: Node, gs: Object) -> Control:
	if host == null or gs == null:
		return null
	if GoobyeState.ist_gekauft(gs) or not GoobyeState.ist_freigeschaltet(gs):
		return null
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	sheet.set_title(I18nService.t("dlc_goobye.angebot.titel"))
	sheet.add_content(_inhalt(sheet, gs))
	sheet.open()
	return sheet


static func _inhalt(sheet: PanelSheet, gs: Object) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var text := Label.new()
	text.text = I18nService.t("dlc_goobye.angebot.text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var preis := Label.new()
	preis.theme_type_variation = &"TitleLabel"
	preis.text = I18nService.t("dlc_goobye.angebot.preis", {"preis": GoobyeKatalog.preis()})
	preis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(preis)
	var hinweis := Label.new()
	hinweis.name = "KaufHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.angebot.frage")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hinweis)
	var knoepfe := HBoxContainer.new()
	knoepfe.add_theme_constant_override("separation", 12)
	knoepfe.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(knoepfe)
	var kaufen := SquishButton.new()
	kaufen.name = "Kaufen"
	kaufen.theme_type_variation = &"BtnLeaf"
	kaufen.text = I18nService.t("dlc_goobye.angebot.kaufen")
	kaufen.focus_mode = Control.FOCUS_NONE
	kaufen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	kaufen.pressed.connect(_on_kaufen.bind(sheet, gs, hinweis))
	knoepfe.add_child(kaufen)
	var spaeter := SquishButton.new()
	spaeter.name = "Spaeter"
	spaeter.theme_type_variation = &"BtnGhost"
	spaeter.text = I18nService.t("dlc_goobye.angebot.spaeter")
	spaeter.focus_mode = Control.FOCUS_NONE
	spaeter.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	spaeter.pressed.connect(_on_spaeter.bind(sheet, gs))
	knoepfe.add_child(spaeter)
	sheet.set_meta(META_KAUFEN, kaufen)
	sheet.set_meta(META_SPAETER, spaeter)
	sheet.set_meta(META_HINWEIS, hinweis)
	return box


## „Schlüssel übernehmen“: atomarer Kauf; Erfolg klingt nach ui_buy und
## reist in den Laden, „zu wenig Münzen“ nach ui_error mit Klartext-Zeile.
static func _on_kaufen(sheet: PanelSheet, gs: Object, hinweis: Label) -> void:
	match GoobyeKauf.kaufe(gs):
		GoobyeKauf.RESULT_OK:
			AudioDirector.try_play(sheet, "ui_buy")
			Haptics.success(sheet)
			var baum := sheet.get_tree()
			sheet.close()
			sheet.queue_free()
			if auto_navigate:
				GoobyeRouten.fahre_zum_laden(baum)
		GoobyeKauf.RESULT_BROKE:
			AudioDirector.try_play(sheet, "ui_error")
			Haptics.warn(sheet)
			hinweis.text = I18nService.t(
				"dlc_goobye.angebot.zu_wenig", {"preis": GoobyeKatalog.preis()}
			)
		_:
			AudioDirector.try_play(sheet, "ui_error")
			sheet.close()
			sheet.queue_free()


## „Später kaufen“: Stand merken — das Angebot bleibt im Hub erreichbar.
static func _on_spaeter(sheet: PanelSheet, gs: Object) -> void:
	AudioDirector.try_play(sheet, "ui_back")
	GoobyeState.angebot_verschieben(gs)
	sheet.close()
	sheet.queue_free()
