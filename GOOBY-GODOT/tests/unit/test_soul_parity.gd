extends TestCase
## FB-6/SEELE: DE/EN-Parität (DoD) + Konsistenz Content-Pack ↔ Strings.
## Jeder Key existiert in BEIDEN Sprachen mit identischen {platzhaltern},
## und jeder text_key aus content/soul/data/soul.json ist wirklich da.

const DE_PATH := "res://strings/de/soul.json"
const EN_PATH := "res://strings/en/soul.json"
const PACK_PATH := "res://content/soul/data/soul.json"


func _flat(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		fail_test("Strings-Datei kaputt: %s" % path)
		return {}
	var out := {}
	_flatten("", parsed, out)
	return out


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flatten(full, node[key], out)
		else:
			out[full] = node[key]


func _placeholders(text: String) -> Array[String]:
	var out: Array[String] = []
	var regex := RegEx.new()
	regex.compile("\\{(\\w+)\\}")
	for hit in regex.search_all(text):
		out.append(hit.get_string(1))
	out.sort()
	return out


func test_de_en_gleiche_keys() -> void:
	var de := _flat(DE_PATH)
	var en := _flat(EN_PATH)
	assert_true(de.size() > 0, "DE-Strings vorhanden")
	for key: String in de:
		assert_true(en.has(key), "EN fehlt: %s" % key)
	for key: String in en:
		assert_true(de.has(key), "DE fehlt: %s" % key)


func test_de_en_gleiche_platzhalter() -> void:
	var de := _flat(DE_PATH)
	var en := _flat(EN_PATH)
	for key: String in de:
		if not en.has(key):
			continue
		assert_eq(
			_placeholders(str(en[key])),
			_placeholders(str(de[key])),
			"Platzhalter weichen ab: %s" % key
		)


func test_alle_pack_textkeys_existieren() -> void:
	var de := _flat(DE_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_PATH))
	assert_true(parsed is Dictionary and parsed.get("items") is Array, "Pack lesbar")
	var gesehen := {}
	for item: Dictionary in parsed.get("items", []):
		var id := str(item.get("id", ""))
		assert_false(id.is_empty(), "Def ohne id")
		assert_false(gesehen.has(id), "doppelte Def-Id: %s" % id)
		gesehen[id] = true
		for text_key: Variant in item.get("text_keys", []):
			assert_true(de.has(str(text_key)), "text_key fehlt in DE: %s" % text_key)


func test_erinnerungs_keys_existieren() -> void:
	# SoulMemories baut text_keys im Code — jeder davon muss existieren.
	var de := _flat(DE_PATH)
	var keys := [
		"soul.erinnerung.rekord",
		"soul.erinnerung.urlaub",
		"soul.erinnerung.kitzeln",
		"soul.erinnerung.garten",
		"soul.erinnerung.streak",
		"soul.erinnerung.funkelpark",
		"soul.erinnerung.spielzeit",
	]
	for key: Variant in keys:
		assert_true(de.has(str(key)), "Erinnerungs-Key fehlt: %s" % key)


func test_geburtstags_panel_keys_existieren() -> void:
	var de := _flat(DE_PATH)
	for key: Variant in [
		"soul.geburtstag_panel.titel",
		"soul.geburtstag_panel.monat",
		"soul.geburtstag_panel.tag",
		"soul.geburtstag_panel.speichern",
		"soul.geburtstag_panel.abbrechen",
		"soul.geburtstag_panel.danke",
	]:
		assert_true(de.has(str(key)), "Panel-Key fehlt: %s" % key)
