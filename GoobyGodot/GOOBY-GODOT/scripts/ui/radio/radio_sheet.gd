class_name RadioSheet
extends VBoxContainer
## Radio-Bedienoberfläche (REST-4 + W13/RADIO, H §6.1) — Web-Vorbild
## GOOBY/src/ui/radioScreen.js, reduziert auf die Godot-Musik-API:
## Senderwahl (mit Level-Schlössern), „Was läuft?"-Ticker, An/Aus,
## Nächster Titel, Musik-Lautstärke (AppSettings `audio.music`),
## "Gefällt mir" (Lieblingssongs, additiv in `radio.likes`) und die
## Titelliste des Senders inkl. Level-Freischaltung.
##
## KAUF-GATE HART (W13, H §6.1): `radio.owned` wird NIE durchs Einschalten
## gesetzt — nur der IKEA-Kauf (Radio-Möbel im Besitz/platziert, dann
## Self-Heal in den Save) bzw. die Grandfathering-Migration schalten das
## Vollradio frei. Ohne Besitz läuft der BORDMUSIK-MODUS: genau EIN
## Loop-Track, Steuerung nur Play/Pause, Skip/Sender/Likes gesperrt,
## dazu ein knuffiger IKEA-Kauf-Hinweis.
##
## Lebt als Inhalt eines PanelSheets (RadioGeraet dockt es an Möbel) und
## ist headless testbar: `gs` + `music` sind injizierbar; ohne Musik-Knoten
## degradiert die Wiedergabe still (Zustand wird trotzdem persistiert).

signal geschlossen

## GameState (Autoload oder Test-Double).
var gs: Object
## MusicDirector-artiger Knoten (Test-Double erlaubt; null = Autoload-Suche).
var music: Node

var _station_id := "bordmusik"
var _owned := false
var _ticker: NowPlayingChip
var _an_aus_btn: Button
var _next_btn: Button
var _like_btn: Button
var _liste_box: VBoxContainer
var _lieblinge_label: Label
var _frei_label: Label


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	if music == null:
		music = MusicDirector.get_or_create(self)
	if music != null and music.has_signal("track_changed"):
		music.track_changed.connect(_on_track_changed)
	_owned = RadioLogic.besitzt_radio(_state())
	if _owned and gs != null and not bool(gs.get_value("radio.owned", false)):
		# IKEA-Kauf = Möbel + Feature-Unlock in einem (H §6.1): einmal
		# gekauft, bleibt das Vollradio im Save freigeschaltet — auch wenn
		# das Möbel später verkauft wird (wie das Grandfathering).
		_schreibe_radio({"owned": true})
	_station_id = _gelesene_station()
	# G4/P17: Rotation/Resize baut mit frischen Metriken neu (Muster
	# News50Panel.open) — Touch-Floor/Fonts stimmen dann in beiden Formaten.
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	_baue_ui()


func _on_viewport_resized() -> void:
	if is_inside_tree():
		_baue_ui()


## ---------------------------------------------------------------- Aufbau


