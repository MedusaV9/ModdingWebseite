class_name McGoobySchichtOverlays
extends RefCounted
## Overlay-/Zeilen-Bausteine der McGooby-Schicht-Szene (Welle A+B) — reine
## statische Builder (Nodes bauen, Referenzen zurückgeben), die Szene
## verdrahtet die Signale selbst. Ausgelagert, damit die Schicht-Szene
## Ablauf-Logik bleibt (gdlint max-file-lines) — Muster: GoobyeUi.
##
## Welle B: die Schicht-Ende-Karte trägt zusätzlich den Angebots-Block
## („Schicht geschafft → Angebot“, Doc §6.2) — ein HINWEIS + KNOPF im
## Karten-Fluss statt eines Auto-Overlays, damit „Nochmal“/„Feierabend“
## direkt tippbar bleiben (Playtest-Flows tippen die Knöpfe per Name).


## Gemeinsames Overlay-Gerüst: Abdunkelung + mittige AcCardLg-Karte.
## Rückgabe: {"overlay": Control, "karte": PanelContainer, "inhalt": VBox}.
static func grund(host: Control, overlay_name: String) -> Dictionary:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	host.add_child(overlay)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.24, 0.16, 0.12, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var zentrum := CenterContainer.new()
	zentrum.name = "Zentrum"
	zentrum.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(zentrum)
	var karte := PanelContainer.new()
	karte.name = "Karte"
	karte.theme_type_variation = &"AcCardLg"
	zentrum.add_child(karte)
	var box := VBoxContainer.new()
	box.name = "Inhalt"
	box.add_theme_constant_override("separation", 10)
	karte.add_child(box)
	return {"overlay": overlay, "karte": karte, "inhalt": box}


## Eröffnungs-Hook-Karte (Doc §1.3). Rückgabe: {overlay, karte, knopf}.
static func intro(host: Control) -> Dictionary:
	var teile := grund(host, "IntroOverlay")
	var box: VBoxContainer = teile["inhalt"]
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_mcgooby.intro.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	for key: String in ["zeile1", "zeile2", "zeile3"]:
		var zeile := Label.new()
		zeile.theme_type_variation = &"SoftLabel"
		zeile.text = I18nService.t("dlc_mcgooby.intro." + key)
		zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(zeile)
	var knopf := SquishButton.new()
	knopf.name = "SchuerzeKnopf"
	knopf.theme_type_variation = &"BtnLeaf"
	knopf.text = I18nService.t("dlc_mcgooby.intro.knopf")
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(knopf)
	return {"overlay": teile["overlay"], "karte": teile["karte"], "knopf": knopf}


## Schicht-Ende-Karte mit Kassensturz + Welle-B-Angebots-Block. Rückgabe:
## {overlay, karte, zeilen, angebot_box, angebot_knopf, nochmal, feierabend}.
static func ende(host: Control) -> Dictionary:
	var teile := grund(host, "EndeOverlay")
	var box: VBoxContainer = teile["inhalt"]
	var titel := Label.new()
	titel.name = "EndeTitel"
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_mcgooby.ende.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	var unter := Label.new()
	unter.theme_type_variation = &"CaptionLabel"
	unter.text = I18nService.t("dlc_mcgooby.ende.untertitel")
	unter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(unter)
	var zeilen := VBoxContainer.new()
	zeilen.name = "Kassensturz"
	zeilen.add_theme_constant_override("separation", 4)
	box.add_child(zeilen)
	# Welle B: Angebots-Block — sichtbar nur ohne Kauf (Szene schaltet).
	var angebot_box := VBoxContainer.new()
	angebot_box.name = "AngebotBlock"
	angebot_box.add_theme_constant_override("separation", 6)
	box.add_child(angebot_box)
	var hinweis := Label.new()
	hinweis.name = "AngebotHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_mcgooby.ende.angebot_hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	angebot_box.add_child(hinweis)
	var angebot_knopf := SquishButton.new()
	angebot_knopf.name = "AngebotAnsehen"
	angebot_knopf.theme_type_variation = &"BtnLeaf"
	angebot_knopf.text = I18nService.t("dlc_mcgooby.ende.angebot")
	angebot_knopf.focus_mode = Control.FOCUS_NONE
	angebot_knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	angebot_box.add_child(angebot_knopf)
	var nochmal := SquishButton.new()
	nochmal.name = "Nochmal"
	nochmal.theme_type_variation = &"BtnTeal"
	nochmal.text = I18nService.t("dlc_mcgooby.ende.nochmal")
	nochmal.focus_mode = Control.FOCUS_NONE
	nochmal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(nochmal)
	var feierabend := SquishButton.new()
	feierabend.name = "Feierabend"
	feierabend.theme_type_variation = &"BtnGhost"
	feierabend.text = I18nService.t("dlc_mcgooby.ende.feierabend")
	feierabend.focus_mode = Control.FOCUS_NONE
	feierabend.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(feierabend)
	return {
		"overlay": teile["overlay"],
		"karte": teile["karte"],
		"zeilen": zeilen,
		"angebot_box": angebot_box,
		"angebot_knopf": angebot_knopf,
		"nochmal": nochmal,
		"feierabend": feierabend,
	}


## Stations-Block der VOLLEN Schicht (Welle B): Pills-Zeile + Bühnen-Knopf
## + Gesten-Hilfezeile — eine EIGENE Zeile im Spalten-Fluss, Playtest-
## Befund B2 (G8-PT2): Pills leben im Layout und liegen NIE über Slots.
## Rückgabe: {block, stationen, buehne_knopf, hilfe}.
static func stationen_block(rows: Control) -> Dictionary:
	var block := VBoxContainer.new()
	block.name = "StationenBlock"
	block.add_theme_constant_override("separation", 6)
	rows.add_child(block)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	block.add_child(zeile)
	var stationen := McGoobyStationenUi.new()
	stationen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(stationen)
	var buehne_knopf := SquishButton.new()
	buehne_knopf.name = "BuehneKnopf"
	buehne_knopf.theme_type_variation = &"BtnLeaf"
	buehne_knopf.text = I18nService.t("dlc_mcgooby.buehne.knopf")
	buehne_knopf.focus_mode = Control.FOCUS_NONE
	zeile.add_child(buehne_knopf)
	var hilfe := Label.new()
	hilfe.name = "GestenHilfe"
	hilfe.theme_type_variation = &"CaptionLabel"
	hilfe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hilfe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(hilfe)
	return {
		"block": block,
		"stationen": stationen,
		"buehne_knopf": buehne_knopf,
		"hilfe": hilfe,
	}


## EINE Kassensturz-Zeile (links Label, rechts Wert — Muster Welle A).
static func ende_zeile(zeilen: VBoxContainer, key: String, wert: String) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 12)
	zeilen.add_child(zeile)
	var links := Label.new()
	links.theme_type_variation = &"SoftLabel"
	links.text = I18nService.t("dlc_mcgooby.ende." + key)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(links)
	var rechts := Label.new()
	rechts.name = "Wert_" + key
	rechts.theme_type_variation = &"HeadlineLabel"
	rechts.text = wert
	zeile.add_child(rechts)
