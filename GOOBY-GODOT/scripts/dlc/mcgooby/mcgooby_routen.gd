class_name McGoobyRouten
extends RefCounted
## Routen-Anmeldung des McGooby-DLC (G5/P25) — Muster Ranch-/GoobyeRouten:
## der SceneRouter erlaubt register_route von überall, die Schicht meldet
## ihr Ziel deshalb SELBST an (idempotent), bevor sie hinreist. Kein
## Eingriff in den Boot-Orchestrator nötig; der DLC-Hub (P24) braucht nur
## EINEN Aufruf: `McGoobyRouten.fahre_zur_schicht(get_tree())`.

const ROUTE_SCHICHT := McGoobySchichtScene.ROUTE
const SZENE_SCHICHT := "res://scripts/dlc/mcgooby/schicht_scene.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter) —
## sonst würde jeder Knopfdruck im Runner eine ECHTE Reise starten.
static var router_override: Object = null


## Schicht-Route registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_SCHICHT, SZENE_SCHICHT)


## Zur Mini-Schicht reisen (registriert vorher die Route).
static func fahre_zur_schicht(baum: SceneTree, params: Dictionary = {}) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(ROUTE_SCHICHT, params)
	return true
