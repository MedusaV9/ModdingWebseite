class_name NetStatusIndicator
extends HBoxContainer
## Verbindungsanzeige (FIX-6): kleiner, überall einbaubarer Punkt+Text-Chip
## „Online / Verbinde… / Offline“ (Strings net.status.*, Farben wie der
## Friends-Status-Chip). Verdrahtet sich selbst mit /root/Net (Duck-Typing,
## Signal status_changed) oder per setup(net) — z. B. für Tests/Screenshots.
## Eingebaut in Battleship-Tisch + Besuchs-Szene; weitere Screens (HUD,
## Settings) können ihn einfach instanzieren (Handoff FIX6 an FIX-1).

const COLOR_ONLINE := Color(0.35, 0.75, 0.45)
const COLOR_CONNECTING := Color(0.72, 0.55, 0.2)
const COLOR_OFFLINE := Color(0.7, 0.68, 0.62)
## NetClient.Status-Werte (Duck-Typing, damit auch Fakes funktionieren).
const STATUS_OFFLINE := 0
const STATUS_CONNECTING := 1
const STATUS_ONLINE := 2

var _net: Node = null
var _dot: Label
var _text: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_dot = Label.new()
	_dot.text = "●"
	add_child(_dot)
	_text = Label.new()
	_text.theme_type_variation = &"CaptionLabel"
	add_child(_text)
	if _net == null:
		var candidate := get_node_or_null("/root/Net")
		if candidate != null and candidate.has_signal("status_changed"):
			setup(candidate)
	_refresh()


## Manuelle Verdrahtung (Tests/Screenshots mit Fake-Net).
func setup(net_client: Node) -> void:
	if _net != null and _net.status_changed.is_connected(_on_status_changed):
		_net.status_changed.disconnect(_on_status_changed)
	_net = net_client
	_net.status_changed.connect(_on_status_changed)
	if is_inside_tree():
		_refresh()


func current_status() -> int:
	if _net == null:
		return STATUS_OFFLINE
	var status: Variant = _net.get("status")
	return int(status) if status != null else STATUS_OFFLINE


func _on_status_changed(_status: int) -> void:
	_refresh()


func _refresh() -> void:
	if _dot == null:
		return
	match current_status():
		STATUS_ONLINE:
			_dot.add_theme_color_override("font_color", COLOR_ONLINE)
			_text.text = I18nService.t("net.status.online")
		STATUS_CONNECTING:
			_dot.add_theme_color_override("font_color", COLOR_CONNECTING)
			_text.text = I18nService.t("net.status.connecting")
		_:
			_dot.add_theme_color_override("font_color", COLOR_OFFLINE)
			_text.text = I18nService.t("net.status.offline")
