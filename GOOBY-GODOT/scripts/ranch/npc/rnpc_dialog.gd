class_name RNpcDialog
extends RefCounted
## Dialog-Anbindung der Ranch-NPCs (RW-3, C1) — nutzt den VORHANDENEN
## OrtDialogRunner (W3a) unverändert wieder: Bäume liegen als JSON unter
## scripts/ranch/npc/data/dialoge/<id>.json (EN-Pendant im en/-Unterordner,
## Runner-Konvention). Dieses Modul ist PURE und übersetzt nur KONTEXT
## (Tageszeit, Wetter, Herzen, Quest-Lage) in Runner-Flags + Startknoten.
##
## Baum-Konvention (jeder NPC hat mindestens diese Knoten, s. PFLICHT_KNOTEN):
##   gruss_morgen/tag/abend + gruss_regen + gruss_freund (Herz >= 4),
##   hub (Options-Drehscheibe), smalltalk_a/b/c (je Freundschaftsstufe),
##   quest_vergabe → quest_annahme|ablehnung, quest_abgabe,
##   geschenk_liebt/mag/normal, geschichte_1/geschichte_2 (Herz-Gates),
##   tschuess.
## Effekt-Konvention (die View meldet Effekte ans Spiel):
##   flag:rw3_quest_annehmen · flag:rw3_quest_abgeben ·
##   flag:rw3_geschichte_1 / _2 (als gehört markieren).

const PFLICHT_KNOTEN: Array[String] = [
	"gruss_morgen",
	"gruss_tag",
	"gruss_abend",
	"gruss_regen",
	"gruss_freund",
	"hub",
	"smalltalk_a",
	"smalltalk_b",
	"smalltalk_c",
	"quest_vergabe",
	"quest_annahme",
	"ablehnung",
	"quest_abgabe",
	"geschenk_liebt",
	"geschenk_mag",
	"geschenk_normal",
	"geschichte_1",
	"geschichte_2",
	"tschuess",
]
const MIN_KNOTEN := 8
## Ab dieser Herz-Stufe grüßt der NPC als Freund (statt nach Uhrzeit).
const FREUND_HERZEN := 4


## Baum eines NPC laden (lokalisiert über die Runner-Konvention).
static func lade_baum(npc_def: Dictionary) -> Dictionary:
	return OrtDialogRunner.baum_laden(str(npc_def.get("dialog", "")))


## Kontext → Runner-Flags. Kontext-Form:
## {stunde: float, wetter: String, herzen: int, quest_vergabe: bool,
##  quest_abgabe: bool, geschenk_dabei: bool, geschichten_gehoert: Array}.
static func kontext_flags(npc_def: Dictionary, kontext: Dictionary) -> Dictionary:
	var flags := {}
	flags["zeit_%s" % zeit_slot(float(kontext.get("stunde", 12.0)))] = true
	if ["regen", "gewitter"].has(str(kontext.get("wetter", ""))):
		flags["regen"] = true
	var herzen := clampi(int(kontext.get("herzen", 0)), 0, RNpcFreundschaft.HERZ_MAX)
	for stufe in range(1, herzen + 1):
		flags["herz%d" % stufe] = true
	flags[_smalltalk_slot(herzen)] = true
	if bool(kontext.get("quest_vergabe", false)):
		flags["quest_vergabe"] = true
	if bool(kontext.get("quest_abgabe", false)):
		flags["quest_abgabe"] = true
	if bool(kontext.get("geschenk_dabei", false)):
		flags["geschenk_dabei"] = true
	var gehoert: Array = (
		kontext.get("geschichten_gehoert") if kontext.get("geschichten_gehoert") is Array else []
	)
	for knoten in ["geschichte_1", "geschichte_2"]:
		var stufe := _geschichte_stufe(npc_def, knoten)
		if stufe > 0 and herzen >= stufe and not gehoert.has(knoten):
			flags["%s_frei" % knoten] = true
	return flags


## Startknoten zum Kontext: Regen schlägt Freundschaft schlägt Uhrzeit —
## fehlt ein Knoten im Baum, fällt die Wahl sicher auf gruss_tag/start.
static func start_knoten(baum: Dictionary, kontext: Dictionary) -> String:
	var nodes: Dictionary = baum.get("nodes", {})
	var kandidaten: Array[String] = []
	if ["regen", "gewitter"].has(str(kontext.get("wetter", ""))):
		kandidaten.append("gruss_regen")
	if int(kontext.get("herzen", 0)) >= FREUND_HERZEN:
		kandidaten.append("gruss_freund")
	kandidaten.append("gruss_%s" % _gruss_slot(float(kontext.get("stunde", 12.0))))
	kandidaten.append("gruss_tag")
	for kandidat in kandidaten:
		if nodes.has(kandidat):
			return kandidat
	return str(baum.get("start", ""))


## Einstiegsknoten für eine Geschenk-Reaktion (RNpcFreundschaft.
## geschenk_reaktion → "liebt"/"mag"/"normal").
static func geschenk_knoten(baum: Dictionary, reaktion: String) -> String:
	var knoten := "geschenk_%s" % reaktion
	if (baum.get("nodes", {}) as Dictionary).has(knoten):
		return knoten
	return "geschenk_normal"


