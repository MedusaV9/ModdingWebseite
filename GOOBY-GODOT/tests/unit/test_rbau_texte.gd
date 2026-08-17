extends TestCase
## RW-4 — Text-Tor für strings/*/ranch_bau.json (Domains rbau + rdorf):
## DE/EN-Parität, {platzhalter}-Gleichheit, keine Emojis, und JEDES
## Katalog-Item (Bau + Dorf-Waren + Händler-Pferde) hat seinen Namen.

const DATEI := "ranch_bau.json"


func _flach(pfad: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	var flat: Dictionary = {}
	if parsed is Dictionary:
		_flatten("", parsed, flat)
	return flat


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var pfad := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flatten(pfad, node[key], out)
		else:
			out[pfad] = node[key]


func test_de_en_paritaet() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	var en := _flach("res://strings/en/%s" % DATEI)
	assert_true(de.size() > 0, "DE ist leer")
	for key: String in de:
		assert_true(en.has(key), "EN fehlt Key %s" % key)
	for key: String in en:
		assert_true(de.has(key), "DE fehlt Key %s" % key)


func test_platzhalter_stimmen_ueberein() -> void:
	var regex := RegEx.new()
	regex.compile("\\{([A-Za-z0-9_]+)\\}")
	var de := _flach("res://strings/de/%s" % DATEI)
	var en := _flach("res://strings/en/%s" % DATEI)
	for key: String in de:
		if not (de[key] is String) or not (en.get(key) is String):
			continue
		var de_ph: Array = []
		for m in regex.search_all(str(de[key])):
			de_ph.append(m.get_string(1))
		de_ph.sort()
		var en_ph: Array = []
		for m in regex.search_all(str(en[key])):
			en_ph.append(m.get_string(1))
		en_ph.sort()
		assert_eq(en_ph, de_ph, "%s: {platzhalter} weichen ab" % key)


func test_keine_emojis() -> void:
	for locale in ["de", "en"]:
		var flat := _flach("res://strings/%s/%s" % [locale, DATEI])
		for key: String in flat:
			if not (flat[key] is String):
				continue
			for i in str(flat[key]).length():
				var code := str(flat[key]).unicode_at(i)
				assert_true(
					code < 0x1F000 and not (code >= 0x2600 and code <= 0x27BF),
					"%s/%s: Emoji im Text" % [locale, key]
				)


func test_jedes_bau_item_hat_einen_namen() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	var defs := RanchBauKatalog.defs(RanchBauKatalog.load_balance())
	for id: String in defs:
		var key := str(defs[id]["name_key"])
		assert_true(de.has(key), "DE fehlt Item-Name %s" % key)
	# Zonen + Nutzen-Texte der Anlagen.
	for zone_id: String in RanchBauKatalog.zonen(RanchBauKatalog.load_balance()):
		assert_true(de.has("rbau.zone.%s" % zone_id), "Zonen-Name %s fehlt" % zone_id)
	for id: String in RanchBauKatalog.ids(RanchBauKatalog.load_balance(), "anlage"):
		assert_true(de.has("rbau.nutzen.%s" % id), "Nutzen-Text %s fehlt" % id)


func test_jede_dorf_ware_hat_einen_namen() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	var bal := DorfKatalog.load_balance()
	for laden_id: String in DorfKatalog.laeden(bal):
		assert_true(de.has("rdorf.laden.%s" % laden_id), "Laden-Name %s fehlt" % laden_id)
		assert_true(de.has("rdorf.npc.%s" % laden_id), "NPC-Name %s fehlt" % laden_id)
		assert_true(de.has("rdorf.gruss.%s" % laden_id), "Gruß %s fehlt" % laden_id)
	for ware: Dictionary in DorfKatalog.futter_waren(bal):
		var key := "rdorf.waren.%s" % str(ware.get("id"))
		assert_true(de.has(key), "Waren-Name %s fehlt" % key)
	for ware: Dictionary in DorfKatalog.schmiede_waren(bal):
		var key := "rdorf.waren.%s" % str(ware.get("id"))
		assert_true(de.has(key), "Waren-Name %s fehlt" % key)
	for eintrag: Dictionary in DorfKatalog.pferde_pool(bal):
		var key := str(eintrag.get("name_key", ""))
		assert_true(de.has(key), "Pferde-Name %s fehlt" % key)


func test_fehlercodes_haben_texte() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for code in [
		RanchBauState.FEHLER_ZU_TEUER,
		RanchBauState.FEHLER_SCHON_GEBAUT,
		RanchBauState.FEHLER_NICHT_GEBAUT,
		RanchBauState.FEHLER_AUSGEBAUT,
		RanchBauState.FEHLER_UNBEKANNT,
		RanchGridData.REASON_OOB,
		RanchGridData.REASON_GESPERRT,
		RanchGridData.REASON_OCCUPIED,
	]:
		assert_true(de.has("rbau.fehler.%s" % code), "rbau.fehler.%s fehlt" % code)
	for code in [
		DorfWirtschaft.FEHLER_ZU_TEUER,
		DorfWirtschaft.FEHLER_LAGER_VOLL,
		DorfWirtschaft.FEHLER_LAGER_LEER,
		DorfWirtschaft.FEHLER_SCHON_GEKAUFT,
		DorfWirtschaft.FEHLER_KEIN_LAGER,
		DorfWirtschaft.FEHLER_NICHT_GEKAUFT,
		DorfHaendler.FEHLER_STALL_VOLL,
		DorfHaendler.FEHLER_NICHT_IM_ANGEBOT,
		DorfHaendler.FEHLER_LETZTES_PFERD,
		DorfHaendler.FEHLER_KEIN_PFERD,
	]:
		assert_true(de.has("rdorf.fehler.%s" % code), "rdorf.fehler.%s fehlt" % code)
