class_name ShopPurchase
extends RefCounted
## Kauf-Logik der Möbel-Ausstellung (CONTENT-B) — pure static-Funktionen über
## dem GameState (Duck-Typing wie überall im Projekt), damit sie headless
## testbar sind und die UI keinen eigenen Regel-Zweig bekommt.
##
## Ein Kauf ist ATOMAR: entweder Münzen weg UND Möbel im Lager, oder nichts.
## Beides passiert in EINEM `gs.update()`-Block (Economy.spend ist selbst
## schon atomar, StorageLogic.add läuft nur bei Erfolg).
##
## Gekauftes landet im LAGER (`home.storage`), nicht direkt im Raum — der
## Baumodus holt es dort ab (Doc D §2.3). Die gewählte Farbvariante reist als
## `variant` im Lager-Eintrag mit.

const RESULT_OK := "ok"
const RESULT_UNKNOWN := "unknown_item"
const RESULT_BROKE := "not_enough_coins"
const RESULT_FULL := "storage_full"
const REASON := "moebelhaus"

const Economy := preload("res://scripts/logic/economy.gd")


static func price_of(item_id: String) -> int:
	return int(ShopCatalog.def(item_id).get("preis", 0))


## Prüft einen Kauf, ohne etwas zu ändern. Liefert RESULT_OK oder den Grund.
static func check(gs: Object, item_id: String) -> String:
	var item := ShopCatalog.def(item_id)
	if item.is_empty() or not ShopCatalog.sellable(item):
		return RESULT_UNKNOWN
	if gs == null:
		return RESULT_UNKNOWN
	if int(gs.get_value("economy.coins", 0)) < int(item["preis"]):
		return RESULT_BROKE
	if not _fits(gs, item_id):
		return RESULT_FULL
	return RESULT_OK


static func can_buy(gs: Object, item_id: String) -> bool:
	return check(gs, item_id) == RESULT_OK


## Kauft ein Exemplar in der gewünschten Farbvariante. Liefert denselben
## Ergebnis-Code wie check(); nur RESULT_OK hat den State verändert.
static func buy(gs: Object, item_id: String, variant_id := FurnitureVariants.DEFAULT_ID) -> String:
	var reason := check(gs, item_id)
	if reason != RESULT_OK:
		return reason
	var item := ShopCatalog.def(item_id)
	var variant := FurnitureVariants.normalize(item, variant_id)
	var preis := int(item["preis"])
	# Einelementiges Array als Rückkanal: GDScript-Lambdas fangen lokale
	# Variablen per WERT ein, eine Zuweisung im Block käme hier nie an.
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			StorageLogic.add(state[HomeState.SLICE_ID]["storage"], item_id, variant)
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	gs.notify_slice_changed(HomeState.SLICE_ID)
	return RESULT_OK


## Freie Lagerpunkte (Anzeige „Lager: 42/100“ in der Ausstellung).
static func storage_free(gs: Object) -> int:
	if gs == null:
		return 0
	var used := StorageLogic.points_used(_storage(gs), ShopCatalog.defs())
	return maxi(0, int(gs.get_value("home.storageCapacity", 100)) - used)


static func _fits(gs: Object, item_id: String) -> bool:
	return StorageLogic.can_add(
		_storage(gs), item_id, ShopCatalog.defs(), int(gs.get_value("home.storageCapacity", 100))
	)


static func _storage(gs: Object) -> Array:
	var raw: Variant = gs.get_value("home.storage", [])
	return raw if raw is Array else []
