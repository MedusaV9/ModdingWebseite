class_name CraftLogic
extends RefCounted
## Crafting-Regeln (Doc D §5.2/§5.3) als PURE static-Funktionen über einem
## Material-Inventar `{materialId: menge}`. Kein Node, kein GameState —
## vollständig headless testbar (tests/unit/test_craft_logic.gd).
##
## Craften kostet NIE Energie (User-Regel, wie Bauen) — es gibt in dieser
## Datei bewusst keinen Energie-Parameter.

## Ablehnungsgründe (stabile Strings für UI/Tests).
const REASON_OK := ""
const REASON_UNKNOWN := "unknown_recipe"
const REASON_STATION := "no_station"
const REASON_BLUEPRINT := "missing_blueprint"
const REASON_MATERIAL := "missing_material"
const REASON_STORAGE := "storage_full"


## Fehlmengen pro Material ({} = alles da).
static func missing_materials(recipe: Dictionary, inventory: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	var needed: Dictionary = recipe.get("materialien", {})
	for material_id: String in needed:
		var lack := int(needed[material_id]) - count_of(inventory, material_id)
		if lack > 0:
			missing[material_id] = lack
	return missing


static func count_of(inventory: Dictionary, material_id: String) -> int:
	return maxi(0, int(inventory.get(material_id, 0)))


## Vollständige Prüfung. `frei_lagerpunkte` = Rest-Kapazität im Lager,
## `lagerwert` = Gewicht EINES Ausgabe-Exemplars (Doc D §2.3).
## Liefert {"ok": bool, "reason": String, "missing": Dictionary}.
static func check(
	recipe: Dictionary,
	inventory: Dictionary,
	blueprints: Array,
	werkstatt_gebaut: bool,
	frei_lagerpunkte := 999,
	lagerwert := 1
) -> Dictionary:
	if recipe.is_empty():
		return _fail(REASON_UNKNOWN)
	if not werkstatt_gebaut:
		return _fail(REASON_STATION)
	var bauplan := str(recipe.get("bauplan", ""))
	if bauplan != "" and not blueprints.has(bauplan):
		return _fail(REASON_BLUEPRINT)
	var missing := missing_materials(recipe, inventory)
	if not missing.is_empty():
		return {"ok": false, "reason": REASON_MATERIAL, "missing": missing}
	var count := int(recipe.get("output", {}).get("count", 1))
	if count * maxi(1, lagerwert) > frei_lagerpunkte:
		return _fail(REASON_STORAGE)
	return {"ok": true, "reason": REASON_OK, "missing": {}}


## Zieht die Rezept-Materialien ab (mutiert `inventory`, leere Zeilen fliegen
## raus). Liefert false, wenn etwas fehlte — dann bleibt das Inventar
## unangetastet (Alles-oder-nichts, damit ein abgelehnter Craft nie frisst).
static func consume(inventory: Dictionary, recipe: Dictionary) -> bool:
	if not missing_materials(recipe, inventory).is_empty():
		return false
	var needed: Dictionary = recipe.get("materialien", {})
	for material_id: String in needed:
		take(inventory, material_id, int(needed[material_id]))
	return true


static func add(inventory: Dictionary, material_id: String, amount := 1) -> void:
	if amount <= 0:
		return
	inventory[material_id] = count_of(inventory, material_id) + amount


## Nimmt `amount` heraus; false = zu wenig da (Inventar bleibt unverändert).
static func take(inventory: Dictionary, material_id: String, amount := 1) -> bool:
	var have := count_of(inventory, material_id)
	if amount <= 0 or have < amount:
		return false
	if have == amount:
		inventory.erase(material_id)
	else:
		inventory[material_id] = have - amount
	return true


## Gesamtkosten eines Rezepts im Baumarkt (Materialien, die man kaufen MUSS,
## also `quelle == "baumarkt"`) — für die „lohnt sich das?“-Anzeige.
static func baumarkt_kosten(recipe: Dictionary, inventory: Dictionary) -> int:
	var total := 0
	for material_id: String in missing_materials(recipe, inventory):
		var row := CraftMaterials.def(material_id)
		if row.get("quelle", "") == "baumarkt":
			total += (
				int(row.get("preis", 0)) * int(missing_materials(recipe, inventory)[material_id])
			)
	return total


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "missing": {}}