func _baue_ui() -> void:
	for kind in get_children():
		kind.queue_free()
	# G4/P17 (Leitidee FB3): EINMAL Metriken ziehen — Touch-Floor +
	# UiScale statt fester 44/48-px-Werte (physisch sonst nur ~24–26 pt).
	var m := ScreenShell.metrics(get_viewport())
	var floor_px: float = m["floor_px"]
	# G7/P53 (FB3-Altbefund „Like läuft aus dem Canvas“): die Layout-Wurzel
	# klemmt ihre Mindestbreite auf die ECHTE Sheet-Innenbreite statt auf
	# die feste BREITE — das nur vertikal scrollende Wirt-Sheet schneidet
	# überbreiten Inhalt sonst rechts ab (FIX1-Regel, s. chrome_width()).
	custom_minimum_size = Vector2(minf(CitySheetBausteine.BREITE, _innen_breite()), 0.0)
	CitySheetBausteine.label(self, I18nService.t("radio.titel"), "HeadlineLabel")

	var jetzt_karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(jetzt_karte, I18nService.t("radio.jetzt"), "CaptionLabel")
	_ticker = NowPlayingChip.new()
	_ticker.name = "WasLaeuft"
	_ticker.inline = true
	_ticker.sicht_breite = CitySheetBausteine.TEXT_BREITE - 70.0
	jetzt_karte.add_child(_ticker)

	# G7/P53: Transportzeile als FLOW statt HBox — die Mindestbreite einer
	# HBox ist die SUMME der drei skalierten Knöpfe und lag im Hochformat
	# (1179×2556, f=3) über der Sheet-Innenbreite; der letzte Knopf („Like“,
	# FB3: P=(961,1150.8) S=(352,156.3)) ragte aus dem Canvas. Der Flow
	# bricht stattdessen um; alle drei Knöpfe füllen ihre Zeile.
	# W20/P3 (Befund B5 „Knöpfe auf volle Blattbreite gestreckt"): die
	# Pillen behalten ihre NATÜRLICHE Breite (Padding aus dem Theme) statt
	# SIZE_EXPAND_FILL — der Flow bricht bei Enge weiter sauber um.
	var transport := HFlowContainer.new()
	transport.name = "Transport"
	transport.add_theme_constant_override("h_separation", 10)
	transport.add_theme_constant_override("v_separation", 10)
	add_child(transport)
	_an_aus_btn = SquishButton.new()
	_an_aus_btn.name = "AnAus"
	_an_aus_btn.theme_type_variation = "PrimaryButton"
	_an_aus_btn.custom_minimum_size = Vector2(0.0, floor_px)
	_an_aus_btn.focus_mode = Control.FOCUS_NONE
	_an_aus_btn.pressed.connect(_on_an_aus)
	transport.add_child(_an_aus_btn)
	_next_btn = SquishButton.new()
	_next_btn.name = "Naechster"
	_next_btn.theme_type_variation = "AccentButton"
	_next_btn.text = I18nService.t("radio.naechster")
	_next_btn.custom_minimum_size = Vector2(0.0, floor_px)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_on_naechster)
	transport.add_child(_next_btn)
	_like_btn = SquishButton.new()
	_like_btn.name = "Like"
	_like_btn.theme_type_variation = "AccentButton"
	_like_btn.text = I18nService.t("radio.gefaellt")
	_like_btn.custom_minimum_size = Vector2(0.0, floor_px)
	_like_btn.focus_mode = Control.FOCUS_NONE
	_like_btn.pressed.connect(_on_like_aktueller)
	transport.add_child(_like_btn)
	if not RadioLogic.aktion_erlaubt(_owned, "skip"):
		_next_btn.disabled = true
		_next_btn.tooltip_text = I18nService.t("radio.nur_mit_radio")
	if not RadioLogic.aktion_erlaubt(_owned, "like"):
		_like_btn.tooltip_text = I18nService.t("radio.nur_mit_radio")

	if _owned:
		_baue_vollradio(m)
	else:
		_baue_kauf_hinweis()

	_baue_lautstaerke(m)

	if _owned:
		_lieblinge_label = CitySheetBausteine.label(self, "", "CaptionLabel")
		_lieblinge_label.name = "Lieblinge"
		CitySheetBausteine.label(self, I18nService.t("radio.titel_liste"), "HeadlineLabel")
		_frei_label = CitySheetBausteine.label(self, "", "CaptionLabel")
		_frei_label.name = "FreiZaehler"
		_liste_box = CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
		_liste_box.name = "TitelListe"
		CitySheetBausteine.label(self, I18nService.t("radio.level_hinweis"), "CaptionLabel")

	# G2-Fixliste F15: Schliessen bleibt bewusst OHNE eigenen Sound —
	# `geschlossen` → RadioGeraet → PanelSheet.close() spielt schon ui_close.
	# W20/P3 Fold-Regel: der Knopf pinnt als Blatt-Fuß des Wirt-Sheets
	# (add_footer-Muster W18/4) — vorher lag er am Ende des Scroll-Inhalts
	# unter der Falz. Ohne Wirt (Standalone/Tests) bleibt er im Fluss.
	var schliessen := SquishButton.new()
	schliessen.name = "Schliessen"
	schliessen.theme_type_variation = "GhostButton"
	schliessen.text = I18nService.t("radio.schliessen")
	schliessen.custom_minimum_size = Vector2(0.0, floor_px)
	schliessen.focus_mode = Control.FOCUS_NONE
	schliessen.pressed.connect(func() -> void: geschlossen.emit())
	var wirt := _wirt_sheet()
	if wirt != null:
		wirt.add_footer(schliessen)
		ScreenShell.scale_fonts(schliessen, UiScale.font_scale(get_viewport()))
	else:
		add_child(schliessen)

	ScreenShell.scale_fonts(self, UiScale.font_scale(get_viewport()))
	_refresh()


## Vollradio (mit Besitz): Senderwahl als Cover-Karten (H §6.1).
func _baue_vollradio(m: Dictionary) -> void:
	CitySheetBausteine.label(self, I18nService.t("radio.sender"), "HeadlineLabel")
	var chips := HFlowContainer.new()
	chips.name = "SenderChips"
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	add_child(chips)
	var level := _level()
	for station: Dictionary in RadioLogic.sender(level):
		chips.add_child(_sender_cover_karte(station, m))


