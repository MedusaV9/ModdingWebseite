class_name GoobyeRouten
extends RefCounted
## Routen-Anmeldung des „Goo und Bye“ (G5/P24) — Muster RanchRouten: der
## SceneRouter erlaubt register_route von überall, der Laden meldet sein
## Ziel deshalb SELBST an (idempotent), bevor er hinreist. Kein Eingriff
## in den Boot-Orchestrator nötig.
##
## Welle B (G6/GOOBYE-B): die Großmarkt-Fahrt (§4.1/§4.2) ist eine
## FLÜCHTIGE Durchgangs-Station (markiere_fluechtig) — sie landet nie in
## der Router-History und setzt ihren Ausgang immer explizit per goto()
## zurück in den Laden (sonst würde „Zurück“ eine neue Fahrt starten).

const ROUTE_LADEN := &"dlc/goobye_laden"
const SZENE_LADEN := "res://scripts/dlc/goobye/laden_scene.tscn"
const ROUTE_GROSSMARKT := &"dlc/goobye_grossmarkt"
const SZENE_GROSSMARKT := "res://scripts/dlc/goobye/grossmarkt_scene.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter) —
## sonst würde jeder Knopfdruck im Runner eine ECHTE Reise starten.
static var router_override: Object = null


## Alle Goo-und-Bye-Routen registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_LADEN, SZENE_LADEN)
	router.register_route(ROUTE_GROSSMARKT, SZENE_GROSSMARKT)
	if router.has_method("markiere_fluechtig"):
		router.markiere_fluechtig([ROUTE_GROSSMARKT])


## In den Laden reisen (registriert vorher die Route).
static func fahre_zum_laden(baum: SceneTree, params: Dictionary = {}) -> bool:
	return _fahre(baum, ROUTE_LADEN, params)


## Zur Großmarkt-Rampe hinter REHWEI fahren (Welle B, §4.1).
static func fahre_zum_grossmarkt(baum: SceneTree, params: Dictionary = {}) -> bool:
	return _fahre(baum, ROUTE_GROSSMARKT, params)


static func _fahre(baum: SceneTree, route: StringName, params: Dictionary) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(route, params)
	return true
