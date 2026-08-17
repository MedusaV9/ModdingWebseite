class_name JsonFixtures
extends RefCounted
## Robustes Laden der Goldwert-Fixtures (tests/expected/*.json, erzeugt von
## tools/cross_check.mjs DIREKT aus der Web-Logik). JSON.new().parse statt
## JSON.parse_string, damit kaputter Input keinen Engine-ERROR loggt (W1a-Tipp).


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var raw := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return null
	return parser.data
