class_name StorageLogic
extends RefCounted
## Lager-Logik (W2a HOUSE) — pure static-Funktionen über dem Save-Format
## `home.storage: [{"item": id, "variant": "default", "count": n}, ...]`.
##
## Kapazität in LAGERPUNKTEN (Doc D §2.3): Basis 100 (home.storageCapacity),
## jedes Item wiegt `lagerwert` 1–4 (Deko 1 … Badewanne 4). Unbekannte Items
## (`__unknown__` nach Pack-/Katalog-Änderung) wiegen 1 und bleiben erhalten.

const UNKNOWN_ITEM := "__unknown__"


## Verbrauchte Lagerpunkte (Summe lagerwert × count).
static func points_used(storage: Array, defs: Dictionary) -> int:
	var total := 0
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		var weight := item_weight(str(entry.get("item", "")), defs)
		total += weight * maxi(0, int(entry.get("count", 0)))
	return total


static func item_weight(item_id: String, defs: Dictionary) -> int:
	if defs.has(item_id):
		return clampi(int(defs[item_id].get("lagerwert", 1)), 1, 4)
	return 1


## Passt EIN weiteres Exemplar von `item_id` noch ins Lager?
static func can_add(storage: Array, item_id: String, defs: Dictionary, capacity: int) -> bool:
	return points_used(storage, defs) + item_weight(item_id, defs) <= capacity


## Legt ein Exemplar ins Lager (merged in bestehende Zeile). KEINE
## Kapazitätsprüfung — die macht der Aufrufer via can_add (Pickup-Fluss
## muss Ablehnung als UI-Feedback zeigen, nicht still verlieren).
static func add(storage: Array, item_id: String, variant := "default") -> void:
	for entry: Variant in storage:
		if entry is Dictionary and entry.get("item") == item_id and entry.get("variant") == variant:
			entry["count"] = int(entry.get("count", 0)) + 1
			return
	storage.append({"item": item_id, "variant": variant, "count": 1})


## Nimmt ein Exemplar heraus (fürs Platzieren). false = nicht vorhanden.
static func take(storage: Array, item_id: String, variant := "default") -> bool:
	for i in storage.size():
		var entry: Variant = storage[i]
		if not (entry is Dictionary):
			continue
		if entry.get("item") == item_id and entry.get("variant") == variant:
			var count := int(entry.get("count", 0))
			if count <= 0:
				return false
			if count == 1:
				storage.remove_at(i)
			else:
				entry["count"] = count - 1
			return true
	return false


static func count_of(storage: Array, item_id: String) -> int:
	var total := 0
	for entry: Variant in storage:
		if entry is Dictionary and entry.get("item") == item_id:
			total += maxi(0, int(entry.get("count", 0)))
	return total
