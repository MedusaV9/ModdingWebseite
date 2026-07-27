class_name Bett
extends Node3D
## Bett-Interactable (REST-3, Rang 5 — Schlafloop-Verkabelung): der EINE Ort,
## an dem der komplette Schlaf-Kreislauf startet. Tap aufs Bett öffnet ein
## kleines Nachtkarten-Panel:
##   Schlafen gehen   — nur wenn Sleep.can_sleep (energy < 70): Zubettgeh-
##                      Ritual (Zähneputzen, brush_teeth-Clip ist da) →
##                      Schlaf startet im Save (Sleep.start_sleep_state) →
##                      sleep_night-Cutscene (existierte, war nie verkabelt).
##   Nickerchen       — Sleep.can_nap (energy < 90): 20-min-Kurzschlaf ohne
##                      grosses Kino (nur Einkuscheln), Reduced-Motion-fair.
##   Geschichte       — delegiert an die vorhandene Geschichten-Stunde
##                      (StoryTime), die vorher direkt am Bett hing.
##   Sanft wecken     — waehrend des Schlafs (nach 5 min, Web §C1.4): frueh
##                      geweckt = Grumpy-Debuff, nie eine Strafe daruber
##                      hinaus.
## Das Aufwachen selbst (Ticker weckt mit Grants) inszeniert der
## PflegeRunner (wake_morning-Cutscene + Overlay) — nicht dieses Panel.

const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")

const RITUAL_PUTZ_S := 2.4

var _host: InteractablesHost
var _furniture: Node3D
var _panel: PanelContainer
var _story: StoryTime
var _rng := RandomNumberGenerator.new()
var _busy := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_furniture = furniture
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	# Geschichten-Stunde als Untermieter (ohne eigene Tap-Zone): das Bett-
	# Menue ruft ihr open_book direkt.
	_story = StoryTime.new()
	_story._host = host
	add_child(_story)


func is_busy() -> bool:
	return _busy


func _on_tapped() -> void:
	if _busy or _room_busy():
		return
	var gs := _host.game_state()
	if gs == null:
		return
	_open_panel()


# ── Nachtkarten-Panel ─────────────────────────────────────────────────────────


func _open_panel() -> void:
	_close_panel()
	AudioDirector.try_play(self, "ui_open")
	var gs := _host.game_state()
	var flat := Sleep.flat_of(gs.state())
	_panel = PanelContainer.new()
	_panel.name = "BettPanel"
	_panel.theme = ThemeService.theme()
	_panel.theme_type_variation = "AcCard"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("sleep.bett.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	if Sleep.is_sleeping(flat):
		_build_wake_entry(box, gs)
	else:
		_build_night_entries(box, flat)
	var schliessen := Button.new()
	schliessen.theme_type_variation = "GhostButton"
	schliessen.text = I18nService.t("sleep.bett.zu")
	schliessen.custom_minimum_size = Vector2(0, 44)
	schliessen.focus_mode = Control.FOCUS_NONE
	schliessen.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_close")
			_close_panel()
	)
	box.add_child(schliessen)
	_ui_layer().add_child(_panel)


func _build_night_entries(box: VBoxContainer, flat: Dictionary) -> void:
	var schlafen := _menu_button(I18nService.t("sleep.bett.schlafen"), "PrimaryButton")
	if Sleep.can_sleep(flat):
		schlafen.pressed.connect(_on_sleep_chosen.bind(false))
	else:
		schlafen.disabled = true
		var hinweis := Label.new()
		hinweis.theme_type_variation = &"CaptionLabel"
		hinweis.text = I18nService.t("sleep.bett.wach")
		hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hinweis.custom_minimum_size = Vector2(260, 0)
		hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hinweis)
	box.add_child(schlafen)
	if Sleep.can_nap(flat):
		var nick := _menu_button(
			I18nService.t("sleep.bett.nickerchen", {"minuten": Sleep.NAP_MIN}), "AccentButton"
		)
		nick.pressed.connect(_on_sleep_chosen.bind(true))
		box.add_child(nick)
	if not StoryTime.stories_from_registry().is_empty():
		var geschichte := _menu_button(I18nService.t("sleep.bett.geschichte"), "AccentButton")
		geschichte.pressed.connect(_on_story_chosen)
		box.add_child(geschichte)
	# Krankem Gooby am Bett Medizin geben (Heilung durch Ruhe+Medizin) —
	# der Eintrag erscheint nur, wenn er auch etwas bewirken kann.
	if Health.grade(_gooby_slice().get("health")) >= 1:
		var medizin := _menu_button(I18nService.t("sleep.bett.medizin"), "AccentButton")
		medizin.pressed.connect(_on_medizin_chosen)
		box.add_child(medizin)


func _build_wake_entry(box: VBoxContainer, gs: Object) -> void:
	var wecken := _menu_button(I18nService.t("sleep.bett.wecken"), "PrimaryButton")
	if Sleep.can_wake_early(Sleep.flat_of(gs.state()), _now_ms()):
		wecken.pressed.connect(_on_wake_chosen)
	else:
		wecken.disabled = true
		var hinweis := Label.new()
		hinweis.theme_type_variation = &"CaptionLabel"
		hinweis.text = I18nService.t("sleep.bett.wecken_noch_nicht")
		hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hinweis)
	box.add_child(wecken)


