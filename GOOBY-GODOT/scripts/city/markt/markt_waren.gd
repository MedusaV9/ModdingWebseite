class_name MarktWaren
extends RefCounted
## W15/MARKT — Waren-Katalog des EIGENEN Marktstands (Doc D §6.3) — PURE.
##
## Der Stand verkauft drei Waren-Quellen (markt_waren.json):
##   - "ernte":    Garten-Ernte aus `inventory.food` (Ids = markt_preise.json;
##                 Basiswert = MarktPreise.marktpreis, bleibt automatisch mit
##                 dem Ankauf-Schalter des Markts synchron).
##   - "craft":    Selbstgebautes — Möbel-Waren aus `home.storage`
##                 (Basiswert = FurnitureCatalog.verkaufswert) und stapelbare
##                 Craft-Waren wie der Kräuterbund aus `inventory.items`.
##   - "souvenir": Mitbringsel (Weltraum-Möhre) aus `inventory.food`.
##
## Lager-IO läuft über nimm/zurueck: alles-oder-nichts pro Menge, IMMER
## verlustfrei — zurueck() prüft bewusst KEINE Lagerkapazität (die Ware kam
## aus dem Lager; Zurücklegen darf nie etwas verschlucken, gleiche Regel wie
## StorageLogic.add).

const WAREN_PFAD := "res://scripts/city/data/markt_waren.json"

const KATEGORIEN: Array[String] = ["ernte", "craft", "souvenir"]
const LAGER_TYPEN: Array[String] = ["food", "items", "storage"]

static var _cache: Array = []
static var _cache_pfad := ""


## Normalisierte Waren-Liste (id, kategorie, lager, basis, name_de, name_en).
static func waren(pfad := WAREN_PFAD) -> Array:
	if _cache_pfad == pfad and not _cache.is_empty():
		return _cache
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("markt_waren.json kaputt: %s" % pfad)
		return []
	var out: Array = []
	var rows: Variant = (json.data as Dictionary).get("waren", [])
	if rows is Array:
		for row: Variant in rows:
			if row is Dictionary:
				var eintrag := _normalisiere(row)
				if not eintrag.is_empty():
					out.append(eintrag)
	_cache = out
	_cache_pfad = pfad
	return out


static func ware(id: String, pfad := WAREN_PFAD) -> Dictionary:
	for eintrag: Dictionary in waren(pfad):
		if str(eintrag["id"]) == id:
			return eintrag
	return {}


static func reset_cache() -> void:
	_cache = []
	_cache_pfad = ""


## Basiswert EINER Einheit (Mitte des Preis-Sliders). Ernte nimmt den
## Markt-Ankaufspreis (inkl. Bonus), Möbel-Waren ihren Goobay-Verkaufswert.
static func basis(id: String, pfad := WAREN_PFAD) -> int:
	var eintrag := ware(id, pfad)
	if eintrag.is_empty():
		return 0
	var explizit := int(eintrag.get("basis", 0))
	if explizit > 0:
		return explizit
	if str(eintrag["lager"]) == "storage":
		var def := FurnitureCatalog.def(id)
		return maxi(1, int(def.get("verkaufswert", 0)))
	return MarktPreise.marktpreis(id)


static func anzeigename(id: String, locale := "de", pfad := WAREN_PFAD) -> String:
	var eintrag := ware(id, pfad)
	if eintrag.is_empty():
		return id
	var eigen := str(eintrag.get("name_en" if locale == "en" else "name_de", ""))
	if not eigen.is_empty():
		return eigen
	if str(eintrag["lager"]) == "storage":
		return FurnitureCatalog.display_name(FurnitureCatalog.def(id), locale)
	var sorte := MarktPreise.sorte(id)
	if not sorte.is_empty():
		return str(sorte.get("name_de", id))
	return id


## ------------------------------------------------------------ Lager-Sicht


