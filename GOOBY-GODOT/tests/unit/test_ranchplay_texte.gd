extends TestCase
## RANCH-2 — Text-Tor für den eigenen Besitz: DE/EN-Parität von
## `strings/*/ranch_play.json` (Keys, {platzhalter}, keine rohen Emojis,
## „Münzen" statt „Coins"), Pflicht-Keys der Screens und die beiden
## Minigame-Manifeste (game.json → MinigameRegistry-Vertrag).

const DATEI := "ranch_play.json"
const MANIFESTE: Array[String] = [
	"res://scripts/minigames/games/ranch_parcours/game.json",
	"res://scripts/minigames/games/ranch_herde/game.json",
]
## Keys, ohne die die Screens/Spiele nicht sprechen können.
const PFLICHT_KEYS: Array[String] = [
	"mg.ranchParcours.title",
	"mg.ranchParcours.hint",
	"mg.ranchHerde.title",
	"mg.ranchHerde.drin",
	"ranchplay.select.done",
	"ranchplay.select.hint_parcours",
	"ranchplay.select.hint_herde",
	"ranchplay.werte.hunger",
	"ranchplay.werte.bindung",
	"ranchplay.pflege.traenken",
	"ranchplay.pflege.striegeln",
	"ranchplay.pflege.ausmisten",
	"ranchplay.ausbau.titel",
	"ranchplay.ausbau.heu_kaufen",
	"ranchplay.ausbau.weidezaun",
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
		assert_false(text.contains("Coins"), "%s sagt „Coins“ statt „Münzen“" % key)
		assert_false(text.contains("..."), "%s nutzt ... statt …" % key)
		for zeichen in text:
			assert_true(zeichen.unicode_at(0) < 0x1F000, "%s enthält ein rohes Emoji" % key)


func test_pflicht_keys_existieren() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for key in PFLICHT_KEYS:
		assert_true(de.has(key), "Pflicht-Key fehlt: %s" % key)


func test_i18n_service_liefert_meine_keys() -> void:
	assert_eq(I18nService.t("mg.ranchParcours.title"), "Hindernis-Parcours")
	assert_eq(I18nService.t("mg.ranchHerde.title"), "Schaf-Hüten")
	assert_ne(
		I18nService.t("ranchplay.pflege.striegeln"),
		"ranchplay.pflege.striegeln",
		"ranch_play.json wird vom I18nService geladen"
	)


func test_minigame_manifeste_erfuellen_den_vertrag() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for pfad in MANIFESTE:
		assert_true(FileAccess.file_exists(pfad), "Manifest fehlt: %s" % pfad)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
		assert_true(data is Dictionary, "%s parst nicht" % pfad)
		if not (data is Dictionary):
			continue
		var manifest: Dictionary = data
		for feld: String in [
			"id", "title_key", "scene", "coin_table", "target", "orientation", "energy_cost"
		]:
			assert_true(manifest.has(feld), "%s fehlt Feld %s" % [pfad, feld])
		assert_true(de.has(str(manifest.get("title_key"))), "%s: title_key fehlt in DE" % pfad)
		assert_true(ResourceLoader.exists(str(manifest.get("scene"))), "%s: Szene fehlt" % pfad)


func test_spiele_stehen_in_der_registry() -> void:
	var ids := {}
	for game in MinigameRegistry.all_games():
		ids[str(game["id"])] = true
	assert_true(ids.has("ranchParcours"), "ranchParcours erscheint im Arcade")
	assert_true(ids.has("ranchHerde"), "ranchHerde erscheint im Arcade")


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
