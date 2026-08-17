class_name DorfRouten
extends RefCounted
## Routen + Anreise-Regeln des Reit-Dorfs Hufingen (RW-4).
##
## ANREISE-REGEL (User-Wunsch): Nach Hufingen wird GERITTEN, kein
## Menü-Teleport. Der Weg führt über RW-1s offene Region (Route
## `ranch/welt`, Zone "hufingen" — s. RW1-welt-api.md); fehlt die Region
## (Parallel-Entwicklung), reitet man den Anreise-Pfad direkt in der
## Dorf-Szene. SCHNELLREISE gibt es erst NACH der ersten Entdeckung
## (ranch.dorf.entdeckt — RanchDorfState.entdecke setzt das Gate).

const ROUTE_DORF := &"ranch/dorf"
const SZENE_DORF := "res://scenes/ranch/dorf/hufingen.tscn"
const ROUTE_WELT := &"ranch/welt"
const SZENE_WELT := "res://scenes/ranch/welt/ranch_region.tscn"

## Tests injizieren hier einen Fake-Router (null = /root/SceneRouter) —
## sonst würde jeder Knopfdruck im Runner eine ECHTE Reise starten.
static var router_override: Object = null


## Dorf-Route anmelden (idempotent — register_route ersetzt).
static func registriere(router: Object) -> void:
	if router == null or not router.has_method("register_route"):
		return
	router.register_route(ROUTE_DORF, SZENE_DORF)


## Schnellreise erlaubt? Erst nach dem ersten Anritt (Entdeckungs-Gate).
static func schnellreise_moeglich(gs: Object) -> bool:
	return RanchDorfState.ist_entdeckt(gs)


## Losreiten Richtung Hufingen: über RW-1s offene Region, wenn sie da ist
## (Spawn am Hof, dann reiten); sonst defensiv direkt in die Dorf-Szene
## mit Anritts-Pfad (params.via = "ritt" — die Szene startet am Weganfang).
static func reite_los(baum: SceneTree, params: Dictionary = {}) -> bool:
	if ResourceLoader.exists(SZENE_WELT):
		var welt_params := params.duplicate(true)
		if not welt_params.has("spawn_zone"):
			welt_params["spawn_zone"] = "hof"
		return _gehe(baum, ROUTE_WELT, welt_params, SZENE_WELT)
	var dorf_params := params.duplicate(true)
	dorf_params["via"] = "ritt"
	return _gehe(baum, ROUTE_DORF, dorf_params, SZENE_DORF)


## Ankunft per Ritt (Region meldet Zone "hufingen", oder der Anritts-Pfad
## endet): in die Dorf-Szene wechseln. Entdeckung bucht die SZENE selbst
## beim Passieren des Ortsschilds (RanchDorfState.entdecke).
static func betrete_dorf(baum: SceneTree, params: Dictionary = {}) -> bool:
	var dorf_params := params.duplicate(true)
	if not dorf_params.has("via"):
		dorf_params["via"] = "ritt"
	return _gehe(baum, ROUTE_DORF, dorf_params, SZENE_DORF)


## Schnellreise (Menü): NUR nach der ersten Entdeckung. Spawnt direkt am
## Ortsschild (via = "schnellreise").
static func schnellreise(baum: SceneTree, gs: Object, params: Dictionary = {}) -> bool:
	if not schnellreise_moeglich(gs):
		return false
	var dorf_params := params.duplicate(true)
	dorf_params["via"] = "schnellreise"
	return _gehe(baum, ROUTE_DORF, dorf_params, SZENE_DORF)


static func _gehe(baum: SceneTree, ziel: StringName, params: Dictionary, szene: String) -> bool:
	var router: Object = router_override
	if router == null and baum != null:
		router = baum.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	if router.has_method("register_route"):
		router.register_route(ziel, szene)
	router.goto(ziel, params)
	return true