## Bordmusik-Modus (ohne Besitz): knuffiger IKEA-Kauf-Hinweis statt Sender.
func _baue_kauf_hinweis() -> void:
	var karte := CitySheetBausteine.karte(self)
	karte.name = "KaufHinweis"
	CitySheetBausteine.label(
		karte, "♫ %s" % I18nService.t("radio.kauf_hinweis_titel"), "HeadlineLabel"
	)
	CitySheetBausteine.label(karte, I18nService.t("radio.kauf_hinweis"))
	var bordmusik := MusicRegistry.entry(MusicDirector.BORDMUSIK_TRACK)
	CitySheetBausteine.label(
		karte,
		I18nService.t(
			"radio.bordmusik_hinweis",
			{"titel": str(bordmusik.get("title", MusicDirector.BORDMUSIK_TRACK))}
		),
		"CaptionLabel"
	)


## Sender als farbige AC-Cover-Karte (Theme-Farben + Glyph, keine Assets).
func _sender_cover_karte(station: Dictionary, m: Dictionary) -> Button:
	var id := str(station.get("id", ""))
	var cover := RadioLogic.cover(id)
	var chip := SquishButton.new()
	chip.name = "Sender_%s" % id
	chip.toggle_mode = true
	chip.focus_mode = Control.FOCUS_NONE
	var f: float = m["f"]
	chip.custom_minimum_size = Vector2(
		AcTokens.px(116.0, f), maxf(AcTokens.px(64.0, f), float(m["floor_px"]))
	)
	var locked := bool(station.get("locked", false))
	if locked:
		chip.text = (
			"%s\n%s (%s)"
			% [
				str(cover["glyph"]),
				RadioLogic.sender_name(station),
				I18nService.t(
					"radio.gesperrt_sender", {"level": int(station.get("unlock_level", 1))}
				),
			]
		)
		chip.disabled = true
	else:
		chip.text = "%s\n%s" % [str(cover["glyph"]), RadioLogic.sender_name(station)]
		chip.pressed.connect(_on_sender_gewaehlt.bind(id))
	chip.button_pressed = id == _station_id
	_style_cover_karte(chip, Color(cover["farbe"]), locked)
	return chip


func _style_cover_karte(chip: Button, farbe: Color, locked: bool) -> void:
	var basis := _cover_stylebox(farbe, false)
	chip.add_theme_stylebox_override("normal", basis)
	chip.add_theme_stylebox_override("hover", basis)
	chip.add_theme_stylebox_override("pressed", _cover_stylebox(farbe, true))
	chip.add_theme_stylebox_override("hover_pressed", _cover_stylebox(farbe, true))
	chip.add_theme_stylebox_override("disabled", _cover_stylebox(AcTokens.PAPER_SHADE, false))
	var tinte := Color(AcTokens.INK, 0.45) if locked else AcTokens.INK
	chip.add_theme_color_override("font_color", tinte)
	chip.add_theme_color_override("font_hover_color", tinte)
	chip.add_theme_color_override("font_pressed_color", tinte)
	chip.add_theme_color_override("font_hover_pressed_color", tinte)
	chip.add_theme_color_override("font_disabled_color", tinte)
	chip.add_theme_color_override("font_focus_color", tinte)


func _cover_stylebox(farbe: Color, gewaehlt: bool) -> StyleBoxFlat:
	var stil := StyleBoxFlat.new()
	stil.bg_color = farbe
	stil.set_corner_radius_all(AcTokens.RADIUS_ROW)
	stil.set_border_width_all(3 if gewaehlt else 0)
	stil.border_color = AcTokens.INK
	stil.content_margin_left = 14.0
	stil.content_margin_right = 14.0
	stil.content_margin_top = 8.0
	stil.content_margin_bottom = 8.0
	return stil


func _baue_lautstaerke(m: Dictionary) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	add_child(zeile)
	var label := Label.new()
	label.text = I18nService.t("radio.lautstaerke")
	zeile.add_child(label)
	var slider := HSlider.new()
	slider.name = "Lautstaerke"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	# Grabber-Trefferfläche auf den Touch-Floor heben (Zeile wächst mit).
	slider.custom_minimum_size = Vector2(180.0 * float(m["f"]), float(m["floor_px"]))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var app := get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("audio_level"):
		slider.value = float(app.audio_level("music"))
	else:
		slider.value = 0.8
	slider.value_changed.connect(_on_lautstaerke)
	zeile.add_child(slider)


