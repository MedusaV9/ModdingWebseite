extends TestCase
## M2/ORTE — Text-Tor für den eigenen Besitz: DE/EN-Parität von
## `strings/*/city.json` + `strings/*/phone.json` und Struktur-Parität der
## fünf neuen Stadt-Dialoge (`data/dialoge/*.json` ↔ `dialoge/en/*.json`).
##
## Das W1c-Tor `test_ui_strings.gd` prüft dasselbe breiter, läuft aber mit
## einem EIGENEN Runner — dieser Test hängt die ORTE-Dateien in den
## Haupt-Runner, damit ein fehlender EN-Satz sofort auffällt.

const DIALOG_DIR := "res://scripts/city/data/dialoge"
const DIALOG_EN_DIR := "res://scripts/city/data/dialoge/en"
const MEINE_DATEIEN: Array[String] = ["city.json", "phone.json"]
## Die W3a-Reise-/Taxi-Texte (`travel.*`) tragen noch Emojis aus der
## Web-Referenz. Die Emoji-Regel gilt für ALLES, was M2/ORTE neu schreibt —
## der Altbestand wird hier bewusst nicht mitgerissen (eigener Auftrag).
const EMOJI_ALTBESTAND := "travel."
## Die Dialoge der fünf neuen Orte.
const NEUE_DIALOGE: Array[String] = [
	"pow.json", "post.json", "autohaus.json", "baumarkt.json", "wochenmarkt.json"
]


func test_meine_strings_sind_de_en_paritaetisch() -> void:
	for datei in MEINE_DATEIEN:
		var de := _flach("res://strings/de/%s" % datei)
		var en := _flach("res://strings/en/%s" % datei)
		assert_true(de.size() > 0, "%s: DE ist leer" % datei)
		for key: String in de:
			assert_true(en.has(key), "%s: EN fehlt Key %s" % [datei, key])
		for key: String in en:
			assert_true(de.has(key), "%s: DE fehlt Key %s" % [datei, key])


func test_meine_strings_haben_gleiche_platzhalter() -> void:
	var regex := RegEx.new()
	regex.compile("\\{([A-Za-z0-9_]+)\\}")
	for datei in MEINE_DATEIEN:
		var de := _flach("res://strings/de/%s" % datei)
		var en := _flach("res://strings/en/%s" % datei)
		for key: String in de:
			if not (de[key] is String) or not (en.get(key) is String):
				continue
			assert_eq(
				_platzhalter(regex, str(en[key])),
				_platzhalter(regex, str(de[key])),
				"%s/%s: {platzhalter} weichen ab" % [datei, key]
			)


func test_deutsch_sagt_muenzen_und_keine_rohen_emojis() -> void:
	for datei in MEINE_DATEIEN:
		var de := _flach("res://strings/de/%s" % datei)
		for key: String in de:
			if not (de[key] is String) or key.begins_with(EMOJI_ALTBESTAND):
				continue
			var text := str(de[key])
			assert_false(text.contains("Coins"), "%s/%s sagt „Coins“ statt „Münzen“" % [datei, key])
			assert_false(text.contains("..."), "%s/%s nutzt ... statt …" % [datei, key])
			for zeichen in text:
				assert_true(
					zeichen.unicode_at(0) < 0x1F000, "%s/%s enthält ein rohes Emoji" % [datei, key]
				)


func test_phone_domain_ist_vollstaendig() -> void:
	var de := _flach("res://strings/de/phone.json")
	for key: String in de:
		assert_true(key.begins_with("phone."), "phone.json darf nur phone.*-Keys haben: %s" % key)
	for app: Dictionary in PhoneApps.alle():
		assert_true(de.has(str(app["name_key"])), "phone.json fehlt %s" % app["name_key"])
		assert_true(de.has(str(app["text_key"])), "phone.json fehlt %s" % app["text_key"])


func test_neue_dialoge_haben_ein_en_pendant() -> void:
	for datei in NEUE_DIALOGE:
		var de_pfad := "%s/%s" % [DIALOG_DIR, datei]
		var en_pfad := "%s/%s" % [DIALOG_EN_DIR, datei]
		assert_true(FileAccess.file_exists(de_pfad), "DE-Dialog fehlt: %s" % de_pfad)
		assert_true(FileAccess.file_exists(en_pfad), "EN-Dialog fehlt: %s" % en_pfad)
		var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(de_pfad))
		var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(en_pfad))
		assert_true(de is Dictionary and en is Dictionary, "%s parst nicht" % datei)
		if not (de is Dictionary and en is Dictionary):
			continue
		assert_eq(str(en.get("start")), str(de.get("start")), "%s: Startknoten" % datei)
		var de_nodes: Dictionary = de.get("nodes", {})
		var en_nodes: Dictionary = en.get("nodes", {})
		assert_eq(en_nodes.keys().size(), de_nodes.keys().size(), "%s: Knotenzahl" % datei)
		for node_id: String in de_nodes:
			assert_true(en_nodes.has(node_id), "%s: EN fehlt Knoten %s" % [datei, node_id])


func test_neue_dialoge_laufen_im_runner() -> void:
	for datei in NEUE_DIALOGE:
		var pfad := "%s/%s" % [DIALOG_DIR, datei]
		var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(pfad))
		assert_true(runner.ist_geladen(), "%s lädt nicht" % datei)
		assert_true(runner.text().size() >= 1, "%s: Startknoten ohne Text" % datei)
		assert_ne(runner.sprecher(), "", "%s: Startknoten ohne Sprecher" % datei)
		var optionen := runner.optionen()
		assert_true(optionen.size() >= 1, "%s: Startknoten ohne Auswahl" % datei)


func test_dialoge_oeffnen_ihren_laden() -> void:
	# Jeder Händler-Ort muss aus dem Dialog heraus sein Sheet öffnen können —
	# sonst hängt der Spieler im Gespräch fest (Effekt "laden").
	for datei in NEUE_DIALOGE:
		var roh := FileAccess.get_file_as_string("%s/%s" % [DIALOG_DIR, datei])
		assert_true(roh.contains('"laden"'), "%s hat keinen laden-Effekt" % datei)


func _flach(pfad: String) -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	if parsed is Dictionary:
		_flatten("", parsed, out)
	return out


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		var value: Variant = node[key]
		if value is Dictionary:
			_flatten(full, value, out)
		else:
			out[full] = value


func _platzhalter(regex: RegEx, text: String) -> Array:
	var names: Array = []
	for m in regex.search_all(text):
		names.append(m.get_string(1))
	names.sort()
	return names
