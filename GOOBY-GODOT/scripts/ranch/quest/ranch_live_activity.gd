class_name RanchLiveActivity
extends RefCounted
## Live-Activity-Schnittstelle für Warte-Quests (RW-3, User-Wunsch C4):
## „Quests mit realer Wartezeit … als Live Activity auf dem iPhone“.
##
## EHRLICHE EINORDNUNG — was hier (noch) NICHT geht:
## Echte iOS Live Activities (Sperrbildschirm/Dynamic Island) brauchen
## ActivityKit, und das gibt es NUR über ein natives Plattform-Plugin in
## einer SIGNIERTEN App mit dem `com.apple.developer.ActivityKit`-
## Push-/Widget-Extension-Setup (Backlog C §8; Widget-Extension muss in
## Xcode mitgebaut werden). Aus GDScript heraus ist das prinzipbedingt
## unmöglich — dieses Skript ist deshalb die SAUBER GEKAPSELTE Godot-Seite:
##  - Das Spiel redet AUSSCHLIESSLICH mit dieser Klasse (nie direkt mit
##    einem Plugin) — start/update/beende + aktive() fürs In-App-HUD.
##  - Liegt später ein natives Plugin als Autoload `LiveActivityBridge`
##    mit denselben Methodennamen vor, wird es automatisch benutzt.
##  - Bis dahin degradiert jede Activity zu einer lokalen Notification
##    über den NotifyStub (In-App-Bubble; das echte lokale Push-Backend
##    merged W3a auf dasselbe Namensschema).
## Zustand ist prozessweit (static) — die Warte-Quests selbst liegen
## persistent im Save, die Activity ist reine Anzeige und darf flüchtig sein.

const BRIDGE_PFAD := "/root/LiveActivityBridge"

## Aktive Activities: id → {id, titel, text, endetAt}.
static var _aktive: Dictionary = {}


## Activity starten (id-idempotent). `endet_at_ms` = erwartetes Ende —
## daraus baut der Sperrbildschirm später den Fortschrittsbalken.
static func start(id: String, titel: String, text: String, endet_at_ms: int) -> void:
	_aktive[id] = {"id": id, "titel": titel, "text": text, "endetAt": endet_at_ms}
	var bridge := _bridge()
	if bridge != null and bridge.has_method("start"):
		bridge.start(id, titel, text, endet_at_ms)
		return
	NotifyStub.schedule_local("liveact_%s" % id, titel, text, endet_at_ms)


## Text/Restzeit einer laufenden Activity aktualisieren (No-op wenn fremd).
static func update(id: String, text: String, endet_at_ms: int) -> void:
	if not _aktive.has(id):
		return
	_aktive[id]["text"] = text
	_aktive[id]["endetAt"] = endet_at_ms
	var bridge := _bridge()
	if bridge != null and bridge.has_method("update"):
		bridge.update(id, text, endet_at_ms)
		return
	NotifyStub.schedule_local("liveact_%s" % id, str(_aktive[id]["titel"]), text, endet_at_ms)


## Activity beenden (Quest fertig/abgebrochen).
static func beende(id: String) -> void:
	_aktive.erase(id)
	var bridge := _bridge()
	if bridge != null and bridge.has_method("beende"):
		bridge.beende(id)
		return
	NotifyStub.cancel_local("liveact_%s" % id)


## Laufende Activities (fürs In-App-HUD; sortiert nach Ende).
static func aktive() -> Array:
	var out := _aktive.values()
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["endetAt"]) < int(b["endetAt"])
	)
	return out


## Nur für Tests.
static func reset_for_tests() -> void:
	_aktive = {}


static func _bridge() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(BRIDGE_PFAD)
	return null
