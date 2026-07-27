class_name RadioSheet
extends VBoxContainer
## Radio-Bedienoberfläche (REST-4, EVAL Rang 10) — Web-Vorbild
## GOOBY/src/ui/radioScreen.js, reduziert auf die Godot-Musik-API:
## Senderwahl (mit Level-Schlössern), Jetzt-läuft-Anzeige, An/Aus,
## Nächster Titel, Musik-Lautstärke (AppSettings `audio.music`),
## "Gefällt mir" (Lieblingssongs, additiv in `radio.likes`) und die
## Titelliste des Senders inkl. Level-Freischaltung.
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
var _jetzt_label: Label
var _sender_label: Label
var _an_aus_btn: Button
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
	_station_id = _gelesene_station()
	_baue_ui()


## ---------------------------------------------------------------- Aufbau


func _baue_ui() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.label(self, I18nService.t("radio.titel"), "HeadlineLabel")

	var jetzt_karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(jetzt_karte, I18nService.t("radio.jetzt"), "CaptionLabel")
	_jetzt_label = CitySheetBausteine.label(jetzt_karte, "", "HeadlineLabel")
	_jetzt_label.name = "JetztTitel"
	_sender_label = CitySheetBausteine.label(jetzt_karte, "", "CaptionLabel")
	_sender_label.name = "JetztSender"

	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 10)
	add_child(transport)
	_an_aus_btn = Button.new()
	_an_aus_btn.name = "AnAus"
	_an_aus_btn.theme_type_variation = "PrimaryButton"
	_an_aus_btn.custom_minimum_size = Vector2(0.0, 48.0)
	_an_aus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_an_aus_btn.focus_mode = Control.FOCUS_NONE
	_an_aus_btn.pressed.connect(_on_an_aus)
	transport.add_child(_an_aus_btn)
	var next_btn := Button.new()
	next_btn.name = "Naechster"
	next_btn.theme_type_variation = "AccentButton"
	next_btn.text = I18nService.t("radio.naechster")
	next_btn.custom_minimum_size = Vector2(0.0, 48.0)
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.pressed.connect(_on_naechster)
	transport.add_child(next_btn)
	_like_btn = Button.new()
	_like_btn.name = "Like"
	_like_btn.theme_type_variation = "AccentButton"
	_like_btn.text = I18nService.t("radio.gefaellt")
	_like_btn.custom_minimum_size = Vector2(0.0, 48.0)
	_like_btn.focus_mode = Control.FOCUS_NONE
	_like_btn.pressed.connect(_on_like_aktueller)
	transport.add_child(_like_btn)

	CitySheetBausteine.label(self, I18nService.t("radio.sender"), "HeadlineLabel")
	var chips := HFlowContainer.new()
	chips.name = "SenderChips"
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	add_child(chips)
	var level := _level()
	for station: Dictionary in RadioLogic.sender(level):
		chips.add_child(_sender_chip(station))

	_baue_lautstaerke()

	_lieblinge_label = CitySheetBausteine.label(self, "", "CaptionLabel")
	_lieblinge_label.name = "Lieblinge"
	CitySheetBausteine.label(self, I18nService.t("radio.titel_liste"), "HeadlineLabel")
	_frei_label = CitySheetBausteine.label(self, "", "CaptionLabel")
	_frei_label.name = "FreiZaehler"
	_liste_box = CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
	_liste_box.name = "TitelListe"
	CitySheetBausteine.label(self, I18nService.t("radio.level_hinweis"), "CaptionLabel")

	var schliessen := Button.new()
	schliessen.name = "Schliessen"
	schliessen.theme_type_variation = "GhostButton"
	schliessen.text = I18nService.t("radio.schliessen")
	schliessen.custom_minimum_size = Vector2(0.0, 44.0)
	schliessen.focus_mode = Control.FOCUS_NONE
	schliessen.pressed.connect(func() -> void: geschlossen.emit())
	add_child(schliessen)

	_refresh()


func _sender_chip(station: Dictionary) -> Button:
	var id := str(station.get("id", ""))
	var chip := Button.new()
	chip.name = "Sender_%s" % id
	chip.toggle_mode = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.theme_type_variation = "AccentButton"
	chip.custom_minimum_size = Vector2(0.0, 44.0)
	var locked := bool(station.get("locked", false))
	if locked:
		chip.text = (
			"%s (%s)"
			% [
				RadioLogic.sender_name(station),
				I18nService.t(
					"radio.gesperrt_sender", {"level": int(station.get("unlock_level", 1))}
				),
			]
		)
		chip.disabled = true
	else:
		chip.text = RadioLogic.sender_name(station)
		chip.pressed.connect(_on_sender_gewaehlt.bind(id))
	chip.button_pressed = id == _station_id
	return chip


func _baue_lautstaerke() -> void:
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
	slider.custom_minimum_size = Vector2(180.0, 32.0)
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
	var playing := _spielt()
	if playing:
		if music != null and music.has_method("radio_stop"):
			music.radio_stop()
	else:
		if music != null and music.has_method("radio_play"):
			music.radio_play(_station_id)
	_schreibe_radio({"playing": not playing, "station": _station_id, "owned": true})
	_refresh()


func _on_naechster() -> void:
	if not _spielt():
		return
	if music != null and music.has_method("radio_next"):
		music.radio_next()
	_refresh()


func _on_sender_gewaehlt(id: String) -> void:
	_station_id = id
	if _spielt() and music != null and music.has_method("radio_play"):
		music.radio_play(id)
	_schreibe_radio({"station": id})
	_baue_ui()


func _on_like_aktueller() -> void:
	var track_id := _aktueller_track()
	if track_id.is_empty():
		return
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
	if _jetzt_label != null:
		if playing and not track_id.is_empty():
			var entry := MusicRegistry.entry(track_id)
			_jetzt_label.text = str(entry.get("title", track_id))
		else:
			_jetzt_label.text = I18nService.t("radio.kein_titel")
	if _sender_label != null:
		_sender_label.text = _sender_anzeige_name(_station_id)
	if _like_btn != null:
		var likes := RadioLogic.likes_von(_state())
		_like_btn.disabled = track_id.is_empty() or not playing
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
	for row: Dictionary in RadioLogic.titel(_station_id, level, likes):
		_liste_box.add_child(_titel_zeile(row))


func _titel_zeile(row: Dictionary) -> Control:
	var zeile := HBoxContainer.new()
	zeile.name = "Titel_%s" % str(row["id"])
	zeile.add_theme_constant_override("separation", 10)
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
		var like := Button.new()
		like.name = "Like_%s" % str(row["id"])
		like.theme_type_variation = "GhostButton"
		like.text = (
			I18nService.t("radio.liebling_kurz")
			if bool(row["liked"])
			else I18nService.t("radio.merken_kurz")
		)
		like.focus_mode = Control.FOCUS_NONE
		like.pressed.connect(_toggle_like.bind(str(row["id"])))
		zeile.add_child(like)
	return zeile


func _on_track_changed(_track_id: String) -> void:
	_refresh()


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
	if not is_inside_tree():
		return
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
