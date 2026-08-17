class_name McGoobySchichtUiTeile
extends RefCounted
## W19/McGooby-B+C — pure UI-Bauteile der McGooby-Schicht-Szene (CI-Split
## wegen gdlint max-file-lines, Muster GoobyeLadenUiTeile): Grundgerüst
## (Kopfzeile/Bestellkarte/Stationen-Mitte), Overlay-Gerüst plus die Karten
## Intro/Ende/Sperre, die Belegstation-Box, die Timing-Boxen der Stationen
## und der geteilte Anzeige-Skin der Timing-Runden (Welle C). NUR Aufbau +
## Refs — Signale verdrahtet die Szene selbst (schicht_scene.gd), Zustand
## lebt dort.

## Runden-Zustandsfarben (Parodie mit Herz: Kohle ist ein Gag, kein Fail).
const FARBE_ROH := Color("#E8A18B")
const FARBE_GOLDBRAUN := Color("#E8C25A")
const FARBE_KOHLE := Color("#54382A")
const FARBE_TEXT_HELL := Color("#FFF3DC")
const FARBE_TEXT_DUNKEL := Color("#6B4A2B")
## Fritteusen-Farben (blass → goldgelb → Knusper-Deluxe, Welle C).
const FARBE_BLASS := Color("#F4E7C0")
const FARBE_GOLDGELB := Color("#EFC75E")
const FARBE_DUNKEL := Color("#7A5230")
## Shake-Farben (flüssig → Flausch-Krone → Schaum, Welle C).
const FARBE_FLUESSIG := Color("#F7C6D9")
const FARBE_KRONE := Color("#FDEFF5")
const FARBE_SCHAUM := Color("#E8E4DA")

## Anzeige-Skin der Timing-Stationen (Welle C): Zustand → Text-Key/Farbe,
## Start-Zustand (früh = freundlich nichts), Spät-Callout (halbe Punkte).
const RUNDEN_SKIN := {
	"grill":
	{
		"start": "roh",
		"spaet_callout": "schicht.roestaroma",
		"texte": {"roh": "schicht.roh", "goldbraun": "schicht.goldbraun", "kohle": "schicht.kohle"},
		"farben": {"roh": FARBE_ROH, "goldbraun": FARBE_GOLDBRAUN, "kohle": FARBE_KOHLE},
		"text_hell": ["kohle"],
	},
	"fritteuse":
	{
		"start": "blass",
		"spaet_callout": "schicht.knusper",
		"texte":
		{
			"blass": "schicht.frit_blass",
			"goldgelb": "schicht.frit_goldgelb",
			"dunkel": "schicht.frit_dunkel",
		},
		"farben": {"blass": FARBE_BLASS, "goldgelb": FARBE_GOLDGELB, "dunkel": FARBE_DUNKEL},
		"text_hell": ["dunkel"],
	},
	"shake":
	{
		"start": "fluessig",
		"spaet_callout": "schicht.schaum",
		"texte":
		{
			"fluessig": "schicht.shake_fluessig",
			"krone": "schicht.shake_krone",
			"schaum": "schicht.shake_schaum",
		},
		"farben": {"fluessig": FARBE_FLUESSIG, "krone": FARBE_KRONE, "schaum": FARBE_SCHAUM},
		"text_hell": [],
	},
}


## Anzeige-Skin EINER Timing-Station (Grill als Fallback — auch während
## der Belegen-Phase zeigt der Grill-Tab den letzten Stand).
static func skin(phase: String) -> Dictionary:
	return RUNDEN_SKIN.get(phase, RUNDEN_SKIN["grill"])


