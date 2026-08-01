class_name Bett
extends Node3D
## Bett-Interactable (REST-3, Rang 5 — Schlafloop-Verkabelung): der EINE Ort,
## an dem der komplette Schlaf-Kreislauf startet. Tap aufs Bett öffnet ein
## kleines Nachtkarten-Panel:
##   Schlafen gehen   — nur wenn Sleep.can_sleep (energy < 70): Zubettgeh-
##                      Ritual (Zähneputzen, brush_teeth-Clip ist da) →
##                      Bett-Pose + Clip → Save-Schlaf →
##                      sleep_night-Cutscene (existierte, war nie verkabelt).
##   Nickerchen       — Sleep.can_nap (energy < 90): 20-min-Kurzschlaf ohne
##                      grosses Kino (nur Einkuscheln), Reduced-Motion-fair.
##   Geschichte       — delegiert an die vorhandene Geschichten-Stunde
##                      (StoryTime), die vorher direkt am Bett hing.
##   Sanft wecken     — waehrend des Schlafs (sofort kuendbar): frueh
##                      geweckt = Grumpy-Debuff, nie eine Strafe daruber
##                      hinaus.
## Das Aufwachen selbst (Ticker weckt mit Grants) inszeniert der
## PflegeRunner (wake_morning-Cutscene + Overlay) — nicht dieses Panel.

const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")

const RITUAL_PUTZ_S := 2.4

var _host: InteractablesHost
var _furniture: Node3D
var _panel: Control
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


## G4/P23 — Nachtkarte als PanelStack-Overlay (Muster daily_bonus_popup)
## statt frei schwebendem Eigenbau: Veil dunkelt den Raum ab (Taps daneben
## gehen nicht mehr ins 3D durch), Android-Back/Escape (SceneRouter →
## PanelStack.close_top) und Backdrop-Tap schließen, Karte + Knöpfe laufen
## über ScreenShell-Metriken (Safe-Area, Touch-Floor, Rotation).
func _open_panel() -> void:
	_close_panel()
	AudioDirector.try_play(self, "ui_open")
	var gs := _host.game_state()
	var flat := Sleep.flat_of(gs.state())
	var overlay := BettOverlay.new()
	overlay.weg_gewuenscht.connect(_on_panel_dismissed)
	var karte := PanelContainer.new()
	karte.name = "BettKarte"
	karte.theme_type_variation = "AcCard"
	overlay.add_child(karte)
	overlay.karte = karte
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	karte.add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("sleep.bett.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	if Sleep.is_sleeping(flat):
		_build_wake_entry(box, gs)
	else:
		_build_night_entries(box, flat)
	var schliessen := _menu_button(I18nService.t("sleep.bett.zu"), "GhostButton")
	schliessen.pressed.connect(_on_panel_dismissed)
	box.add_child(schliessen)
	_panel = overlay
	_ui_layer().add_child(overlay)


## Schließen über Knopf, Backdrop-Tap oder Back-Geste — EIN Pfad.
func _on_panel_dismissed() -> void:
	AudioDirector.try_play(self, "ui_close")
	_close_panel()


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
		hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hinweis)
	box.add_child(schlafen)
	if Sleep.can_nap(flat):
		var nick := _menu_button(
			I18nService.t("sleep.bett.nickerchen", {"minuten": Sleep.NAP_MIN}), "AccentButton"
		)
		nick.pressed.connect(_on_sleep_chosen.bind(true))
		box.add_child(nick)
	if StoryTime.story_option_available():
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
	var flat := Sleep.flat_of(gs.state())
	var now := _now_ms()
	var can := Sleep.can_wake_early(flat, now)
	if can:
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
	# G4/P23: SquishButton statt nacktem Button (Audio-Grammatik — Squish +
	# Tap-Haptik zentral); der physische Touch-Floor kommt vom Overlay.
	var btn := SquishButton.new()
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
## walk_to Bett → lie_on_bed → sleep-Clip → Save-Schlaf → Kino. Awaitbar.
## Save-State erst NACH der Pose, damit PflegeRunner den Walk nicht killt.
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
	var bed_node: Node3D = _furniture if _furniture != null else self
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(bed_node.global_position + Vector3(0.0, 0.0, 0.6), 5.0)
		if gooby.has_method("lie_on_bed"):
			gooby.lie_on_bed(bed_node)
		if gooby.get("rig") != null:
			gooby.rig.set_emotion("sleepy")
		gooby.play_clip("sleep")
	var ok := {"ok": false}
	var now := _now_ms()
	gs.update(func(state: Dictionary) -> void: ok["ok"] = Sleep.start_sleep_state(state, now, nap))
	if not bool(ok["ok"]):
		_say(I18nService.t("sleep.bett.wach"))
		if gooby != null:
			gooby.play_clip("idle")
			gooby.set_wander_enabled(true)
		_busy = false
		return
	if not nap and not _reduced_motion():
		await _spiele_cutscene("sleep_night")
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
	if _story == null:
		return
	# W13B: mit Bücher-Katalog öffnet sich Goobys Bücherregal (Abnutzung,
	# REHWEI-Nachschub); ohne Pack bleibt der Legacy-Zufallspfad erhalten.
	if not StoryBooks.books_from_registry().is_empty():
		_story.open_library()
		return
	var stories := StoryTime.stories_from_registry()
	if stories.is_empty():
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


