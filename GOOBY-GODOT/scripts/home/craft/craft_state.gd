class_name CraftState
extends RefCounted
## Werkstatt & Crafting — Save-Anbindung (Doc D §5). Additiv im bestehenden
## `home`-Slice: `home.materials` (Material-Inventar), `home.blueprints`
## (gekaufte Baupläne). Die Werkstatt selbst ist eine Garten-Struktur
## (`home.garden.structures`, kind "werkstatt").
##
## BAUMARKT-DATENVERTRAG (Laden = ORTE-Agent):
##   CraftMaterials.baumarkt_angebot() -> [{art, id, preis}]
##   CraftState.add_material(gs, id, menge)
##   CraftState.add_blueprint(gs, id)
## Handoff: /tmp/gooby-godot/handoffs/HAUS-baumarkt-api.md
##
## Craften kostet KEINE Energie (User-Regel, wie Bauen).

const Economy := preload("res://scripts/logic/economy.gd")

## Zuordnung City-Baumarkt-Einkauf (inventory.items) → Werkstatt-Material
## (home.materials) für die W15/MARKT-Bridge: bewusst eine feste Tabelle
## (5 Bretter = 5 Holz usw.), fremde Items bleiben unangetastet liegen.
const BAUMARKT_MATERIAL_MAP := {
	"bretter": "holz",
	"stoecke": "stock",
	"naegel": "naegel",
	"eisen": "eisen",
	"saatgut": "saatgut",
}


static func materials(gs: Object) -> Dictionary:
	var raw: Variant = gs.get_value("home.materials", {})
	return raw if raw is Dictionary else {}


static func material_count(gs: Object, material_id: String) -> int:
	return CraftLogic.count_of(materials(gs), material_id)


## Material gutschreiben (Baumarkt-Kauf, Garten-Fund, Baum-Ernte).
static func add_material(gs: Object, material_id: String, menge := 1) -> void:
	if menge <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			CraftLogic.add(state["home"]["materials"], material_id, menge)
	)
	gs.notify_slice_changed("home")


## Baumarkt-Kauf inkl. Münzen (der Laden ruft das, ORTE-Agent).
## Liefert false bei unbekanntem Material oder zu wenig Münzen.
static func kaufe_material(gs: Object, material_id: String, menge := 1) -> bool:
	var preis := CraftMaterials.baumarkt_preis("material", material_id)
	if preis <= 0 or menge <= 0:
		return false
	var gesamt := preis * menge
	if int(gs.get_value("economy.coins", 0)) < gesamt:
		return false
	gs.update(
		func(state: Dictionary) -> void:
			if Economy.spend(state["economy"], gesamt, "baumarkt"):
				CraftLogic.add(state["home"]["materials"], material_id, menge)
	)
	gs.notify_slice_changed("home")
	return true


## Vereinte Bauplan-Sicht (W15/MARKT-Bridge, additiv): home.blueprints
## (CraftState.add_blueprint) PLUS die im City-Baumarkt gekauften
## bauplan_*-Flag-Items (inventory.items) — deren `werkstatt_id` schaltet
## per Konvention das Rezept mit bauplan "bp_<werkstatt_id>" frei.
static func blueprints(gs: Object) -> Array:
	var raw: Variant = gs.get_value("home.blueprints", [])
	var eigene: Array = raw if raw is Array else []
	var out := eigene.duplicate()
	for werkstatt_id: String in BaumarktKatalog.freigeschaltete_rezepte(gs):
		if werkstatt_id.is_empty():
			continue
		var bp := "bp_%s" % werkstatt_id
		if not out.has(bp):
			out.append(bp)
	return out


static func has_blueprint(gs: Object, blueprint_id: String) -> bool:
	return blueprints(gs).has(blueprint_id)


