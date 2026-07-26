class_name NotificationService
extends Node
## RW-7 — NotificationService (Autoload „Notify“): baut den NotifyStub zum
## sauberen Dienst aus (Doc §3.4). EHRLICHKEIT zuerst — was passiert wirklich:
##
## - App LÄUFT (Vorder-/Hintergrund im Editor/Desktop): fällige Einträge
##   werden als In-App-Banner zugestellt (dieser Dienst pollt den Stub).
## - App GESCHLOSSEN auf iOS: es kommt HEUTE NICHTS an. Godot hat keine
##   portable Local-Notification-API; dafür braucht es das native Plugin
##   (UNUserNotificationCenter) UND eine signierte App — eine unsignierte
##   App startet auf keinem iPhone (Doc §3.1/§3.8). `_os_schedule()` ist
##   der vorbereitete, dokumentierte Andockpunkt und liefert bewusst false.
## - Deshalb bleibt die Planung idempotent im Stub liegen: sobald das
##   native Backend existiert, übernimmt es dieselben Einträge.
##
## Kategorien/Gates/Ruhezeiten: NotifyRules (pur, getestet). Bestehende
## Direkt-Aufrufer von NotifyStub (rquest_warte, ranch_live_activity,
## random_events) werden bei der ZUSTELLUNG über ihre ID-Präfixe gefiltert —
## kein fremder Code musste angefasst werden.

signal notification_shown(entry: Dictionary)
signal notification_deferred(entry: Dictionary, new_at_ms: int)

const POLL_INTERVAL_S := 1.0
const BANNER_LAYER := 115
const BANNER_SECONDS := 4.0
const BANNER_SECONDS_LANG := 8.0

## Test-Injektion (ersetzt /root/AppSettings) + abschaltbares Banner-UI.
var settings_override: Object = null
var banner_ui_enabled := true

var _accum := 0.0
var _banner_layer: CanvasLayer
var _banner: PanelContainer
var _banner_timer: SceneTreeTimer


func _ready() -> void:
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "NotifyBanner"
	_banner_layer.layer = BANNER_LAYER
	add_child(_banner_layer)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_INTERVAL_S:
		return
	_accum = 0.0
	poll_now(Time.get_unix_time_from_system() * 1000.0)


## Öffentliche Plan-API (Doc §3.4-Interface). category muss eine
## NotifyRules.KATEGORIEN sein; das Gate wird schon beim Planen geprüft
## (aus = gar nicht erst planen), Ruhezeiten erst bei Zustellung.
func schedule(category: String, id: String, title: String, body: String, at_ms: int) -> bool:
	var settings := _settings()
	if settings != null and not settings.notify_allowed(category):
		return false
	NotifyStub.schedule_local(id, title, body, at_ms)
	if _os_schedule(id, title, body, at_ms):
		return true
	return true


func cancel(id: String) -> void:
	NotifyStub.cancel_local(id)


func pending() -> Array:
	return NotifyStub.pending()


## Erlaubnis-Anfrage (Doc: erst nach erklärendem In-Game-Dialog). Ohne
## natives Backend immer sofort „erteilt“ (In-App-Banner brauchen nichts).
func request_permission() -> bool:
	return true


## Fällige Einträge zustellen — von _process gepollt, Tests rufen direkt.
## Gibt die Liste der GEZEIGTEN Einträge zurück.
func poll_now(now_ms: float) -> Array:
	var shown: Array = []
	for entry: Dictionary in NotifyStub.take_due(int(now_ms)):
		var decision := NotifyRules.decide(entry, int(now_ms), _settings())
		match str(decision["action"]):
			"zeigen":
				shown.append(entry)
				_show_entry(entry)
			"verschieben":
				var new_at := int(decision["at_ms"])
				NotifyStub.schedule_local(
					str(entry["id"]), str(entry["title"]), str(entry["body"]), new_at
				)
				notification_deferred.emit(entry, new_at)
			_:
				pass
	return shown


## Direktes In-App-Banner (z. B. Notbremse-Hinweis) — respektiert
## Reduced-Motion und die Hinweis-Anzeigedauer aus den Settings.
func show_banner(title: String, body: String) -> void:
	notification_shown.emit({"id": "", "title": title, "body": body})
	if not banner_ui_enabled or _banner_layer == null:
		return
	_dismiss_banner()
	_banner = _build_banner(title, body)
	_banner_layer.add_child(_banner)
	var seconds := BANNER_SECONDS
	var settings := _settings()
	if settings != null and String(settings.value_of("accessibility.hint_duration")) == "lang":
		seconds = BANNER_SECONDS_LANG
	_banner_timer = get_tree().create_timer(seconds)
	_banner_timer.timeout.connect(_dismiss_banner)


func is_banner_visible() -> bool:
	return _banner != null and is_instance_valid(_banner)


func _show_entry(entry: Dictionary) -> void:
	show_banner(str(entry.get("title", "")), str(entry.get("body", "")))
	notification_shown.emit(entry)


## Andockpunkt fürs native iOS-Plugin (UNUserNotificationCenter). Solange es
## das Plugin/die signierte App nicht gibt: false = nur In-App-Pfad.
func _os_schedule(_id: String, _title: String, _body: String, _at_ms: int) -> bool:
	return false


func _dismiss_banner() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = null


func _build_banner(title: String, body: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "BannerPanel"
	panel.theme_type_variation = "AcCard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := get_viewport()
	var f := UiScale.for_viewport(viewport)
	var tf := UiScale.font_scale(viewport)
	var canvas := Vector2(viewport.get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(viewport)
	var width := minf(520.0 * f, canvas.x - 32.0)
	panel.custom_minimum_size = Vector2(width, 0.0)
	panel.position = Vector2((canvas.x - width) * 0.5, float(insets["top"]) + 10.0 * f)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(2.0 * f))
	var title_label := Label.new()
	title_label.name = "BannerTitle"
	title_label.theme_type_variation = "TitleLabel"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * tf))
	rows.add_child(title_label)
	var body_label := Label.new()
	body_label.name = "BannerBody"
	body_label.theme_type_variation = "SoftLabel"
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * tf))
	rows.add_child(body_label)
	panel.add_child(rows)
	return panel


func _settings() -> Object:
	if settings_override != null:
		return settings_override
	return get_node_or_null("/root/AppSettings")
