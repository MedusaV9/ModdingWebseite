class_name GooberandoRestaurants
extends RefCounted
## GOOBERANDO-Restaurant-Katalog (W13B, Doc E §5.1): lädt die 3 virtuellen
## Lieferküchen aus `data/gooberando_restaurants.json`. PURE — kein Node,
## kein UI. Gericht-Ids sind FoodCatalog-Ids (scripts/logic/food_catalog.gd),
## die Lieferung bucht sie 1:1 in `inventory.food`. `strasse` ist der
## Straßen-Tile-Startknoten der Fahrer-Sim (delivery/fahrer_sim.gd).

const PFAD := "res://scripts/city/data/gooberando_restaurants.json"


## Alle Restaurants in Katalog-Reihenfolge ([] bei kaputter Datei).
static func alle() -> Array:
	var raw := FileAccess.get_file_as_string(PFAD)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("Restaurant-Katalog kaputt: %s" % PFAD)
		return []
	return json.data.get("restaurants", [])


static func restaurant(id: String) -> Dictionary:
	for eintrag: Dictionary in alle():
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


static func gerichte(restaurant_id: String) -> Array:
	return restaurant(restaurant_id).get("gerichte", [])


static func gericht(restaurant_id: String, gericht_id: String) -> Dictionary:
	for eintrag: Dictionary in gerichte(restaurant_id):
		if str(eintrag.get("id", "")) == gericht_id:
			return eintrag
	return {}


## Straßen-Tile des Restaurants (Fahrer-Startknoten). (-1,-1) = unbekannt —
## Aufrufer fallen dann auf die GOOBERANDO-Küche der Karte zurück.
static func strasse_tile(restaurant_id: String) -> Vector2i:
	var raw: Variant = restaurant(restaurant_id).get("strasse", [])
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)
