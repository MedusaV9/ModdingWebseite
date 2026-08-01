class_name GoobyeRouten
extends RefCounted
## Routen-Anmeldung des „Goo und Bye“ (G5/P24) — Muster RanchRouten: der
## SceneRouter erlaubt register_route von überall, der Laden meldet sein
## Ziel deshalb SELBST an (idempotent), bevor er hinreist. Kein Eingriff
## in den Boot-Orchestrator nötig.

const ROUTE_LADEN := &"dlc/goobye_laden"
const SZENE_LADEN := "res://scripts/dlc/goobye/laden_scene.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter) —
## sonst würde jeder Knopfdruck im Runner eine ECHTE Reise starten.
static var router_override: Object = null


## Laden-Route registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_LADEN, SZENE_LADEN)


## In den Laden reisen (registriert vorher die Route).
static func fahre_zum_laden(baum: SceneTree, params: Dictionary = {}) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(ROUTE_LADEN, params)
	return true
