class_name RanchRouten
extends RefCounted
## Routen-Anmeldung der Gooby Ranch (RANCH-1). Der SceneRouter erlaubt
## register_route von überall — die Ranch registriert ihre Ziele deshalb
## SELBST (idempotent), bevor sie hinreist: kein Eingriff in den Boot-
## Orchestrator nötig (Muster: W2/W3-Agents melden Routen an, W1a-Handoff).

const ROUTE_FAHRT := &"ranch/fahrt"
const ROUTE_HOF := &"ranch/hof"
const SZENE_FAHRT := "res://scenes/ranch/ranch_fahrt.tscn"
const SZENE_HOF := "res://scenes/ranch/ranch_hof.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter) —
## sonst würde jeder Knopfdruck im Runner eine ECHTE Reise starten.
static var router_override: Object = null


## Beide Ranch-Routen registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_FAHRT, SZENE_FAHRT)
	router.register_route(ROUTE_HOF, SZENE_HOF)


## Zur Überlandfahrt reisen (registriert vorher die Routen).
static func fahre_zur_ranch(baum: SceneTree, params: Dictionary = {}) -> bool:
	return _gehe(baum, ROUTE_FAHRT, params)


## Direkt auf den Hof reisen (nach dem Kauf).
static func fahre_zum_hof(baum: SceneTree, params: Dictionary = {}) -> bool:
	return _gehe(baum, ROUTE_HOF, params)


static func _gehe(baum: SceneTree, ziel: StringName, params: Dictionary) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(ziel, params)
	return true
