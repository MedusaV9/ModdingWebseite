extends TestCase
## RW-5 — Text-Tor für den Wettbewerbs-Besitz: DE/EN-Parität von
## `strings/*/ranch_comp.json` (Keys, {platzhalter}, keine rohen Emojis,
## „Münzen"-Regel), Pflicht-Keys der Screens und die drei Minigame-
## Manifeste (game.json → MinigameRegistry-Vertrag).

const DATEI := "ranch_comp.json"
const MANIFESTE: Array[String] = [
	"res://scripts/minigames/games/ranch_turnier/game.json",
	"res://scripts/minigames/games/ranch_tonnen/game.json",
	"res://scripts/minigames/games/ranch_zeit/game.json",
]
## Keys, ohne die die Screens nicht sprechen können.
const PFLICHT_KEYS: Array[String] = [
	"mg.ranchTurnier.title",
	"mg.ranchTonnen.title",
	"mg.ranchZeit.title",
	"rcomp.menu.title",
	"rcomp.menu.liga",
	"rcomp.menu.klasse_wahl",
	"rcomp.menu.geist",
	"rcomp.einweisung.los",
	"rcomp.ergebnis.titel",
	"rcomp.ergebnis.aufstieg",
	"rcomp.zeremonie.titel",
	"rcomp.lauf.perfekt",
	"rcomp.hud.zeit",
	"rcomp.hud.kommando",
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


## Alle 7 Disziplinen haben Name + Regel-Einweisung, alle 5 Klassen Namen.
func test_jede_disziplin_und_klasse_hat_texte() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for disziplin in RanchCompKatalog.DISZIPLINEN:
		assert_true(de.has("rcomp.disziplin.%s" % disziplin), "Name fehlt: %s" % disziplin)
		assert_true(de.has("rcomp.regeln.%s" % disziplin), "Regeln fehlen: %s" % disziplin)
	for klasse in RanchCompKatalog.KLASSEN:
		assert_true(de.has("rcomp.klasse.%s" % klasse), "Klassenname fehlt: %s" % klasse)


## Jeder Event-Key, den RcompHud in Callouts übersetzt, existiert in DE.
func test_hud_event_keys_existieren() -> void:
	var de := _flach("res://strings/de/%s" % DATEI)
	for typ: String in RcompHud.EVENT_TEXTE:
		var key := str((RcompHud.EVENT_TEXTE[typ] as Array)[0])
		if key.is_empty():
			continue
		assert_true(de.has(key), "HUD-Event-Key fehlt: %s" % key)


func test_i18n_service_liefert_meine_keys() -> void:
	assert_eq(I18nService.t("mg.ranchTurnier.title"), "Turnier-Liga")
	assert_eq(I18nService.t("rcomp.disziplin.tonnen"), "Tonnenrennen")
	assert_ne(
		I18nService.t("rcomp.menu.title"),
		"rcomp.menu.title",
		"ranch_comp.json wird vom I18nService geladen"
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
	for id: String in ["ranchTurnier", "ranchTonnen", "ranchZeit"]:
		assert_true(ids.has(id), "%s erscheint im Arcade" % id)


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