## Knopf der aktiven Timing-Runde einfärben/beschriften — der geteilte
## Skin (RUNDEN_SKIN) macht Grill, Fritteuse und Shake-Bar zu EINER
## Visualisierungs-Strecke.
static func runde_stil_anwenden(knopf: Button, phase: String, zustand: String) -> void:
	var s := skin(phase)
	var texte: Dictionary = s["texte"]
	var farben: Dictionary = s["farben"]
	var start := str(s["start"])
	var text_farbe := FARBE_TEXT_DUNKEL
	if (s["text_hell"] as Array).has(zustand):
		text_farbe = FARBE_TEXT_HELL
	knopf.text = I18nService.t("dlc_mcgooby." + str(texte.get(zustand, texte[start])))
	knopf.add_theme_color_override("font_color", text_farbe)
	knopf.add_theme_color_override("font_pressed_color", text_farbe)
	knopf.add_theme_color_override("font_hover_color", text_farbe)
	var stil := StyleBoxFlat.new()
	stil.bg_color = farben.get(zustand, farben[start])
	stil.set_corner_radius_all(int(knopf.custom_minimum_size.y / 2.0))
	knopf.add_theme_stylebox_override("normal", stil)
	knopf.add_theme_stylebox_override("hover", stil)
	knopf.add_theme_stylebox_override("pressed", stil)


## Grundgerüst der Schicht-Szene: Wallpaper, Spalte, Kopfzeile (Zurück/
## Titel/Pause), Punkte-Zeile, Bestellkarte und die mittige Stationen-Box
## mit Callout. Rückgabe: {"rows", "back", "pause", "punkte",
## "bestellung", "gericht", "patty", "callout", "stationen"}.
static func grundgeruest(host: Control) -> Dictionary:
	var wallpaper := AcWallpaper.new()
	wallpaper.name = "Wallpaper"
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(wallpaper)
	var rows := VBoxContainer.new()
	rows.name = "Spalte"
	rows.add_theme_constant_override("separation", 12)
	host.add_child(rows)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	rows.add_child(header)
	var back := SquishButton.new()
	back.name = "Zurueck"
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("dlc_mcgooby.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	header.add_child(back)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_mcgooby.titel")
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(titel)
	var pause := SquishButton.new()
	pause.name = "Pause"
	pause.theme_type_variation = &"BtnGhost"
	pause.text = I18nService.t("dlc_mcgooby.schicht.pause")
	pause.focus_mode = Control.FOCUS_NONE
	header.add_child(pause)
	var punkte := Label.new()
	punkte.name = "Punkte"
	punkte.theme_type_variation = &"CaptionLabel"
	punkte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(punkte)
	var karte := PanelContainer.new()
	karte.name = "BestellKarte"
	karte.theme_type_variation = &"AcCard"
	rows.add_child(karte)
	var karte_box := VBoxContainer.new()
	karte_box.add_theme_constant_override("separation", 4)
	karte.add_child(karte_box)
	var bestellung := Label.new()
	bestellung.name = "Bestellung"
	bestellung.theme_type_variation = &"CaptionLabel"
	karte_box.add_child(bestellung)
	var gericht := Label.new()
	gericht.name = "Gericht"
	gericht.theme_type_variation = &"TitleLabel"
	gericht.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	karte_box.add_child(gericht)
	var patty := Label.new()
	patty.name = "PattyZaehler"
	patty.theme_type_variation = &"CaptionLabel"
	karte_box.add_child(patty)
	# Mittig: Callout über den Stationen, darunter die aktive Stations-Box.
	var mitte := CenterContainer.new()
	mitte.name = "Mitte"
	mitte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(mitte)
	var stationen := VBoxContainer.new()
	stationen.name = "Stationen"
	stationen.add_theme_constant_override("separation", 14)
	stationen.alignment = BoxContainer.ALIGNMENT_CENTER
	mitte.add_child(stationen)
	var callout := Label.new()
	callout.name = "Callout"
	callout.theme_type_variation = &"HeadlineLabel"
	callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callout.text = " "
	stationen.add_child(callout)
	return {
		"rows": rows,
		"back": back,
		"pause": pause,
		"punkte": punkte,
		"bestellung": bestellung,
		"gericht": gericht,
		"patty": patty,
		"callout": callout,
		"stationen": stationen,
	}


