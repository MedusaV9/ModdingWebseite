class_name McGoobyOffer
extends RefCounted
## Das McGooby-Kauf-Angebot (G6/MCGOOBY-B) — GoobyeOffer/RanchOffer als
## Code-Vorlage (DLC-Hub-Angebots-Sheet-Muster G5). McGooby-Zuschnitt:
## das Angebot ist der ÜBERGANG nach der freien Probeschicht („Schicht
## geschafft → Angebot“, Doc §6.2) — es öffnet deshalb AUCH unterhalb des
## Level-Gates (Kaufen-Knopf dann gesperrt + freundliche Gate-Zeile) statt
## fail-closed zu verschwinden; nur ein BESITZER sieht nie ein Angebot.
##
## Sound nach AUDIO-GRAMMATIK: der Kauf-Ausgang steht erst NACH dem Druck
## fest — der Druck bleibt stumm, der AUSGANG klingt (ui_buy/ui_error).

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Meta-Keys am zurückgegebenen Sheet (Tests drücken die Knöpfe darüber).
const META_KAUFEN := "mcgooby_kaufen_button"
const META_SPAETER := "mcgooby_spaeter_button"
const META_HINWEIS := "mcgooby_hinweis_label"

## Tests: Navigation nach dem Kauf abschaltbar.
static var auto_navigate := true


## Baut + öffnet das Angebot-Sheet. `nach_kauf` (optional): läuft nach dem
## erfolgreichen Kauf STATT der Standard-Reise — die Schicht-Szene startet
## damit ihre volle Schicht in place (kein Routen-Remount nötig).
static func zeige(host: Node, gs: Object, nach_kauf: Callable = Callable()) -> Control:
	if host == null or gs == null or McGoobyState.ist_gekauft(gs):
		return null
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	sheet.set_title(I18nService.t("dlc_mcgooby.angebot.titel"))
	sheet.add_content(_inhalt(sheet, gs, nach_kauf))
	sheet.open()
	McGoobyState.angebot_gesehen(gs)
	return sheet


static func _inhalt(sheet: PanelSheet, gs: Object, nach_kauf: Callable) -> Control:
	var gesperrt := not McGoobyState.ist_freigeschaltet(gs)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var text := Label.new()
	text.text = I18nService.t("dlc_mcgooby.angebot.text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var preis := Label.new()
	preis.theme_type_variation = &"TitleLabel"
	preis.text = I18nService.t("dlc_mcgooby.angebot.preis", {"preis": McGoobyKatalog.preis()})
	preis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(preis)
	var hinweis := Label.new()
	hinweis.name = "KaufHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = _gate_text(gs) if gesperrt else I18nService.t("dlc_mcgooby.angebot.frage")
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
	kaufen.text = I18nService.t("dlc_mcgooby.angebot.kaufen")
	kaufen.focus_mode = Control.FOCUS_NONE
	kaufen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	kaufen.disabled = gesperrt
	kaufen.pressed.connect(_on_kaufen.bind(sheet, gs, hinweis, nach_kauf))
	knoepfe.add_child(kaufen)
	var spaeter := SquishButton.new()
	spaeter.name = "Spaeter"
	spaeter.theme_type_variation = &"BtnGhost"
	spaeter.text = I18nService.t("dlc_mcgooby.angebot.spaeter")
	spaeter.focus_mode = Control.FOCUS_NONE
	spaeter.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	spaeter.pressed.connect(_on_spaeter.bind(sheet, gs))
	knoepfe.add_child(spaeter)
	sheet.set_meta(META_KAUFEN, kaufen)
	sheet.set_meta(META_SPAETER, spaeter)
	sheet.set_meta(META_HINWEIS, hinweis)
	return box


## „Schlüssel übernehmen“: atomarer Kauf; Erfolg klingt nach ui_buy und
## startet die volle Schicht, „zu wenig Münzen“ nach ui_error mit
## Klartext-Zeile (Level-Gate ebenso — falls der Knopf je aktiv war).
static func _on_kaufen(sheet: PanelSheet, gs: Object, hinweis: Label, nach_kauf: Callable) -> void:
	match McGoobyKauf.kaufe(gs):
		McGoobyKauf.RESULT_OK:
			AudioDirector.try_play(sheet, "ui_buy")
			Haptics.success(sheet)
			var baum := sheet.get_tree()
			sheet.close()
			sheet.queue_free()
			if nach_kauf.is_valid():
				nach_kauf.call()
			elif auto_navigate:
				McGoobyRouten.fahre_zur_schicht(baum)
		McGoobyKauf.RESULT_BROKE:
			AudioDirector.try_play(sheet, "ui_error")
			Haptics.warn(sheet)
			hinweis.text = I18nService.t(
				"dlc_mcgooby.angebot.zu_wenig", {"preis": McGoobyKatalog.preis()}
			)
		McGoobyKauf.RESULT_LOCKED:
			AudioDirector.try_play(sheet, "ui_error")
			hinweis.text = _gate_text(gs)
		_:
			AudioDirector.try_play(sheet, "ui_error")
			sheet.close()
			sheet.queue_free()


## „Später kaufen“: Stand merken — das Angebot bleibt nach jeder
## Probeschicht (und über den DLC-Hub) erreichbar.
static func _on_spaeter(sheet: PanelSheet, gs: Object) -> void:
	AudioDirector.try_play(sheet, "ui_back")
	McGoobyState.angebot_verschieben(gs)
	sheet.close()
	sheet.queue_free()


## Level-Gate-Zeile: freundlich, mit beiden Zahlen (Soll + Ist).
static func _gate_text(gs: Object) -> String:
	var aktuell := 1
	if gs != null and gs.has_method("get_value"):
		aktuell = int(gs.get_value("progression.level", 1))
	return I18nService.t(
		"dlc_mcgooby.angebot.gate", {"level": McGoobyKatalog.freischalt_level(), "aktuell": aktuell}
	)