## Vorrat einer Ware im jeweiligen Lager (0 bei unbekannter Ware/ohne gs).
static func vorrat(gs: Object, id: String, pfad := WAREN_PFAD) -> int:
	if gs == null:
		return 0
	var eintrag := ware(id, pfad)
	match str(eintrag.get("lager", "")):
		"food":
			return maxi(0, int(gs.get_value("inventory.food.%s" % id, 0)))
		"items":
			return maxi(0, int(gs.get_value("inventory.items.%s" % id, 0)))
		"storage":
			var storage: Variant = gs.get_value("home.storage", [])
			return StorageLogic.count_of(storage if storage is Array else [], id)
	return 0


## Verkaufbares Lager-Angebot: [{id, name, vorrat, basis, kategorie}].
static func angebot(gs: Object, locale := "de", pfad := WAREN_PFAD) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eintrag: Dictionary in waren(pfad):
		var id := str(eintrag["id"])
		var menge := vorrat(gs, id, pfad)
		if menge <= 0:
			continue
		(
			out
			. append(
				{
					"id": id,
					"name": anzeigename(id, locale, pfad),
					"vorrat": menge,
					"basis": basis(id, pfad),
					"kategorie": str(eintrag["kategorie"]),
				}
			)
		)
	return out


## Nimmt `menge` aus dem Lager (mutiert `state`). Rückgabe = wirklich
## entnommene Menge (nie mehr als der Vorrat, nie negativ).
static func nimm(state: Dictionary, id: String, menge: int, pfad := WAREN_PFAD) -> int:
	if menge <= 0:
		return 0
	var eintrag := ware(id, pfad)
	match str(eintrag.get("lager", "")):
		"food":
			return _nimm_aus_map(_map(state, "inventory", "food"), id, menge)
		"items":
			return _nimm_aus_map(_map(state, "inventory", "items"), id, menge)
		"storage":
			var storage: Array = _storage(state)
			var genommen := 0
			for _i in menge:
				if not StorageLogic.take(storage, id):
					break
				genommen += 1
			return genommen
	return 0


## Legt `menge` zurück ins Lager (mutiert `state`) — verlustfrei, auch wenn
## das Möbellager voll ist (bewusst OHNE can_add, s. Kopfkommentar).
static func zurueck(state: Dictionary, id: String, menge: int, pfad := WAREN_PFAD) -> void:
	if menge <= 0:
		return
	var eintrag := ware(id, pfad)
	match str(eintrag.get("lager", "")):
		"food":
			var food := _map(state, "inventory", "food")
			food[id] = maxi(0, int(food.get(id, 0))) + menge
		"items":
			var items := _map(state, "inventory", "items")
			items[id] = maxi(0, int(items.get(id, 0))) + menge
		"storage":
			var storage: Array = _storage(state)
			for _i in menge:
				StorageLogic.add(storage, id)


static func _nimm_aus_map(map: Dictionary, id: String, menge: int) -> int:
	var da := maxi(0, int(map.get(id, 0)))
	var genommen := mini(da, menge)
	map[id] = da - genommen
	return genommen


static func _map(state: Dictionary, wurzel: String, key: String) -> Dictionary:
	if not (state.get(wurzel) is Dictionary):
		state[wurzel] = {}
	var eltern: Dictionary = state[wurzel]
	if not (eltern.get(key) is Dictionary):
		eltern[key] = {}
	return eltern[key]


static func _storage(state: Dictionary) -> Array:
	if not (state.get("home") is Dictionary):
		state["home"] = {}
	var home: Dictionary = state["home"]
	if not (home.get("storage") is Array):
		home["storage"] = []
	return home["storage"]


static func _normalisiere(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	var kategorie := str(raw.get("kategorie", ""))
	var lager := str(raw.get("lager", ""))
	if id.is_empty() or not KATEGORIEN.has(kategorie) or not LAGER_TYPEN.has(lager):
		push_error("Markt-Ware ungültig: %s" % str(raw))
		return {}
	return {
		"id": id,
		"kategorie": kategorie,
		"lager": lager,
		"basis": maxi(0, int(raw.get("basis", 0))),
		"name_de": str(raw.get("name_de", "")),
		"name_en": str(raw.get("name_en", raw.get("name_de", ""))),
	}