## ---------------------------------------------------------------- Aktionen


func _on_an_aus() -> void:
	# F15: An/Aus ist ein Schalter → ui_toggle (Grammatik §3).
	AudioDirector.try_play(self, "ui_toggle")
	var playing := _spielt()
	if playing:
		if music != null and music.has_method("radio_stop"):
			music.radio_stop()
	elif _owned:
		if music != null and music.has_method("radio_play"):
			music.radio_play(_station_id)
	elif music != null and music.has_method("bordmusik_play"):
		# Kauf-Gate (H §6.1): ohne Radio-Besitz nur die Bordmusik-Schleife.
		music.bordmusik_play()
	# KAUF-GATE HART: `owned` wird hier bewusst NICHT geschrieben.
	_schreibe_radio({"playing": not playing, "station": _station_id})
	_refresh()


func _on_naechster() -> void:
	if not RadioLogic.aktion_erlaubt(_owned, "skip"):
		return
	if not _spielt():
		return
	# F15: Klang erst NACH den Gates — ein wirkungsloser Druck bleibt stumm.
	AudioDirector.try_play(self, "ui_click")
	if music != null and music.has_method("radio_next"):
		music.radio_next()
	_refresh()


func _on_sender_gewaehlt(id: String) -> void:
	if not RadioLogic.aktion_erlaubt(_owned, "sender"):
		return
	AudioDirector.try_play(self, "ui_chip")
	_station_id = id
	if _spielt() and music != null and music.has_method("radio_play"):
		music.radio_play(id)
	_schreibe_radio({"station": id})
	_baue_ui()


func _on_like_aktueller() -> void:
	if not RadioLogic.aktion_erlaubt(_owned, "like"):
		# F15: „nur mit Radio“-Ablehnung klingt als Fehler.
		AudioDirector.try_play(self, "ui_error")
		return
	var track_id := _aktueller_track()
	if track_id.is_empty():
		return
	AudioDirector.try_play(self, "ui_confirm")
	_toggle_like(track_id)


func _toggle_like(track_id: String) -> void:
	if gs == null:
		return
	# Box statt lokaler Variable: Lambdas fangen Primitive per WERT.
	var box := {"neu": false}
	gs.update(func(state: Dictionary) -> void: box["neu"] = RadioLogic.toggle_like(state, track_id))
	gs.notify_slice_changed("radio")
	_zeige_toast(
		I18nService.t("radio.gemerkt" if bool(box["neu"]) else "radio.gefaellt_nicht_mehr")
	)
	_refresh()


func _on_lautstaerke(wert: float) -> void:
	var app := get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("set_setting"):
		app.set_setting("audio.music", wert)


## ---------------------------------------------------------------- Anzeige


func _refresh() -> void:
	var playing := _spielt()
	if _an_aus_btn != null:
		_an_aus_btn.text = I18nService.t("radio.aus" if playing else "radio.an")
	var track_id := _aktueller_track()
	if _ticker != null:
		if playing and not track_id.is_empty():
			var entry := MusicRegistry.entry(track_id)
			_ticker.set_now(str(entry.get("title", track_id)), _sender_anzeige_name(_station_id))
		else:
			_ticker.set_leer(I18nService.t("radio.kein_titel"))
	if _like_btn != null:
		var likes := RadioLogic.likes_von(_state())
		_like_btn.disabled = not _owned or track_id.is_empty() or not playing
		_like_btn.text = I18nService.t("radio.gefaellt")
		_like_btn.button_pressed = likes.has(track_id)
	if _lieblinge_label != null:
		_lieblinge_label.text = (
			"%s: %d" % [I18nService.t("radio.lieblinge"), RadioLogic.like_anzahl(_state())]
		)
	_refresh_titel_liste()


func _refresh_titel_liste() -> void:
	if _liste_box == null:
		return
	for kind in _liste_box.get_children():
		_liste_box.remove_child(kind)
		kind.queue_free()
	var level := _level()
	var likes := RadioLogic.likes_von(_state())
	var zaehler := RadioLogic.frei_zaehler(_station_id, level)
	if _frei_label != null:
		_frei_label.text = I18nService.t(
			"radio.freigeschaltet", {"n": int(zaehler["frei"]), "gesamt": int(zaehler["gesamt"])}
		)
	var m := ScreenShell.metrics(get_viewport())
	for row: Dictionary in RadioLogic.titel(_station_id, level, likes):
		_liste_box.add_child(_titel_zeile(row, m))
	ScreenShell.scale_fonts(_liste_box, UiScale.font_scale(get_viewport()))


