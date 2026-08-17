class_name FuetterSprueche
extends RefCounted
## W14/FRIDGE — 8 rotierende Bubble-Sprüche je Regal-Kategorie
## (`fuettern.sprueche.<kategorie>`, DE führend). ROTATION statt Zufall:
## jede Fütterung nimmt den NÄCHSTEN Spruch ihrer Kategorie (statischer
## Session-Zähler) — so wiederholt sich nichts, bevor alle 8 dran waren.

static var _zaehler: Dictionary = {}


## Nächster Spruch für dieses Essen ({essen}-Platzhalter wird gefüllt).
static func naechster(food_id: String) -> String:
	var kategorie := FoodCatalog.kategorie(food_id)
	var liste := I18nService.items("fuettern.sprueche." + kategorie)
	if liste.is_empty():
		return FoodCatalog.display_name(food_id)
	var index := int(_zaehler.get(kategorie, 0)) % liste.size()
	_zaehler[kategorie] = index + 1
	return String(liste[index]).format({"essen": FoodCatalog.display_name(food_id)})


## Nur für Tests: Rotation zurücksetzen.
static func reset_fuer_tests() -> void:
	_zaehler.clear()