func _menu_button(text: String, variation: String) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = variation
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 52)
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


# ── Schlafen / Nickerchen ─────────────────────────────────────────────────────


func _on_sleep_chosen(nap: bool) -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	start_sleep_flow(nap)


## Kompletter Einschlaf-Ablauf (Tests/Screenshots rufen direkt): Ritual →
## Save-Schlaf → Kino. Awaitbar.
func start_sleep_flow(nap: bool) -> void:
	if _busy:
		return
	_busy = true
	var gs := _host.game_state()
	var gooby := _gooby()
	if not nap:
		await _ritual_zaehne(gooby)
	else:
		_say(I18nService.t("sleep.nap.los"))
	var ok := {"ok": false}
	var now := _now_ms()
	gs.update(func(state: Dictionary) -> void: ok["ok"] = Sleep.start_sleep_state(state, now, nap))
	if not bool(ok["ok"]):
		_say(I18nService.t("sleep.bett.wach"))
		_busy = false
		return
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.0, 0.0, 0.6), 5.0)
		if gooby.get("rig") != null:
			gooby.rig.set_emotion("sleepy")
	if not nap and not _reduced_motion():
		await _spiele_cutscene("sleep_night")
	if gooby != null:
		gooby.play_clip("sleep")
	_say(
		I18nService.t(
			"sleep.gute_nacht", {"gooby": str(gs.get_value("meta.goobyNickname", "Gooby"))}
		)
	)
	_busy = false


## Zubettgeh-Ritual: Zähneputzen (der brush_teeth-Clip ist schon im Rig).
## Reduced Motion: Ton + Zeile bleiben, der Clip-Aufenthalt ist stark verkürzt.
func _ritual_zaehne(gooby: Node) -> void:
	_say(I18nService.t("sleep.ritual.zaehne"))
	if gooby == null:
		return
	gooby.set_wander_enabled(false)
	await gooby.walk_to(global_position + Vector3(0.7, 0.0, 0.8), 4.0)
	gooby.play_clip("brush_teeth")
	AudioDirector.try_play(self, "care_buersten")
	if is_inside_tree():
		var dauer := 0.5 if _reduced_motion() else RITUAL_PUTZ_S
		await get_tree().create_timer(dauer).timeout
	gooby.play_clip("idle")
	_say(I18nService.t("sleep.ritual.kuscheln"))


func _spiele_cutscene(id: String) -> void:
	var room := _host.room()
	if room == null or not is_inside_tree():
		return
	var player := CutscenePlayer.play_in_room(room, _host.game_state(), id)
	if player != null:
		await player.spielen()


# ── Wecken / Geschichte ───────────────────────────────────────────────────────


func _on_wake_chosen() -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	var gs := _host.game_state()
	var events := {"list": []}
	var now := _now_ms()
	gs.update(func(state: Dictionary) -> void: events["list"] = Sleep.wake_early_state(state, now))
	if (events["list"] as Array).has("wokeEarly"):
		var gooby := _gooby()
		if gooby != null:
			gooby.play_clip("idle")
			if gooby.get("rig") != null:
				gooby.rig.set_emotion("angry")
			gooby.set_wander_enabled(true)
		_say(I18nService.t("sleep.frueh_geweckt"))


func _on_story_chosen() -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	var stories := StoryTime.stories_from_registry()
	if stories.is_empty() or _story == null:
		return
	_story.open_book(stories[_rng.randi_range(0, stories.size() - 1)])


## Medizin geben (Web useMedicine): sick → queasy, queasy → healthy. Ohne
## Medizin im Inventar gibt es nur den freundlichen GOOBYTHEKE-Hinweis.
func _on_medizin_chosen() -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	var gs := _host.game_state()
	var res := {"r": {}}
	var now := _now_ms()
	gs.update(func(state: Dictionary) -> void: res["r"] = Health.use_medicine_state(state, now))
	var r: Dictionary = res["r"]
	if bool(r.get("ok", false)):
		AudioDirector.try_play(self, "care_erfolg")
		_say(I18nService.t("health.medizin_ok"))
	elif str(r.get("reason", "")) == "none":
		_say(I18nService.t("health.medizin_keine"))
	else:
		_say(I18nService.t("health.medizin_gesund"))


# ── Helfer ────────────────────────────────────────────────────────────────────


func _now_ms() -> int:
	var gs := _host.game_state()
	if gs != null and gs.get("clock") != null:
		return gs.clock.now_ms()
	return int(Time.get_unix_time_from_system() * 1000.0)


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _gooby_slice() -> Dictionary:
	var gs := _host.game_state()
	if gs == null or not gs.has_method("state"):
		return {}
	var raw: Variant = (gs.state() as Dictionary).get("gooby")
	return raw if raw is Dictionary else {}


func _say(text: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(text)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer
