class_name RanchWeltRouten
extends RefCounted
## Routen-Anmeldung der offenen Ranch-Region (RW-1) — Muster RanchRouten:
## die Region registriert ihr Ziel selbst (idempotent), bevor sie hinreist.
## Andere Agents reisen mit `RanchWeltRouten.reite_los(get_tree())` in die
## Region (optional params: {"spawn_zone": "see"}).

const ROUTE_WELT := &"ranch/welt"
const SZENE_WELT := "res://scenes/ranch/welt/ranch_region.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter).
static var router_override: Object = null


## Region-Route registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_WELT, SZENE_WELT)


## In die offene Ranch-Region reiten.
static func reite_los(baum: SceneTree, params: Dictionary = {}) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(ROUTE_WELT, params)
	return true
