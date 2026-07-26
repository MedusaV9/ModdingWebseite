class_name RanchWeltState
extends RefCounted
## Save-Anbindung der Ranch-Region (RW-1) — ADDITIV im bestehenden
## `ranch`-Slice (RanchState), KEIN Version-Bump: neue Unterschlüssel
## `ranch.welt` (entdeckte Zonen) und `ranch.wetter` (Wetter-Seed).
## Unbekannte Unterschlüssel überleben RanchState.normalize_slice verbatim;
## dieses Modul heilt seine Daten deshalb beim LESEN (Self-Heal-Muster).

const WELT_KEY := "ranch.welt"
const WETTER_KEY := "ranch.wetter"


static func default_welt() -> Dictionary:
	return {"v": 1, "entdeckt": ["hof"]}


static func default_wetter() -> Dictionary:
	return {"v": 1, "seed": RanchKarte.seed_wert()}


## Geheilte Welt-Daten aus dem Save (gs = GameState oder Test-Double).
static func welt_daten(gs: Object) -> Dictionary:
	if gs == null:
		return default_welt()
	return normalize_welt(gs.get_value(WELT_KEY, null))


static func normalize_welt(raw: Variant) -> Dictionary:
	var welt: Dictionary = raw if raw is Dictionary else default_welt()
	welt["v"] = maxi(1, int(welt.get("v", 1)))
	var entdeckt: Array[String] = []
	var roh: Variant = welt.get("entdeckt")
	if roh is Array:
		for eintrag: Variant in roh:
			var id := str(eintrag)
			if not entdeckt.has(id) and not RanchKarte.zone(id).is_empty():
				entdeckt.append(id)
	if not entdeckt.has("hof"):
		entdeckt.insert(0, "hof")
	welt["entdeckt"] = entdeckt
	return welt


## Bereits entdeckte Zonen-Ids.
static func entdeckte_zonen(gs: Object) -> Array[String]:
	var entdeckt: Array[String] = []
	for id: Variant in welt_daten(gs)["entdeckt"]:
		entdeckt.append(str(id))
	return entdeckt


## Zone als entdeckt markieren; true = war NEU (Toast zeigen).
static func entdecke_zone(gs: Object, zone_id: String) -> bool:
	if gs == null or RanchKarte.zone(zone_id).is_empty():
		return false
	if entdeckte_zonen(gs).has(zone_id):
		return false
	var welt := welt_daten(gs)
	(welt["entdeckt"] as Array[String]).append(zone_id)
	gs.set_value(WELT_KEY, welt)
	return true


## Wetter-Seed des Spielstands (stabil pro Save, deterministisch offline).
static func wetter_seed(gs: Object) -> int:
	if gs == null:
		return RanchKarte.seed_wert()
	var wetter := normalize_wetter(gs.get_value(WETTER_KEY, null))
	return int(wetter["seed"])


static func normalize_wetter(raw: Variant) -> Dictionary:
	var wetter: Dictionary = raw if raw is Dictionary else default_wetter()
	wetter["v"] = maxi(1, int(wetter.get("v", 1)))
	var seed_roh: Variant = wetter.get("seed")
	if not (seed_roh is int or seed_roh is float):
		wetter["seed"] = RanchKarte.seed_wert()
	else:
		wetter["seed"] = int(seed_roh)
	return wetter
