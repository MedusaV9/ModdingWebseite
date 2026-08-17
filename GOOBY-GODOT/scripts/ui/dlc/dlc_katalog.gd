class_name DlcKatalog
extends RefCounted
## Daten-Sicht auf den DLC-Hub-Katalog (W14/DLCHUB) — PURE + static, Muster
## RanchKatalog. Quelle: Domain `dlcs` der ContentRegistry (append-by-id,
## Pack `content/dlc/` — per Update-Pack mit höherer Priorität überschattbar,
## so wird ein „kommt_bald“-Eintrag ohne App-Update „verfuegbar“). Läuft die
## Registry nicht (isolierte Test-SceneTrees), wird die eingebaute Pack-Datei
## direkt gelesen — der Hub bleibt funktionsfähig.
##
## Status-Modell: das JSON kennt nur die REDAKTIONELLEN Stufen `verfuegbar` /
## `kommt_bald`; der ANZEIGE-Status pro Spielstand kommt aus status_fuer()
## (installiert/verfuegbar/gesperrt/kommt_bald — Kaufstand via RanchState/
## GoobyeState, Level-Gate via RanchKatalog/GoobyeKatalog; G5/P24 hat
## „Goo und Bye“ nach exakt dem Ranch-Muster spielbar geschaltet).

const PACK_DOMAIN := "dlcs"
const PACK_DATEI := "res://content/dlc/data/dlcs.json"

## Abgeleitete Anzeige-Status (status_fuer).
const STATUS_INSTALLIERT := "installiert"
const STATUS_VERFUEGBAR := "verfuegbar"
const STATUS_GESPERRT := "gesperrt"
const STATUS_KOMMT_BALD := "kommt_bald"

## Aktionen hinter dem Detail-Knopf (aktion_fuer).
const AKTION_HOF := &"hof"
const AKTION_ANGEBOT := &"angebot"
const AKTION_GESPERRT := &"gesperrt"
const AKTION_BALD := &"bald"

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Array = []
static var _loaded := false


## Alle DLC-Einträge in Pack-Reihenfolge (tiefe Kopien).
static func eintraege() -> Array:
	if not _loaded:
		_cache = _lade_items()
		_loaded = true
	var out: Array = []
	for eintrag: Variant in _cache:
		if eintrag is Dictionary:
			out.append((eintrag as Dictionary).duplicate(true))
	return out


## Eintrag per id ({} = unbekannt).
static func eintrag(id: String) -> Dictionary:
	for kandidat: Dictionary in eintraege():
		if str(kandidat.get("id", "")) == id:
			return kandidat
	return {}


## Anzeige-Status eines Eintrags für DIESEN Spielstand. Ranch und
## Goo und Bye (G5/P24) haben echten Kauf-/Level-Stand; weitere kaufbare
## DLCs docken hier an.
static func status_fuer(dlc: Dictionary, gs: Object) -> String:
	if str(dlc.get("status", "")) != STATUS_VERFUEGBAR:
		return STATUS_KOMMT_BALD
	match str(dlc.get("id", "")):
		"ranch":
			if RanchState.ist_gekauft(gs):
				return STATUS_INSTALLIERT
			if not RanchState.ist_freigeschaltet(gs):
				return STATUS_GESPERRT
		"goo_und_bye":
			if GoobyeState.ist_gekauft(gs):
				return STATUS_INSTALLIERT
			if not GoobyeState.ist_freigeschaltet(gs):
				return STATUS_GESPERRT
		"mcgooby":
			# W19/McGooby-B: Kauf-Gate nach Goobye-Muster. Die Probeschicht
			# bleibt als Tages-Demo trotzdem spielbar (Demo-Knopf im
			# Detail-Sheet, DlcScreen._baue_detail_aktion).
			if McGoobyState.ist_gekauft(gs):
				return STATUS_INSTALLIERT
			if not McGoobyState.ist_freigeschaltet(gs):
				return STATUS_GESPERRT
	return STATUS_VERFUEGBAR


## Welche Aktion der Detail-Knopf auslöst: „Losreiten“ (Hof), das bestehende
## Ranch-Angebots-Sheet, ein Level-Gate-Hinweis oder der Kommt-bald-Gag.
static func aktion_fuer(dlc: Dictionary, gs: Object) -> StringName:
	match status_fuer(dlc, gs):
		STATUS_INSTALLIERT:
			return AKTION_HOF
		STATUS_VERFUEGBAR:
			return AKTION_ANGEBOT if str(dlc.get("route", "")) != "" else AKTION_BALD
		STATUS_GESPERRT:
			return AKTION_GESPERRT
		_:
			return AKTION_BALD


## Lokalisierter Text-Feldzugriff (`teaser`/`unlock` → `<feld>_<locale>`,
## DE als Fallback — die Texte liegen bewusst BEIDSPRACHIG im Pack).
static func text_von(dlc: Dictionary, feld: String) -> String:
	var wert: Variant = dlc.get("%s_%s" % [feld, I18nService.get_locale()])
	if wert is String and not (wert as String).is_empty():
		return wert
	return str(dlc.get("%s_de" % feld, ""))


## Lokalisierte Features-Stichpunkte (Fallback DE).
static func features_von(dlc: Dictionary) -> Array:
	var wert: Variant = dlc.get("features_%s" % I18nService.get_locale())
	if wert is Array and not (wert as Array).is_empty():
		return wert
	var fallback: Variant = dlc.get("features_de", [])
	return fallback if fallback is Array else []


## Unlock-Zeile fürs Detail-Sheet. Die Vorlagen tragen {level}/{preis}
## und werden aus dem Balance-Pack gefüllt (EINE Wahrheit: Ranch-/
## GoobyeKatalog) — ein Preis-Update per Pack ändert die Anzeige ohne
## Textpflege.
static func unlock_text(dlc: Dictionary) -> String:
	var vorlage := text_von(dlc, "unlock")
	match str(dlc.get("id", "")):
		"ranch":
			return vorlage.format(
				{"level": RanchKatalog.freischalt_level(), "preis": RanchKatalog.preis()}
			)
		"goo_und_bye":
			return vorlage.format(
				{"level": GoobyeKatalog.freischalt_level(), "preis": GoobyeKatalog.preis()}
			)
		"mcgooby":
			return vorlage.format(
				{"level": McGoobyKatalog.freischalt_level(), "preis": McGoobyKatalog.preis()}
			)
	return vorlage


## Cache leeren (Tests / nach Pack-Update per content_reloaded).
static func reset_cache() -> void:
	_cache = []
	_loaded = false


static func _lade_items() -> Array:
	var registry := _registry()
	if registry != null and registry.has_method("get_items"):
		var raw: Variant = registry.get_items(PACK_DOMAIN)
		if raw is Array and not (raw as Array).is_empty():
			return raw
	return _lade_pack_datei()


## Fallback ohne Registry: die eingebaute Pack-Datei direkt lesen.
static func _lade_pack_datei() -> Array:
	if not FileAccess.file_exists(PACK_DATEI):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_DATEI))
	if not (parsed is Dictionary):
		push_warning("DLC-Pack-Datei kaputt: %s" % PACK_DATEI)
		return []
	var items: Variant = (parsed as Dictionary).get("items", [])
	return items if items is Array else []


static func _registry() -> Object:
	if registry_override != null:
		return registry_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	return null
