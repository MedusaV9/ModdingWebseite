class_name SettingsUpdateGlue
extends Node
## Glue zwischen W1c-SettingsScreen („Suche nach Updates“-Knopf) und dem
## W2b-UpdateService — bewusst als eigene Datei in scripts/updates/, damit
## W1c-Dateien unangetastet bleiben (Plan §3.1).
##
## W1c-Kontrakt (W1c-uikit.md): settings_screen.gd feuert `update_check_requested`
## und ruft — falls vorhanden — `/root/UpdateManager.check_for_updates()` selbst.
## Diese Glue übernimmt den Rest: Ergebnis → deutscher Toast (updates.*-Strings)
## über den ToastLayer des Screens.
##
## Verwendung (wer den Settings-Screen instanziert, hängt die Glue daneben):
##   var glue := SettingsUpdateGlue.new()
##   add_child(glue)
##   glue.attach(settings_screen)          # Service = /root/UpdateManager
##   glue.attach(settings_screen, service) # oder explizit injiziert (Tests)

## Optionaler Toast-Sink für Tests: Callable(text: String). Ungültig → ToastLayer.
var toast_sink := Callable()

var _screen: Node
var _service: Node


## Verbindet Screen-Signal und Service-Ergebnis. `service` == null →
## /root/UpdateManager (Autoload-Request, s. project-godot-requests.md).
func attach(screen: Node, service: Node = null) -> void:
	_screen = screen
	_service = service if service != null else get_node_or_null("/root/UpdateManager")
	if screen.has_signal("update_check_requested"):
		screen.update_check_requested.connect(_on_update_check_requested)
	if _service != null and _service.has_signal("check_completed"):
		_service.check_completed.connect(_on_check_completed)


## Ergebnis → updates.*-String-Keys (statisch, damit pur testbar).
## UPDATED mit native_update/gated liefert ZWEI Toasts (geladen + IPA-Hinweis).
static func result_text_keys(result: int, details: Dictionary) -> Array[String]:
	var needs_native: bool = (
		bool(details.get("native_update", false)) or not details.get("gated", []).is_empty()
	)
	match result:
		UpdateService.Result.UPDATED:
			var keys: Array[String] = ["updates.update_geladen"]
			if needs_native:
				keys.append("updates.braucht_ipa")
			return keys
		UpdateService.Result.NEEDS_NATIVE:
			return ["updates.braucht_ipa"]
		UpdateService.Result.UP_TO_DATE:
			return ["updates.alles_aktuell"]
		_:
			return ["updates.fehler"]


func _on_update_check_requested() -> void:
	# Existiert das UpdateManager-Autoload, hat der Screen den Check schon selbst
	# angestoßen (W1c-Duck-Typing) — nur den injizierten Fallback selbst treten.
	if get_node_or_null("/root/UpdateManager") != null:
		return
	if _service != null and _service.has_method("check_for_updates"):
		_service.check_for_updates()


func _on_check_completed(result: int, details: Dictionary) -> void:
	for key in result_text_keys(result, details):
		_show_toast(I18nService.t(key))


func _show_toast(text: String) -> void:
	if toast_sink.is_valid():
		toast_sink.call(text)
		return
	var layer := _find_toast_layer()
	if layer != null:
		layer.show_toast(text)
	else:
		push_warning("SettingsUpdateGlue: kein ToastLayer gefunden — %s" % text)


func _find_toast_layer() -> Node:
	if _screen == null or not is_instance_valid(_screen):
		return null
	# W1c-Screen hat einen ToastLayer unter %Toast; Duck-Typing statt fester Pfade.
	var by_unique := _screen.get_node_or_null("%Toast")
	if by_unique != null and by_unique.has_method("show_toast"):
		return by_unique
	return _find_node_with_method(_screen, "show_toast")


func _find_node_with_method(root: Node, method: String) -> Node:
	for child in root.get_children():
		if child.has_method(method):
			return child
		var found := _find_node_with_method(child, method)
		if found != null:
			return found
	return null
