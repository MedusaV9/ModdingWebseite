class_name RanchOffer
extends RefCounted
## Das Ranch-Kauf-Angebot (RANCH-1) — EXAKT der User-Wunsch: direkt nach
## dem Rückblick erscheint ab Level 20 „Du kannst jetzt zur Ranch fahren
## und sie kaufen.“ mit Preis in ᴳ und den Knöpfen „Jetzt losfahren“ /
## „Später kaufen“. „Später“ merkt sich den Stand (ranch.angebotVerschoben);
## das Angebot bleibt über die Stadtausfahrt und `RanchOffer.zeige()`
## (Handy-/Hinweis-Integrationen) erreichbar.
##
## Einbindung (Recap-Owner, Handoff RANCH1-recap-request.md):
##   RanchOffer.maybe_show(host, gs)   # nach recap_finished aufrufen
## host = beliebiger Node im Baum (das Sheet hängt sich dort ein).

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Meta-Keys am zurückgegebenen Sheet (Tests drücken die Knöpfe darüber).
const META_JETZT := "ranch_jetzt_button"
const META_SPAETER := "ranch_spaeter_button"


## Zeigt das Angebot GENAU EINMAL automatisch: ab Freischalt-Level, solange
## die Ranch nicht gekauft und das Angebot noch nie beantwortet wurde.
## Gibt das Sheet zurück (null = nichts zu zeigen).
static func maybe_show(host: Node, gs: Object) -> Control:
	if not sollte_zeigen(gs):
		return null
	return zeige(host, gs)


## Soll das Angebot nach dem Rückblick automatisch aufgehen?
static func sollte_zeigen(gs: Object) -> bool:
	if gs == null or not gs.has_method("get_value"):
		return false
	if RanchState.ist_gekauft(gs) or not RanchState.ist_freigeschaltet(gs):
		return false
	return not bool(gs.get_value("ranch.angebotGesehen", false))


## Baut + öffnet das Angebot-Sheet (auch für „Angebot erneut ansehen“ aus
## Handy/Hinweisen — zeigt NICHT, wenn gekauft oder Level zu niedrig).
static func zeige(host: Node, gs: Object) -> Control:
	if host == null or gs == null:
		return null
	if RanchState.ist_gekauft(gs) or not RanchState.ist_freigeschaltet(gs):
		return null
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	sheet.set_title(I18nService.t("ranch.angebot.titel"))
	sheet.add_content(_inhalt(sheet, gs))
	sheet.open()
	return sheet


static func _inhalt(sheet: PanelSheet, gs: Object) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var text := Label.new()
	text.text = I18nService.t("ranch.angebot.text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var preis := Label.new()
	preis.theme_type_variation = "TitleLabel"
	preis.text = I18nService.t("ranch.angebot.preis", {"preis": RanchKatalog.preis()})
	preis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(preis)
	var frage := Label.new()
	frage.theme_type_variation = "CaptionLabel"
	frage.text = I18nService.t("ranch.angebot.frage")
	frage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(frage)
	var knoepfe := HBoxContainer.new()
	knoepfe.add_theme_constant_override("separation", 12)
	knoepfe.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(knoepfe)
	var jetzt := Button.new()
	jetzt.theme_type_variation = "PrimaryButton"
	jetzt.text = I18nService.t("ranch.angebot.jetzt")
	jetzt.pressed.connect(func() -> void: _jetzt_losfahren(sheet, gs))
	knoepfe.add_child(jetzt)
	var spaeter := Button.new()
	spaeter.theme_type_variation = "GhostButton"
	spaeter.text = I18nService.t("ranch.angebot.spaeter")
	spaeter.pressed.connect(func() -> void: _spaeter_kaufen(sheet, gs))
	knoepfe.add_child(spaeter)
	sheet.set_meta(META_JETZT, jetzt)
	sheet.set_meta(META_SPAETER, spaeter)
	return box


## „Jetzt losfahren“: Angebot gesehen + ab auf die Landstraße.
static func _jetzt_losfahren(sheet: PanelSheet, gs: Object) -> void:
	RanchState.angebot_gesehen(gs)
	var baum := sheet.get_tree()
	sheet.close()
	sheet.queue_free()
	RanchRouten.fahre_zur_ranch(baum)


## „Später kaufen“: Stand merken — Angebot bleibt über die Stadtausfahrt
## (RanchExit) und RanchOffer.zeige() erreichbar.
static func _spaeter_kaufen(sheet: PanelSheet, gs: Object) -> void:
	RanchState.angebot_verschieben(gs)
	sheet.close()
	sheet.queue_free()
