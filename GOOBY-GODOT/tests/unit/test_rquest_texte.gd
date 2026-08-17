extends TestCase
## RW-3 — Text-Tor fuer den eigenen Besitz: DE/EN-Paritaet von
## `strings/*/ranch_quest.json` (Keys, {platzhalter}, keine rohen Emojis,
## Muenzen statt Coins) plus Vollstaendigkeit: jeder Katalog-NPC hat
## Name/Rolle, jede Katalog-Quest hat Titel/Text, und die Warte-/Ziel-/
## Freischaltungs-Keys der UI existieren.

const DATEI := "ranch_quest.json"

## Keys, ohne die Quest-Log/Freundschafts-UI nicht sprechen koennen.
const PFLICHT_KEYS: Array[String] = [
	"rquest.log.titel",
	"rquest.log.tab_haupt",
	"rquest.log.tab_neben",
	"rquest.log.tab_tages",
	"rquest.log.annehmen",
	"rquest.log.abgeben",
	"rquest.log.wartend_bis",
	"rquest.warte.gleich",
	"rquest.warte.minuten",
	"rquest.warte.stunden",
	"rquest.warte.notify_fertig",
	"rquest.warte.alternative_titel",
	"rquest.warte.alternative_1",
	"rquest.warte.alternative_2",
	"rquest.warte.alternative_3",
	"rquest.warte.alternative_4",
	"rnpc.ui.titel",
	"rnpc.ui.naechste",
	"rnpc.ui.max",
	"rnpc.ui.freischaltungen",
	"rnpc.frei.smalltalk",
	"rnpc.frei.rabatt",
	"rnpc.frei.geschichte",
	"rnpc.frei.quest",
	"rnpc.frei.rezept",
	"rnpc.frei.cosmetic",
]


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
		assert_eq(
			_platzhalter(regex, str(en[key])),
			_platzhalter(regex, str(de[key])),
			"%s: {platzhalter} weichen ab" % key
		)


func test_deutsch_sagt_muenzen_und_keine_rohen_emojis() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for key: String in de:
		if not (de[key] is String):
			continue
		var text := str(de[key])
		assert_false(text.contains("Coins"), "%s sagt Coins statt Muenzen" % key)
		assert_false(text.contains("..."), "%s nutzt ... statt Auslassungszeichen" % key)
		for zeichen in text:
			assert_true(zeichen.unicode_at(0) < 0x1F000, "%s enthaelt ein rohes Emoji" % key)


func test_pflicht_keys_existieren() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for key in PFLICHT_KEYS:
		assert_true(de.has(key), "Pflicht-Key fehlt: %s" % key)


func test_jeder_npc_hat_name_und_rolle() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for npc_id: String in RNpcKatalog.ids():
		assert_true(de.has("rnpc.%s.name" % npc_id), "%s: Name fehlt" % npc_id)
		assert_true(de.has("rnpc.%s.rolle" % npc_id), "%s: Rolle fehlt" % npc_id)


func test_jede_quest_hat_titel_und_text() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for def: Dictionary in RQuestKatalog.alle():
		var quest_id := str(def["id"])
		assert_true(de.has("rquest.q.%s.titel" % quest_id), "%s: Titel fehlt" % quest_id)
		assert_true(de.has("rquest.q.%s.text" % quest_id), "%s: Text fehlt" % quest_id)


func test_alle_ziel_referenzen_sind_lokalisiert() -> void:
	# Jede Orts-/Item-/Aktions-/Strecken-/Disziplin-Referenz aller Quests
	# hat einen DE-Key — sonst zeigt das Quest-Log rohe Ids.
	var de := _flach("res://strings/de/%s" % DATEI)
	var praefix := {
		"gehe_zu": ["ort", "rquest.ort.%s"],
		"sammle": ["item", "rquest.item.%s"],
		"pflege": ["aktion", "rquest.aktion.%s"],
		"reite_strecke": ["strecke", "rquest.strecke.%s"],
		"gewinne_wettbewerb": ["disziplin", "rquest.disziplin.%s"],
	}
	for def: Dictionary in RQuestKatalog.alle():
		for ziel: Dictionary in def.get("ziele", []):
			var typ := str(ziel.get("typ", ""))
			if not praefix.has(typ):
				continue
			var feld: Array = praefix[typ]
			var key: String = str(feld[1]) % str(ziel.get(feld[0], ""))
			assert_true(de.has(key), "%s: Key %s fehlt" % [def.get("id"), key])


func test_i18n_service_liefert_meine_keys() -> void:
	assert_eq(I18nService.t("rnpc.rosi.rolle"), "Stallmeisterin")
	assert_ne(
		I18nService.t("rquest.log.titel"),
		"rquest.log.titel",
		"ranch_quest.json wird vom I18nService geladen"
	)


func _flach(pfad: String) -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	if parsed is Dictionary:
		_flatten("", parsed, out)
	return out


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flatten(full, node[key], out)
		else:
			out[full] = node[key]


func _platzhalter(regex: RegEx, text: String) -> Array:
	var out: Array = []
	for treffer in regex.search_all(text):
		out.append(treffer.get_string(1))
	out.sort()
	return out
