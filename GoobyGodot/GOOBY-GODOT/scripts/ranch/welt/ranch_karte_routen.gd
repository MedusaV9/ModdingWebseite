class_name RanchKarteRouten
extends RefCounted
## Routen-Anmeldung der Entdecker-Karte (W19) — Muster RanchWeltRouten:
## der Screen registriert sein Ziel selbst (idempotent), bevor er öffnet.
## Die Karte DARF in die Router-History (Zurück von der Karte führt dahin,
## wo sie geöffnet wurde) — deshalb KEIN markiere_fluechtig.

const ROUTE_KARTE := &"ranch/karte"
const SZENE_KARTE := "res://scenes/ranch/welt/ranch_karte_screen.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter).
static var router_override: Object = null


## Karten-Route registrieren (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_KARTE, SZENE_KARTE)


## Entdecker-Karte öffnen (registriert vorher die Route).
static func oeffne_karte(baum: SceneTree, params: Dictionary = {}) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	registriere(router)
	router.goto(ROUTE_KARTE, params)
	return true
