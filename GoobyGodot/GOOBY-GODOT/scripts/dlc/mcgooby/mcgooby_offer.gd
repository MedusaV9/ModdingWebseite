class_name McGoobyOffer
extends RefCounted
## Das McGooby-Kauf-Angebot (Welle B) — GoobyeOffer als Code-Vorlage (Doc
## §10.3 nennt ranch_offer/kauf ausdrücklich als Blaupause): der Kauf
## passiert DIREKT im Sheet („Schlüssel zum Laden!“), danach geht es sofort
## in die erste eigene Schicht. „Später“ merkt sich den Stand
## (mcgooby.angebotVerschoben); das Angebot bleibt über den DLC-Hub
## erreichbar, und die Probeschicht bleibt als Tages-Demo frei (Teaser).
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


## Baut + öffnet das Angebot-Sheet (zeigt NICHT, wenn gekauft oder Level
## zu niedrig — fail-closed wie Ranch-/GoobyeOffer.zeige).
static func zeige(host: Node, gs: Object) -> Control:
	if host == null or gs == null:
		return null
	if McGoobyState.ist_gekauft(gs) or not McGoobyState.ist_freigeschaltet(gs):
		return null
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	sheet.set_title(I18nService.t("dlc_mcgooby.angebot.titel"))
	sheet.add_content(_inhalt(sheet, gs))
	sheet.open()
	return sheet


static func _inhalt(sheet: PanelSheet, gs: Object) -> Control:
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
	var demo := Label.new()
	demo.name = "DemoHinweis"
	demo.theme_type_variation = &"CaptionLabel"
	demo.text = I18nService.t("dlc_mcgooby.angebot.demo")
	demo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(demo)
	# W18/4 Befund B4: Hinweiszeile + Knopfzeile sitzen GEPINNT im Blatt-Fuß
	# (PanelSheet.add_footer) statt am Ende des scrollenden Inhalts — quer
	# läge der Kauf-Knopf sonst unter der Falz (IKEA-Muster W18/F6).
	var fuss := VBoxContainer.new()
	fuss.name = "KaufFuss"
	fuss.add_theme_constant_override("separation", 12)
	var hinweis := Label.new()
	hinweis.name = "KaufHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_mcgooby.angebot.frage")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fuss.add_child(hinweis)
	var knoepfe := HBoxContainer.new()
	knoepfe.add_theme_constant_override("separation", 12)
	knoepfe.alignment = BoxContainer.ALIGNMENT_CENTER
	fuss.add_child(knoepfe)
	var kaufen := SquishButton.new()
	kaufen.name = "Kaufen"
	kaufen.theme_type_variation = &"BtnLeaf"
	kaufen.text = I18nService.t("dlc_mcgooby.angebot.kaufen")
	kaufen.focus_mode = Control.FOCUS_NONE
	kaufen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	kaufen.pressed.connect(_on_kaufen.bind(sheet, gs, hinweis))
	knoepfe.add_child(kaufen)
	var spaeter := SquishButton.new()
	spaeter.name = "Spaeter"
	spaeter.theme_type_variation = &"BtnGhost"
	spaeter.text = I18nService.t("dlc_mcgooby.angebot.spaeter")
	spaeter.focus_mode = Control.FOCUS_NONE
	spaeter.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	spaeter.pressed.connect(_on_spaeter.bind(sheet, gs))
	knoepfe.add_child(spaeter)
	sheet.add_footer(fuss)
	sheet.set_meta(META_KAUFEN, kaufen)
	sheet.set_meta(META_SPAETER, spaeter)
	sheet.set_meta(META_HINWEIS, hinweis)
	# W18/4 Befund B12 („Kauf-Knopf aktiv-grün trotz Münzmangel“): reicht das
	# Münzsäckel nicht, ist der Knopf DISABLED und die Hinweiszeile sagt
	# sofort Klartext — kein lockender grüner Knopf, der erst beim Tap warnt.
	if McGoobyKauf.check(gs) == McGoobyKauf.RESULT_BROKE:
		kaufen.disabled = true
		_warne(
			hinweis,
			I18nService.t("dlc_mcgooby.angebot.zu_wenig", {"preis": McGoobyKatalog.preis()})
		)
	kaufen.gui_input.connect(_on_kaufen_gesperrt_input.bind(kaufen, sheet))
	return box


## W20/P3 (Befund E6 „Warnung winzig"): sobald die Hinweiszeile WARNT,
## spricht sie in normaler Textgröße und DANGER-Ton statt als Mini-Caption.
static func _warne(hinweis: Label, text: String) -> void:
	hinweis.text = text
	hinweis.theme_type_variation = &""
	hinweis.add_theme_color_override("font_color", AcTokens.DANGER)


## „Schlüssel zum Laden!“: atomarer Kauf; Erfolg klingt nach ui_buy und
## reist in die erste eigene Schicht, „zu wenig Münzen“ nach ui_error.
static func _on_kaufen(sheet: PanelSheet, gs: Object, hinweis: Label) -> void:
	match McGoobyKauf.kaufe(gs):
		McGoobyKauf.RESULT_OK:
			AudioDirector.try_play(sheet, "ui_buy")
			Haptics.success(sheet)
			var baum := sheet.get_tree()
			sheet.close()
			sheet.queue_free()
			if auto_navigate:
				McGoobyRouten.fahre_zur_schicht(baum)
		McGoobyKauf.RESULT_BROKE:
			AudioDirector.try_play(sheet, "ui_error")
			Haptics.warn(sheet)
			_warne(
				hinweis,
				I18nService.t("dlc_mcgooby.angebot.zu_wenig", {"preis": McGoobyKatalog.preis()})
			)
		_:
			AudioDirector.try_play(sheet, "ui_error")
			sheet.close()
			sheet.queue_free()


## „Später kaufen“: Stand merken — das Angebot bleibt im Hub erreichbar.
static func _on_spaeter(sheet: PanelSheet, gs: Object) -> void:
	AudioDirector.try_play(sheet, "ui_back")
	McGoobyState.angebot_verschieben(gs)
	sheet.close()
	sheet.queue_free()


## B12: Tipp-Versuch auf den DISABLED Kauf-Knopf — disabled Knöpfe feuern
## kein pressed, ihr gui_input kommt aber weiter an. Reagiert NUR auf den
## Touch-Press (das Projekt pinnt emulate_touch_from_mouse; PanelSheet-Muster).
static func _on_kaufen_gesperrt_input(event: InputEvent, kaufen: Button, sheet: Control) -> void:
	if not kaufen.disabled:
		return
	if not (event is InputEventScreenTouch) or not (event as InputEventScreenTouch).pressed:
		return
	AudioDirector.try_play(sheet, "ui_error")
	Haptics.warn(sheet)
	_kopfschuetteln(kaufen)


## Sanftes Nein-Schütteln des Kauf-Knopfs (zu teuer) — 1:1 das
## Garderoben-Muster (RM = ohne Bewegung; laufendes Schütteln stapelt nicht).
static func _kopfschuetteln(knopf: Control) -> void:
	if knopf == null or not knopf.is_inside_tree() or UiMotion.reduced(knopf):
		return
	if knopf.has_meta(&"w19_schuettel"):
		var alt: Variant = knopf.get_meta(&"w19_schuettel")
		if alt is Tween and (alt as Tween).is_valid():
			return
	var rast := knopf.position.x
	var tween := knopf.create_tween()
	knopf.set_meta(&"w19_schuettel", tween)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for versatz: float in [-7.0, 6.0, -4.0, 0.0]:
		tween.tween_property(knopf, "position:x", rast + versatz, 0.055)
