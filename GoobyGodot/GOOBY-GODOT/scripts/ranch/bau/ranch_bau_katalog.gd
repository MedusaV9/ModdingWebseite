class_name RanchBauKatalog
extends RefCounted
## Bau-Katalog des Ranch-Ausbaus (RW-4, IDEAS-3 §6) — PURE Daten-Sicht auf
## `bau_balance.json`. Kosten/Stufen/Effekte sind DATEN und über den
## Balance-Namespace "ranchbau" der ContentRegistry Content-Pack-updatebar
## (Muster = RanchWirtschaft). Bauen kostet GOLD, niemals Energie.
##
## Item-Kategorien:
## - anlage: Ausbauten mit Stufen + spürbarem Nutzen (Boxen, Weide, ...);
##   max. EINE Instanz auf dem Grid, Stufe liegt in ranch.bau.anlagen.
##   Sonderfall "weidezaun": upgrade=true — keine Platzierung, wertet ALLE
##   gesetzten Zäune auf (Optik + Sauberkeits-Effekt).
## - deko: 1×1-Schmuck (40–120 G, je 5 Stück +1 Stilpunkt, max +10).
## - boden: Wege/Beläge (BODEN-Layer, Objekte dürfen drauf stehen).
## - zaun: KANTEN-Item (RanchGridData-Kanten, 1 Kante = 3 m).

const BALANCE_PATH := "res://scripts/ranch/bau/bau_balance.json"
const BALANCE_NAMESPACE := "ranchbau"

const KATEGORIEN: Array[String] = ["anlage", "deko", "boden", "zaun"]


## Effektive Balance: eingebautes JSON + Registry-Override (Deep-Merge).
## registry=null → Autoload /root/ContentRegistry (fehlt es, z. B. in
## Pure-Tests, gilt der eingebaute Stand).
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := read_json(BALANCE_PATH)
	var reg := registry if registry != null else _autoload_registry()
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_deep_merge(balance, overrides)
	return balance