## Tab-Leiste unten in der Daumen-Zone (Doc §2.2: Stations-Wechsel per
## Tap). Rückgabe: {"leiste", "knoepfe": {station_id: Button}}.
static func tabs_leiste(rows: VBoxContainer) -> Dictionary:
	var tabs := HBoxContainer.new()
	tabs.name = "StationsTabs"
	tabs.add_theme_constant_override("separation", 12)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(tabs)
	var knoepfe := {}
	for station_id: String in McGoobyKatalog.STATION_IDS:
		var tab := SquishButton.new()
		tab.name = "Tab_" + station_id
		tab.text = McGoobyKatalog.text_von(McGoobyKatalog.station(station_id), "name")
		tab.focus_mode = Control.FOCUS_NONE
		tabs.add_child(tab)
		knoepfe[station_id] = tab
	return {"leiste": tabs, "knoepfe": knoepfe}


## Kassensturz-Zeilen der Ende-Karte NEU befüllen — inkl. Laden-Rang
## (Welle C, Doc §6.1): Sterne-Band + ehrliches Nächstes-Ziel (die Schicht
## ist zu diesem Zeitpunkt schon verbucht).
static func ende_fuellen(
	zeilen: VBoxContainer, kasse: Dictionary, perfekt_gesamt: int, gs: Object
) -> void:
	for kind in zeilen.get_children():
		# Sofort AUS dem Baum nehmen (Muster Zutaten-Leiste): mit
		# queue_free allein stünde das alte RangZiel bis zum Frame-Ende im
		# Weg und Godot benennte das neue um (@Label@…) — nach der zweiten
		# Schicht („Noch eine Schicht“) wäre RangZiel nicht mehr findbar
		# (Playtest-Befund flow_w19_mcgooby_vier_stationen).
		zeilen.remove_child(kind)
		kind.queue_free()
	ende_zeile(zeilen, "punkte", str(int(kasse.get("punkte", 0))))
	ende_zeile(zeilen, "perfekt", str(perfekt_gesamt))
	ende_zeile(zeilen, "trinkgeld", str(int(kasse.get("trinkgeld", 0))))
	ende_zeile(zeilen, "muenzen", str(int(kasse.get("muenzen", 0))))
	if gs == null:
		return
	ende_zeile(zeilen, "rang", McGoobyFortschritt.sterne_band(McGoobyFortschritt.sterne(gs)))
	var ziel := Label.new()
	ziel.name = "RangZiel"
	ziel.theme_type_variation = &"CaptionLabel"
	ziel.text = McGoobyFortschritt.ziel_zeile(gs)
	ziel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ziel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zeilen.add_child(ziel)


## EINE Kassensturz-Zeile (links Beschriftung, rechts Wert_<key>).
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


## Gemeinsames Overlay-Gerüst: Abdunkelung + mittige AcCardLg-Karte.
## Rückgabe: {"overlay": Control, "karte": PanelContainer, "inhalt": VBox}.
static func overlay_grund(host: Control, overlay_name: String) -> Dictionary:
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


## Eröffnungs-Hook-Karte (Doc §1.3). Rückgabe: overlay/karte + "knopf".
static func intro_overlay(host: Control) -> Dictionary:
	var teile := overlay_grund(host, "IntroOverlay")
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
	teile["knopf"] = knopf(box, "SchuerzeKnopf", &"BtnLeaf", "dlc_mcgooby.intro.knopf")
	return teile


## Schicht-Ende-Karte mit Kassensturz. Rückgabe: overlay/karte + "zeilen",
## "nochmal", "demo_hinweis" (Welle B), "angebot" (Welle B), "feierabend".
static func ende_overlay(host: Control) -> Dictionary:
	var teile := overlay_grund(host, "EndeOverlay")
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
	teile["zeilen"] = zeilen
	teile["nochmal"] = knopf(box, "Nochmal", &"BtnTeal", "dlc_mcgooby.ende.nochmal")
	# Demo-Variante (Welle B): statt „Noch eine Schicht“ sagt die Karte
	# ehrlich, dass die Tages-Demo verbraucht ist — mit Angebots-Abzweig.
	var demo_hinweis := Label.new()
	demo_hinweis.name = "DemoHinweis"
	demo_hinweis.theme_type_variation = &"CaptionLabel"
	demo_hinweis.text = I18nService.t("dlc_mcgooby.ende.demo_hinweis")
	demo_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	demo_hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	demo_hinweis.visible = false
	box.add_child(demo_hinweis)
	teile["demo_hinweis"] = demo_hinweis
	var angebot: Button = knopf(box, "EndeAngebot", &"BtnLeaf", "dlc_mcgooby.knopf.angebot")
	angebot.visible = false
	teile["angebot"] = angebot
	teile["feierabend"] = knopf(box, "Feierabend", &"BtnGhost", "dlc_mcgooby.ende.feierabend")
	return teile


