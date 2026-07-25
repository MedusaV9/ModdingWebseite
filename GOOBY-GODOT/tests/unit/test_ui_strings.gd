extends W1cTestCase
## Strings-Qualitätstor (W1c, in W4-P4 auf ALLE Domains ausgeweitet):
## DE/EN-Parität über die komplette geflachte Tabelle, Key-Kollisionsfreiheit
## über alle Quelldateien, {platzhalter}-Parität DE↔EN, „Münzen statt Coins“-
## Konsistenz und keine hartkodierten deutschen UI-Texte (Umlaut-Literale).
## FIX-G (E6 P2-13): zusätzlich Struktur-Parität der Stadt-Dialoge
## (`scripts/city/data/dialoge/*.json` ↔ `dialoge/en/*.json`).

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
	"veil.",
]
## Stadt-Dialoge: DE-Bäume + EN-Pendants (E6 P2-13; Wiring s. Handoff
## FIXG-text-requests.md — der Loader wählt bei locale=en das en/-Pendant).
const DIALOG_DIR := "res://scripts/city/data/dialoge"
const DIALOG_EN_DIR := "res://scripts/city/data/dialoge/en"


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


func test_stadt_dialoge_de_en_paritaet() -> void:
	var dir := DirAccess.open(DIALOG_DIR)
	check(dir != null, "Dialog-Verzeichnis fehlt: %s" % DIALOG_DIR)
	if dir == null:
		return
	var gefunden := 0
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		gefunden += 1
		_check_dialog_paritaet(file)
	check(gefunden >= 3, "mindestens 3 Stadt-Dialoge erwartet (%d)" % gefunden)


func test_keine_hartkodierten_umlaut_literale() -> void:
	for dir_path in SCRIPT_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".gd"):
				continue
			_check_file("%s/%s" % [dir_path, file])


## Struktur-Parität eines Dialogbaums: gleiche Knoten/Optionen/conds/Effekte,
## gleich viele Textzeilen, keine leeren Texte — nur die Sprache darf abweichen.
func _check_dialog_paritaet(file: String) -> void:
	var de_pfad := "%s/%s" % [DIALOG_DIR, file]
	var en_pfad := "%s/%s" % [DIALOG_EN_DIR, file]
	check(FileAccess.file_exists(en_pfad), "EN-Pendant fehlt: %s" % en_pfad)
	if not FileAccess.file_exists(en_pfad):
		return
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(de_pfad))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(en_pfad))
	check(de is Dictionary and en is Dictionary, "Dialog parst: %s" % file)
	if not (de is Dictionary and en is Dictionary):
		return
	check_eq(str(en.get("id")), str(de.get("id")), "%s: id gleich" % file)
	check_eq(str(en.get("start")), str(de.get("start")), "%s: start gleich" % file)
	var de_nodes: Dictionary = de.get("nodes", {})
	var en_nodes: Dictionary = en.get("nodes", {})
	for node_id: String in de_nodes:
		check(en_nodes.has(node_id), "%s: EN fehlt Knoten %s" % [file, node_id])
	for node_id: String in en_nodes:
		check(de_nodes.has(node_id), "%s: DE fehlt Knoten %s" % [file, node_id])
	for node_id: String in de_nodes:
		if not en_nodes.has(node_id):
			continue
		_check_knoten_paritaet(file, node_id, de_nodes[node_id], en_nodes[node_id])


func _check_knoten_paritaet(
	file: String, node_id: String, de_node: Dictionary, en_node: Dictionary
) -> void:
	var wo := "%s/%s" % [file, node_id]
	check_eq(
		str(en_node.get("sprecher", "")), str(de_node.get("sprecher", "")), "%s: sprecher" % wo
	)
	var de_zeilen := _dialog_zeilen(de_node)
	var en_zeilen := _dialog_zeilen(en_node)
	check_eq(en_zeilen.size(), de_zeilen.size(), "%s: gleich viele Textzeilen" % wo)
	for zeile in de_zeilen + en_zeilen:
		check(not str(zeile).strip_edges().is_empty(), "%s: keine leere Zeile" % wo)
	check_eq(str(en_node.get("next", "")), str(de_node.get("next", "")), "%s: next" % wo)
	check_eq(bool(en_node.get("ende", false)), bool(de_node.get("ende", false)), "%s: ende" % wo)
	var de_effekte: Array = de_node.get("effekt", [])
	var en_effekte: Array = en_node.get("effekt", [])
	check_eq(en_effekte, de_effekte, "%s: effekt identisch" % wo)
	var de_opts: Array = de_node.get("optionen", [])
	var en_opts: Array = en_node.get("optionen", [])
	check_eq(en_opts.size(), de_opts.size(), "%s: gleich viele Optionen" % wo)
	for i in mini(de_opts.size(), en_opts.size()):
		var de_opt: Dictionary = de_opts[i]
		var en_opt: Dictionary = en_opts[i]
		check_eq(str(en_opt.get("next")), str(de_opt.get("next")), "%s[%d]: next" % [wo, i])
		check_eq(str(en_opt.get("cond", "")), str(de_opt.get("cond", "")), "%s[%d]: cond" % [wo, i])
		check(not str(de_opt.get("text", "")).is_empty(), "%s[%d]: DE-Text da" % [wo, i])
		check(not str(en_opt.get("text", "")).is_empty(), "%s[%d]: EN-Text da" % [wo, i])


func _dialog_zeilen(node: Dictionary) -> Array:
	var raw: Variant = node.get("text", [])
	if raw is String:
		return [raw]
	return raw if raw is Array else []


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