## Alle Item-Defs (id → normalisierte Def) für RanchGridData + UI.
## Def-Keys: id, kategorie, layer, footprint (Vector2i), kante (bool),
## kosten (Platzierungs-Kosten = Stufe-1-Preis bei Anlagen), stufen (Array),
## upgrade (bool, nur weidezaun), name_key.
static func defs(balance: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var anlagen := _dict(balance, "anlagen")
	for id: String in anlagen:
		var roh: Dictionary = anlagen[id]
		var stufen: Array = roh.get("stufen") if roh.get("stufen") is Array else [0]
		var fp_raw: Array = roh.get("footprint") if roh.get("footprint") is Array else [1, 1]
		out[id] = {
			"id": id,
			"kategorie": "anlage",
			"layer": RanchGridData.Layer.OBJEKT,
			"footprint": Vector2i(int(fp_raw[0]), int(fp_raw[1])),
			"kante": false,
			"kosten": maxi(0, int(_num(stufen[0], 0.0))),
			"stufen": stufen,
			"upgrade": bool(roh.get("upgrade", false)),
			"name_key": "rbau.item.%s" % id,
		}
	var gruppen := [
		{"json": "deko", "kategorie": "deko", "layer": RanchGridData.Layer.OBJEKT, "kante": false},
		{
			"json": "boeden",
			"kategorie": "boden",
			"layer": RanchGridData.Layer.BODEN,
			"kante": false
		},
		{"json": "zaeune", "kategorie": "zaun", "layer": RanchGridData.Layer.OBJEKT, "kante": true},
	]
	for gruppe: Dictionary in gruppen:
		var eintraege := _dict(balance, str(gruppe["json"]))
		for id: String in eintraege:
			out[id] = {
				"id": id,
				"kategorie": str(gruppe["kategorie"]),
				"layer": int(gruppe["layer"]),
				"footprint": Vector2i.ONE,
				"kante": bool(gruppe["kante"]),
				"kosten": maxi(0, int(_num(_dict(eintraege, id).get("kosten"), 0.0))),
				"stufen": [],
				"upgrade": false,
				"name_key": "rbau.item.%s" % id,
			}
	return out


## Ids einer Kategorie (sortiert — deterministische UI-Reihenfolge).
static func ids(balance: Dictionary, kategorie: String) -> Array:
	var out: Array = []
	var alle := defs(balance)
	for id: String in alle:
		if alle[id]["kategorie"] == kategorie:
			out.append(id)
	out.sort()
	return out


## Stufen-Kostenliste einer Anlage ([] = keine Anlage).
static func stufen_kosten(balance: Dictionary, anlage_id: String) -> Array:
	var roh := _dict(_dict(balance, "anlagen"), anlage_id)
	return roh.get("stufen") if roh.get("stufen") is Array else []


## Maximale Stufe einer Anlage (0 = unbekannt).
static func max_stufe(balance: Dictionary, anlage_id: String) -> int:
	return stufen_kosten(balance, anlage_id).size()


## Kosten der NÄCHSTEN Stufe (aktuelle Stufe 1-basiert; -1 = ausgebaut).
static func naechste_stufe_kosten(balance: Dictionary, anlage_id: String, stufe: int) -> int:
	var stufen := stufen_kosten(balance, anlage_id)
	if stufe < 0 or stufe >= stufen.size():
		return -1
	return maxi(0, int(_num(stufen[stufe], 0.0)))


## Grid-Maße (Vector2i) aus der Balance.
static func grid_groesse(balance: Dictionary) -> Vector2i:
	var grid := _dict(balance, "grid")
	return Vector2i(int(_num(grid.get("breite"), 16.0)), int(_num(grid.get("tiefe"), 16.0)))


## Zonen-Tabelle: id → {"rect": Rect2i, "kosten": int}.
static func zonen(balance: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var roh := _dict(_dict(balance, "grid"), "zonen")
	for id: String in roh:
		var zone := _dict(roh, id)
		var rect_raw: Array = zone.get("rect") if zone.get("rect") is Array else [0, 0, 0, 0]
		out[id] = {
			"rect": Rect2i(int(rect_raw[0]), int(rect_raw[1]), int(rect_raw[2]), int(rect_raw[3])),
			"kosten": maxi(0, int(_num(zone.get("kosten"), 0.0))),
		}
	return out


## Anteil (0..1) der Baukosten, der beim Abriss zurückkommt.
static func abriss_erstattung(balance: Dictionary) -> float:
	return clampf(_num(balance.get("abriss_erstattung"), 0.5), 0.0, 1.0)


## Effekt-Block ({} wenn leer).
static func effekte(balance: Dictionary) -> Dictionary:
	return _dict(balance, "effekte")


## Wirtschafts-Modell (Einnahmen-Schätzung + Grind-Grenzen) für den
## Bilanz-Test — offene Daten statt Bauchgefühl.
static func wirtschaft_modell(balance: Dictionary) -> Dictionary:
	return _dict(balance, "wirtschaft_modell")


## Summe der geschätzten Einnahmen pro aktiver Spielstunde.
static func einnahmen_pro_stunde(balance: Dictionary) -> int:
	var quellen := _dict(wirtschaft_modell(balance), "einnahmen_pro_stunde")
	var summe := 0
	for quelle: String in quellen:
		summe += maxi(0, int(_num(quellen[quelle], 0.0)))
	return summe


## JSON-Datei als Dictionary lesen ({} bei Fehler).
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("RanchBauKatalog: Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("RanchBauKatalog: JSON kaputt: %s" % path)
		return {}
	return parsed


static func _autoload_registry() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	return null


static func _deep_merge(base: Dictionary, overrides: Dictionary) -> void:
	for k: Variant in overrides.keys():
		if base.get(k) is Dictionary and overrides[k] is Dictionary:
			_deep_merge(base[k], overrides[k])
		else:
			base[k] = overrides[k]


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