## Sperre-Karte des Demo-Gates (Welle B): die Tages-Probeschicht ist
## verbraucht. Rückgabe: overlay/karte + "angebot", "feierabend".
static func sperre_overlay(host: Control) -> Dictionary:
	var teile := overlay_grund(host, "SperreOverlay")
	var box: VBoxContainer = teile["inhalt"]
	var titel := Label.new()
	titel.name = "SperreTitel"
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_mcgooby.sperre.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	var zeile := Label.new()
	zeile.theme_type_variation = &"SoftLabel"
	zeile.text = I18nService.t("dlc_mcgooby.sperre.text")
	zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(zeile)
	teile["angebot"] = knopf(box, "SperreAngebot", &"BtnLeaf", "dlc_mcgooby.knopf.angebot")
	teile["feierabend"] = knopf(box, "SperreFeierabend", &"BtnGhost", "dlc_mcgooby.ende.feierabend")
	return teile


## Belegstation-Box (Doc §2.2 #2): Ticket-Turm + Zutaten-Leiste. Rückgabe:
## {"box", "status", "turm", "hinweis", "leiste"}.
static func belegen_box() -> Dictionary:
	var box := VBoxContainer.new()
	box.name = "BelegenBox"
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.visible = false
	var status := Label.new()
	status.name = "BelegenStatus"
	status.theme_type_variation = &"CaptionLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var turm := Label.new()
	turm.name = "BelegenTurm"
	turm.theme_type_variation = &"SoftLabel"
	turm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(turm)
	var hinweis := Label.new()
	hinweis.name = "BelegenHinweis"
	hinweis.theme_type_variation = &"SoftLabel"
	hinweis.text = I18nService.t("dlc_mcgooby.schicht.belegen_leer")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hinweis)
	var leiste := HBoxContainer.new()
	leiste.name = "ZutatenLeiste"
	leiste.add_theme_constant_override("separation", 10)
	leiste.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(leiste)
	return {"box": box, "status": status, "turm": turm, "hinweis": hinweis, "leiste": leiste}


## Timing-Stations-Box (Welle C, Fritteuse/Shake-Bar — Muster GrillBox):
## großer runder Stations-Knopf + Fortschritts-Balken + Gesten-Hinweis.
## Rückgabe: {"box", "knopf", "balken", "hinweis"}.
static func timing_box(box_name: String, knopf_name: String, balken_name: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = box_name
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.visible = false
	var stations_knopf := SquishButton.new()
	stations_knopf.name = knopf_name
	stations_knopf.focus_mode = Control.FOCUS_NONE
	stations_knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(stations_knopf)
	var balken := ProgressBar.new()
	balken.name = balken_name
	balken.min_value = 0.0
	balken.max_value = 1.0
	balken.show_percentage = false
	balken.custom_minimum_size = Vector2(0.0, 10.0)
	box.add_child(balken)
	var hinweis := Label.new()
	hinweis.name = box_name + "Hinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hinweis)
	return {"box": box, "knopf": stations_knopf, "balken": balken, "hinweis": hinweis}


## Mittiger Karten-Knopf (SquishButton, Squish-Standard der Overlays).
static func knopf(
	box: VBoxContainer, knopf_name: String, variation: StringName, text_key: String
) -> SquishButton:
	var neu := SquishButton.new()
	neu.name = knopf_name
	neu.theme_type_variation = variation
	neu.text = I18nService.t(text_key)
	neu.focus_mode = Control.FOCUS_NONE
	neu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(neu)
	return neu
