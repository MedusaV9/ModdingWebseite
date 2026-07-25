class_name CosmeticsCatalog
extends RefCounted
## Garderoben-Katalog (CONTENT-A): die EINZIGE Sicht auf alle Cosmetics.
##
## Quelle ist ausschließlich die W2b-ContentRegistry (Domain "cosmetics") —
## also eingebautes `content/cosmetics/data/cosmetics.json` PLUS jedes per
## Auto-Updater nachgelieferte Pack. Neue Items brauchen deshalb KEIN
## App-Update: Pack mit höherer Version drüber, `ContentRegistry.reload()`,
## fertig. Nichts im Spiel liest Cosmetics-Dateien direkt.
##
## Roh-Eintrag (Pack-Autoren-Vertrag, alles optional außer id/kategorie):
##   id, kategorie (hut|brille|hals|ruecken|fell), name_de/_en, desc_de/_en,
##   preis, rarity (haeufig|selten|episch|legendaer), min_level,
##   build (Builder-Id in CosmeticBuilders), farben (Array Hex),
##   params (Dictionary, builder-spezifisch), standard (bool, gratis besessen)
## Legacy-Schreibweisen werden weich übersetzt: `type`/`slot` statt
## `kategorie`, englische Kategorien (hat/glasses/neck/back/fur), `price`
## statt `preis`, `name`/`desc`. Kaputte Einträge fliegen still raus
## (validate() nennt sie beim Namen) — ein Pack darf die Garderobe nie killen.

## Anzeige-Reihenfolge der Tabs im Wardrobe-Screen.
const KATEGORIEN: Array[String] = ["hut", "brille", "hals", "ruecken", "fell"]
## Kategorie → Slot-Key im Save (`cosmetics.outfits.equipped`, save_schema v5).
## "fell" fehlt bewusst: Fell lebt in `cosmetics.fur` (eigener Ein-Slot-Zweig).
const SLOT_BY_KATEGORIE := {"hut": "hat", "brille": "glasses", "hals": "neck", "ruecken": "back"}
const FELL := "fell"
const RARITIES: Array[String] = ["haeufig", "selten", "episch", "legendaer"]
## Fell ist NUR im Shop kaufbar (User-Regel) — nie Beute, nie Questlohn.
const NUR_IM_SHOP: Array[String] = ["fell"]
const DOMAIN := "cosmetics"

## Toleranz-Tabelle für Fremdschreibweisen (Web-Export, M1-Testdaten).
const KATEGORIE_ALIAS := {
	"hat": "hut",
	"hut": "hut",
	"glasses": "brille",
	"brille": "brille",
	"neck": "hals",
	"hals": "hals",
	"back": "ruecken",
	"ruecken": "ruecken",
	"fur": "fell",
	"fell": "fell",
}

static var _cache: Array = []
static var _cache_key := ""
static var _injected := false


## Alle gültigen Items in Katalog-Reihenfolge (normalisiert, gecacht bis zum
## nächsten Pack-Reload). Ohne ContentRegistry-Autoload leer — Tests injizieren
## über `set_items()`.
static func all() -> Array:
	if _injected:
		return _cache
	var key := _registry_key()
	if key != _cache_key:
		_cache = normalize_all(_raw_items())
		_cache_key = key
	return _cache


## Items einer Kategorie (Katalog-Reihenfolge).
static func by_kategorie(kategorie: String) -> Array:
	var out: Array = []
	for def: Dictionary in all():
		if def["kategorie"] == kategorie:
			out.append(def)
	return out


## Def zu einer Id ({} wenn unbekannt — Aufrufer degradieren weich).
static func by_id(id: String) -> Dictionary:
	for def: Dictionary in all():
		if def["id"] == id:
			return def
	return {}


static func has(id: String) -> bool:
	return not by_id(id).is_empty()


static func ids() -> Array:
	var out: Array = []
	for def: Dictionary in all():
		out.append(def["id"])
	return out


## Kategorie einer Id ("" wenn unbekannt).
static func kategorie_of(id: String) -> String:
	return str(by_id(id).get("kategorie", ""))


## Save-Slot einer Id ("hat"/"glasses"/"neck"/"back"; "" für Fell/unbekannt).
static func slot_of(id: String) -> String:
	return str(SLOT_BY_KATEGORIE.get(kategorie_of(id), ""))


## Gratis-Items (`standard: true`) — Fell "cream" gehört jedem von Anfang an.
static func standard_ids(kategorie := "") -> Array:
	var out: Array = []
	for def: Dictionary in all():
		if def["standard"] and (kategorie.is_empty() or def["kategorie"] == kategorie):
			out.append(def["id"])
	return out


## Lokalisierter Anzeigename (DE führend, EN nur bei aktiver en-Locale).
static func name_of(def: Dictionary) -> String:
	return _localized(def, "name")


## Lokalisierte Kurzbeschreibung.
static func desc_of(def: Dictionary) -> String:
	return _localized(def, "desc")


