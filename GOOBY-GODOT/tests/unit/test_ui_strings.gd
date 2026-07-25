extends W1cTestCase
## Strings-Qualitätstor (W1c, in W4-P4 auf ALLE Domains ausgeweitet):
## DE/EN-Parität über die komplette geflachte Tabelle, Key-Kollisionsfreiheit
## über alle Quelldateien, {platzhalter}-Parität DE↔EN, „Münzen statt Coins“-
## Konsistenz und keine hartkodierten deutschen UI-Texte (Umlaut-Literale).

const SCRIPT_DIRS := [
	"res://scripts/ui",
	"res://scripts/ui/onboarding",
	"res://scripts/ui/friends",
	"res://scripts/ui/social",
	"res://themes",
]
## gooby_preview.gd enthält bewusst KEINE Strings; Kommentare sind erlaubt.
const UMLAUTE := ["ä", "ö", "ü", "Ä", "Ö", "Ü", "ß"]
## Erwartete Domain-Präfixe (strings/OWNERSHIP.md). Die Paritäts-Schleife
## deckt ohnehin JEDEN Key ab — diese Liste erkennt zusätzlich eine komplett
## fehlende/umbenannte Domain-Datei.
const EXPECTED_DOMAINS := [
	"ui.",
	"hud.",
	"dialog.",
	"onboarding.",
	"settings.",
	"news.",
	"home.",
	"build.",
	"updates.",
	"mg.",
	"net.",
	"city.",
	"travel.",
	"gvz.",
	"social.",
	"board.",
	"events.",
	"album.",
	"bad.",
	"sys.",
]


func test_de_en_paritaet_alle_domains() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	check(de.size() > 250, "DE-Tabelle gefüllt (%d Keys)" % de.size())
	for key: String in de:
		check(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		check(de.has(key), "DE fehlt Key: %s" % key)
	for domain: String in EXPECTED_DOMAINS:
		var found := false
		for key: String in de:
			if key.begins_with(domain):
				found = true
				break
		check(found, "Domain fehlt komplett: %s" % domain)
	var de_items: Array = de.get("news.items", [])
	var en_items: Array = en.get("news.items", [])
	check_eq(en_items.size(), de_items.size(), "news.items DE/EN gleich lang")
	check_eq(de_items.size(), 6, "6 News-Highlights")


func test_platzhalter_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var regex := RegEx.new()
	regex.compile("\\{([A-Za-z0-9_]+)\\}")
	for key: String in de:
		if not (de[key] is String) or not en.has(key) or not (en[key] is String):
			continue
		check_eq(
			_placeholders(regex, str(en[key])),
			_placeholders(regex, str(de[key])),
			"{platzhalter} DE↔EN gleich: %s" % key
		)


func test_keine_key_kollisionen_zwischen_dateien() -> void:
	for locale: String in I18nService.SUPPORTED_LOCALES:
		var seen: Dictionary = {}
		for path in _string_files(locale):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			check(parsed is Dictionary, "Strings-Datei parst: %s" % path)
			if not (parsed is Dictionary):
				continue
			var flat: Dictionary = {}
			_flatten("", parsed, flat)
			for key: String in flat:
				check(
					not seen.has(key), "Key-Kollision %s (%s UND %s)" % [key, seen.get(key), path]
				)
				seen[key] = path


func test_de_sagt_muenzen_statt_coins() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	for key: String in de:
		if de[key] is String:
			check(not str(de[key]).contains("Coins"), "„Coins“ in DE (→ Münzen): %s" % key)


func test_t_und_format_und_fallback() -> void:
	I18nService.reset_cache()
	I18nService.set_locale("de")
	check_eq(I18nService.t("ui.weiter"), "Weiter", "t() liefert DE-Text")
	check_eq(I18nService.t("hud.level_pill", {"level": 12}), "Lv 12", "Format-Args")
	I18nService.set_locale("en")
	check_eq(I18nService.t("ui.weiter"), "Next", "Locale-Wechsel greift")
	I18nService.set_locale("de")
	check_eq(I18nService.t("gibt.es.nicht"), "gibt.es.nicht", "Fallback = Key")


func test_keine_hartkodierten_umlaut_literale() -> void:
	for dir_path in SCRIPT_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".gd"):
				continue
			_check_file("%s/%s" % [dir_path, file])


func _placeholders(regex: RegEx, text: String) -> Array:
	var names: Array = []
	for m in regex.search_all(text):
		names.append(m.get_string(1))
	names.sort()
	return names


func _string_files(locale: String) -> Array[String]:
	var files: Array[String] = ["%s/%s.json" % [I18nService.STRINGS_DIR, locale]]
	var dir_path := "%s/%s" % [I18nService.STRINGS_DIR, locale]
	var dir := DirAccess.open(dir_path)
	if dir != null:
		var names := dir.get_files()
		names.sort()
		for file in names:
			if file.ends_with(".json"):
				files.append("%s/%s" % [dir_path, file])
	return files


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		var value: Variant = node[key]
		if value is Dictionary:
			_flatten(full, value, out)
		else:
			out[full] = value


func _check_file(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	var line_no := 0
	for line in source.split("\n"):
		line_no += 1
		var code := line.get_slice("#", 0)  # Kommentare sind erlaubt (DEUTSCH!)
		if code.contains("push_error(") or code.contains("push_warning("):
			continue  # Entwickler-Diagnostik, keine UI-Strings
		if not code.contains('"'):
			continue
		var in_string := false
		var literal := ""
		for ch in code:
			if ch == '"':
				if in_string:
					_check_literal(literal, path, line_no)
					literal = ""
				in_string = not in_string
				continue
			if in_string:
				literal += ch
	checks += 1


func _check_literal(literal: String, path: String, line_no: int) -> void:
	for umlaut in UMLAUTE:
		if literal.contains(umlaut):
			failures.append(
				'Hartkodierter deutscher String in %s:%d → "%s"' % [path, line_no, literal]
			)
			return
