class_name SoftRestart
extends Node
## W13C/RELEASE — „Jetzt neu laden“-Soft-Restart nach installiertem Update
## (Doc B §2.4; docs/UPDATES.md §5.5). Bewusst als eigene, pur testbare
## Statemaschine: alle Dienste UND die Zeit sind injizierbar — die Fakes in
## tests/unit/test_w13c_softrestart.gd prüfen die Aufruf-Reihenfolge als
## Protokoll, ohne echte Autoloads/Szenen.
##
## Reihenfolge (FROZEN, docs/UPDATES.md §5.5):
##   Gate → GameState.save_now → Net.disconnect_now → Music.stop_music
##   (+ Fade abwarten) → PackLoader.remount_for_soft_restart →
##   ContentRegistry.reload → SceneRouter.clear_history →
##   Boot-Szene neu laden (reload_current_scene; main.tscn instanziert
##   HomeEntry frisch — Routen/Mount-Point/HUD entstehen neu).
## Ein nacktes reload_current_scene() OHNE Remount+Registry-Reload reicht
## ausdrücklich NICHT — die frischen user://-Packs würden nie greifen.
##
## ENTSCHEIDUNG echter Prozess-Neustart: NEIN. OS.set_restart_on_exit() ist
## Desktop-only (auf iOS nicht implementiert), quit() gilt auf iOS als Crash
## (Apple-HIG) — und die Boot-Guard-Falle wiegt schwerer: ein quit() NACH dem
## Remount (attempts wurde gerade auf >= 1 gezählt) ließe den nächsten echten
## Start als „Versuch 2“ erscheinen und die 2-Crash-Regel (Doc B §2.5) würde
## das frisch installierte Pack fälschlich deaktivieren. Deshalb rein
## in-process; ersetzte Assets bleiben ehrlich „wirksam ab echtem Neustart“.

signal state_changed(state: int)
signal finished(report: Dictionary)

enum State { IDLE, REFUSED, SAVING, DISCONNECTING, FADING, REMOUNTING, REBOOTING, DONE }

## Router-Ziele, bei denen verweigert wird (Minigame läuft bzw. steht
## unmittelbar bevor — Spiegel von ArcadeScreen.ROUTE_PREGAME/ROUTE_HOST).
const BLOCKED_ROUTES: Array[String] = ["mg_host", "mg_pregame"]
## Musik-Fade in Sekunden (Größenordnung MusicDirector.CROSSFADE_S).
const FADE_S := 0.6

## Injizierbare Dienste (Tests: Fakes setzen, BEVOR run() läuft).
## null → Autoload-Lookup unter /root (Duck-Typing, fehlend = Step übersprungen).
var game_state: Object = null
var net: Object = null
var music: Object = null
var pack_loader: Object = null
var registry: Object = null
var router: Object = null
var social: Object = null
## Zeit injizieren (Tests): Callable(seconds) statt SceneTree-Timer.
var wait_fn := Callable()
## Reboot injizieren (Tests): statt get_tree().reload_current_scene().
var reboot_fn := Callable()

var _state: int = State.IDLE
var _running := false
var _protocol: Array[String] = []


## "" = frei; sonst Verweigerungs-Grund: "minigame" / "reise" / "besuch" /
## "brettspiel". Reine Zustandsabfrage — verändert nichts.
func blocked_reason() -> String:
	var the_router := _svc(router, "SceneRouter")
	if the_router != null:
		if the_router.has_method("get_current_target"):
			if str(the_router.get_current_target()) in BLOCKED_ROUTES:
				return "minigame"
		if the_router.has_method("is_busy") and the_router.is_busy():
			return "reise"
	var the_social := _svc(social, "Social")
	if the_social != null:
		if _child_active(the_social, "visit"):
			return "besuch"
		if _child_active(the_social, "board") or _child_active(the_social, "chess"):
			return "brettspiel"
	return ""


## Kompletter Soft-Restart (Coroutine). Report:
## { "ok": bool, "refused": String, "protocol": Array[String] }.
## Gate wird HIER nochmal geprüft (Dialog-Race: Besuch kann zwischen
## Knopf-Angebot und Bestätigung eingetroffen sein).
func run() -> Dictionary:
	if _running:
		return {"ok": false, "refused": "laeuft_bereits", "protocol": []}
	var reason := blocked_reason()
	if reason != "":
		_set_state(State.REFUSED)
		return _finish(false, reason)
	_running = true
	_protocol.clear()
	_set_state(State.SAVING)
	_call_step(game_state, "GameState", "save_now")
	_set_state(State.DISCONNECTING)
	_call_step(net, "Net", "disconnect_now")
	_set_state(State.FADING)
	_call_step(music, "Music", "stop_music", [FADE_S])
	await _wait(FADE_S)
	_set_state(State.REMOUNTING)
	_call_step(pack_loader, "PackLoader", "remount_for_soft_restart")
	_call_step(registry, "ContentRegistry", "reload")
	_set_state(State.REBOOTING)
	_call_step(router, "SceneRouter", "clear_history")
	_reboot()
	_set_state(State.DONE)
	_running = false
	return _finish(true, "")


func get_state() -> int:
	return _state


## Aufruf-Protokoll des letzten Laufs (Kopie — für Tests/Debug).
func call_protocol() -> Array[String]:
	return _protocol.duplicate()


## Dienst-Methode best-effort rufen (fehlender Dienst/Methode = Warnung +
## Protokoll-Eintrag "fehlt:…", KEIN Abbruch — der Neustart selbst heilt).
func _call_step(explicit: Object, autoload_name: String, method: String, args: Array = []) -> void:
	var service := _svc(explicit, autoload_name)
	var label := "%s.%s" % [autoload_name, method]
	if service == null or not service.has_method(method):
		_protocol.append("fehlt:" + label)
		push_warning("SoftRestart: %s nicht verfügbar — Schritt übersprungen." % label)
		return
	_protocol.append(label)
	service.callv(method, args)


func _wait(seconds: float) -> void:
	_protocol.append("wait:%.1f" % seconds)
	if wait_fn.is_valid():
		await wait_fn.call(seconds)
		return
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout


func _reboot() -> void:
	_protocol.append("reboot")
	if reboot_fn.is_valid():
		reboot_fn.call()
		return
	if not is_inside_tree():
		push_warning("SoftRestart: nicht im Tree — Boot-Szene wird nicht neu geladen.")
		return
	var err := get_tree().reload_current_scene()
	if err != OK:
		push_error("SoftRestart: reload_current_scene fehlgeschlagen (Fehler %d)." % err)


func _finish(ok: bool, reason: String) -> Dictionary:
	var report := {"ok": ok, "refused": reason, "protocol": _protocol.duplicate()}
	finished.emit(report)
	return report


func _svc(explicit: Object, autoload_name: String) -> Object:
	if explicit != null and is_instance_valid(explicit):
		return explicit
	if is_inside_tree():
		return get_node_or_null("/root/" + autoload_name)
	return null


## Duck-Typing: holder.<property>.is_active() — fehlt etwas davon → false.
static func _child_active(holder: Object, property: String) -> bool:
	var child: Variant = holder.get(property)
	if child is Object and (child as Object).has_method("is_active"):
		return bool((child as Object).is_active())
	return false


func _set_state(state: int) -> void:
	_state = state
	state_changed.emit(state)