## Bauplan freischalten (Baumarkt-Kauf). false = schon vorhanden.
static func add_blueprint(gs: Object, blueprint_id: String) -> bool:
	if has_blueprint(gs, blueprint_id):
		return false
	gs.update(func(state: Dictionary) -> void: state["home"]["blueprints"].append(blueprint_id))
	gs.notify_slice_changed("home")
	return true


## City-Baumarkt-Einkäufe (inventory.items, BaumarktSheet) ins
## Werkstatt-Lager (home.materials) übernehmen — W15/MARKT-Bridge, additiv.
## Das Craft-Panel ruft das beim Öffnen/Refresh (BAUMARKT_MATERIAL_MAP oben).
static func uebernehme_baumarkt_einkaeufe(gs: Object) -> void:
	if gs == null:
		return
	var offen := false
	for item_id: String in BAUMARKT_MATERIAL_MAP:
		if int(gs.get_value("inventory.items.%s" % item_id, 0)) > 0:
			offen = true
			break
	if not offen:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("inventory") is Dictionary):
				return
			var inventory: Dictionary = state["inventory"]
			if not (inventory.get("items") is Dictionary):
				return
			var items: Dictionary = inventory["items"]
			for item_id: String in BAUMARKT_MATERIAL_MAP:
				var menge := maxi(0, int(items.get(item_id, 0)))
				if menge <= 0:
					continue
				items.erase(item_id)
				CraftLogic.add(
					state["home"]["materials"], str(BAUMARKT_MATERIAL_MAP[item_id]), menge
				)
	)
	gs.notify_slice_changed("home")


## Steht die Werkstatt im Garten? (Ohne sie ist die Werkbank nicht nutzbar.)
static func werkstatt_gebaut(gs: Object) -> bool:
	for entry: Variant in GardenState.slice(gs).get("structures", []):
		if entry is Dictionary and str(entry.get("kind", "")) == "werkstatt":
			return true
	return false


## Prüfung eines Rezepts gegen den aktuellen Spielstand (UI-Zustand der Karte).
static func check(gs: Object, recipe_id: String) -> Dictionary:
	var recipe := CraftRecipes.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": CraftLogic.REASON_UNKNOWN, "missing": {}}
	var item_def := FurnitureCatalog.def(str(recipe["output"]["item"]))
	var frei := HomeState.storage_capacity(gs) - HomeState.storage_points_used(gs)
	return CraftLogic.check(
		recipe,
		materials(gs),
		blueprints(gs),
		werkstatt_gebaut(gs),
		frei,
		int(item_def.get("lagerwert", 1))
	)


## Craften: Materialien abziehen, Möbel ins LAGER legen (Doc D §5.3).
## Liefert {"ok", "reason", "item", "count"}.
static func craft(gs: Object, recipe_id: String) -> Dictionary:
	var pruefung := check(gs, recipe_id)
	if not pruefung["ok"]:
		return {
			"ok": false,
			"reason": pruefung["reason"],
			"item": "",
			"count": 0,
		}
	var recipe := CraftRecipes.recipe(recipe_id)
	var item_id := str(recipe["output"]["item"])
	var count := int(recipe["output"]["count"])
	gs.update(
		func(state: Dictionary) -> void:
			var home: Dictionary = state["home"]
			if not CraftLogic.consume(home["materials"], recipe):
				return
			for _i in count:
				StorageLogic.add(home["storage"], item_id)
	)
	gs.notify_slice_changed("home")
	return {"ok": true, "reason": CraftLogic.REASON_OK, "item": item_id, "count": count}


## Alle Rezepte mit ihrem UI-Zustand (Liste im Crafting-Panel).
static func recipe_states(gs: Object, station := CraftRecipes.STATION_WERKBANK) -> Array:
	var out: Array = []
	for recipe: Dictionary in CraftRecipes.for_station(station):
		var status := check(gs, str(recipe["id"]))
		(
			out
			. append(
				{
					"recipe": recipe,
					"ok": bool(status["ok"]),
					"reason": str(status["reason"]),
					"missing": status["missing"],
				}
			)
		)
	return out
