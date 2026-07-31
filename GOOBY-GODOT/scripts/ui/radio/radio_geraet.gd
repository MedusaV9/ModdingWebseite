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

## W14/UISCREENS-B Sheet-Einheitslook: das Radio öffnet im ZENTRALEN
## PanelSheet (Veil-Backdrop, Griff-Leiste, Radius 36, PanelStack-Back-
## Geste) statt in einer Eigenbau-Karte mit fester 560-px-Breite.
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

var _host: InteractablesHost
var _panel: PanelSheet


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
	_panel = SHEET_SCENE.instantiate() as PanelSheet
	_panel.name = "RadioPanel"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_panel.theme = ThemeService.theme()
	_panel.closed.connect(_close_panel)
	_ui_layer().add_child(_panel)
	# RadioSheet bringt seine eigene Kopfzeile mit — die Sheet-Titelzeile
	# bleibt aus, Griff-Leiste + Scroll + Backdrop kommen vom PanelSheet.
	_panel.set_title("")
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.geschlossen.connect(func() -> void: _schliesse_sheet())
	_panel.add_content(sheet)
	_panel.open()


## Schließen-Knopf im RadioSheet: übers PanelSheet zumachen (spielt selbst
## ui_close und räumt den PanelStack auf), dann freigeben.
func _schliesse_sheet() -> void:
	if _panel != null and is_instance_valid(_panel) and _panel.is_open():
		_panel.close()
	else:
		_close_panel()


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