## Roh-Liste → normalisierte Defs; kaputte Einträge werden verworfen.
static func normalize_all(raw_items: Array) -> Array:
	var out: Array = []
	var seen := {}
	for raw: Variant in raw_items:
		var def := normalize(raw)
		if def.is_empty() or seen.has(def["id"]):
			continue
		seen[def["id"]] = true
		out.append(def)
	return out


## EIN Roh-Eintrag → normalisierte Def ({} = unbrauchbar).
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var item: Dictionary = raw
	var id := str(item.get("id", "")).strip_edges()
	var kategorie := _kategorie_of_raw(item)
	if id.is_empty() or kategorie.is_empty():
		return {}
	var rarity := str(item.get("rarity", "haeufig"))
	var farben: Array = item.get("farben", []) if item.get("farben") is Array else []
	return {
		"id": id,
		"kategorie": kategorie,
		"slot": str(SLOT_BY_KATEGORIE.get(kategorie, FELL)),
		"name_de": str(item.get("name_de", item.get("name", id))),
		"name_en": str(item.get("name_en", item.get("name_de", item.get("name", id)))),
		"desc_de": str(item.get("desc_de", item.get("desc", ""))),
		"desc_en": str(item.get("desc_en", item.get("desc_de", item.get("desc", "")))),
		"preis": maxi(0, int(item.get("preis", item.get("price", 0)))),
		"rarity": rarity if RARITIES.has(rarity) else "haeufig",
		"min_level": maxi(1, int(item.get("min_level", item.get("minLevel", 1)))),
		"build": str(item.get("build", "")),
		"farben": farben.map(func(value: Variant) -> String: return str(value)),
		"params": item.get("params", {}) if item.get("params") is Dictionary else {},
		"standard": bool(item.get("standard", false)),
	}


## Katalog-Prüfung für Tests/Boot: Liste von Klartext-Fehlern (leer = sauber).
## Läuft absichtlich auf den ROHEN Registry-Daten, damit auch die Einträge
## auffallen, die normalize() still verwirft.
static func validate(raw_items: Array) -> Array:
	var errors: Array = []
	var seen := {}
	for raw: Variant in raw_items:
		if not (raw is Dictionary):
			errors.append("Eintrag ist kein Objekt")
			continue
		var item: Dictionary = raw
		var id := str(item.get("id", "")).strip_edges()
		if id.is_empty():
			errors.append("Eintrag ohne id")
			continue
		if seen.has(id):
			errors.append("%s: doppelte id" % id)
		seen[id] = true
		var kategorie := _kategorie_of_raw(item)
		if kategorie.is_empty():
			errors.append("%s: unbekannte Kategorie '%s'" % [id, item.get("kategorie", "")])
			continue
		for feld in ["name_de", "name_en", "desc_de", "desc_en"]:
			if str(item.get(feld, "")).strip_edges().is_empty():
				errors.append("%s: Feld '%s' fehlt" % [id, feld])
		if not RARITIES.has(str(item.get("rarity", ""))):
			errors.append("%s: unbekannte rarity '%s'" % [id, item.get("rarity", "")])
		if int(item.get("preis", item.get("price", -1))) < 0:
			errors.append("%s: preis fehlt/negativ" % id)
		if str(item.get("build", "")).strip_edges().is_empty():
			errors.append("%s: build fehlt" % id)
		if kategorie == FELL and (not (item.get("farben") is Array) or item["farben"].size() < 3):
			errors.append("%s: Fell braucht 3 Farben (body/bauch/ohr)" % id)
	return errors


## Test-Hook: Katalog hart setzen (umgeht die Registry). {} bzw. [] = zurück
## auf die Registry-Sicht.
static func set_items(raw_items: Array) -> void:
	if raw_items.is_empty():
		reset_cache()
		return
	_cache = normalize_all(raw_items)
	_cache_key = "injiziert"
	_injected = true


static func reset_cache() -> void:
	_cache = []
	_cache_key = ""
	_injected = false


## Rohe Registry-Items (für validate() und Pack-Merge-Tests).
static func raw_items() -> Array:
	return _raw_items()


static func _localized(def: Dictionary, feld: String) -> String:
	var locale := I18nService.get_locale()
	var key := "%s_%s" % [feld, locale]
	var text := str(def.get(key, ""))
	return text if not text.is_empty() else str(def.get("%s_de" % feld, ""))


static func _kategorie_of_raw(item: Dictionary) -> String:
	for feld in ["kategorie", "type", "slot"]:
		var value := str(item.get(feld, "")).strip_edges().to_lower()
		if KATEGORIE_ALIAS.has(value):
			return KATEGORIE_ALIAS[value]
	return ""


static func _raw_items() -> Array:
	var registry := _registry()
	if registry == null:
		return []
	return registry.get_items(DOMAIN)


## Cache-Schlüssel: Pack-Version der Domain. Nach einem Update-Reload steht da
## eine andere Version → der Katalog baut sich beim nächsten Zugriff neu auf.
static func _registry_key() -> String:
	var registry := _registry()
	if registry == null:
		return ""
	return "%s@%s" % [DOMAIN, registry.version_of(DOMAIN)]


static func _registry() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return null
	return registry
