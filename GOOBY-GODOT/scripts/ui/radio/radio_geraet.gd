class_name RadioGeraet
extends Node3D
## Radio-Interactable (REST-4, EVAL Rang 10): dockt per InteractablesHost an
## Radio-Möbel (`radio`, `radioRetro`, `speaker`) und öffnet auf Tap die
## RadioSheet-Bedienoberfläche (Senderwahl, Titel, Lautstärke, Likes).
## Web-Vorbild: radioScreen.js wireFurnitureTap ('tap:radio' → radioPanel).
##
## Läuft das Radio beim Öffnen bereits, freut sich Gooby sichtbar (kleiner
## Hop — Web: happyBounce).
##
## W13/RADIO: hängt zusätzlich den „Was läuft?"-Mini-Chip (NowPlayingChip)
## in die Raum-UI-Ebene — der blendet kurz ein, wenn im Haus ein neuer
## Radio-/Bordmusik-Track startet (bewusst hier statt im HUD, Ownership).

var _host: InteractablesHost
var _panel: PanelContainer


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	if is_inside_tree():
		NowPlayingChip.install_floating(_ui_layer(), MusicDirector.get_or_create(self))


func _on_tapped() -> void:
	if _room_busy():
		return
	var gs := _host.game_state()
	if gs == null:
		return
	AudioDirector.try_play(self, "ui_open")
	_open_panel(gs)
	if bool(gs.get_value("radio.playing", false)):
		var gooby := _gooby()
		if gooby != null and gooby.has_method("play_clip"):
			gooby.play_clip("hop")


func _open_panel(gs: Object) -> void:
	_close_panel()
	_panel = PanelContainer.new()
	_panel.name = "RadioPanel"
	_panel.theme = ThemeService.theme()
	_panel.theme_type_variation = "AcCard"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Höhen-Deckel + Scroll: das Sheet ist inhaltsreich und darf auf kleinen
	# Screens nicht über den Rand wachsen (Kuehlschrank-Muster).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	var hoehe := 640.0
	if is_inside_tree() and get_viewport() != null:
		hoehe = minf(hoehe, get_viewport().get_visible_rect().size.y - 80.0)
	scroll.custom_minimum_size = Vector2(560.0, maxf(320.0, hoehe))
	_panel.add_child(scroll)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.geschlossen.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_close")
			_close_panel()
	)
	scroll.add_child(sheet)
	_ui_layer().add_child(_panel)


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


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