func _titel_zeile(row: Dictionary, m: Dictionary) -> Control:
	var floor_px: float = m["floor_px"]
	var zeile := HBoxContainer.new()
	zeile.name = "Titel_%s" % str(row["id"])
	zeile.add_theme_constant_override("separation", 10)
	# Zeilenhöhe ≥ Touch-Floor — die Like-Knöpfe sind sonst physisch winzig.
	zeile.custom_minimum_size = Vector2(0.0, floor_px)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	if bool(row["locked"]):
		label.text = (
			"%s — %s"
			% [
				str(row["title"]),
				I18nService.t("radio.gesperrt_titel", {"level": int(row["unlock_level"])}),
			]
		)
		label.add_theme_color_override("font_color", Color(AcTokens.INK, 0.45))
	else:
		label.text = "%s  %s" % [str(row["title"]), RadioLogic.zeit(float(row["duration_sec"]))]
	zeile.add_child(label)
	if not bool(row["locked"]):
		var like := SquishButton.new()
		like.name = "Like_%s" % str(row["id"])
		like.theme_type_variation = "GhostButton"
		like.text = (
			I18nService.t("radio.liebling_kurz")
			if bool(row["liked"])
			else I18nService.t("radio.merken_kurz")
		)
		like.custom_minimum_size = Vector2(floor_px, floor_px)
		like.focus_mode = Control.FOCUS_NONE
		like.pressed.connect(_on_titel_like.bind(str(row["id"])))
		zeile.add_child(like)
	return zeile


## F15: Listen-Likes sind Mikro-Schritte → ui_tick (Grammatik §3).
func _on_titel_like(track_id: String) -> void:
	AudioDirector.try_play(self, "ui_tick")
	_toggle_like(track_id)


func _on_track_changed(_track_id: String) -> void:
	_refresh()


## ---------------------------------------------------------------- Layout


## Tatsächlich nutzbare Innenbreite des Wirt-Sheets in Canvas-px (FIX1-
## Muster wie reise_app.gd: `PanelSheetLayout.sheet_width − chrome_width`).
## Ohne Wirt-Sheet (Standalone/Tests) wird nur der Body-Rand geschätzt.
func _innen_breite() -> float:
	var vp := get_viewport()
	if vp == null:
		return CitySheetBausteine.BREITE
	var canvas := Vector2(vp.get_visible_rect().size)
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp)
	var breite := PanelSheetLayout.sheet_width(canvas, insets, f)
	var wirt := _wirt_sheet()
	if wirt != null:
		breite -= wirt.chrome_width()
	else:
		breite -= 2.0 * PanelSheet.BODY_MARGIN * f
	return maxf(breite, 0.0)


## Nächstes PanelSheet über uns (RadioGeraet hängt uns in dessen Body).
func _wirt_sheet() -> PanelSheet:
	var knoten := get_parent()
	while knoten != null:
		if knoten is PanelSheet:
			return knoten as PanelSheet
		knoten = knoten.get_parent()
	return null


## ---------------------------------------------------------------- Zustand


func _state() -> Dictionary:
	if gs == null or not gs.has_method("state"):
		return {}
	return gs.state()


func _level() -> int:
	if gs == null:
		return 1
	return int(gs.get_value("progression.level", 1))


func _spielt() -> bool:
	if music != null and music.has_method("is_radio_playing"):
		return bool(music.is_radio_playing())
	if gs != null:
		return bool(gs.get_value("radio.playing", false))
	return false


func _aktueller_track() -> String:
	if music != null and music.has_method("current_track_id"):
		return str(music.current_track_id())
	return ""


func _gelesene_station() -> String:
	if not _owned:
		# Bordmusik-Modus kennt keine Senderwahl.
		return "bordmusik"
	if gs == null:
		return "bordmusik"
	var id := str(gs.get_value("radio.station", "bordmusik"))
	for station: Dictionary in MusicRegistry.stations():
		if str(station.get("id", "")) == id:
			return id
	return "bordmusik"


func _sender_anzeige_name(id: String) -> String:
	for station: Dictionary in MusicRegistry.stations():
		if str(station.get("id", "")) == id:
			return RadioLogic.sender_name(station)
	return id


func _schreibe_radio(patch: Dictionary) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("radio") is Dictionary):
				state["radio"] = {}
			var radio: Dictionary = state["radio"]
			for key: String in patch:
				radio[key] = patch[key]
	)
	gs.notify_slice_changed("radio")


func _zeige_toast(text: String) -> void:
	ToastLayer.zeige(self, text)
