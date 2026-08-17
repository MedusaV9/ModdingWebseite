class_name AutoKatalog
extends RefCounted
## CarDef-Katalog (Doc E §1.4, USER §D48) — PURE. EIN Owning-Modul für
## Autohaus (Kauf + Farbwahl) UND die Fahr-Minispiele (cityDrive/deliveryRush/
## toyRacer, Doc G §6): beide lesen dieselben Stats über `aktives_auto()`,
## damit die Kataloge nicht driften (Doc E §8 Risiko 5).
##
## Save (city-Slice, additiv): `autos` = {id: farbe_hex} (Besitz + gewählte
## Farbe), `aktivesAuto` = id. Der Start-Wagen (`start: true`) gehört immer
## dazu — auch in Alt-Saves, die den Schlüssel noch nicht kennen.

const KATALOG_PFAD := "res://scripts/city/data/cars.json"
const ASSET_DIR := "res://assets/city/autos"


static func daten(pfad := KATALOG_PFAD) -> Dictionary:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("cars.json kaputt: %s" % pfad)
		return {}
	return json.data


static func autos(pfad := KATALOG_PFAD) -> Array:
	var raw: Variant = daten(pfad).get("autos", [])
	return raw if raw is Array else []


static func auto(id: String, pfad := KATALOG_PFAD) -> Dictionary:
	for eintrag: Dictionary in autos(pfad):
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


## Id des Start-Wagens (immer im Besitz).
static func start_auto_id(pfad := KATALOG_PFAD) -> String:
	for eintrag: Dictionary in autos(pfad):
		if bool(eintrag.get("start", false)):
			return str(eintrag.get("id", ""))
	return ""


## GLB-Pfad eines CarDefs ("" wenn unbekannt).
static func glb_pfad(id: String, pfad := KATALOG_PFAD) -> String:
	var eintrag := auto(id, pfad)
	if eintrag.is_empty():
		return ""
	return "%s/%s" % [ASSET_DIR, str(eintrag.get("glb", ""))]


## Deutscher Farbname zum Hex ("" = unbekannt → Hex selbst anzeigen).
static func farb_name(hex: String, pfad := KATALOG_PFAD) -> String:
	return str(daten(pfad).get("farben_namen", {}).get(hex, hex))


## Besitz-Dictionary {auto_id: farbe_hex} inklusive Start-Wagen.
static func besitz(gs: Object, pfad := KATALOG_PFAD) -> Dictionary:
	var out: Dictionary = {}
	var start := start_auto_id(pfad)
	if not start.is_empty():
		var farben: Array = auto(start, pfad).get("farben", ["#FFF4E6"])
		out[start] = str(farben[0]) if not farben.is_empty() else "#FFF4E6"
	if gs == null:
		return out
	var roh: Variant = gs.get_value("city.autos", {})
	if roh is Dictionary:
		for id: String in roh:
			out[id] = str(roh[id])
	return out


static func besitzt(gs: Object, id: String, pfad := KATALOG_PFAD) -> bool:
	return besitz(gs, pfad).has(id)


## Aktives Auto samt Stats + Farbe — DER Contract für die Fahr-Minispiele.
## Rückgabe: CarDef-Kopie + {"farbe": hex}. Fällt auf den Start-Wagen zurück.
static func aktives_auto(gs: Object, pfad := KATALOG_PFAD) -> Dictionary:
	var eigene := besitz(gs, pfad)
	var id := start_auto_id(pfad)
	if gs != null:
		var gewaehlt := str(gs.get_value("city.aktivesAuto", ""))
		if eigene.has(gewaehlt):
			id = gewaehlt
	var eintrag := auto(id, pfad).duplicate(true)
	if eintrag.is_empty():
		return {}
	eintrag["farbe"] = str(eigene.get(id, "#FFF4E6"))
	return eintrag


## Kauf-Prüfung (PURE): reicht das Geld, ist das Auto neu, gibt es die Farbe?
static func kann_kaufen(gs: Object, id: String, farbe: String, pfad := KATALOG_PFAD) -> bool:
	var eintrag := auto(id, pfad)
	if eintrag.is_empty() or besitzt(gs, id, pfad):
		return false
	if not (eintrag.get("farben", []) as Array).has(farbe):
		return false
	if gs == null:
		return false
	return int(gs.get_value("economy.coins", 0)) >= int(eintrag.get("preis", 0))


## Farbe eines BESESSENEN Wagens umlackieren (kostenlos, Doc E §2.4-Gag).
static func lackieren(gs: Object, id: String, farbe: String, pfad := KATALOG_PFAD) -> void:
	if gs == null or not besitzt(gs, id, pfad):
		return
	if not (auto(id, pfad).get("farben", []) as Array).has(farbe):
		return
	_schreibe_besitz(gs, id, farbe)


## Aktives Auto wechseln (nur wenn im Besitz).
static func waehle(gs: Object, id: String, pfad := KATALOG_PFAD) -> void:
	if gs == null or not besitzt(gs, id, pfad):
		return
	gs.set_value("city.aktivesAuto", id)
	gs.notify_slice_changed(CityState.SLICE_ID)


## Besitz eintragen (Geld zieht der Aufrufer über Economy ab).
static func eintragen(gs: Object, id: String, farbe: String) -> void:
	if gs == null:
		return
	_schreibe_besitz(gs, id, farbe)
	gs.set_value("city.aktivesAuto", id)


static func _schreibe_besitz(gs: Object, id: String, farbe: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var city: Dictionary = state.get(CityState.SLICE_ID, {})
			var eigene: Dictionary = city.get("autos", {})
			eigene[id] = farbe
			city["autos"] = eigene
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
