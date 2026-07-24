extends W1cTestCase
## Strings: DE/EN-Parität der W1c-Domains + keine hartkodierten deutschen
## UI-Texte (Umlaut-Literale) in den W1c-Skripten.

const W1C_DOMAINS := ["ui.", "hud.", "dialog.", "onboarding.", "settings.", "news."]
const SCRIPT_DIRS := ["res://scripts/ui", "res://scripts/ui/onboarding", "res://themes"]
## gooby_preview.gd enthält bewusst KEINE Strings; Kommentare sind erlaubt.
const UMLAUTE := ["ä", "ö", "ü", "Ä", "Ö", "Ü", "ß"]


func test_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	check(de.size() > 40, "DE-Tabelle gefüllt (%d Keys)" % de.size())
	for key: String in de:
		if not _is_w1c_key(key):
			continue
		check(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if not _is_w1c_key(key):
			continue
		check(de.has(key), "DE fehlt Key: %s" % key)
	var de_items: Array = de.get("news.items", [])
	var en_items: Array = en.get("news.items", [])
	check_eq(en_items.size(), de_items.size(), "news.items DE/EN gleich lang")
	check_eq(de_items.size(), 6, "6 News-Highlights")


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


func _is_w1c_key(key: String) -> bool:
	for domain in W1C_DOMAINS:
		if key.begins_with(domain):
			return true
	return false


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
