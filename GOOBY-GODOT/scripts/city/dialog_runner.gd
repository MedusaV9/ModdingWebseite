class_name OrtDialogRunner
extends RefCounted
## Dialogbaum-Runner (W3a CITY, Doc E §2.4): PURE Auswertung der JSON-Bäume
## unter scripts/city/data/dialoge/*.json. Die View (dialog_view.gd) rendert
## Text-Bubbles (W1c) + Gebrabbel (W1b) und wendet die Effekte an — der
## Runner kennt weder Nodes noch GameState, nur ein Flags-Dictionary.
##
## Baum-Format: {id, start, nodes:{<id>:{sprecher, text (String|Array),
## optionen:[{text, next, cond}], effekt:[String], ende (bool)}}}.
## cond: "flag:<name>" / "!flag:<name>". effekt: "flag:<name>" (setzen),
## "flag_weg:<name>" (löschen), "item:<id>" (Inventar +1), "laden"
## (Händler-Sheet öffnen).

var baum: Dictionary = {}
var flags: Dictionary = {}
var aktuell := ""


func _init(dialog_baum: Dictionary, aktive_flags: Dictionary = {}) -> void:
	baum = dialog_baum
	flags = aktive_flags
	aktuell = str(baum.get("start", ""))


## Baum aus JSON-Datei laden ({} bei kaputter Datei, Fehler via push_error).
## FIX-G-Handoff: bei nicht-deutschem Locale das en/-Pendant bevorzugen
## (Fallback auf DE, falls das Pendant fehlt).
static func baum_laden(pfad: String) -> Dictionary:
	var real_pfad := _localized_pfad(pfad)
	var raw := FileAccess.get_file_as_string(real_pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("Dialogbaum kaputt: %s" % real_pfad)
		return {}
	return json.data


static func _localized_pfad(pfad: String) -> String:
	var locale := I18nService.get_locale()
	if locale == I18nService.DEFAULT_LOCALE:
		return pfad
	var cand := pfad.get_base_dir().path_join(locale).path_join(pfad.get_file())
	if FileAccess.file_exists(cand):
		return cand
	return pfad


## Eine cond-Klausel gegen die Flags auswerten ("" = immer wahr).
static func cond_ok(cond: String, aktive_flags: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.begins_with("!flag:"):
		return not bool(aktive_flags.get(cond.substr(6), false))
	if cond.begins_with("flag:"):
		return bool(aktive_flags.get(cond.substr(5), false))
	push_warning("Unbekannte Dialog-cond: %s" % cond)
	return false


## Effekt-String → strukturiert: {typ:"flag"|"item"|"laden", name, wert}.
static func effekt_parsen(effekt: String) -> Dictionary:
	if effekt.begins_with("flag_weg:"):
		return {"typ": "flag", "name": effekt.substr(9), "wert": false}
	if effekt.begins_with("flag:"):
		return {"typ": "flag", "name": effekt.substr(5), "wert": true}
	if effekt.begins_with("item:"):
		return {"typ": "item", "name": effekt.substr(5), "wert": true}
	if effekt == "laden":
		return {"typ": "laden", "name": "", "wert": true}
	push_warning("Unbekannter Dialog-effekt: %s" % effekt)
	return {}


func ist_geladen() -> bool:
	return not baum.is_empty() and knoten().has(aktuell)


func knoten() -> Dictionary:
	return baum.get("nodes", {})


func knoten_aktuell() -> Dictionary:
	return knoten().get(aktuell, {})


func sprecher() -> String:
	return str(knoten_aktuell().get("sprecher", ""))


## Textzeilen des aktuellen Knotens (String wird zu 1-elementigem Array).
func text() -> Array[String]:
	var raw: Variant = knoten_aktuell().get("text", [])
	var zeilen: Array[String] = []
	if raw is String:
		zeilen.append(raw)
	elif raw is Array:
		for zeile: Variant in raw:
			zeilen.append(str(zeile))
	return zeilen


## Sichtbare Optionen (cond-gefiltert): [{text, next, index}].
func optionen() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = knoten_aktuell().get("optionen", [])
	if not (raw is Array):
		return out
	for i: int in raw.size():
		var option: Dictionary = raw[i]
		if cond_ok(str(option.get("cond", "")), flags):
			out.append(
				{
					"text": str(option.get("text", "")),
					"next": str(option.get("next", "")),
					"index": i
				}
			)
	return out


## Geparste Effekte des AKTUELLEN Knotens (die View wendet sie beim Betreten
## des Knotens genau einmal an — und spiegelt Flag-Effekte in `flags`).
func effekte() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eintrag: Variant in knoten_aktuell().get("effekt", []):
		var geparst := effekt_parsen(str(eintrag))
		if not geparst.is_empty():
			out.append(geparst)
	return out


## Knoten-eigener Auto-Weiter-Verweis ("" = keiner).
func auto_next() -> String:
	return str(knoten_aktuell().get("next", ""))


## Auto-Weiter folgen (Knoten mit "next" statt Optionen). false = keiner da.
func weiter() -> bool:
	var ziel := auto_next()
	if ziel.is_empty() or not knoten().has(ziel):
		return false
	aktuell = ziel
	_flags_anwenden()
	return true


## Endknoten? (ende:true ODER weder Optionen noch Auto-Weiter).
func ist_ende() -> bool:
	if bool(knoten_aktuell().get("ende", false)):
		return true
	return optionen().is_empty() and auto_next().is_empty()


## Option wählen (Index aus optionen()); wendet Flag-Effekte des ZIEL-Knotens
## auf die lokale Flags-Kopie an, damit Folge-conds sofort stimmen.
## Rückgabe false bei ungültiger Wahl.
func waehlen(options_index: int) -> bool:
	var sichtbar := optionen()
	if options_index < 0 or options_index >= sichtbar.size():
		return false
	var ziel := str(sichtbar[options_index]["next"])
	if not knoten().has(ziel):
		push_warning("Dialog-next unbekannt: %s" % ziel)
		return false
	aktuell = ziel
	_flags_anwenden()
	return true


## Flag-Effekte des aktuellen Knotens in die lokale Flags-Kopie spiegeln.
func _flags_anwenden() -> void:
	for effekt in effekte():
		if str(effekt["typ"]) == "flag":
			if bool(effekt["wert"]):
				flags[str(effekt["name"])] = true
			else:
				flags.erase(str(effekt["name"]))
