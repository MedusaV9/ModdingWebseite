class_name DevService
extends Node
## RW-7 — DevService (Autoload „Dev“): Zustand des versteckten Entwickler-
## modus (Doc §5). Zuständig für:
## - Aktivieren/Deaktivieren (persistiert in AppSettings dev.enabled;
##   dev.was_active bleibt für immer true, damit der Save-Marker-Slice
##   auch nach dem Abschalten registriert bleibt und nicht wegnormalisiert
##   wird).
## - Das permanente gelb-schwarze DEV-Badge (öffnet das Menü per Tipp).
## - Den redigierten Netzwerk-Log-Ringpuffer (Doc §5.2: Secrets werden
##   schon beim ERFASSEN entfernt, max. 500 Einträge).
##
## In Nicht-Debug-Builds bleibt der Dienst passiv nutzbar (der Einstieg
## über den Settings-Trigger existiert weiter — privater Sideload-Build,
## Doc §5.1 „optionaler Build-Schalter“ ist Export-Sache).

signal dev_mode_changed(enabled: bool)

const BADGE_LAYER := 118
const NET_LOG_MAX := 500
const MENU_SCRIPT := "res://scripts/dev/dev_menu.gd"

var _badge_layer: CanvasLayer
var _badge: Button
var _net_log: Array[Dictionary] = []
var _net_connected := false
var _menu: Control
## W14/NETSET: Uhr-Offset (ms) fürs Dev-Menü — TRANSIENT (nie im Save).
## Solange > 0, re-pinnt _process die öffentliche GameState-Uhr pro Frame
## auf „Systemzeit + Offset“ (DevZeit), damit sie mit Offset WEITERLÄUFT.
var _clock_offset_ms := 0


func _ready() -> void:
	set_process(false)
	var settings := _settings()
	if settings != null and settings.has_method("is_dev_enabled"):
		if bool(settings.get_setting("dev.was_active", false)):
			_register_slice_deferred()
		if settings.is_dev_enabled():
			_activate_ui()


func _process(_delta: float) -> void:
	if _clock_offset_ms <= 0:
		set_process(false)
		return
	DevZeit.apply_offset(_game_clock(), _clock_offset_ms)


func is_enabled() -> bool:
	var settings := _settings()
	return settings != null and settings.is_dev_enabled()


## Entwicklermodus aktivieren (Settings-Screen ruft das NACH der
## Halte-Bestätigung). Save wird dabei NICHT angefasst — erst mutierende
## Menü-Aktionen markieren ihn.
func enable() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_setting("dev.enabled", true)
	settings.set_setting("dev.was_active", true)
	_activate_ui()
	dev_mode_changed.emit(true)


func disable() -> void:
	var settings := _settings()
	if settings != null:
		settings.set_setting("dev.enabled", false)
	set_clock_offset_ms(0)
	close_menu()
	_remove_badge()
	dev_mode_changed.emit(false)


## Dev-Menü als Overlay öffnen (über allem; ein Menü gleichzeitig).
func open_menu() -> void:
	if not is_enabled():
		return
	if _menu != null and is_instance_valid(_menu):
		return
	var script: Variant = load(MENU_SCRIPT)
	if script == null:
		return
	_menu = script.new()
	var layer := CanvasLayer.new()
	layer.name = "DevMenuLayer"
	layer.layer = BADGE_LAYER - 1
	layer.add_child(_menu)
	add_child(layer)
	_menu.tree_exited.connect(func() -> void: layer.queue_free())


func close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func is_menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)


## Redigierter Netzwerk-Log (neueste zuletzt; Kopie).
func net_log() -> Array[Dictionary]:
	return _net_log.duplicate()


## W14/NETSET: Uhr-Offset setzen (ms; 0 = Echtzeit). Wendet den Offset
## SOFORT auf die öffentliche GameState-Uhr an und holt per run_catch_up()
## die „übersprungene“ Zeit nach (Stats/Schlaf/Urlaub ziehen sofort nach).
func set_clock_offset_ms(offset_ms: int) -> void:
	_clock_offset_ms = maxi(0, offset_ms)
	DevZeit.apply_offset(_game_clock(), _clock_offset_ms)
	set_process(_clock_offset_ms > 0)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("run_catch_up") and gs.has_method("is_loaded"):
		if bool(gs.is_loaded()):
			gs.run_catch_up()


func clock_offset_ms() -> int:
	return _clock_offset_ms


func _game_clock() -> Object:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	var clock: Variant = gs.get("clock")
	return clock if clock is Object else null


func _activate_ui() -> void:
	_register_slice_deferred()
	_show_badge()
	_connect_net_log()


## Slice-Registrierung, sobald GameState da ist (Autoload-Reihenfolge egal).
func _register_slice_deferred() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		DevActions.ensure_slice(gs)


func _show_badge() -> void:
	if _badge_layer != null:
		_badge_layer.visible = true
		return
	_badge_layer = CanvasLayer.new()
	_badge_layer.name = "DevBadge"
	_badge_layer.layer = BADGE_LAYER
	_badge = Button.new()
	_badge.name = "DevBadgeButton"
	_badge.text = "DEV"
	_badge.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFD34D")
	style.border_color = Color("#1A1A1A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	_badge.add_theme_stylebox_override("normal", style)
	_badge.add_theme_stylebox_override("hover", style)
	_badge.add_theme_stylebox_override("pressed", style)
	_badge.add_theme_color_override("font_color", Color("#1A1A1A"))
	_badge.add_theme_color_override("font_pressed_color", Color("#1A1A1A"))
	_badge.add_theme_color_override("font_hover_color", Color("#1A1A1A"))
	_badge.pressed.connect(open_menu)
	_badge_layer.add_child(_badge)
	add_child(_badge_layer)
	_position_badge()
	get_viewport().size_changed.connect(_position_badge)


func _position_badge() -> void:
	if _badge == null:
		return
	var viewport := get_viewport()
	var canvas := Vector2(viewport.get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(viewport)
	_badge.reset_size()
	_badge.position = Vector2(
		canvas.x - float(insets["right"]) - _badge.size.x - 12.0, float(insets["top"]) + 8.0
	)


func _remove_badge() -> void:
	if _badge_layer != null:
		_badge_layer.visible = false


func _connect_net_log() -> void:
	if _net_connected:
		return
	var net := get_node_or_null("/root/Net")
	if net == null:
		return
	if net.has_signal("message_received"):
		net.message_received.connect(_on_net_message)
	if net.has_signal("status_changed"):
		net.status_changed.connect(_on_net_status)
	_net_connected = true


func _on_net_message(envelope: Dictionary) -> void:
	_push_log(
		{
			"at": Time.get_ticks_msec(),
			"typ": str(envelope.get("t", "?")),
			"groesse": JSON.stringify(envelope).length(),
			"payload": DevActions.redact(envelope.get("d", {})),
		}
	)


func _on_net_status(status: int) -> void:
	_push_log({"at": Time.get_ticks_msec(), "typ": "STATUS", "groesse": 0, "payload": status})


func _push_log(entry: Dictionary) -> void:
	_net_log.append(entry)
	while _net_log.size() > NET_LOG_MAX:
		_net_log.pop_front()


func _settings() -> Object:
	return get_node_or_null("/root/AppSettings")