class BettOverlay:
	extends Control
	## G4/P23 — Vollbild-Schleier + zentrierte Nachtkarte nach dem
	## daily_bonus_popup-Muster: PanelStack-Anmeldung (Back/Escape schließt
	## über close()), Backdrop-Tap nur als oberstes Panel, ScreenShell-
	## Metriken (Kartenbreite, Touch-Floor, Schrift-Skalierung) und
	## Relayout bei Rotation. Das Bett baut den KARTEN-Inhalt, das Overlay
	## besitzt nur Geometrie + Dismiss-Pfade.

	signal weg_gewuenscht

	const CARD_BASE_WIDTH := 420.0

	var karte: PanelContainer

	func _init() -> void:
		name = "BettPanel"
		theme = ThemeService.theme()
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var veil := ColorRect.new()
		veil.name = "Veil"
		veil.color = AcTokens.VEIL
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		veil.gui_input.connect(_on_veil_input)
		add_child(veil)

	func _ready() -> void:
		PanelStack.push(self)
		_relayout()
		get_viewport().size_changed.connect(_relayout)

	func _exit_tree() -> void:
		PanelStack.remove(self)

	## Escape/Back-Pfad (SceneRouter → PanelStack.close_top).
	func close() -> void:
		weg_gewuenscht.emit()

	func _relayout() -> void:
		if karte == null or not is_inside_tree():
			return
		var m := ScreenShell.metrics(get_viewport())
		var f: float = m["f"]
		ScreenShell.scale_fonts(self, f)
		for btn: Node in find_children("*", "Button", true, false):
			ScreenShell.touch_target(btn as Control, m)
		var width := ScreenShell.card_width(m, CARD_BASE_WIDTH)
		karte.custom_minimum_size = Vector2(width, 0.0)
		var wanted := karte.get_combined_minimum_size()
		var height := minf(wanted.y, ScreenShell.card_max_height(m))
		var insets: Dictionary = m["insets"]
		var canvas: Vector2 = m["canvas"]
		var safe := Rect2(
			Vector2(float(insets["left"]), float(insets["top"])),
			Vector2(
				canvas.x - float(insets["left"]) - float(insets["right"]),
				canvas.y - float(insets["top"]) - float(insets["bottom"])
			)
		)
		var pos := safe.position + (safe.size - Vector2(width, height)) / 2.0
		karte.set_anchors_preset(Control.PRESET_TOP_LEFT)
		karte.offset_left = pos.x
		karte.offset_top = pos.y
		karte.offset_right = pos.x + width
		karte.offset_bottom = pos.y + height

	## Backdrop-Dismiss-Policy (Web): Tap auf den Schleier schließt, aber
	## nur als oberstes Panel.
	func _on_veil_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton or event is InputEventScreenTouch):
			return
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			return
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			return
		if PanelStack.is_top(self):
			weg_gewuenscht.emit()
