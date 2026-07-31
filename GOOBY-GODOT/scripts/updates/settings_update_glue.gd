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
##
## W13C „Jetzt neu laden“ (Doc B §2.4): meldet der Service ein installiertes
## PCK-Update (UPDATED mit mindestens einem Nicht-config-Pack), bietet die
## Glue ZUSÄTZLICH zum „beim nächsten Start“-Toast einen Knopf in der
## Updates-Sektion an. Knopf nur, wenn kein Minigame/Besuch aktiv ist
## (SoftRestart.blocked_reason); Bestätigungs-Dialog davor; der Lauf selbst
## prüft das Gate nochmal (Race Dialog↔Besuch). Ein reines config-Update
## wirkt sofort und bekommt bewusst KEINEN Knopf (docs/UPDATES.md §5.5).

const RESTART_BUTTON_NAME := "SoftRestartButton"
const RESTART_DIALOG_NAME := "SoftRestartConfirm"
## Verweigerungs-Grund (SoftRestart.blocked_reason) → updates.*-Toast-Key.
const RESTART_BLOCKED_KEYS := {
	"besuch": "updates.neu_laden_besuch",
	"brettspiel": "updates.neu_laden_brettspiel",
	"minigame": "updates.neu_laden_minigame",
	"reise": "updates.neu_laden_reise",
}

## Optionaler Toast-Sink für Tests: Callable(text: String). Ungültig → ToastLayer.
var toast_sink := Callable()
## DI für Tests: SoftRestart mit Fake-Diensten/-Gates. null → Lazy-Default.
var soft_restart: SoftRestart

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
## W15/UPDREPO: ERROR mit details.token_required (privates Update-Repo ohne
## Zugangsschlüssel angefragt) bekommt den klaren Token-Hinweis statt des
## generischen „gerade nicht erreichbar“.
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
			if bool(details.get("token_required", false)):
				return ["updates.token_fehlt"]
			return ["updates.fehler"]


func _on_update_check_requested() -> void:
	# Existiert das UpdateManager-Autoload, hat der Screen den Check schon selbst
	# angestoßen (W1c-Duck-Typing) — nur den injizierten Fallback selbst treten.
	if get_node_or_null("/root/UpdateManager") != null:
		return
	if _service != null and _service.has_method("check_for_updates"):
		_service.check_for_updates()


## true = mindestens ein installiertes Pack braucht den Neustart (PCK).
## Reine config-Updates wirken sofort (Registry-Overlay) — kein Knopf.
static func needs_soft_restart(details: Dictionary) -> bool:
	for entry: Dictionary in details.get("updated", []):
		if str(entry.get("id", "")) != "config":
			return true
	return false


func _on_check_completed(result: int, details: Dictionary) -> void:
	for key in result_text_keys(result, details):
		_show_toast(I18nService.t(key))
	if result == UpdateService.Result.UPDATED and needs_soft_restart(details):
		_offer_restart_button()


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


## --------------------------- W13C „Jetzt neu laden“ (Soft-Restart, B §2.4)


## Knopf in die Updates-Sektion hängen — nur wenn das Gate frei ist und er
## nicht schon existiert. (Der Screen baut seine Rows bei Resize/_rebuild neu;
## dann verschwindet der Knopf mit — der nächste Update-Check bietet ihn
## erneut an. Bewusst keine Rebuild-Verdrahtung in fremde W1c-Interna.)
func _offer_restart_button() -> void:
	if _screen == null or not is_instance_valid(_screen):
		return
	if _restart_blocked_reason() != "":
		return
	var rows := _updates_rows()
	if rows == null:
		push_warning("SettingsUpdateGlue: Updates-Sektion fehlt — kein Neu-laden-Knopf.")
		return
	if rows.get_node_or_null(RESTART_BUTTON_NAME) != null:
		return
	var btn := SquishButton.new()
	btn.name = RESTART_BUTTON_NAME
	btn.theme_type_variation = "BtnYellow"
	btn.text = I18nService.t("updates.jetzt_neu_laden")
	btn.custom_minimum_size = Vector2(0, 52.0 * _screen_scale())
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_restart_pressed)
	rows.add_child(btn)


func _on_restart_pressed() -> void:
	var reason := _restart_blocked_reason()
	if reason != "":
		_show_toast(I18nService.t(RESTART_BLOCKED_KEYS.get(reason, "updates.fehler")))
		return
	_open_restart_dialog()


## Bestätigungs-Dialog (Reduced-Surprise: „Dauert nur einen Hoppler!“) —
## Scrim + AcCard, „Später“ schließt, „Los geht’s!“ startet den Lauf.
func _open_restart_dialog() -> void:
	if _screen == null or not is_instance_valid(_screen):
		return
	if _screen.get_node_or_null(RESTART_DIALOG_NAME) != null:
		return
	_screen.add_child(_build_restart_dialog())


func _start_soft_restart() -> void:
	var restart := _ensure_soft_restart()
	var report: Dictionary = await restart.run()
	if not bool(report.get("ok", false)):
		var reason := str(report.get("refused", ""))
		_show_toast(I18nService.t(RESTART_BLOCKED_KEYS.get(reason, "updates.fehler")))


func _restart_blocked_reason() -> String:
	return _ensure_soft_restart().blocked_reason()


func _ensure_soft_restart() -> SoftRestart:
	if soft_restart == null or not is_instance_valid(soft_restart):
		soft_restart = SoftRestart.new()
		soft_restart.name = "SoftRestart"
		add_child(soft_restart)
	return soft_restart


## Rows-Container der Updates-Sektion des W1c-Screens (Duck-Typing über
## Node-Namen — SectionUpdates/Rows, s. settings_screen._add_section).
func _updates_rows() -> VBoxContainer:
	var section := _screen.find_child("SectionUpdates", true, false)
	if section == null:
		return null
	return section.find_child("Rows", true, false) as VBoxContainer


func _build_restart_dialog() -> Control:
	var f := _screen_scale()
	var dialog := Control.new()
	dialog.name = RESTART_DIALOG_NAME
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.11, 0.09, 0.08, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				dialog.queue_free()
	)
	dialog.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = "AcCard"
	card.custom_minimum_size = Vector2(420.0 * f, 0.0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", int(12.0 * f))
	card.add_child(rows)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "TitleLabel"
	title.text = I18nService.t("updates.neu_laden_titel")
	rows.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.text = I18nService.t("updates.neu_laden_text")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", int(12.0 * f))
	rows.add_child(buttons)
	var cancel := SquishButton.new()
	cancel.name = "CancelButton"
	cancel.theme_type_variation = "GhostButton"
	cancel.text = I18nService.t("updates.neu_laden_spaeter")
	cancel.custom_minimum_size = Vector2(140.0 * f, 52.0 * f)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: dialog.queue_free())
	buttons.add_child(cancel)
	var confirm := SquishButton.new()
	confirm.name = "ConfirmButton"
	confirm.theme_type_variation = "BtnTeal"
	confirm.text = I18nService.t("updates.neu_laden_los")
	confirm.custom_minimum_size = Vector2(140.0 * f, 52.0 * f)
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(
		func() -> void:
			dialog.queue_free()
			_start_soft_restart()
	)
	buttons.add_child(confirm)
	return dialog


func _screen_scale() -> float:
	if _screen is Control and (_screen as Control).is_inside_tree():
		return UiScale.for_viewport((_screen as Control).get_viewport())
	return 1.0