## Fertig konfigurierter Runner (Startknoten + Flags aus dem Kontext).
static func runner(npc_def: Dictionary, kontext: Dictionary) -> OrtDialogRunner:
	var baum := lade_baum(npc_def)
	baum["start"] = start_knoten(baum, kontext)
	return OrtDialogRunner.new(baum, kontext_flags(npc_def, kontext))


## Tageszeit-Slot (morgen 5–11, tag 11–17, abend 17–22, nacht sonst).
static func zeit_slot(stunde: float) -> String:
	if stunde >= 5.0 and stunde < 11.0:
		return "morgen"
	if stunde >= 11.0 and stunde < 17.0:
		return "tag"
	if stunde >= 17.0 and stunde < 22.0:
		return "abend"
	return "nacht"


## Integritätsprüfung eines Baums (leer = gesund): Startknoten existiert,
## alle next-/Options-Ziele existieren, alle Knoten sind vom Start (plus
## den bekannten Direkt-Einstiegen) erreichbar, Texte nicht leer,
## Mindestgröße + Pflicht-Knoten vorhanden.
static func baum_probleme(baum: Dictionary) -> Array[String]:
	var probleme: Array[String] = []
	var nodes: Dictionary = baum.get("nodes", {}) if baum.get("nodes") is Dictionary else {}
	if nodes.size() < MIN_KNOTEN:
		probleme.append("nur %d Knoten (Minimum %d)" % [nodes.size(), MIN_KNOTEN])
	for pflicht in PFLICHT_KNOTEN:
		if not nodes.has(pflicht):
			probleme.append("Pflicht-Knoten fehlt: %s" % pflicht)
	if not nodes.has(str(baum.get("start", ""))):
		probleme.append("Startknoten fehlt: %s" % baum.get("start", ""))
	for id: String in nodes:
		var knoten: Dictionary = nodes[id] if nodes[id] is Dictionary else {}
		var text: Variant = knoten.get("text", "")
		if (
			(text is String and (text as String).is_empty())
			or (text is Array and (text as Array).is_empty())
		):
			probleme.append("%s: Text leer" % id)
		var naechster := str(knoten.get("next", ""))
		if not naechster.is_empty() and not nodes.has(naechster):
			probleme.append("%s: next-Ziel unbekannt (%s)" % [id, naechster])
		for option: Variant in knoten.get("optionen", []):
			if option is Dictionary and not nodes.has(str((option as Dictionary).get("next", ""))):
				probleme.append(
					"%s: Options-Ziel unbekannt (%s)" % [id, (option as Dictionary).get("next", "")]
				)
	for id: String in nodes:
		if not _erreichbar(nodes, id):
			probleme.append("%s: unerreichbar" % id)
	return probleme


static func _smalltalk_slot(herzen: int) -> String:
	if herzen >= 4:
		return "smalltalk_c"
	if herzen >= 2:
		return "smalltalk_b"
	return "smalltalk_a"


## Begrüßungs-Slot: nachts wird der Abend-Gruß benutzt (NPCs haben
## Feierabend, ein eigener Nacht-Text lohnt nicht).
static func _gruss_slot(stunde: float) -> String:
	var slot := zeit_slot(stunde)
	return "abend" if slot == "nacht" else slot


## Herz-Stufe, an der eine Geschichte laut NPC-Definition hängt (0 = keine).
static func _geschichte_stufe(npc_def: Dictionary, knoten: String) -> int:
	for stufe in range(1, RNpcFreundschaft.HERZ_MAX + 1):
		for frei: Variant in RNpcFreundschaft.freischaltungen_der_stufe(npc_def, stufe):
			var passt := (
				frei is Dictionary
				and str((frei as Dictionary).get("typ", "")) == "geschichte"
				and str((frei as Dictionary).get("knoten", "")) == knoten
			)
			if passt:
				return stufe
	return 0


## Erreichbarkeit: vom Start + allen Direkt-Einstiegen (Begrüßungen,
## Geschenk-Reaktionen) aus per next/optionen laufen.
static func _erreichbar(nodes: Dictionary, ziel: String) -> bool:
	var starts: Array[String] = [
		"gruss_morgen",
		"gruss_tag",
		"gruss_abend",
		"gruss_regen",
		"gruss_freund",
		"geschenk_liebt",
		"geschenk_mag",
		"geschenk_normal",
	]
	var offen: Array[String] = []
	for start in starts:
		if nodes.has(start):
			offen.append(start)
	var besucht := {}
	while not offen.is_empty():
		var id: String = offen.pop_back()
		if besucht.has(id) or not nodes.has(id):
			continue
		besucht[id] = true
		if id == ziel:
			return true
		var knoten: Dictionary = nodes[id] if nodes[id] is Dictionary else {}
		var naechster := str(knoten.get("next", ""))
		if not naechster.is_empty():
			offen.append(naechster)
		for option: Variant in knoten.get("optionen", []):
			if option is Dictionary:
				offen.append(str((option as Dictionary).get("next", "")))
	return besucht.has(ziel)
